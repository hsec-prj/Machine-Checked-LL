#!/usr/bin/env python3
"""Reclassify the historical returned-key fixture indexed in docs/RESULTS.md#evaluation-records.

Input: tab-resist.tsv; no new SAT attack is executed."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from table_io import read_tsv, write_tsv, write_tex

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "experiments/scripts"))
from splice_sfll import gen_ksec


def classify(planted, returned, n, h):
    if len(planted) != n or set(planted) - {"0", "1"}:
        raise ValueError("invalid full planted key")
    if returned in {"NA", "-", ""}:
        return "no-key", "NA"
    if len(returned) != n or set(returned) - {"0", "1"}:
        raise ValueError("invalid full returned key")
    distance = sum(a != b for a, b in zip(planted, returned))
    return ("exact" if distance == 0 else "functional-complement"
            if distance == n and n == 2 * h else "undecided"), distance


def ocr(n, h, distance):
    if distance == "NA":
        return "NA"
    intersection = 0
    if distance % 2 == 0:
        e = distance // 2
        if 0 <= h - e <= n - distance:
            intersection = math.comb(distance, e) * math.comb(n - distance, h - e)
    return 2 * math.comb(n, h) - 2 * intersection


def reconstruct(source):
    result = []
    for row in read_tsv(source):
        n, h = int(row["n"]), int(row["h"])
        seed = f"tools/sld/benchmarks/original/c432.bench:{n}:{h}"
        planted = "".join(map(str, gen_ksec(n, seed)))
        outcome, distance = classify(planted, row["key"], n, h)
        result.append(dict(bench=row["bench"], n=n, h=h, planted=planted, returned=row["key"],
                           HD=distance, outcome=outcome, OCR_max=2 * math.comb(n, h),
                           OCR_returned=ocr(n, h, distance), SAT_iters=row["SAT_iters"],
                           SAT_cpu_s=row["SAT_cpu_s"], wall_s=row["wall_s"], status=row["status"],
                           seed=seed, planted_provenance="reconstructed-from-delivered-seed-rule",
                           historical_fixture_sha256=hashlib.sha256(Path(source).read_bytes()).hexdigest()))
    return result


def render(rows, label):
    out = [r"\begin{table}[t]", r"\centering\small", r"\setlength{\tabcolsep}{4pt}",
           r"\begin{tabular}{r r r r r l}", r"\hline",
           r"$n$ & $\OCR_{\max}$ & $\OCR_{\rm returned}$ & iterations & CPU (s) & outcome\\", r"\hline"]
    for row in rows:
        n = int(row["n"])
        maximum = f"{int(row['OCR_max']):,}".replace(",", r"{,}")
        value = str(row["OCR_returned"]).replace("NA", "---")
        iterations = row["SAT_iters"].replace("NA", "---")
        cpu = "---" if row["SAT_cpu_s"] == "NA" else f"{float(row['SAT_cpu_s']):.2f}"
        outcome = {"exact": "exact", "functional-complement": "functional (complement)",
                   "no-key": "no key at 180 s", "undecided": "undecided"}[row["outcome"]]
        out.append(f"{n} & ${maximum}$ & {value} & {iterations} & {cpu} & {outcome}\\\\")
    out += [r"\hline", r"\end{tabular}",
            r"\caption{\EMPIRICAL{} Historical c432 splice runs at $h=n/2$, reclassified without rerunning SAT. "
            r"Each width uses one key reconstructed from the recorded origin string and delivered seed rule; "
            r"the full keys and that provenance are retained in \texttt{fixtures/tab-resist.tsv}. "
            r"The $n=20,28$ returns are complements, hence functional by Theorem~\ref{thm:complement}, not exact. "
            r"$\OCR_{\max}=2\bin{n}{n/2}$ is the odd/far maximum over key distances, not the corruption "
            r"of the returned key. No-key rows have no returned-key OCR. Timing and iteration counts "
            r"belong to the historical run; timeout is not a defence-success verdict.}",
            f"\\label{{{label}}}", r"\end{table}"]
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("tsv", type=Path)
    ap.add_argument("--reconstruct", action="store_true")
    ap.add_argument("--output", type=Path)
    ap.add_argument("--json", type=Path)
    ap.add_argument("--tex", type=Path)
    ap.add_argument("--label", default="tab:resist")
    args = ap.parse_args()
    rows = reconstruct(args.tsv) if args.reconstruct else read_tsv(args.tsv)
    if args.output:
        write_tsv(args.output, rows)
    if args.json:
        args.json.write_text(json.dumps({"mode": "historical reclassification; no new SAT execution",
                                        "producer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                                        "rows": rows}, indent=2) + "\n")
    if args.tex:
        write_tex(args.tex, render(rows, args.label))


if __name__ == "__main__":
    main()
