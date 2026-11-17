#!/usr/bin/env python3
"""Produce an artifact table of the recorded common-flow PPA measurements (docs/RESULTS.md#evaluation-records)."""
import argparse, csv, pathlib

ORDER = ["unlocked", "SFLL-HD", "XOR-random"]
NAME = {"unlocked": "unlocked", "SFLL-HD": "SFLL-HD", "XOR-random": "random XOR"}


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv"); ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:ppa")
    a = ap.parse_args()
    rows = read_tsv(a.tsv)
    hosts = []
    for r in rows:
        if r["host"] not in hosts:
            hosts.append(r["host"])

    out = [r"\begin{table}[htbp]", r"\centering\scriptsize", r"\setlength{\tabcolsep}{3pt}",
           r"\begin{tabular}{l l rrr r rrr}", r"\hline",
           r"host & configuration & area & delay & cells & power & $\Delta A$ & $\Delta D$ & $\Delta P$\\",
           r" & & ($\mu$m$^2$) & (ps) & & (mW) & (\%) & (\%) & (\%)\\", r"\hline"]
    for h in hosts:
        for cfg in ORDER:
            r = next(x for x in rows if x["host"] == h and x["config"] == cfg)
            lbl = f"\\texttt{{{h}}}" if cfg == ORDER[0] else ""
            changes = " & ".join(f"{float(r[field + '_overhead_pct']):+.1f}" for field in ['area_um2','delay_ps','total_W'])
            out.append(f"{lbl} & {NAME[cfg]} & {float(r['area_um2']):.1f} & "
                       f"{float(r['delay_ps']):.1f} & {r['cells']} & "
                       f"{1000 * float(r['total_W']):.3f} & {changes}\\\\")
        out.append(r"\hline")
    out += [r"\end{tabular}",
            r"\caption{\EMPIRICAL{} PPA measurements of all 21 frozen "
            r"designs using a port-preserving output adapter. ABC~\cite{berkeley-nd-abc} maps area/delay; OpenSTA~\cite{cherry-nd-opensta} "
            r"uses that same mapped netlist and Nangate-45 library~\cite{nangate-nd-nangate45}. "
            r"Power uses a 1 ns virtual clock, 0.5 transitions per period and "
            r"input duty 0.5; key ports have zero activity and duty equal to the "
            r"planted bit. Internal activity is propagated, with no global "
            r"pin override, parasitics or output loads. Delay remains the "
            r"unconstrained combinational critical path. Relative changes use "
            r"the unlocked row of each host. These are vectorless estimates, "
            r"not workload or silicon measurements. Component powers in watts, "
            r"all 21 Tcl files, tool/library hashes and resource records are "
            r"in the processed TSV and \texttt{raw/submitted-ppa-20261110/power/}. "
            r"Every original PO has a fresh external name and an identity BUF. "
            r"Compared with the historical mapping, preserving pass-through "
            r"outputs adds 76 cells in each c2670 configuration and one in each "
            r"c7552 configuration. Complete ordered PI/PO checks, original/adapter and "
            r"mapped CEC, planted restoration, and an output-inversion negative "
            r"control gate every row. The earlier 21-row common-flow record is "
            r"retained separately; its six incomplete output interfaces are not "
            r"used in this table.}",
            f"\\label{{{a.label}}}", r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
