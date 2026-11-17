"""Recorded, resource-limited subprocesses for the 2026-09-18 revision runs."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import time

MEMORY_BYTES = 8 * 1024 ** 3


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def machine():
    return dict(platform=platform.platform(), architecture=platform.machine(),
                logical_cpus=os.cpu_count(), python=platform.python_version(),
                memory_limit_bytes=MEMORY_BYTES, memory_policy='sampled process-RSS watchdog; not an OS address-space limit',
                clock='monotonic elapsed seconds',
                peak_rss_scope='process RSS sampled with ps; KiB; excludes unobserved peaks and child processes')


def limited(command, output, seconds, cwd=None, env=None):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    record = dict(command=[str(x) for x in command], cwd=str(cwd or Path.cwd()),
                  timeout_seconds=seconds, memory_limit_bytes=MEMORY_BYTES,
                  memory_policy='sampled process-RSS watchdog; macOS RLIMIT_AS rejected 8 GiB',
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    start, peak, timed_out, memory_exceeded = time.monotonic(), 0, False, False
    with output.open('w') as log:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        while process.poll() is None:
            sample = subprocess.run(['ps', '-o', 'rss=', '-p', str(process.pid)], capture_output=True, text=True)
            if sample.stdout.strip().isdigit():
                peak = max(peak, int(sample.stdout.strip()))
            if peak * 1024 > MEMORY_BYTES:
                memory_exceeded = True
                os.killpg(process.pid, signal.SIGKILL)
                break
            if time.monotonic() - start > seconds:
                timed_out = True
                os.killpg(process.pid, signal.SIGKILL)
                break
            time.sleep(0.1)
        code = process.wait()
    record.update(exit_code=code, timeout=timed_out, memory_exceeded=memory_exceeded,
                  elapsed_s=round(time.monotonic() - start, 3),
                  peak_rss_kib_sampled=peak, output_sha256=sha(output))
    output.with_suffix(output.suffix + '.json').write_text(json.dumps(record, indent=2) + '\n')
    return record, output.read_text(errors='replace')
