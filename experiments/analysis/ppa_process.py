"""PPA subprocess receipts; monitoring failure never becomes a successful run."""
import datetime
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from revision_common import MEMORY_BYTES, sha


def limited(command, output, seconds, cwd=None):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    record = dict(command=[str(x) for x in command], cwd=str(cwd or Path.cwd()),
                  timeout_seconds=seconds, memory_limit_bytes=MEMORY_BYTES,
                  memory_policy='sampled process-RSS watchdog; not an OS address-space limit',
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    start, peak, samples, exit_races = time.monotonic(), 0, 0, 0
    timed_out, memory_exceeded, monitor_error = False, False, None
    cleanup_errors, reaped = [], False
    interruption = None
    with output.open('w') as log:
        try:
            process = subprocess.Popen(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
        except OSError as error:
            record.update(exit_code=None, timeout=False, memory_exceeded=False,
                          monitor_error=f'launch failed: {error}', rss_samples=0, rss_exit_races=0,
                          cleanup_errors=[], child_reaped=True, child_pid=None,
                          elapsed_s=round(time.monotonic() - start, 3), peak_rss_kib_sampled=0,
                          output_sha256=sha(output))
            output.with_suffix(output.suffix + '.json').write_text(json.dumps(record, indent=2) + '\n')
            return record, ''
        deadline = start + seconds
        try:
            while True:
                if process.poll() is not None:
                    timed_out = time.monotonic() > deadline
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    timed_out = True
                    break
                try:
                    sample = subprocess.run(['/bin/ps', '-o', 'rss=', '-p', str(process.pid)],
                                            capture_output=True, text=True, timeout=min(5, remaining))
                except subprocess.TimeoutExpired:
                    if time.monotonic() >= deadline:
                        timed_out = True
                        break
                    raise
                rss = sample.stdout.strip()
                valid = (sample.returncode == 0 and not sample.stderr.strip()
                         and rss.isascii() and rss.isdigit() and int(rss) > 0)
                gone = (not sample.stderr.strip() and
                        ((sample.returncode in (0, 1) and not rss) or
                         (sample.returncode == 0 and rss == '0')))
                if not valid and not gone:
                    timed_out = time.monotonic() >= deadline
                    raise RuntimeError(f'invalid RSS sample: ps exit {sample.returncode}; '
                                       f'stdout={rss!r}; stderr={sample.stderr.strip()!r}')
                if time.monotonic() >= deadline:
                    timed_out = True
                    break
                if valid:
                    samples += 1
                    peak = max(peak, int(rss))
                else:
                    if not samples:
                        raise RuntimeError('process-gone RSS sample without any positive observation')
                    # Only the documented process-gone signature permits an exit race.
                    remaining = deadline - time.monotonic()
                    try:
                        process.wait(timeout=min(0.02, remaining))
                    except subprocess.TimeoutExpired:
                        if time.monotonic() >= deadline:
                            timed_out = True
                            break
                        raise RuntimeError('process-gone RSS sample but owned child remains alive')
                    else:
                        timed_out = time.monotonic() > deadline
                        exit_races += 1
                        break
                if peak * 1024 > MEMORY_BYTES:
                    memory_exceeded = True
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    timed_out = True
                    break
                # A bounded wait observes exits before the next sample/deadline.
                try:
                    process.wait(timeout=min(0.1, remaining))
                except subprocess.TimeoutExpired:
                    if time.monotonic() >= deadline:
                        timed_out = True
                        break
                else:
                    timed_out = time.monotonic() > deadline
                    break
        except Exception as error:
            monitor_error = f'{type(error).__name__}: {error}'
        except BaseException as error:
            interruption = error
            monitor_error = f'interrupted: {type(error).__name__}'
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except OSError as error:
                    cleanup_errors.append(f'killpg: {type(error).__name__}: {error}')
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass
                    except OSError as direct_error:
                        cleanup_errors.append(f'kill: {type(direct_error).__name__}: {direct_error}')
            try:
                code = process.wait(timeout=5)
                reaped = True
            except subprocess.TimeoutExpired:
                code = None
                cleanup_errors.append('owned child was not reaped within 5 seconds')
    if samples == 0 and monitor_error is None:
        monitor_error = 'no positive process RSS observation'
    record.update(exit_code=code, timeout=timed_out, memory_exceeded=memory_exceeded,
                  monitor_error=monitor_error, rss_samples=samples, rss_exit_races=exit_races,
                  cleanup_errors=cleanup_errors, child_reaped=reaped, child_pid=process.pid,
                  elapsed_s=round(time.monotonic() - start, 3),
                  peak_rss_kib_sampled=peak, output_sha256=sha(output))
    output.with_suffix(output.suffix + '.json').write_text(json.dumps(record, indent=2) + '\n')
    if interruption:
        raise interruption
    return record, output.read_text(errors='replace')
