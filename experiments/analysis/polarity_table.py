#!/usr/bin/env python3
"""Aggregate independently recounted operator and protected-input NOT counts."""
import argparse
from table_io import read_tsv, write_tex


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('tsv'); ap.add_argument('--tex', required=True)
    ap.add_argument('--label', default='tab:polarity')
    args = ap.parse_args(); rows = read_tsv(args.tsv)
    groups = [('certified unfused', [r for r in rows if r['source']=='certified' and r['path']=='unfused']),
              ('certified fused', [r for r in rows if r['source']=='certified' and r['path']=='fused'])]
    groups += [('splice ' + r['key_id'].replace('_', ', '), [r]) for r in rows if r['source']=='splice']
    out = [r'\begin{table}[t]', r'\centering\small', r'\begin{tabular}{l r r r}', r'\hline',
           r'input family & files & all NOT gates & direct protected-PI NOT\\', r'\hline']
    for name, group in groups:
        out.append(f"{name} & {len(group)} & {sum(int(r['not_gates']) for r in group):,} & "
                   f"{sum(int(r['not_on_protected']) for r in group):,}" + r'\\')
    out += [r'\hline', r'\end{tabular}',
            r'\caption{\EMPIRICAL{} Case-insensitive NOT recount, checked against '
            r'an independent lexical counter for every file. Direct protected-PI '
            r'counts require a primary-input fanin in the recorded protected set; '
            r'they are neither total inversions nor a key decoder. The two splice '
            r'inputs were recovered from matching local historical caches, with '
            r'hashes and their first-$n$ protection maps retained. The original '
            r'polarity producer was not recovered, so the old discrepancy\textquotesingle{}s '
            r'cause is not established.}', f'\\label{{{args.label}}}', r'\end{table}']
    write_tex(args.tex, '\n'.join(out) + '\n')


if __name__ == '__main__': main()
