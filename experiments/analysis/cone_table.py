#!/usr/bin/env python3
"""Render the recorded cone-equivalence results as a LaTeX table.

Input: experiments/data/processed/p49-cone-cec.tsv (docs/RESULTS.md#evaluation-records).
External preprocessing and ABC equivalence remain trusted.
"""
import argparse, csv, pathlib


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv"); ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:conecec")
    a = ap.parse_args()
    rows = read_tsv(a.tsv)
    out = [r"\begin{table}[t]", r"\centering\small",
           r"\setlength{\tabcolsep}{5pt}",
           r"\begin{tabular}{l l rr l r}", r"\hline",
           r"host & cone output & cone PI & cone gates & \texttt{cec} & s\\",
           r"\hline"]
    ok = 0
    for r in rows:
        ok += r["verdict"] == "equivalent"
        out.append(f"\\texttt{{{r['host']}}} & \\texttt{{{r['cone_out']}}} & "
                   f"{r['cone_pi']} & {r['cone_gates']} & {r['verdict']} & {r['cec_s']}\\\\")
    out += [r"\hline", r"\end{tabular}",
            r"\caption{\EMPIRICAL{} The verified importer's cone against the "
            r"extraction script's, checked over \emph{all} inputs. "
            f"ABC reports equivalence for {ok} of {len(rows)} hosts. "
            r"The Agda side is the emitted lock with the correct key wired in, "
            r"which by \agda{lockHostFlat-restores} is the imported cone; there "
            r"is no separate cone-emitting path.  \texttt{abc}'s cone keeps the "
            r"structural support of the output while the extraction keeps the "
            r"smaller set the cone depends on, so the extra inputs are added to "
            r"the Agda side as \emph{unused} --- an interface difference, not a "
            r"functional one.  Both files' hashes are in "
            r"\texttt{experiments/data/processed/p49-cone-cec.tsv}.}",
            f"\\label{{{a.label}}}", r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
