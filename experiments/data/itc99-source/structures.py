"""Reconstruct retained ITC circuit files from shipped, editable circuit inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
DATA = HERE.parent
RAW = DATA / "raw"
SCRIPTS = DATA.parent / "scripts"
sys.path[:0] = [str(SCRIPTS), str(DATA.parent / "analysis")]
from sim_po_cone import cone_support, driver_map, parse as parse_lut
from bench_io import parse as parse_bench
from ppa_ports import output_adapter
from ppa_flow import emit

LIB_SHA = "2efd0b32eb580e4e60e72fc0575bb3bc69aac907c91d908442e4ae6d7fe55895"


def canonical(path, kind):
    data = path.read_bytes()
    if kind == "bytes":
        return data
    header, sep, data = data.partition(b"\n")
    marker = b"//" if kind == "verilog" else b"#"
    if not sep or not re.fullmatch(marker + rb' Benchmark "[^"\r\n]+" written by ABC on [A-Za-z0-9 :]+', header):
        raise ValueError(f"Unexpected ABC header in {path}")
    if kind == "blif":
        model, sep, data = data.partition(b"\n")
        if not sep or not re.fullmatch(rb"\.model \S+", model):
            raise ValueError(f"Unexpected BLIF model in {path}")
    if kind == "verilog" and path.name == "mapped.v":
        data, count = re.subn(rb'(?m)^module [^\s(]+\s*\(', b'module top (', data, count=1)
        if count != 1:
            raise ValueError(f"Unexpected module name in {path}")
    return data


def compare(generated, frozen, kind="bytes"):
    actual = canonical(generated, kind)
    expected = canonical(frozen, kind)
    matched = actual == expected
    print(json.dumps(dict(file=str(frozen.relative_to(DATA)), comparison=kind, match=matched,
                          generated_sha256=hashlib.sha256(actual).hexdigest(),
                          frozen_sha256=hashlib.sha256(expected).hexdigest())), flush=True)
    if not matched:
        raise ValueError(f"Circuit comparison failed: {frozen}")


def run_to(command, out):
    with out.open("xb") as stream:
        subprocess.run(command, stdout=stream, check=True)


def abc(cwd, command):
    subprocess.run(["yosys-abc", "-q", command], cwd=cwd, stdout=sys.stderr, check=True)


def p44(work, host, original):
    directory = work / host
    directory.mkdir()
    frozen = RAW / "p44-ppa" / host
    compare(original, frozen / "unlocked/design.bench", "bench")
    sfll = directory / "sfll.bench"
    run_to([sys.executable, SCRIPTS / "splice_sfll.py", original, DATA / "fixtures/popcount_16_8.bench",
            "16", "8", "0", "1011001010110010"], sfll)
    # The submitted splicer prints one additional metadata line since the August run.
    lines = sfll.read_bytes().splitlines(keepends=True)
    if not lines[2].startswith(b"# ordered protected inputs = "):
        raise ValueError("Unexpected splicer header")
    sfll.write_bytes(b"".join(lines[:2] + lines[3:]))
    compare(sfll, frozen / "SFLL-HD/design.bench")
    xor = directory / "xor.bench"
    run_to([sys.executable, SCRIPTS / "splice_xor.py", original, "16", host], xor)
    compare(xor, frozen / "XOR-random/design.bench")
    return {"unlocked": original, "SFLL-HD": sfll, "XOR-random": xor}


def map_circuits(directory, host, designs, lib):
    for config, design in designs.items():
        cwd = directory / config
        cwd.mkdir()
        shutil.copyfile(lib, cwd / "cells.lib")
        shutil.copyfile(design, cwd / "design.bench")
        adapted, _ = output_adapter(parse_bench(design.read_text()))
        (cwd / "port-adapted.bench").write_text(emit(adapted))
        for cohort, source in [("revision-20260918", "design.bench"),
                               ("submitted-ppa-20261110", "port-adapted.bench")]:
            abc(cwd, f"read_lib cells.lib; read_bench {source}; strash; dch; map; topo; stime; print_stats; write_verilog mapped.v")
            mapped = cwd / "mapped.v"
            archived = RAW / cohort / "power" / host / config
            if cohort == "revision-20260918":
                compare(mapped, archived / "mapped.v", "verilog")
            content, count = re.subn(r"\bmodule\s+\S+\s*\(", "module top (", mapped.read_text(), count=1)
            if count != 1:
                raise ValueError(f"Missing module in {mapped}")
            top = cwd / "top.v"
            top.write_text(content)
            compare(top, archived / "top.v", "verilog")
            # Never let a later ABC failure reuse an earlier netlist.
            mapped.unlink()


def named_cone(lut, co, fixed, script_cone, dest):
    inputs, _, gates = parse_lut(lut)
    support = cone_support(co, driver_map(gates), set(inputs))
    content = fixed.read_text()
    output = re.search(r"OUTPUT\((w\d+)\)", content).group(1)
    content = re.sub(r"\b" + output + r"\b", co, content)
    content = re.sub(r"\bw(\d+)\b", lambda m: support[int(m[1])] if int(m[1]) < len(support) else m[0], content)
    declared = set(re.findall(r"(?m)^INPUT\(([^)]+)\)", content))
    extra = [w for w in re.findall(r"(?m)^INPUT\(([^)]+)\)", script_cone.read_text()) if w not in declared]
    if extra:
        lines = content.splitlines()
        last = max(i for i, line in enumerate(lines) if line.strip().startswith(("INPUT(", "OUTPUT(")))
        lines[last + 1:last + 1] = [f"INPUT({w})" for w in extra]
        content = "\n".join(lines) + "\n"
    dest.write_text(content)


def cones(directory, host, emitter, original):
    reference = RAW / "p49-cone-cec" / host
    lut = directory / "lut2.bench"
    shutil.copyfile(original, directory / "unlocked.bench")
    abc(directory, "read_bench unlocked.bench; strash; if -K 2; write_bench lut2.bench")
    compare(lut, HERE / "lut2" / (host + "_lut2.bench"), "bench")
    flat = directory / "host.flat"
    run_to([sys.executable, SCRIPTS / "gen_netlist_data.py", "--flat", lut], flat)
    compare(flat, reference / "host.flat")
    co = {"b14": "po117", "b20": "po053"}[host]
    inputs, outputs, gates = parse_lut(lut)
    width = len(cone_support(co, driver_map(gates), set(inputs)))
    secret = ("10110010" * (width // 8 + 1))[:width]
    abc(directory, f"read_bench lut2.bench; cone -O {outputs.index(co)}; write_bench cone_script.bench")
    script_cone = directory / "cone_script.bench"
    compare(script_cone, reference / "cone_script.bench", "bench")
    locked = directory / "locked.bench"
    run_to([emitter, "emitlockhostflat", flat, "0", secret], locked)
    compare(locked, reference / "locked.bench")
    fixed = directory / "cone_agda.bench"
    subprocess.run([sys.executable, HERE / "fix_wires.py", locked, str(width), secret, fixed], check=True)
    compare(fixed, reference / "cone_agda.bench")
    named = directory / "cone_agda_named.bench"
    named_cone(lut, co, fixed, script_cone, named)
    compare(named, reference / "cone_agda_named.bench")
    for key, bits in [("k1", "10110010"), ("k2", "01001101")]:
        for route, argv in [("unfused", ["emitlockhostflat", flat, "0", bits]),
                            ("fused", ["emitlockhostflatmerged", flat, bits])]:
            name = f"{host}_{key}_{route}_emitted.bench"
            net = directory / name
            run_to([emitter, *argv], net)
            compare(net, RAW / "p40-decode" / host / key / route / "emitted.bench")
            abc(directory, f"read_bench {name}; print_stats; strash; write_blif {name}.blif")
            compare(directory / (name + ".blif"), RAW / "p47-readers" / (name + ".blif"), "blif")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new directory for generated circuits")
    parser.add_argument("--emitter", type=Path, required=True, help="compiled artifact extract/Main")
    parser.add_argument("--hosts-dir", type=Path, help="fresh build.py output; default uses retained P44 hosts")
    parser.add_argument("--lib", type=Path, help="pinned Nangate45 Liberty for physical mapping")
    args = parser.parse_args()
    if args.lib and hashlib.sha256(args.lib.read_bytes()).hexdigest() != LIB_SHA:
        parser.error("Liberty differs from the archived Nangate45 pin")
    args.output.mkdir(parents=True, exist_ok=False)
    for host in ("b14", "b17", "b20"):
        original = (args.hosts_dir / (host + ".bench") if args.hosts_dir
                    else RAW / "p44-ppa" / host / "unlocked/design.bench")
        designs = p44(args.output, host, original)
        directory = args.output / host
        if host in {"b14", "b20"}:
            cones(directory, host, args.emitter.resolve(), original)
        if args.lib:
            map_circuits(directory, host, designs, args.lib)


if __name__ == "__main__":
    main()
