"""Identify user-supplied paired study files by host, role, byte length and SHA-256."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import sys


TABLE = Path(__file__).with_name("paired-file-identities.tsv")
HOSTS = ("c6288", "c1355", "c5315", "c7552")
ROLES = ("native_output", "historical_structure", "run003_certified", "run003_splice")


def load_table():
    entries = {}
    with TABLE.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != ["host", "role", "bytes", "sha256"]:
            raise ValueError("Invalid checksum table columns")
        for row in reader:
            key = row["host"], row["role"]
            if (None in row or key in entries or not re.fullmatch(r"[1-9][0-9]*", row["bytes"] or "")
                    or not re.fullmatch(r"[0-9a-f]{64}", row["sha256"] or "")):
                raise ValueError(f"Invalid checksum table row: {key}")
            entries[key] = {"bytes": int(row["bytes"]), "sha256": row["sha256"]}
    if set(entries) != {(host, role) for host in HOSTS for role in ROLES}:
        raise ValueError("Incomplete or unexpected host/role set")
    return entries


def file_identity(path):
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""):
            size += len(chunk)
            digest.update(chunk)
    return {"bytes": size, "sha256": digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", nargs=3, action="append", default=[], metavar=("HOST", "ROLE", "FILE"))
    parser.add_argument("--output", type=Path, help="Write JSON to a new file (default: stdout)")
    args = parser.parse_args()
    table = load_table()
    supplied = {}
    for host, role, filename in args.file:
        key = host, role
        if key not in table or key in supplied:
            parser.error(f"Unknown or repeated host/role: {key}")
        path = Path(filename)
        if not path.is_file():
            parser.error(f"Supplied path is not a regular file: {path}")
        supplied[key] = path
    rows = []
    for key, expected in table.items():
        actual = file_identity(supplied[key]) if key in supplied else None
        status = "unchecked"
        if actual is not None:
            status = "match" if actual == expected else "mismatch"
        rows.append(dict(host=key[0], role=key[1], expected=expected, observed=actual, status=status))
    payload = json.dumps({"rows": rows}, indent=2) + "\n"
    if args.output is None:
        sys.stdout.write(payload)
    else:
        with args.output.open("x", encoding="utf-8") as stream:
            stream.write(payload)
    return int(any(row["status"] == "mismatch" for row in rows))


if __name__ == "__main__":
    raise SystemExit(main())
