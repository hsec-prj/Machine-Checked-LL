#!/usr/bin/env python3
"""Describe separate evidence subjects for compile-time Netlist literals.

For generated hosts, regenerates compares the recorded generator/input with
the committed gate list; cone check records CEC for the stated extraction and
benchmark cones. Neither certifies arbitrary external preprocessing (O5).
The hand-written c17 multi-output literal instead has c17nl2-is-c17, relating
that literal to its Agda c17 specification over all inputs. Its theorem and
the other hosts' generator/input and CEC checks concern different objects.
Keep these distinctions visible without ordering them as a single guarantee.
"""
import argparse, csv, pathlib

FIDELITY = {"c17": r"\agda{c17nl2-is-c17}~\FORMAL"}


from table_io import read_tsv, write_tex

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv"); ap.add_argument("cec")
    ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:literal")
    a = ap.parse_args()
    rows = read_tsv(a.tsv)
    cec = {r["host"]: r for r in
           csv.DictReader(open(a.cec, encoding="utf-8"), delimiter="\t")}

    out = [r"\begin{table}[t]", r"\centering\footnotesize",
           r"\setlength{\tabcolsep}{3pt}",
           r"\begin{tabular}{l rr l l l}", r"\hline",
           r"host & PI & gates & benchmark file & regenerates & cone\\",
           r"\hline"]
    exact = lut = 0
    for r in rows:
        h = r["host"]
        if r["regenerates"] == "exact":
            exact += 1
        if r["mapping" if "mapping" in r else "transform"] == "LUT2":
            lut += 1
        bench = r["benchmark"].replace("_", r"\_")
        c = cec.get(h)
        conecol = (FIDELITY.get(h) or
                   (r"equiv.~\EMPIRICAL" if c and c["verdict"] == "equivalent"
                    else r"\emph{not run}"))
        out.append(" & ".join([
            r"\texttt{%s}" % h, r["inputs"], r["gates"],
            # A separate mapping column exceeded the available width. The filename suffix
            # `_lut2` conveys the same mapping, which the caption explains, so removing
            # the column preserves the information.
            r"\texttt{%s}" % bench if bench != "--" else "---",
            {"exact": r"exact~\EMPIRICAL", "hand-written": r"\emph{by hand}",
             "DIFFERS": r"\textbf{differs}"}[r["regenerates"]],
            conecol]) + r"\\")
    out += [r"\hline", r"\end{tabular}",
            r"\caption{\EMPIRICAL{} Provenance of the compile-time \agda{Netlist} "
            r"literals.  \emph{regenerates} is a regeneration diff: the generator "
            r"named in \texttt{experiments/analysis/literal\_provenance.py}, run on the file "
            r"named here, reproduces the committed gate list exactly -- %d of %d "
            r"hosts.  The file is not always the published benchmark: %d of the "
            r"%d generated literals are read from a \texttt{\_lut2} file, an ABC "
            r"2-input LUT mapping of the published one. "
            r"Regenerating \texttt{c880} from the "
            r"published \texttt{c880.bench} gives $124$ gates against the "
            r"committed $119$.  The two columns support the literal only together: "
            r"the first says it is what the script produces, the second that the "
            r"script's cone is the file's.  \texttt{c17} is in neither column --- "
            r"its literal is the two-output design, written by hand, and its "
            r"fidelity is a theorem over all inputs instead.}"
            % (exact, len(rows) - 1, lut, len(rows) - 1),
            r"\label{%s}" % a.label, r"\end{table}"]
    write_tex(a.tex, "\n".join(out) + "\n")
    print(f"{exact} exact, {lut} LUT-mapped, {len(rows)} hosts")


if __name__ == "__main__":
    main()
