"""Re-emit the 22 configured Tier S4 DUTs and repeat their recorded functional I/O simulations."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
REBUILD = HERE.parent
ROOT = REBUILD.parent
DATA = ROOT / "experiments/data"
sys.path.insert(0, str(REBUILD))
sys.path.insert(0, str(REBUILD / "agda"))
import exhaustive as E
from c17 import verilog
from s4_sampler import run_sim


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, msg):
    if not condition:
        raise ValueError(msg)


def extra_independence(golden, work):
    """Prove that unbound golden inputs do not affect the selected output."""
    if not golden.extra:
        return 0
    primary = {wire: f"x{pos}" for wire, pos in golden.leaf_pos.items()}
    for fixed in (False, True):
        names = primary.copy()
        lines = [f"INPUT({name})" for name in sorted(set(names.values()))]
        for i, wire in enumerate(golden.extra):
            lines.append(f"INPUT(e{i})")
            names[wire] = "zero" if fixed else f"e{i}"
        lines += ["OUTPUT(y)", "zero = XOR(x0,x0)"]
        for i, (dest, op, args, code) in enumerate(golden.gates):
            require(code is None and op in ("BUF","NOT","NOR","NAND","AND","OR","XOR","XNOR"),
                    f"unexpected golden operation {op}")
            operands = ", ".join(names[arg] for arg in args)
            names[dest] = f"g{i}"
            lines.append(f"g{i} = {'BUFF' if op=='BUF' else op}({operands})")
        lines.append(f"y = BUFF({names[golden.target]})")
        (work/f"extra{int(fixed)}.bench").write_text("\n".join(lines) + "\n")
    abc = shutil.which("yosys-abc")
    require(abc is not None, "yosys-abc is needed for the redundant golden inputs")
    proc = subprocess.run([abc, "-c", "cec extra0.bench extra1.bench"], cwd=work, check=True,
                          capture_output=True, text=True, timeout=180)
    require("Networks are equivalent" in proc.stdout, "extra golden inputs did not pass equivalence")
    return len(golden.extra)


def prepare(row, rtl, maps, work):
    host, out = row["host"], row["out"]
    pm = json.loads(maps[row["portmap_sha256"]].read_bytes())
    require(pm["out"] == out and len(pm["support"]) == row["n"], f"wrong port map for {host}")
    corr = DATA / "configured/corr" / (host + ".json")
    require(sha(corr) == row["corr_sha256"], f"correspondence changed for {host}")
    tool = ROOT / "experiments/scripts/gen_netlist_data.py"
    flat = work / (host + ".flat")
    with flat.open("wb") as stream:
        subprocess.run([sys.executable, "-B", tool, "--flat", pm["bench"], "--out", out],
                       cwd=tool.parent, check=True, stdout=stream)
    require(sha(flat) == row["flat_sha256"], f"regenerated flat bytes differ for {host}")
    if host == "c17":
        pins = json.loads((REBUILD/"inputs/pins.json").read_bytes())
        require(sha(rtl) == pins["sources"]["v/c17.v"]["sha256"], "c17 RTL differs from the source pin")
        ins, outs, gates = verilog(rtl)
        require(out in outs, "missing c17 output")
        golden = E.Golden("rtl", [(w, op, list(args), None) for w, op, args in gates], out, False,
                          {name:i for i,name in enumerate(pm["support"])}, str(rtl), sha(rtl),
                          host, source_inputs=set(ins))
    else:
        golden = E.load_golden(json.loads(corr.read_bytes()), pm, str(DATA/"configured/sld"/(host + ".bench")))
        if row["golden_source_sha256"] is not None:
            require(golden.source_sha256 == row["golden_source_sha256"], f"independent golden changed for {host}")
    extra = extra_independence(golden, work)
    return pm, flat, golden, extra


def replay(main, rtl, output, requested):
    require(not output.exists(), "choose a new receipt path")
    rows = json.loads((HERE/"s4-records.json").read_bytes())
    with (DATA/"processed/p53-iscas-configured.tsv").open(newline="") as stream:
        public = {r["config"]:r for r in csv.DictReader(stream, delimiter="\t")
                  if (r["tier"], r["call"], r["counted"]) == ("S","sim","yes")}
    all_ids = {row["config"] for row in rows}
    require(len(rows) == 22 and all_ids == set(public), "S4 case population differs from the processed TSV")
    require(not set(requested)-all_ids, f"unknown S4 case: {sorted(set(requested)-all_ids)}")
    maps = {sha(p):p for p in (DATA/"configured/portmaps").glob("*.json")}
    require(maps, "restore the configured inputs before running S4")
    results = []
    with tempfile.TemporaryDirectory() as folder:
        work = Path(folder)
        cache = {}
        for row in rows:
            config = row["config"]
            if requested and config not in requested:
                continue
            known = public[config]
            require(row["dut_sha256"] == known["dut_sha256"] and row["h"] == int(known["h"]) and
                    row["n"] == int(known["n"]) and row["out"] == known["out"] and row["host"] == known["host"],
                    f"public data disagree for {config}")
            key = tuple(row[k] for k in ("host","out","portmap_sha256","corr_sha256","flat_sha256","golden_source_sha256"))
            if key not in cache:
                cache[key] = prepare(row, rtl, maps, work)
            pm, flat, golden, extra = cache[key]
            dut = work/"current.bench"
            with dut.open("wb") as stream:
                subprocess.run([main, "emitlockhostflat", flat, str(row["h"]), row["planted"]], check=True, stdout=stream)
            require(sha(dut)==row["dut_sha256"], f"emitted bytes differ for {config}")
            case = E.Case(E.read_bench(str(dut)), pm, golden, row["planted"], row["h"])
            count = row["expected"]["xcheck_main"]
            use_main = count != "NA"
            observed, checks, details = run_sim(case, row["seed"], row["vectors"], row["scalar_samples"],
                                                main_bin=str(main) if use_main else None,
                                                main_samples=int(count) if use_main else 0, emitted_path=str(dut))
            require(observed == row["expected"], f"{config}: simulation differs: {observed}, {details}")
            require(all(x==y for _,x,y in checks) and details["xcheck_positions"] == row["positions"],
                    f"{config}: cross-check or sample positions differ")
            for k in ("mismatches","mismatches_targeted","xcheck_sim_bench","xcheck_sim_bench_bad","xcheck_main","xcheck_main_bad"):
                require(str(observed[k]) == known[k], f"{config}: processed TSV differs for {k}")
            results.append(dict(config=config, independent_extra_inputs=extra, dut_sha256=row["dut_sha256"], **observed))
            print(f"{config}: {observed['vectors_random']} random + {observed['vectors_targeted']} targeted, "
                  f"{observed['xcheck_sim_bench']} scalar Python, {count} scalar Main", flush=True)
    keys = tuple(rows[0]["expected"])
    totals = {k:sum(r[k] for r in results if r[k] != "NA") for k in keys}
    receipt = dict(status="PASS", cases=len(results), all_cases=len(rows), main_sha256=sha(main),
                   full_case_set=len(results)==len(rows), totals=totals, results=results)
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open("x") as stream:
        json.dump(receipt, stream, indent=2)
        stream.write("\n")
    print(json.dumps({"cases":len(results),"totals":totals}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main", required=True, type=Path)
    parser.add_argument("--rtl", required=True, type=Path, help="restored original c17.v")
    parser.add_argument("--out", required=True, type=Path, help="new JSON receipt")
    parser.add_argument("--case", action="append", default=[], help="restrict to a named S4 config, e.g. S.c17.N22.k1")
    opts = parser.parse_args()
    replay(opts.main.resolve(), opts.rtl.resolve(), opts.out.resolve(), opts.case)
