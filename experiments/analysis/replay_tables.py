"""Rebuild the 327 historical P53 rows and 13 table files into a fresh output directory."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile

import configured_facts
import regenerate_tables

DATA = Path(__file__).resolve().parents[1] / "data"


def replay(output):
    output = output.resolve()
    if output.exists():
        raise ValueError(f"choose a new output directory: {output}")
    root = DATA.parents[1]
    if root in output.parents or output == root:
        raise ValueError("choose an output directory outside the artifact")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temp:
        stage = Path(temp) / "result"
        rows = configured_facts.build_rows(DATA / "p53-facts")
        serialized = configured_facts.render(rows)
        name = "p53-iscas-configured.tsv"
        if len(rows) != 327 or (DATA / "processed" / name).read_bytes() != serialized:
            raise ValueError("the 327 reconstructed P53 rows differ from the historical TSV")
        regenerate_tables.tables(stage)
        expected = json.loads((DATA / "table-output-sha256.json").read_bytes())
        actual = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in stage.iterdir()}
        if len(actual) != 13 or actual != expected:
            raise ValueError("generated table filenames or digests differ from the 13 historical references")
        (stage / name).write_bytes(serialized)
        stage.rename(output)
    print("Verified 327 P53 rows byte for byte and 13 table files by SHA-256.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    replay(parser.parse_args().output)
