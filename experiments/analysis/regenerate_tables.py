#!/usr/bin/env python3
"""Regenerate thirteen table files from the committed experiment records.

Only files under experiments/data are read: no attack, synthesis or measurement is repeated.
--compare-paper also compares seven generator-matched files byte for byte with paper/sup-tables/.
The other retained manuscript files have separately edited captions. Appendix B.2-B.3 prints four
evaluation tables (controls, decoding, and the two configured tables in one file); the thirteen
generated files and seven byte comparisons are different sets. docs/RESULTS.md#evaluation-records indexes the records.

Usage: python experiments/analysis/regenerate_tables.py --output DIR [--compare-paper ../paper]
"""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TABLES = {
    'outcomes_from_raw': ('tab:outcomes-raw', ['fixtures/e4-keys-sphere-deep.tsv']),
    'decode_table': ('tab:decode-certified', ['processed/p40-decode.tsv']),
    'dip_table': ('tab:dips', ['processed/p41-dips.tsv']),
    'recovery_table': ('tab:recrate', ['processed/p43-recovery.tsv']),
    'controls_table': ('tab:controls', ['processed/p46-controls.tsv']),
    'cone_table': ('tab:conecec', ['processed/p49-cone-cec.tsv']),
    'ppa_table': ('tab:ppa', ['processed/p44-ppa-common-flow.tsv']),
    'paired_table': ('tab:paired', ['processed/p412-paired.tsv']),
    'literal_table': ('tab:literal', ['processed/p52-literal.tsv', 'processed/p49-cone-cec.tsv']),
    'resistance_table': ('tab:resist', ['fixtures/tab-resist.tsv']),
    'attack_execution_table': ('tab:attacks-exec', ['fixtures/attacks.tsv']),
    'polarity_table': ('tab:polarity', ['processed/p411-polarity.tsv']),
    'configured_table': ('tab:iscas-configured', ['processed/p53-iscas-configured.tsv']),
}
REVISION_TABLES = {'decode_table': 'tab-decode-certified', 'paired_table': 'tab-paired',
                   'ppa_table': 'tab-ppa', 'resistance_table': 'tab-resist',
                   'attack_execution_table': 'tab-attacks-exec', 'polarity_table': 'tab-polarity',
                   'configured_table': 'tab-iscas-configured'}


def tables(output, paper=None):
    output = output.resolve()
    for protected in (ROOT / 'experiments/data', ROOT / 'src'):
        if output == protected or protected in output.parents:
            raise SystemExit('Choose an output outside committed evidence/source directories')
    output.mkdir(parents=True, exist_ok=True)
    for name, (label, inputs) in TABLES.items():
        command = [sys.executable, '-B', str(ROOT / 'experiments/analysis' / (name + '.py'))]
        command += [str(ROOT / 'experiments/data' / p) for p in inputs]
        command += ['--tex', str(output / (name + '.tex')), '--label', label]
        subprocess.run(command, check=True)
    print(f'Tables: {len(TABLES)}/{len(TABLES)} generated (not a manuscript byte comparison)')
    if paper:
        for generator, target in REVISION_TABLES.items():
            committed = paper / 'sup-tables' / (target + '.tex')
            if committed.read_bytes() != (output / (generator + '.tex')).read_bytes():
                raise SystemExit('Manuscript table differs: ' + str(committed))
        print(f'Manuscript comparison files: {len(REVISION_TABLES)}/{len(REVISION_TABLES)} byte-identical')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compare-paper', type=Path)
    args = parser.parse_args()
    tables(args.output, args.compare_paper)


if __name__ == '__main__':
    main()
