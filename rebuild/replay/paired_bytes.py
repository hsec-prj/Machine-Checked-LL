"""Measure the paired regression components and optionally identify supplied local files."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from paired_functional import ROW_PIN, checked

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_SHA = "01caed62c3f703425b331383d1b58785dc8a3e42b83152f86c5f8bdec2e6c7ce"


def identity(stream):
    digest = hashlib.sha256()
    size = 0
    for chunk in iter(lambda: stream.read(65536), b""):
        digest.update(chunk)
        size += len(chunk)
    return {"bytes": size, "sha256": digest.hexdigest()}


def file_identity(path):
    with path.open("rb") as stream:
        return identity(stream)


def measure(command):
    with subprocess.Popen(command, stdout=subprocess.PIPE) as process:
        result = identity(process.stdout)
        if process.wait():
            raise ValueError(f"Regression command failed: {command[1]}")
    return result


def catalog():
    cases = json.loads(checked(ROOT / "rebuild/replay/paired-functions.json", ROW_PIN))
    with (ROOT / "experiments/data/processed/p412-paired.tsv").open() as stream:
        table = list(csv.DictReader(stream, delimiter="\t"))
    original = {(r["host"], r["path"]): r["input_sha256"] for r in table}
    seen = set()
    for case in cases:
        for route, kind in (("certified", "native_intermediate"), ("splice", "standalone_comparator")):
            key = case["host"], route
            spec = case["routes"][route]
            if (key in seen or original.get(key) != spec["input_sha256"]
                    or spec["prerequisite"]["kind"] != kind
                    or spec["prerequisite"]["sha256"] == spec["input_sha256"]):
                raise ValueError(f"Historical identity or stage conflict: {key}")
            seen.add(key)
    if len(seen) != 8 or len(table) != 8 or set(original) != seen:
        raise ValueError("Expected the eight distinct paired rows")
    return cases, seen


def components(case, flat):
    host = case["host"]
    width = case["width"]
    lut = ROOT / f"experiments/data/benchmarks/iscas85/{host}_lut2.bench"
    if file_identity(lut)["sha256"] != case["source_sha256"]["literal_bench"]:
        raise ValueError(f"Source identity: {host}")
    script = ROOT / "experiments/scripts/gen_netlist_data.py"
    with flat.open("wb") as stream:
        subprocess.run([sys.executable, "-B", script, "--flat", lut, "--out", case["output"]],
                       cwd=script.parent, stdout=stream, check=True)
    if file_identity(flat)["sha256"] != case["flat_sha256"]:
        raise ValueError(f"Flat identity: {host}")
    main = ROOT / "experiments/extract/_bin/Main"
    # Width-only synthetic argument from the pinned general ITC regression.
    argument = ("10110010" * (width // 8 + 1))[:width]
    return {"certified": measure([main, "emitlockhostflat", flat, "0", argument]),
            "splice": measure([main, "popcount", str(width), "0"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--final", nargs=3, action="append", default=[], metavar=("HOST", "ROUTE", "FILE"))
    args = parser.parse_args()
    cases, keys = catalog()
    supplied = {}
    for host, route, name in args.final:
        key = host, route
        if key not in keys or key in supplied:
            parser.error(f"Unknown or repeated row {key}")
        supplied[key] = Path(name)
    fixture = ROOT / "experiments/data/itc99-source/structures.py"
    if file_identity(fixture)["sha256"] != FIXTURE_SHA:
        raise ValueError("Unexpected general regression source")
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for case in cases:
            observed = components(case, Path(tmp) / "host.flat")
            for route, measured in observed.items():
                host = case["host"]
                spec = case["routes"][route]
                pin = spec["prerequisite"]
                expected = {k: pin[k] for k in ("bytes", "sha256")}
                final = {"bytes": spec["final_bytes"], "sha256": spec["input_sha256"]}
                supplied_path = supplied.get((host, route))
                actual = file_identity(supplied_path) if supplied_path is not None else None
                final_status = "unchecked" if actual is None else ("match" if actual == final else "mismatch")
                rows.append(dict(host=host, route=route, kind=pin["kind"],
                                 prerequisite_expected=expected, prerequisite_observed=measured,
                                 prerequisite_status="match" if expected == measured else "mismatch",
                                 final_expected=final, final_supplied=actual, final_status=final_status))
    with args.output.open("x") as stream:
        json.dump({"campaign": "paired-run003", "rows": rows}, stream, indent=2)
        stream.write("\n")
    for row in rows:
        print(row["host"], row["route"], row["prerequisite_status"], row["final_status"])
    return int(any(r["prerequisite_status"] != "match" or r["final_status"] == "mismatch" for r in rows))


if __name__ == "__main__":
    raise SystemExit(main())
