"""Rebuild archived interface records from locally acquired circuit declarations."""
import json
from pathlib import Path
import re
import subprocess
import sys


def ports(bench, direction):
    pattern = rf"(?m)^{direction}\(([^)]+)\)\s*$"
    return re.findall(pattern, bench.read_text())


def numeric(name):
    return int(re.sub(r"\D", "", name))


def c17_records(rtl, norm):
    inputs, outputs = ports(norm, "INPUT"), ports(norm, "OUTPUT")
    gates = []
    for op, args in re.findall(r"(?m)^\s*(nand)\s+\w+\s*\(([^()]+)\)\s*;", rtl):
        out, *ins = [w.strip() for w in args.split(",")]
        gates.append(f"{out}={op.upper()}({','.join(ins)})")
    if not gates or not outputs:
        raise ValueError("No gates or output declarations found in the pinned c17 sources")
    rule = f"identity: the classic netlist uses the normalized port names (PI {' '.join(inputs)}, PO {' '.join(outputs)})"
    corr = dict(host="c17", golden="c17-classic", rule=rule,
                source="configured_check.py C17_CLASSIC: " + " ".join(gates),
                verified="cec EQ against the normalized c17.bench (tests/check_builtin_goldens.py)",
                norm="../data/configured/norm/c17.bench")
    order = ",".join(w.lower() for w in inputs)
    pmap = dict(route="compile-time: Main emitlockhost c17 <h> <bits>", out=outputs[-1],
                n=len(inputs), support=inputs,
                source=f"W4-certified-gamma.py: 'The order of toList x is [{order}]'; reproduces W4 on the frozen p40 c17 bytes")
    return corr, pmap


def multiplier(norm):
    ins = sorted(ports(norm, "INPUT"), key=numeric)
    out = sorted(ports(norm, "OUTPUT"), key=numeric)
    if len(ins) != 32 or len(out) != 32:
        raise ValueError("Unexpected multiplier interface")
    out[-2], out[-1] = out[-1], out[-2]
    return dict(host="c6288", golden="mult16x16", A=ins[:16], B=ins[16:], P=out,
                rule=f"P = A * B, unsigned; A and B listed lsb first; P listed p0..p31 (p30 = {out[-2]}, p31 = {out[-1]})",
                source="plan section 3 (no sld original exists); ports derived in the pilot (c6288_arith2.py) from the support chains",
                verified="random/edge simulation of the normalized c6288.bench against the integer product, all 32 outputs (tests/check_builtin_goldens.py)",
                norm="../data/configured/norm/c6288.bench")


def io_map(golden, norm, host):
    by_number = host in {"c1355", "c2670", "c7552"}
    pairs = []
    for direction in ("INPUT", "OUTPUT"):
        left = ports(golden, direction)
        right = ports(norm, direction)
        if len(left) != len(right) or len(set(left)) != len(left) or len(set(right)) != len(right):
            raise ValueError(f"Invalid {host} {direction} correspondence")
        pairs.append(dict(zip(left, sorted(right, key=numeric) if by_number else right)))
    negated = host == "c1355"
    record = {"po_negated": True} if negated else {}
    record.update(host=host, pi=pairs[0], po=pairs[1],
                  verified="cec EQ only after inverting every sld PO (no pure port bijection exists)" if negated else "cec EQ",
                  abc="UC Berkeley, ABC 1.01 (compiled Aug  5 2026 05:43:12)",
                  sld=f"../data/configured/sld/{host}.bench", norm=f"../data/configured/norm/{host}.bench",
                  rule="sld declaration order <-> norm " + ("names sorted by numeric part" if by_number else "declaration order"))
    return record


def write_record(path, record, newline):
    path.write_bytes((json.dumps(record, indent=1) + newline).encode())


def rebuild(data, stage, release, pins, rtl, check_hash):
    # The historical JSON's version and verification annotations are restored
    # metadata. This operation compares the resulting bytes to the prior digest.
    cfg = data / "configured"
    corr, pmap = c17_records(rtl.decode(), cfg/"norm/c17.bench")
    for name, expected in pins.items():
        dest = data / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        host, *selector = dest.stem.split("_")
        norm = cfg / "norm" / f"{host}.bench"
        if dest.parent.name == "corr":
            if host == "c17":
                write_record(dest, corr, "\n")
            elif host == "c6288":
                write_record(dest, multiplier(norm), "\n")
            else:
                write_record(dest, io_map(cfg/"sld"/f"{host}.bench", norm, host), "")
        elif selector[-1] == "compiletime":
            write_record(dest, pmap, "\n")
        else:
            filename = host + ("_dc2" if selector[-1] == "dc2" else "") + "_lut2.bench"
            if host == "c432":
                filename = f"{host}.bench"
            literal = data/"benchmarks/iscas85"/filename
            bench = literal if literal.is_file() else cfg/"lut2"/filename
            arg = "../data/" + bench.relative_to(data).as_posix()
            subprocess.run([sys.executable, "-B", str(release/"experiments/scripts/gen_netlist_data.py"),
                            "--flat", arg, "--out", selector[0], "--portmap", str(dest)],
                           cwd=stage/"experiments/scripts", stdout=subprocess.DEVNULL, check=True)
        check_hash(dest.read_bytes(), expected, name)
