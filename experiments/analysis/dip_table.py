#!/usr/bin/env python3
"""Render the recorded point-lock DIP sweep as an artifact table.

Read `experiments/data/processed/p41-dips.tsv` directly, without transcribing results.
The recorded structural-solver iterations do not measure the Boolean-query bound.
"""
import argparse, csv, pathlib


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv")
    ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:dips")
    a = ap.parse_args()

    rows = read_tsv(a.tsv)
    by = {}
    for r in rows:
        by.setdefault(int(r["n"]), []).append(r)

    out = [r"\begin{table}[t]", r"\centering\small",
           r"\setlength{\tabcolsep}{5pt}",
           r"\begin{tabular}{r rrr rr}", r"\hline",
           r"$n$ & runs & terminated & key $=$ \ksec & DIPs (mean) & queried \ksec\\",
           r"\hline"]
    tot = term = match = has = 0
    last_always = True
    for n in sorted(by):
        g = by[n]
        t = sum(1 for r in g if r["sld_status"] == "OK")
        m = sum(1 for r in g if r["key_match"] == "Y")
        h = sum(1 for r in g if r["contains_ksec"] == "Y")
        ds = [int(r["dips_total"]) for r in g if r["dips_total"].isdigit()]
        for r in g:
            if r["contains_ksec"] == "Y" and r["first_ksec_index"] != r["dips_total"]:
                last_always = False
        tot += len(g); term += t; match += m; has += h
        out.append(f"{n} & {len(g)} & {t} & {m} & "
                   f"{(sum(ds)/len(ds) if ds else 0):.0f} & {h}/{len(g)}\\\\")
    out += [r"\hline",
            f"total & {tot} & {term} & {match} & --- & {has}/{tot}\\\\",
            r"\hline", r"\end{tabular}"]
    tail = (r"  In every run that queried it, the secret point was the "
            r"\emph{last} distinguishing input the attack asked for."
            if last_always else "")
    out += [r"\caption{\EMPIRICAL{} What the SAT attack actually queried.  Each "
            r"run plants a pseudo-random secret cube, splices the lock and runs "
            r"\texttt{sld} with its output kept rather than discarded; the last "
            r"column counts the runs in which one of the distinguishing inputs "
            r"\emph{is} the secret point." + tail +
            r"  The secret point is read off the first $n$ original inputs, "
            r"which is where \texttt{splice\_sfll.py} puts the protected cube.  "
            r"One solver build, one host, at the stated budget: this "
            r"characterises these runs and estimates nothing beyond them.  "
            r"Per-run records, including every DIP, are in "
            r"\texttt{experiments/data/raw/p41-dips/}.}",
            f"\\label{{{a.label}}}", r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
