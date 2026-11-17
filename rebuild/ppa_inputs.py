"""Rebuild the historical physical comparison inputs from the local golden files."""
import csv
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "experiments/data"
SCRIPTS = ROOT / "experiments/scripts"
rows = list(csv.DictReader((DATA / "processed/p44-ppa-common-flow.tsv").read_text().splitlines(), delimiter="\t"))
if len(rows) != 21:
    raise ValueError("Missing PPA reference cells")
for row in rows:
    host, config = row["host"], row["config"]
    destination = DATA / "raw/p44-ppa" / host / config / "design.bench"
    if host.startswith("c"):
        source = DATA / "configured/sld" / (host + ".bench")
        if config == "unlocked":
            data = source.read_bytes()
        elif config == "SFLL-HD":
            args = [SCRIPTS / "splice_sfll.py", source, DATA / "fixtures/popcount_16_8.bench", "16", "8", "0", "1011001010110010"]
            lines = subprocess.check_output([sys.executable, "-B", *args]).splitlines(keepends=True)
            if not lines[2].startswith(b"# ordered protected inputs = "):
                raise ValueError("Unexpected SFLL serialization")
            data = b"".join(lines[:2] + lines[3:])
        elif config == "XOR-random":
            data = subprocess.check_output([sys.executable, "-B", SCRIPTS / "splice_xor.py", source, "16", host])
        else:
            raise ValueError(config)
    else:
        data = destination.read_bytes()
    if hashlib.sha256(data).hexdigest() != row["sha256_bench"]:
        raise ValueError(f"Input mismatch: {host} {config}")
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    elif destination.read_bytes() != data:
        raise ValueError(destination)
    print(host, config, row["sha256_bench"])
