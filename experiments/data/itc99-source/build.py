"""Convert the bundled CCSL RTL to combinational BENCH using local tools."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
HOSTS = ("b14", "b15", "b17", "b20", "b21", "b22")
P44_HOSTS = {"b14", "b17", "b20"}
ARCHIVE = HERE.parent / "raw/p44-ppa"
LUT_CONVERTER = HERE.parents[1] / "scripts/lut2gate.py"


def check_sources():
    entries = (HERE / "SHA256SUMS").read_text().splitlines()
    expected = {f"ccsl/{host}.v" for host in HOSTS} | {f"polito/{host}.vhd" for host in HOSTS}
    seen = set()
    for line in entries:
        digest, name = line.split("  ", 1)
        if name not in expected or name in seen:
            raise ValueError(f"Unexpected or duplicate source pin: {name}")
        if hashlib.sha256((HERE / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Source digest mismatch: {name}")
        seen.add(name)
    if seen != expected:
        raise ValueError(f"Missing source pins: {sorted(expected - seen)}")


def convert(host, target):
    with tempfile.TemporaryDirectory(prefix=f".{host}-", dir=target.parent) as temp:
        work = Path(temp)
        shutil.copyfile(HERE / "ccsl" / (host + ".v"), work / "design.v")
        synthesis = f"read_verilog design.v; synth -top {host} -flatten; async2sync; dffunmap; write_blif synth.blif"
        subprocess.run(["yosys", "-q", "-p", synthesis], cwd=work, stdout=sys.stderr, check=True)
        mapping = "read_blif synth.blif; comb; strash; short_names; write_bench synth.bench"
        subprocess.run(["yosys-abc", "-q", mapping], cwd=work, stdout=sys.stderr, check=True)
        if not (work / "synth.bench").stat().st_size:
            raise ValueError(f"ABC emitted an empty netlist for {host}")
        with (work / "synth.bench").open("rb") as lut, (work / "output.bench").open("xb") as gates:
            subprocess.run([sys.executable, "-B", str(LUT_CONVERTER)], cwd=work,
                           stdin=lut, stdout=gates, check=True)
        # Validate the actual header and first input before replacing a cache entry.
        netlist_body(host, (work / "output.bench").read_bytes())
        os.replace(work / "output.bench", target)


def netlist_body(host, data):
    head, _, body = data.partition(b"\n")
    pattern = rb'# Benchmark "' + host.encode() + rb'" written by ABC on [A-Za-z0-9: ]+'
    if not re.fullmatch(pattern, head.rstrip(b"\r")) or not body.startswith(b"INPUT("):
        raise ValueError(f"Expected ABC benchmark header and input in {host}.bench")
    return body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="directory for each host.bench")
    parser.add_argument("hosts", nargs="*", help="hosts to convert (default: all six)")
    parser.add_argument("--reuse-existing", action="store_true", help="reuse existing host.bench files")
    parser.add_argument("--require-match", action="store_true", help="exit 1 on a P44 benchmark-body difference")
    args = parser.parse_args()
    hosts = args.hosts or HOSTS
    if any(host not in HOSTS for host in hosts) or len(set(hosts)) != len(hosts):
        parser.error(f"choose unique hosts from {', '.join(HOSTS)}")
    if args.require_match and args.reuse_existing:
        parser.error("--require-match requires a fresh conversion")
    if args.require_match and not P44_HOSTS.intersection(hosts):
        parser.error("--require-match needs at least one host with a P44 reference")
    check_sources()
    args.output.mkdir(parents=True, exist_ok=True)
    all_match = True
    for host in hosts:
        target = args.output / (host + ".bench")
        if target.exists() and not args.reuse_existing:
            parser.error(f"Output exists: {target}. Choose a fresh directory.")
        cached = target.exists()
        if not cached:
            convert(host, target)
        data = target.read_bytes()
        body = netlist_body(host, data)
        archived = ARCHIVE / host / "unlocked/design.bench"
        row = dict(host=host, cached=cached, bytes=len(data),
                   sha256=hashlib.sha256(data).hexdigest(), body_sha256=hashlib.sha256(body).hexdigest(),
                   p44_body_match=None)
        if host in P44_HOSTS:
            reference = netlist_body(host, archived.read_bytes())
            row.update(p44_body_match=body == reference, p44_body_sha256=hashlib.sha256(reference).hexdigest())
            all_match = all_match and row["p44_body_match"]
        print(json.dumps(row), flush=True)
    return int(args.require_match and not all_match)


if __name__ == "__main__":
    sys.exit(main())
