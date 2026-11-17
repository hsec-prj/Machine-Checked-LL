#!/usr/bin/env python3
"""Render the recorded control-suite results for the Appendix B.2 table.

The data source is `experiments/data/processed/p46-controls.tsv`.
"""
import argparse, csv, pathlib, statistics


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv"); ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:controls")
    a = ap.parse_args()
    rows = read_tsv(a.tsv)

    cells = {}
    for r in rows:
        cells.setdefault((r["host"], r["h"], r["ksec"]), []).append(r)

    out = [r"\begin{table}[t]", r"\centering\small",
           r"\setlength{\tabcolsep}{5pt}",
           r"\begin{tabular}{l rl rr rr l}", r"\hline",
           r"host & $h$ & \ksec & \multicolumn{2}{c}{negative} & "
           r"\multicolumn{2}{c}{positive} & \texttt{cec} (s, max)\\",
           r" & & & run & fired & run & held & \\", r"\hline"]
    tn = tnf = tp = tph = 0
    for (host, h, ks) in sorted(cells, key=lambda k: (k[0], int(k[1]), k[2])):
        g = cells[(host, h, ks)]
        neg = [r for r in g if r["family"] == "negative"]
        pos = [r for r in g if r["family"] == "positive"]
        nf = sum(1 for r in neg if r["verdict"] == "different")
        ph = sum(1 for r in pos if r["verdict"] == "equivalent")
        tn += len(neg); tnf += nf; tp += len(pos); tph += ph
        mx = max((float(r["cec_s"]) for r in g), default=0.0)
        out.append(f"\\texttt{{{host}}} & {h} & \\texttt{{{ks}}} & {len(neg)} & {nf} & "
                   f"{len(pos)} & {ph} & {mx:.3f}\\\\")
    out += [r"\hline",
            f"total & & & {tn} & {tnf} & {tp} & {tph} & \\\\",
            r"\hline", r"\end{tabular}",
            r"\caption{The equivalence check's discriminating power, "
            r"measured exhaustively.  A \emph{negative} control is the emitted "
            r"lock with a wrong key wired in, compared against the same lock at "
            r"the right one; it \emph{fires} when \texttt{abc cec} reports the "
            r"two inequivalent and returns a distinguishing input.  The "
            r"\texttt{c17} key bus is five wide, so every wrong key is "
            r"enumerated --- the count per cell is $2^{5}-1$, not a sample.  A "
            r"\emph{positive} control re-emits the same cell and wires in the "
            r"\emph{right} key: it must hold, since a suite whose negatives all "
            r"fire and whose positives fire too is measuring the checker rather "
            r"than the lock.  For each secret and radius, all 31 wrong applied "
            r"keys, including one-bit neighbours, are tested.}",
            f"\\label{{{a.label}}}", r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
