#!/usr/bin/env python3
"""Render the recorded structural decoding sweep for the Appendix B.2 table.

The input, `experiments/data/processed/p40-decode.tsv`, is produced by the sweep from
the emitted bytes. Values are derived directly instead of copied by hand.
`regenerate_tables.py --compare-paper` compares this output with its manuscript file.
This renderer reads recorded measurements; it does not rerun the decoder or sweep.
"""

import argparse
import csv
import pathlib

ROUTE = {"unfused": "un-fused", "fused": "fused"}


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv")
    ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:decode-certified")
    a = ap.parse_args()

    rows = read_tsv(a.tsv)
    hosts = []
    for r in rows:
        if r["host"] not in hosts:
            hosts.append(r["host"])

    out = [r"\begin{table}[t]", r"\centering\small",
           r"\setlength{\tabcolsep}{5pt}",
           r"\begin{tabular}{l r l rr l}", r"\hline",
           r"host & $n$ & key prefix & \multicolumn{2}{c}{constants} & decoder verdict\\",
           r" & & & unfused & fused & \\", r"\hline"]
    for h in hosts:
        for kid in ("k1", "k2"):
            got = {r["path"]: r for r in rows if r["host"] == h and r["key_id"] == kid}
            u, f = got.get("unfused"), got.get("fused")
            if not u:
                continue
            fc = "---" if not f or f["constants"] == "-" else f["constants"]
            verdict = (r"exact; fused no prefix"
                       if u["success_class"] == "exact"
                       and (not f or f["success_class"] != "exact")
                       else "see raw run")
            if f and f['success_class'] == 'no-route':
                verdict = 'exact; fused no route'
            out.append(f"\\texttt{{{h}}} & {u['n']} & \\texttt{{{u['input_key_prefix']}}} & "
                       f"{u['constants']} & {fc} & {verdict}\\\\")
    out += [r"\hline", r"\end{tabular}",
            r"\caption{The structural decoder run against the "
            r"\emph{certified} emitter's own output, on both routes.  Every "
            r"un-fused emission's first $|\ksec|$ constant payloads are \ksec\ "
            r"exactly, at zero oracle queries; no fused emission carries enough "
            r"constants to decode at all, having only the comparator's two "
            r"rails.  The key width is the input count of the cone the emitter "
            r"locks, so it differs by host. The displayed key prefixes are "
            r"truncated or zero-padded to that width; the processed TSV records and checks "
            r"the full planted and decoded strings and their hashes. "
            r"There are 14 full-key successes, 12 fused no-prefix results and "
            r"two no-route entries. The measured \texttt{c17} emission is the "
            r"compile-time route, which has no fused variant (a flat-route "
            r"\texttt{c17} cone is checked in \S\ref{sec:results-iscas}). "
            r"A separate, unverified measurement decoder checks the payload "
            r"relation predicted by the certified theorem "
            r"(\S\ref{sec:netlists-emitters}) against emitted files, recording "
            r"full-key equality and hashes.}",
            f"\\label{{{a.label}}}", r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
