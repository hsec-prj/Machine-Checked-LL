#!/usr/bin/env python3
"""Re-measure 21 frozen designs through the port-preserving ABC/OpenSTA flow."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import uuid
from bench_io import parse
from revision_common import machine, sha
from ppa_flow import measure
from table_io import write_tsv

ROOT = Path(__file__).resolve().parents[2]
HOSTS = ['c432', 'c880', 'c2670', 'c7552', 'b14', 'b20', 'b17']
CONFIGS = ['unlocked', 'SFLL-HD', 'XOR-random']


def write_manifest(output, manifest):
    temporary = output / 'manifest.json.tmp'
    temporary.write_text(json.dumps(manifest, indent=2) + '\n')
    temporary.replace(output / 'manifest.json')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--lib', type=Path, required=True)
    ap.add_argument('--abc', default=shutil.which('yosys-abc'))
    ap.add_argument('--sta', default=shutil.which('sta'))
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--tsv', type=Path, required=True)
    ap.add_argument('--period-ns', type=float, default=1.0)
    ap.add_argument('--activity', type=float, default=0.5)
    ap.add_argument('--duty', type=float, default=0.5)
    args = ap.parse_args()
    if args.period_ns <= 0 or args.activity < 0 or not 0 <= args.duty <= 1:
        ap.error('invalid power protocol')
    args.lib, args.output = args.lib.resolve(), args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    template = ROOT / 'experiments/scripts/sta-power.tcl'
    manifest = dict(schema=2, machine=machine(), producer_sha256=sha(__file__),
                    dependency_sha256={p.name: sha(p) for p in [Path(__file__).with_name(name) for name in
                        ['ppa_flow.py', 'ppa_ports.py', 'ppa_process.py', 'bench_io.py', 'revision_common.py', 'table_io.py']]},
                    port_policy='unique external output names plus one BUF per original PO; surviving BUF costs included',
                    equivalence='complete ordered PI/PO map, original-adapter and mapped CEC, inverted output negative, planted restoration',
                    historical_reference='raw/revision-20260918/power/manifest.json; original records retained',
                    tcl_sha256=sha(template),
                    library=dict(path=str(args.lib), sha256=sha(args.lib)),
                    tools={name: dict(path=path, sha256=sha(path), version=subprocess.check_output(
                        [path, '-c', 'version'] if name == 'abc' else [path, '-version'], text=True).strip())
                           for name, path in [('abc', args.abc), ('sta', args.sta)]},
                    period_ns=args.period_ns, activity_transitions_per_period=args.activity, duty=args.duty,
                    key_policy='zero input activity, duty equal to the correct planted bit; no global pin activity override',
                    parasitics='none; no output loads; liberty default operating conditions',
                    delay='ABC unconstrained combinational critical path; virtual clock only sets power activity frequency',
                    selection='same 21 frozen historical inputs; no post-result exclusions', status='RUNNING', expected_rows=21, rows=[])
    rows = []
    for host in HOSTS:
        for config in CONFIGS:
            source = ROOT / 'experiments/data/raw/p44-ppa' / host / config / 'design.bench'
            net = parse(source.read_text())
            keys = [w for w in net.inputs if w.startswith('keyinput')]
            if config == 'SFLL-HD':
                m = re.search(r'secret cube ksec = ([01]+)', source.read_text())
                if not m:
                    raise ValueError('missing frozen SFLL secret')
                keybits = m[1]
            else:
                keybits = '0' * len(keys)
            if len(keys) != len(keybits) or set(keys) != {f'keyinput{i}' for i in range(len(keys))}:
                raise ValueError('invalid static key policy')
            out = args.output / host / config; out.mkdir(parents=True)
            result = measure(source, out, args.abc, args.lib, sta=args.sta, keybits=keybits,
                             oracle=ROOT / 'experiments/data/raw/p44-ppa' / host / 'unlocked/design.bench',
                             period=args.period_ns, activity=args.activity, duty=args.duty)
            fields = ['area_um2', 'delay_ps', 'cells', 'internal_W', 'switching_W', 'leakage_W', 'total_W',
                      'sha256_bench', 'sha256_adapted', 'sha256_mapped', 'period_ns', 'activity', 'duty',
                      'static_key_bits', 'abc_elapsed_s', 'sta_elapsed_s', 'peak_rss_kib_sampled',
                      'original_pi', 'original_po', 'passthrough_outputs', 'full_port_checks', 'required_checks_complete']
            row = dict(host=host, config=config, **{field: result[field] for field in fields})
            baseline = row if config == 'unlocked' else next(r for r in rows if r['host'] == host and r['config'] == 'unlocked')
            for field in ['area_um2', 'delay_ps', 'total_W']:
                row[field + '_overhead_pct'] = round(100 * (float(row[field]) / float(baseline[field]) - 1), 4)
            rows.append(row)
            manifest['rows'].append(dict(host=host, config=config, input=str(source.relative_to(ROOT)),
                                         input_sha256=sha(source), mapped_sha256=result['sha256_mapped'],
                                         adapted_sha256=result['sha256_adapted'],
                                         port_map_sha256=sha(out / 'port-map.json'),
                                         result_sha256=sha(out / 'result.json'),
                                         tcl_sha256=result['tcl_sha256'], key_bits=keybits,
                                         full_port_checks=result['full_port_checks'],
                                         required_checks_complete=result['required_checks_complete'],
                                         gates=result['gates'], abc=result['abc'], sta=result['sta']))
            write_manifest(args.output, manifest)
            print(host, config, 'area', row['area_um2'], 'delay', row['delay_ps'], 'total_W', row['total_W'], flush=True)
    if len(rows) != 21 or not all(row['required_checks_complete'] for row in rows):
        raise ValueError('incomplete PPA population; final TSV was not published')
    # Keep a reader's previous table intact until every requested row succeeds.
    args.tsv = args.tsv.resolve()
    args.tsv.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.tsv.with_name('.' + args.tsv.name + '.tmp-' + uuid.uuid4().hex)
    write_tsv(temporary, rows)
    temporary.replace(args.tsv)
    manifest['status'] = 'COMPLETE'
    manifest['tsv_sha256'] = sha(args.tsv)
    write_manifest(args.output, manifest)


if __name__ == '__main__':
    main()
