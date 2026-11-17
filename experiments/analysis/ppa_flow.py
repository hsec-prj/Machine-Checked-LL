"""Common port-preserving ABC/OpenSTA flow, with recorded full-output CEC gates.

Every original output gets a fresh external name and an identity BUF before
mapping. The mapped costs include surviving buffers (notably PI/PO aliases).
No verdict is accepted from a failed process or an ABC diagnostic.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil

from bench_io import Bench, parse
from ppa_ports import adapter_miter, bench_ports, output_adapter, require_ports, verilog_ports
from revision_common import sha
from ppa_process import limited

ROOT = Path(__file__).resolve().parents[2]
LIB_SHA = '2efd0b32eb580e4e60e72fc0575bb3bc69aac907c91d908442e4ae6d7fe55895'
LIB_WARNING = 'Warning: Detected 2 multi-output cells (for example, "FA_X1").'
ERROR_MARKERS = ('CANNOT OPEN', 'HAS FAILED', 'ERROR', 'WARNING', 'NON-DRIVEN',
                 'UNKNOWN COMMAND', 'ASSERTION', 'CANNOT DETERMINE', 'SEGMENTATION', 'ABORT')
RESOURCE_FAILURES = ('out of memory', 'out of dynamic memory', 'memory exhausted', 'bad_alloc',
                     'memory limit exceeded', 'timeout', 'time limit')


def emit(net):
    return '\n'.join([*(f'INPUT({w})' for w in net.inputs), *(f'OUTPUT({w})' for w in net.outputs),
                      *(f'{w} = {op.lower()}({", ".join(args)})' for w, op, args in net.gates)]) + '\n'


def abc_path(path, directory):
    """Give ABC a safe relative filename, even in a checkout containing spaces."""
    path, directory = Path(path).resolve(), Path(directory).resolve()
    if path.parent == directory and re.fullmatch(r'[A-Za-z0-9_.-]+', path.name):
        return path.name
    name = 'ppa-external-' + hashlib.sha256(str(path).encode()).hexdigest()[:16] + (path.suffix if path.suffix in {'.bench', '.v', '.lib'} else '.input')
    alias = directory / name
    if alias.is_symlink():
        if alias.resolve() != path:
            raise ValueError('ABC input alias collision')
    elif alias.exists():
        raise ValueError('ABC input alias already exists')
    else:
        alias.symlink_to(path)
    index = directory / 'abc-inputs.json'
    records = json.loads(index.read_text()) if index.exists() else {}
    records[name] = dict(path=str(path), sha256=sha(path))
    index.write_text(json.dumps(records, indent=2) + '\n')
    return name


def run_abc(abc, flow, log, library=None):
    info, text = limited([abc, '-c', flow], log, 300, cwd=Path(log).parent)
    allowed = [LIB_WARNING] if library and sha(library) == LIB_SHA else []
    checked = '\n'.join(line for line in text.splitlines() if line.strip() not in allowed).upper()
    if (info['exit_code'] or info['timeout'] or info['memory_exceeded'] or info['monitor_error'] or info['cleanup_errors'] or not info['child_reaped'] or any(m in checked for m in ERROR_MARKERS)
            or any(m in text.lower() for m in RESOURCE_FAILURES)):
        raise ValueError(f'ABC failed or diagnosed an error: {log}')
    return info, text


def cec(abc, left, right, log, expected='equivalent'):
    info, text = run_abc(abc, f'cec {abc_path(left, Path(log).parent)} {abc_path(right, Path(log).parent)}', log)
    verdict = ('inequivalent' if 'Networks are NOT EQUIVALENT' in text else
               'equivalent' if re.search(r'Networks are equivalent', text, re.I) else 'unknown')
    record = dict(info, verdict=verdict, expected=expected,
                  left_sha256=sha(left), right_sha256=sha(right))
    Path(log).with_suffix('.verdict.json').write_text(json.dumps(record, indent=2) + '\n')
    if verdict != expected:
        raise ValueError(f'CEC {verdict}, expected {expected}: {log}')
    return record


def fixed_key(net, bits):
    keys = [f'keyinput{i}' for i in range(len(bits))]
    if set(w for w in net.inputs if w.startswith('keyinput')) != set(keys) or set(bits) - {'0', '1'}:
        raise ValueError('invalid complete planted key')
    primary = [w for w in net.inputs if w not in keys]
    if not primary:
        raise ValueError('fixed-key checking requires a primary input')
    used = set(net.inputs) | {w for w, _, _ in net.gates}
    prefix = 'ppa_constant'
    while any(prefix + suffix in used for suffix in ('_not', '_zero', '_one')):
        prefix += '_'
    inverse, zero, one = [prefix + suffix for suffix in ('_not', '_zero', '_one')]
    constants = [(inverse, 'NOT', [primary[0]]), (zero, 'AND', [primary[0], inverse]),
                 (one, 'OR', [primary[0], inverse])]
    mapping = {name: one if bit == '1' else zero for name, bit in zip(keys, bits)}
    return Bench(primary, net.outputs, constants +
                 [(w, op, [mapping.get(a, a) for a in args]) for w, op, args in net.gates])


def finite(values):
    result = [float(x) for x in values]
    if any(not math.isfinite(x) or x < 0 for x in result):
        raise ValueError('nonfinite or negative PPA measurement')
    return result


def measure(source, out, abc, lib, *, sta=None, keybits='', oracle=None,
            period=1.0, activity=0.5, duty=0.5):
    """Measure one source. Caller creates a new, empty out directory."""
    source, out, lib = Path(source).resolve(), Path(out).resolve(), Path(lib).resolve()
    if not math.isfinite(period) or period <= 0 or not math.isfinite(activity) or activity < 0 or not 0 <= duty <= 1:
        raise ValueError('invalid power protocol')
    net = parse(source.read_text())
    gates = {}
    if oracle:
        restored = fixed_key(net, keybits)
        reference = parse(Path(oracle).read_text())
        require_ports(dict(inputs=reference.inputs, outputs=reference.outputs),
                      dict(inputs=restored.inputs, outputs=restored.outputs))
        restored_path = out / 'planted-fixed-key.bench'; restored_path.write_text(emit(restored))
        gates['planted_restoration'] = cec(abc, restored_path, oracle, out / 'planted-cec.log')
    adapted, mapping = output_adapter(net)
    adapted_path = out / 'port-adapted.bench'; adapted_path.write_text(emit(adapted))
    (out / 'port-map.json').write_text(json.dumps(mapping, indent=2) + '\n')
    miter, zero = adapter_miter(net, adapted, mapping)
    miter_path, zero_path = out / 'adapter-miter.bench', out / 'adapter-zero.bench'
    miter_path.write_text(emit(miter)); zero_path.write_text(emit(zero))
    gates['port_adapter'] = cec(abc, miter_path, zero_path, out / 'adapter-cec.log')
    index = next((i for i, entry in enumerate(mapping['output_map']) if entry['passthrough']), 0)
    target = adapted.outputs[index]
    wrong = Bench(adapted.inputs, adapted.outputs,
                  [(w, 'NOT', aa) if w == target else (w, op, aa) for w, op, aa in adapted.gates])
    wrong_path = out / 'wrong-output-identity.bench'; wrong_path.write_text(emit(wrong))
    gates['port_identity_negative'] = cec(abc, adapted_path, wrong_path, out / 'identity-negative-cec.log', 'inequivalent')
    mapped = out / 'mapped.v'
    flow = (f'read_lib {abc_path(lib, out)}; read_bench {abc_path(adapted_path, out)}; '
            f'strash; dch; map; topo; stime; print_stats; write_verilog {abc_path(mapped, out)}')
    abc_info, abc_log = run_abc(abc, flow, out / 'abc.log', lib)
    metrics = re.findall(r'Gates\s*=\s*(\d+).*?Area\s*=\s*([0-9.]+).*?Delay\s*=\s*([0-9.]+)\s*ps',
                         re.sub(r'\x1b\[[0-9;]*m', '', abc_log))
    if not metrics or not mapped.is_file():
        raise ValueError('missing ABC mapping result')
    cells, area, delay = metrics[-1]; finite([cells, area, delay])
    require_ports(mapping['adapted_interface'], verilog_ports(mapped.read_text()))
    normalized = out / 'mapped-normalized.bench'
    run_abc(abc, f'read_lib {abc_path(lib, out)}; read -m {abc_path(mapped, out)}; strash; write_bench {abc_path(normalized, out)}',
            out / 'normalize.log', lib)
    require_ports(mapping['adapted_interface'], bench_ports(normalized.read_text()))
    gates['mapped_equivalence'] = cec(abc, adapted_path, normalized, out / 'mapped-cec.log')
    content, count = re.subn(r'\bmodule\s+\S+\s*\(', 'module top (', mapped.read_text(), count=1)
    if count != 1:
        raise ValueError('missing mapped module')
    top = out / 'top.v'; top.write_text(content)
    require_ports(mapping['adapted_interface'], verilog_ports(top.read_text()))
    result = dict(area_um2=area, delay_ps=delay, cells=cells, sha256_bench=sha(source),
                  sha256_adapted=sha(adapted_path), sha256_mapped=sha(top),
                  abc_elapsed_s=abc_info['elapsed_s'], peak_rss_kib_sampled=abc_info['peak_rss_kib_sampled'],
                  full_port_checks=True, original_pi=len(net.inputs), original_po=len(net.outputs),
                  passthrough_outputs=sum(e['passthrough'] for e in mapping['output_map']), gates=gates,
                  abc=abc_info, measurement_kind='port-preserving output BUF costs included')
    if sta:
        # Width/bit validity is checked independently by the Tcl as well.
        fixed_key(net, keybits)
        template = ROOT / 'experiments/scripts/sta-power.tcl'
        values = dict(STA_LIB=str(lib), STA_NETLIST=str(top), STA_TOP='top', STA_ACTIVITY=str(activity),
                      STA_PERIOD=str(period), STA_DUTY=str(duty), STA_KEY_BITS=keybits)
        if any('}' in v or '\n' in v for v in values.values()):
            raise ValueError('unsupported Tcl parameter')
        tcl = out / 'power.tcl'
        tcl.write_text('\n'.join(f'set ::env({k}) {{{v}}}' for k, v in values.items()) + '\n' + template.read_text())
        sta_info, sta_log = limited([sta, '-no_init', '-exit', tcl.name], out / 'sta.log', 300, cwd=out)
        totals = re.findall(r'^Total\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)', sta_log, re.M)
        if (sta_info['exit_code'] or sta_info['timeout'] or sta_info['memory_exceeded'] or sta_info['monitor_error'] or sta_info['cleanup_errors'] or not sta_info['child_reaped'] or len(totals) != 1
                or 'REVISION_POWER_PROTOCOL_OK' not in sta_log or re.search(r'(?m)^Error:', sta_log)
                or any(m in sta_log.lower() for m in RESOURCE_FAILURES)):
            raise ValueError(f'OpenSTA failed: {out / "sta.log"}')
        internal, switching, leakage, total = totals[0]; finite(totals[0])
        if abs(sum(map(float, (internal, switching, leakage))) - float(total)) > max(1e-12, float(total) * 1e-5):
            raise ValueError('power component sum mismatch')
        result.update(internal_W=internal, switching_W=switching, leakage_W=leakage, total_W=total,
                      period_ns=period, activity=activity, duty=duty, static_key_bits=keybits,
                      sta_elapsed_s=sta_info['elapsed_s'], sta=sta_info, tcl_sha256=sha(tcl),
                      peak_rss_kib_sampled=max(result['peak_rss_kib_sampled'], sta_info['peak_rss_kib_sampled']))
    result['required_checks_complete'] = True
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    for alias in out.glob('ppa-external-*'):
        alias.unlink()
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('source', type=Path)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--lib', type=Path, required=True)
    ap.add_argument('--abc', default=shutil.which('yosys-abc'))
    ap.add_argument('--sta')
    ap.add_argument('--key-bits', default='')
    ap.add_argument('--period-ns', type=float, default=1.0)
    ap.add_argument('--activity', type=float, default=0.5)
    ap.add_argument('--duty', type=float, default=0.5)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    result = measure(args.source, args.output, args.abc, args.lib, sta=args.sta, keybits=args.key_bits,
                     period=args.period_ns, activity=args.activity, duty=args.duty)
    if args.sta:
        print(' '.join(f'{v * 1e6:.4g}' for v in [float(result['leakage_W']),
              float(result['internal_W']) + float(result['switching_W']), float(result['total_W'])]))
    else:
        print(result['area_um2'], result['delay_ps'], result['cells'])


if __name__ == '__main__':
    main()
