"""Compare fresh P44 measurement cells and complete port checks with the paper data."""
import argparse
import csv
from decimal import Decimal
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
METRICS = ("cells","area_um2","delay_ps","internal_W","switching_W","leakage_W","total_W")


def rows(path):
    with path.open() as stream:
        records = list(csv.DictReader(stream,delimiter="\t"))
    by_cell = {(r["host"],r["config"]):r for r in records}
    if len(records) != 21 or len(by_cell) != len(records):
        raise ValueError("Expected 21 distinct cells")
    return by_cell


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tsv",type=Path)
    parser.add_argument("measurement_dir",type=Path)
    args = parser.parse_args()
    old = rows(ROOT/"experiments/data/processed/p44-ppa-common-flow.tsv")
    new = rows(args.tsv)
    if old.keys() != new.keys():
        raise ValueError("Different host or configuration")
    summary=[]
    for key, baseline in old.items():
        row = new[key]
        if baseline["sha256_bench"] != row["sha256_bench"]:
            raise ValueError(f"Different input for {key}")
        result = json.loads((args.measurement_dir/key[0]/key[1]/"result.json").read_bytes())
        if not (result["full_port_checks"] and result["required_checks_complete"]):
            raise ValueError(f"Missing comparison gates for {key}")
        differences={k:[baseline[k],row[k]] for k in METRICS if Decimal(baseline[k])!=Decimal(row[k])}
        summary.append(dict(host=key[0],config=key[1],different_metrics=differences,
                            gates={k:v["verdict"] for k,v in result["gates"].items()}))
    print(json.dumps(summary,indent=1))
    if any(cell["different_metrics"] for cell in summary):
        raise SystemExit(1)
