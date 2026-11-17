"""Reproduce the registered functional conformance and mutation controls for the supplied test fixtures."""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

import s4
import sm_kernel as kernel
from sm_mutations import mutant_bytes
from c6288_bridge import verify_bridge

HERE = Path(__file__).resolve().parent
DATA = HERE.parents[1] / "experiments/data"
ROWS_HASH = "24d9bf040ac9d0461609f4b55f43f1c7f2f1371f9187fb30d8215bf6e600480f"
FIELDS = {
    "golden": ("S1", "S2", "S6_dc2", "S6_if6", "golden_extra", "golden_extra_independent"),
    "miter": ("Q0", "Q1", "Q2", "Q3", "P0", "P1", "P2", "P3"),
    "controls": ("neg_keys", "neg_NEQ", "neg_cex_in_sk", "neg_cex_unparsed", "neg_positions_EQ", "neg_sim_sk_ok",
                 "pos_k_eq_s", "flip_secret", "swap_pair", "swap_golden"),
    "pair": ("cec_unfused_fused", "decoded_eq_secret", "payload_full_ok", "fused_payload_ok"),
}


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def historical():
    result = {}
    for tier in ("S", "M"):
        idx, = (DATA / "p53-facts").glob(f"index-tier{tier}-*.tsv")
        with idx.open(newline="") as stream:
            for r in csv.DictReader(stream, delimiter="\t"):
                if r["call"] == "sim":
                    continue
                suffix = ".r1" if r["attempt_dir"].endswith("/r1") else ""
                label = f"{r['config']}.{r['call']}{suffix}"
                require(label not in result, "duplicate historical attempt")
                result[label] = r
    return result


class Fixtures:
    def __init__(self, work, main, rtl):
        self.work, self.main, self.rtl = work, main, rtl
        self.maps = {s4.sha(p):p for p in (DATA/"configured/portmaps").glob("*.json")}
        self.records = {r["config"]:r for r in json.loads((HERE/"s4-records.json").read_bytes())}
        self.prepared, self.emissions, self.bridges = {}, {}, {}

    def load(self, job):
        config = job["fixture"]
        r = self.records[config]
        require((r["host"], r["out"], r["h"]) == (job["host"], job["out"], 0), "unexpected fixture")
        if config not in self.prepared:
            work = self.work / config
            work.mkdir()
            pm, flat, golden, extra = s4.prepare(r, self.rtl, self.maps, work)
            self.prepared[config] = work, pm, flat, golden, extra
        work, pm, flat, golden, extra = self.prepared[config]
        if config not in self.emissions:
            unfused, fused = work/"unfused.bench", work/"fused.bench"
            for path, args, pin in [(unfused, ["emitlockhostflat", flat, "0", r["planted"]], r["dut_sha256"]),
                                    (fused, ["emitlockhostflatmerged", flat, r["planted"]], job["fused_sha256"])]:
                with path.open("xb") as stream:
                    subprocess.run([self.main, *args], stdout=stream, check=True)
                require(s4.sha(path)==pin, f"emission digest mismatch {config}/{path.name}")
            self.emissions[config] = unfused, fused
        unfused, fused = self.emissions[config]
        dut = fused if job["call"]=="goldenF" else unfused
        if job["mutation"]:
            dut = work / (job["mutation"] + ".bench")
            if not dut.exists():
                dut.write_bytes(mutant_bytes(unfused.read_bytes(), job["mutation"]))
        require(s4.sha(dut)==job["dut_sha256"] and s4.sha(fused)==job["fused_sha256"], "test fixture digest")
        return r, pm, golden, extra, dut, fused

    def bind(self, case, r, pm):
        if not self.bridges:
            rec = verify_bridge(HERE.parents[1])
            require(rec["status"]=="PASS" and rec["lut_expansion_cec"]=="EQ", "arithmetic bridge certification")
            self.bridges["c6288"] = {k:rec[k] for k in ("status","observed","lut_expansion_cec")}
        kernel.bind_bridge(case, self.maps[r["portmap_sha256"]], (DATA.parent/"scripts"/pm["bench"]).resolve(),
                           DATA/"configured/corr/c6288.json")


def measure(job, fixture, abc_path, temp):
    r, pm, golden, extra, dut, fused = fixture.load(job)
    abc = kernel.Abc(str(abc_path), job["timeout"])
    work = kernel.Work(str(temp/job["id"]), job["id"], prune=True)
    call = job["call"]
    bits = r["planted"]
    extra_checks = []
    if call == "pair":
        _, result, checks, _ = kernel.run_pair(str(dut), str(fused), bits, abc, work)
    else:
        case = s4.E.Case(s4.E.read_bench(str(dut)), pm, golden, bits, r["h"])
        if job["bridge"]:
            fixture.bind(case, r, pm)
        if extra:
            extra_checks.append(("golden_extra_independent", "EQ", "EQ"))
        if call.startswith("golden"):
            result, checks, _ = kernel.run_golden(case, abc, work, str(dut))
            result.update(golden_extra=extra, golden_extra_independent="EQ" if extra else "NA")
        elif call == "miter":
            result, checks, _ = kernel.run_miter(case, abc, work, job["fraig"])
        elif call == "controls":
            seed = f"configured_check|controls|{r['host']}|{r['out']}|n={r['n']}|h=0|s={bits}"
            result, checks, _ = kernel.run_controls(case, abc, work, str(dut), seed, job["flip_bit"])
        else:
            raise ValueError(call)
    checks = extra_checks + list(checks)
    status, _ = kernel.judge(checks)
    bad = [(name, val) for name, val, expected in checks if val!=expected]
    unknown = {"TIMEOUT", "ERROR", "UNKNOWN"}
    inconclusive = [name for name,val in bad if str(val) in unknown]
    failed = [name for name,val in bad if str(val) not in unknown]
    fields = FIELDS["golden" if call.startswith("golden") else call]
    observed = {k:result[k] for k in fields}
    diagnostic = {}
    if call == "controls":
        diagnostic.update(swap_pairs_tried=result["swap_pairs_tried"], swap_pair_budget=256)
    return dict(status=status, observed=observed, failed_checks=failed, inconclusive_checks=inconclusive,
                checks=len(checks), **diagnostic)


def execute(args):
    path=HERE/"sm-rows.json"
    require(s4.sha(path)==ROWS_HASH, "functional schedule digest")
    jobs=json.loads(path.read_bytes())
    ref=historical()
    require(len(jobs)==178 and set(ref)=={j["id"] for j in jobs}, "historical and current schedules differ")
    for attr in ("host", "tier", "call"):
        if getattr(args,attr):
            jobs=[j for j in jobs if j[attr]==getattr(args,attr)]
    if args.case:
        jobs=[j for j in jobs if args.case in (j["id"],j["config"],j["fixture"])]
    require(jobs,"no matching registered functional cases")
    require(not args.out.exists(), "choose a new output path")
    abc_path=shutil.which("yosys-abc")
    require(abc_path, "missing yosys-abc")
    report=[]
    with tempfile.TemporaryDirectory() as tmp:
        fixtures=Fixtures(Path(tmp),args.main.resolve(),args.rtl.resolve())
        for j in jobs:
            start=time.monotonic()
            record={k:j[k] for k in ("id","tier","config","call","attempt","counted","host","out","dut_sha256","timeout")}
            try:
                measured=measure(j,fixtures,abc_path,Path(tmp))
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                measured=dict(status="ERROR", reason=type(error).__name__, diagnostic=str(error)[:500],
                              checks=0, failed_checks=[], inconclusive_checks=[], observed={})
            record.update(measured)
            original=ref[j["id"]]
            compared={k:str(v) for k,v in record["observed"].items()}
            expected=dict(part.split("=",1) for part in original["result"].split(";"))
            record["matched"]=(compared==expected and record["status"]==original["status"]
                               and j["dut_sha256"]==original["dut_sha256"] and j["counted"]==(original["counted"]=="yes"))
            record["seconds"]=round(time.monotonic()-start,3)
            report.append(record)
            print(json.dumps(record,sort_keys=True),flush=True)
        bridge=fixtures.bridges
    summary=dict(attempts=len(report),counted=sum(r["counted"] for r in report),matched=sum(r["matched"] for r in report),
                 verdicts=dict(Counter(r["status"] for r in report)),complete_campaign=len(report)==178)
    result=dict(summary=summary,main_sha256=s4.sha(args.main),abc_version=kernel.Abc(abc_path).version(),
                bridge=bridge,rows=report)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    with args.out.open("x") as out:
        json.dump(result,out,indent=2)
        out.write("\n")
    print(json.dumps(summary),flush=True)
    return 0 if summary["matched"]==len(report) else 1


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--main",type=Path,required=True)
    p.add_argument("--rtl",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    p.add_argument("--host",help="limit to one registered host")
    p.add_argument("--tier",choices=["S","M"])
    p.add_argument("--case",help="one registered fixture, configuration, or attempt ID")
    p.add_argument("--call",choices=["goldenU","goldenF","miter","controls","pair","golden"])
    raise SystemExit(execute(p.parse_args()))
