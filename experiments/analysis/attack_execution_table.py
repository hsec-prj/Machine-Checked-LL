#!/usr/bin/env python3
"""Render executed recovery checks separately from formula-only rows."""
import argparse
from table_io import read_tsv, write_tex


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('tsv'); ap.add_argument('--tex', required=True)
    ap.add_argument('--label', default='tab:attacks-exec')
    args = ap.parse_args(); rows = read_tsv(args.tsv)
    out = [r'\begin{table}[t]', r'\centering\small', r'\begin{tabular}{r rrr}', r'\hline',
           r'$n=k$ & FALL $n+1$ & oscillation scan $2^k$ & point-DIP $2^n$\\', r'\hline']
    states = {'EXECUTED': 'E', 'FORMULA': 'F', 'SKIP': 'S', 'FAIL': 'X'}
    for n in sorted({int(r['n']) for r in rows}):
        values = []
        for attack in ['FALL', 'CycSAT', 'DIP']:
            row = next(r for r in rows if r['attack'] == attack and int(r['n']) == n)
            if row['execution_state'] == 'EXECUTED' and row['verdict'] != 'PASS':
                raise ValueError('executed table row did not pass')
            values.append('$' + f"{int(row['typed_budget']):,}".replace(',', r'{,}') + '^{\\mathrm{' + states[row['execution_state']] + '}}$')
        out.append(str(n) + ' & ' + ' & '.join(values) + r'\\')
    out += [r'\hline', r'\end{tabular}',
            r'\caption{\EMPIRICAL{} Native recovery checks from the current sources. '
            r'E: executed and recovered the independently selected key; F: formula '
            r'only; S: runner unavailable; X: failure. FALL is executed through '
            r'$n=20$, the oscillation scan through $k=16$, and point-DIP through '
            r'$n=12$. Every number shown is a typed/formula budget, including '
            r'the native runners\textquotesingle{} printed \texttt{queries} field; '
            r'actual oracle calls are not instrumented. Formula-only rows have '
            r'no recovery verdict. The equality $n=k$ is a sweep convention; '
            r'these algorithms observe different interfaces and their columns '
            r'do not rank attack costs.}', f'\\label{{{args.label}}}', r'\end{table}']
    write_tex(args.tex, '\n'.join(out) + '\n')


if __name__ == '__main__': main()
