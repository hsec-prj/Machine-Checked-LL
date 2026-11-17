#!/usr/bin/env python3
"""Derive recovery classifications solely from individual run records.

Per-run returned keys are required for reclassification; aggregate totals alone
do not retain that information. Exact and functional recovery are distinct
outcomes (Appendix B.1). A different returned key need not indicate failure:
when h = n/2, the complement protects the same
sphere, restores the host on every input, and causes zero corruption.
SFLL.Complement proves these facts as complement-restores and complement-ocr-0.
Returning that complement is therefore successful functional recovery.

Read the per-run file and decide equivalence only in cases that can be proved.
The six categories are:

    exact                the returned key equals the planted key
    functional           a different key with proven equivalence
                         (currently the complement when h = n/2)
    functional-unknown   a returned key with equivalence left undecided
    wrong                a returned key proved inequivalent by a checker
    no-key               no key was returned within the budget
    tool-failure         execution yielded no security outcome

Until an equivalence checker supplies negative evidence, wrong remains empty.
Failure to match a decidable case does not establish inequivalence.

    python3 outcomes_from_raw.py RAW.tsv [--tex OUT.tex] [--label tab:x]

Return status 0 unless a required classification column is missing. Missing
columns indicate a sweep-data failure rather than an analysis failure.
"""

import argparse
import collections
import pathlib
import sys

NEEDED = ("n", "ksec", "sld_key", "sld_status")
ORDER = ["exact", "functional", "functional-unknown", "wrong", "no-key", "tool-failure"]


def read_rows(path):
    rows, cols = [], None
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        if cols is None:
            cols = f
            continue
        rows.append(dict(zip(cols, f)))
    return cols or [], rows


def radius(row, cols):
    """Obtain the protection radius only from the row, if that field is present."""
    if "h" in cols and row.get("h", "").isdigit():
        return int(row["h"])
    return None


def classify(row, cols):
    key = (row.get("sld_key") or "").strip()
    sec = (row.get("ksec") or "").strip()
    status = (row.get("sld_status") or "").strip()

    if key in ("", "-", "NA"):
        return "tool-failure" if status in ("NOSPLICE", "NOSLD") else "no-key"
    if key == sec:
        return "exact"
    if len(key) != len(sec):
        return "functional-unknown"

    h = radius(row, cols)
    n = len(sec)
    # The supported equivalence case is the complement at h = n/2, which
    # defines the same sphere by SFLL.Complement.complement-restores.
    if h is not None and n == 2 * h and all(a != b for a, b in zip(sec, key)):
        return "functional"
    return "functional-unknown"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("raw")
    ap.add_argument("--tex")
    ap.add_argument("--label", default="tab:outcomes-raw")
    ap.add_argument("--assume-h",
                    help="radius for rows that do not record one: an integer, or "
                         "`half` for the sphere regime h = n/2.  It declares an "
                         "assumption the file does not carry, and the output says so.")
    a = ap.parse_args()

    cols, rows = read_rows(a.raw)
    missing = [c for c in NEEDED if c not in cols]
    if missing:
        sys.exit(f"error: {a.raw} lacks {', '.join(missing)}.  Those runs cannot be "
                 f"classified, only counted: a sweep that does not record the returned "
                 f"key and the radius leaves rows that no later analysis can recover.")

    assumed = a.assume_h is not None and "h" not in cols
    if assumed:
        cols = cols + ["h"]
        for r in rows:
            r["h"] = (str(int(r["n"]) // 2) if a.assume_h == "half"
                      else str(int(a.assume_h)))

    cells = collections.defaultdict(collections.Counter)
    for r in rows:
        cells[(r.get("bench", "?"), int(r["n"]))][classify(r, cols)] += 1

    tot = collections.Counter()
    for c in cells.values():
        tot.update(c)

    note = (f"   (radius {a.assume_h} assumed; the file does not record one)"
            if assumed else "")
    print(f"{a.raw}: {len(rows)} runs, {len(cells)} cells{note}")
    for k in ORDER:
        if tot[k]:
            print(f"  {k:20s} {tot[k]:4d}")
    got = tot["exact"] + tot["functional"]
    print(f"  {'-> functional recovery':22s} {got:4d} / {len(rows)}")
    if tot["functional-unknown"]:
        print(f"  {'   undecided':22s} {tot['functional-unknown']:4d}"
              f"  (a bound, not a rate: {got}..{got + tot['functional-unknown']})")

    if a.tex:
        out = ["% GENERATED by experiments/analysis/outcomes_from_raw.py -- do not edit.",
               f"% source: {pathlib.Path(a.raw).name}", "\\begin{table}[t]",
               "\\centering\\small", "\\begin{tabular}{lr rrrr}", "\\hline",
               "host & $n$ & exact & functional & undecided & no key\\\\", "\\hline"]
        for (b, n) in sorted(cells):
            c = cells[(b, n)]
            out.append(f"\\texttt{{{b}}} & {n} & {c['exact']} & {c['functional']} & "
                       f"{c['functional-unknown']} & {c['no-key'] + c['tool-failure']}\\\\")
        out += ["\\hline", "\\end{tabular}",
                "\\caption{Recovery outcomes classified from per-run records.  "
                "``functional'' is a returned key \\emph{proved} to restore the host: at "
                "$h=n/2$ the complement of the secret does "
                "(Theorem~\\ref{thm:complement}), so it is a successful attack and not a "
                "failure.  ``undecided'' is a returned key whose equivalence no checker "
                "has adjudicated, left undecided rather than counted either way.  Every "
                "number is computed from the per-run file named above it; none is "
                "transcribed.  \\EMPIRICAL}",
                f"\\label{{{a.label}}}", "\\end{table}", ""]
        pathlib.Path(a.tex).write_text("\n".join(out), encoding="utf-8")
        print(f"  wrote {a.tex}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
