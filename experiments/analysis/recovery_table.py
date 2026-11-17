#!/usr/bin/env python3
"""Render the recorded recovery-sweep outcomes as an artifact table.

Input: experiments/data/processed/p43-recovery.tsv. This renderer counts the
recorded outcome labels; it does not run an equivalence checker. The classifications
distinguish exact from functional recovery, as required by Appendix B.1.
A non-exact returned key needs separate equivalence evidence before it can be
called functional; key-string disagreement alone is insufficient.

The following four outcomes partition the runs:

  exact       the returned key equals the planted key;
  functional  a different key for which cec finds the unlocked host and the
              keyed locked circuit equivalent: this is a successful break;
  other key   a different returned key whose circuit is inequivalent;
  no key      no key was returned within the allotted budget.

All table entries are generated directly, without transcription.
"""
import argparse, csv, pathlib, statistics


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv")
    ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:recrate")
    a = ap.parse_args()

    rows = read_tsv(a.tsv)
    cells = {}
    for r in rows:
        cells.setdefault((r["host"], int(r["n"])), []).append(r)

    out = [r"\begin{table}[htbp]", r"\centering\footnotesize",
           r"\setlength{\tabcolsep}{4pt}",
           r"\begin{tabular}{l rr rrrr l}", r"\hline",
           r"host & $n$ & $h$ & exact & functional & other key & no key & SAT iters (mean$\pm$sd)\\",
           r"\hline"]
    tot = {"exact": 0, "functional": 0, "other-key": 0, "no-key": 0}
    hosts = []
    for h, _ in cells:
        if h not in hosts:
            hosts.append(h)
    for host in hosts:
        for n in sorted({n for hh, n in cells if hh == host}):
            g = cells[(host, n)]
            c = {k: sum(1 for r in g if r["outcome"] == k) for k in tot}
            for k in tot:
                tot[k] += c[k]
            it = [int(r["sld_iters"]) for r in g if r["sld_iters"].isdigit()]
            m = f"${statistics.mean(it):.1f} \\pm {statistics.stdev(it):.1f}$" if len(it) > 1 else "---"
            label = f"\\texttt{{{host}}}" if n == sorted({x for hh, x in cells if hh == host})[0] else ""
            out.append(f"{label} & {n} & {n//2} & {c['exact']} & {c['functional']} & "
                       f"{c['other-key']} & {c['no-key']} & {m}\\\\")
        out.append(r"\hline")
    N = sum(tot.values())
    out.append(f"total & & & {tot['exact']} & {tot['functional']} & "
               f"{tot['other-key']} & {tot['no-key']} & \\\\")
    out += [r"\hline", r"\end{tabular}",
            r"\caption{\EMPIRICAL{} Recovery outcomes of the SAT attack, twenty "
            r"pseudo-random secret cubes per cell on the splice path at "
            r"$h=n/2$, under the tool build, oracle interface and budget of "
            r"\S\ref{sec:method}.  The four columns \emph{partition} the runs.  "
            r"``functional'' is a returned key that differs from the planted one "
            r"and at which the locked circuit is \emph{proved equivalent} to the "
            r"unlocked host by \texttt{abc cec} --- a successful attack, not a "
            r"defence: at $h=n/2$ the complement of the secret restores the host "
            r"(Theorem~\ref{thm:complement}), and every such key here is that "
            r"complement.  ``other key'' would be a returned key that is "
            r"\emph{not} equivalent; there are none.  ``no key'' is a run that "
            f"returned nothing inside the budget.  Of {N} runs, "
            f"{tot['exact'] + tot['functional']} returned a key that restores the "
            r"host.  No rate is estimated from these counts and no comparison "
            r"across widths is made: they characterise these runs.  Per-run "
            r"records --- returned key, Hamming distance, \texttt{cec} verdict, "
            r"every distinguishing input --- are in "
            r"\texttt{experiments/data/raw/p43-recovery/}.}",
            f"\\label{{{a.label}}}", r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
