"""Measure four key-free reference circuits using the historical analysis converter."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ARTIFACT = HERE.parents[1]
CONVERTER = HERE / "lut2gate.py"
CONVERTER_SHA = "256dfa184670448f5edf463896848b3e0dc5e3d98a3568b8847593e71544dd0b"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identity(data, output):
    header, lf, body = data.partition(b"\n")
    if not lf or not header.startswith(b"# Benchmark ") or outputs(body) != [output]:
        raise ValueError("Unexpected reference circuit format")
    return dict(bytes=len(data), sha256=sha(data), body_bytes=len(body), body_sha256=sha(body),
                first_line=header.decode("utf-8"))


def outputs(data):
    return re.findall(rb"(?m)^OUTPUT\(([^)]+)\)[ \t]*\r?$", data)


def measure(case, data_dir, abc, historical_comment):
    host = case["host"]
    output = case["output"].encode()
    bench = (data_dir / "benchmarks/iscas85" / (host + "_lut2.bench")).read_bytes()
    labels = outputs(bench)
    if sha(bench) != case["source_sha256"]["literal_bench"] or labels.count(output) != 1:
        raise ValueError("Unexpected restored source for " + host)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / "source.bench").write_bytes(bench)
        index = labels.index(output)
        command = f"read_bench source.bench; cone -O {index}; strash; write_bench cone.bench"
        subprocess.run([abc, "-q", command], cwd=work, check=True)
        subprocess.run([sys.executable, "-B", CONVERTER, "--lsb-first", "cone.bench", "reference.bench"],
                       cwd=work, check=True)
        lut = identity((work / "cone.bench").read_bytes(), output)
        path = work / "reference.bench"
        fresh = path.read_bytes()
        final = identity(fresh, output)
        if not re.fullmatch(r'# Benchmark "[^"\r\n]+" written by ABC on [^\r\n]+', historical_comment):
            raise ValueError("Invalid ABC comment for " + host)
        restored_bytes = historical_comment.encode("ascii") + b"\n" + fresh.partition(b"\n")[2]
        path.write_bytes(restored_bytes)
        restored = identity(path.read_bytes(), output)
        cec = subprocess.check_output([abc, "-q", "cec cone.bench reference.bench"], cwd=work, text=True)
        if "Networks are equivalent" not in cec or "NOT EQUIVALENT" in cec:
            raise ValueError("Reference conversion failed equivalence check for " + host)
    return dict(host=host, output=case["output"], lut=lut, reference=final, restored_reference=restored, local_cec="EQ")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=ARTIFACT / "experiments/data",
                        help="Restored experiments/data directory")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if sha(CONVERTER.read_bytes()) != CONVERTER_SHA:
        raise ValueError("Historical converter identity changed")
    abc = shutil.which("abc")
    if abc is None:
        parser.error("Standalone abc must be available on PATH")
    cases = json.loads((ARTIFACT / "rebuild/replay/paired-functions.json").read_bytes())
    if len(cases) != 4 or {r["host"] for r in cases} != {"c6288", "c1355", "c5315", "c7552"}:
        raise ValueError("Unexpected host catalog")
    comments = json.loads((HERE / "abc-comments.json").read_bytes())
    if set(comments) != {c["host"] for c in cases}:
        raise ValueError("Historical comment population differs")
    result = dict(converter_sha256=CONVERTER_SHA, abc_sha256=sha(Path(abc).read_bytes()),
                  abc_version=subprocess.check_output([abc, "-q", "version"], text=True).strip(),
                  python=sys.version.split()[0], rows=[measure(c, args.data, abc, comments[c["host"]]) for c in cases])
    with args.output.open("x") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")


if __name__ == "__main__":
    main()
