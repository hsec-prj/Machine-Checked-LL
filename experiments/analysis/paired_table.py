#!/usr/bin/env python3
"""Produce an artifact table for the recorded paired-route subset (docs/RESULTS.md#evaluation-records)."""
import argparse, csv, pathlib


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv"); ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:paired")
    a = ap.parse_args()
    rows = read_tsv(a.tsv)
    hosts = []
    for r in rows:
        if r["host"] not in hosts:
            hosts.append(r["host"])

    out = [r"\begin{table}[t]", r"\centering\small", r"\setlength{\tabcolsep}{4pt}",
           r"\begin{tabular}{l r l l r r l}", r"\hline",
           r"host & $n$ & route & outcome & iterations & wall (s) & key\\", r"\hline"]
    for h in hosts:
        for path in ("certified", "splice"):
            row = next(x for x in rows if x["host"] == h and x["path"] == path)
            key = r"$=\ksec$" if row["key_match"] == "Y" else "---"
            wall = "---" if row["wall_s"] == "NA" else f"{float(row['wall_s']):.2f}"
            out.append(f"\\texttt{{{h}}} & {row['cone_pi']} & {path} & {row['sld_status']} & "
                       f"{row['sld_iters']} & {wall} & {key}\\\\")
        out.append(r"\hline")
    out += [r"\end{tabular}",
            r"\caption{\EMPIRICAL{} Paired-route measurements of four $h=0$ pairs with the "
            r"same ordered protected inputs, full secret, output and oracle. "
            r"All four pairs pass ABC equivalence for every data/key input; "
            r"each regenerated constant-free adapter also passes against the "
            r"renamed frozen certified bytes. Swapping two key connections "
            r"is rejected for all four negative controls. Only then is exact "
            r"\texttt{sld} run with a 180 s wall deadline. Iterations on timeout "
            r"are partial progress, not recovery. The 8 GiB sampled process-RSS "
            r"watchdog, hashes, command lines and raw logs are recorded under "
            r"\texttt{raw/revision-20260918/paired-run003/}; the solver's "
            r"\texttt{-m 8192} request was not applied, as every solver log "
            r"opens with its data-limit notice. "
            r"One run per route/host supports no distributional speed claim. "
            r"The adapter removes literal constants, so this table does not "
            r"measure the original structural disclosure channel.}",
            f"\\label{{{a.label}}}", r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
