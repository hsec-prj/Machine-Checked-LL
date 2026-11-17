"""Fresh Tier E measurements over a chosen support-width budget, including a negative control."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import random
import subprocess
import sys
import tempfile
import exhaustive as E

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CONF = ROOT / "experiments/data/configured"
sys.path.insert(0, str(HERE/"agda"))
from c17 import verilog


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def one(row, main, rtl, tmp, portmaps, negative, max_width):
    host, out, secret, radius = row["host"], row["out"], row["secret"], row["h"]
    pm = json.loads(portmaps[row["portmap"]].read_bytes())
    correspondence = CONF/"corr"/(host+".json")
    if sha(correspondence) != row["corr"]:
        raise ValueError(correspondence)
    if row["command"] == "emitlockhost":
        args = ["emitlockhost",host,str(radius),secret]
    else:
        script = ROOT/"experiments/scripts/gen_netlist_data.py"
        flat = tmp/"host.flat"
        with flat.open("wb") as stream:
            subprocess.run([sys.executable,"-B",script,"--flat",pm["bench"],"--out",out],cwd=script.parent,stdout=stream,check=True)
        if sha(flat) != row["flat"]:
            raise ValueError(f"Flat input mismatch for {row['label']}")
        args = [row["command"],str(flat),*([str(radius)] if row["command"]=="emitlockhostflat" else []),secret]
    data = subprocess.check_output([main,*args])
    if hashlib.sha256(data).hexdigest() != row["emitted"]:
        raise ValueError(f"Emitter mismatch for {row['label']}")
    if host == "c17":
        ins, outs, gates = verilog(rtl)
        if out not in outs:
            raise ValueError(out)
        golden = E.Golden("rtl", [(n,op,list(a),None) for n,op,a in gates], out,False,
                          {name:i for i,name in enumerate(pm["support"])},str(rtl),sha(rtl),host,source_inputs=set(ins))
    else:
        golden = E.load_golden(json.loads(correspondence.read_bytes()),pm,str(CONF/"sld"/(host+".bench")))
    if golden.extra:
        raise ValueError("Extra golden inputs require a separate independence proof")
    text = data.decode()
    if negative:
        name, = re.findall(r"(?m)^OUTPUT\(([^)]+)\)",text)
        new = "local_positive_output"
        if new in text:
            raise ValueError(new)
        text,count = re.subn(r"(?m)^"+re.escape(name)+r"(\s*=)",new+r"\1",text)
        if count != 1:
            raise ValueError(name)
        text += f"\n{name} = NOT({new})\n"
    case = E.Case(E.parse_bench(text),pm,golden,secret,radius)
    if not negative and case.n > max_width:
        # Deterministic fresh functional probes above the enumeration budget.
        # Include the planted key/output and both centers of the corruption spheres.
        rng = random.Random(row["label"])
        points = []
        for _ in range(64):
            x, k = rng.getrandbits(case.n), rng.getrandbits(case.n)
            mask = sum(1 << i for i in rng.sample(range(case.n), radius))
            points.extend([(x,k),(x,case.S),(case.S ^ mask,k),(k ^ mask,k)])
        observed = case.batch_D(points)
        expected = [int(((x ^ case.S).bit_count()==radius) != ((x ^ k).bit_count()==radius)) for x,k in points]
        if observed != expected:
            raise ValueError(f"Functional sample mismatch for {row['label']}")
        print(json.dumps(dict(label=row["label"],mode="sample",vectors=len(points),mismatches=0,emitted_sha256=hashlib.sha256(data).hexdigest())),flush=True)
        return
    values,checks,_ = E.run_exhaustive(case)
    values.update(golden_gates=len(golden.cone.order),emitted_gates=len(case.emitted.gates))
    if negative:
        if values["mismatches"] != 2**values["pairs_log2"]:
            raise ValueError("Output inversion accepted")
    elif not all(a==b for _,a,b in checks) or any(values[k]!=v for k,v in row["counters"].items()):
        raise ValueError((row["label"],values,row["counters"]))
    print(json.dumps(dict(label=row["label"],negative=negative,**values)),flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main",required=True,type=Path)
    parser.add_argument("--rtl",required=True,type=Path)
    parser.add_argument("--max-width",type=int,required=True)
    args=parser.parse_args()
    maps={sha(p):p for p in (CONF/"portmaps").glob("*.json")}
    selected=json.loads((HERE/"exhaustive-rows.json").read_bytes())
    enumerated=[r for r in selected if len(r["secret"])<=args.max_width]
    if not enumerated:
        parser.error("The support-width budget selected no rows")
    with tempfile.TemporaryDirectory() as folder:
        for row in selected:
            one(row,args.main.resolve(),args.rtl,Path(folder),maps,False,args.max_width)
        one(enumerated[0],args.main.resolve(),args.rtl,Path(folder),maps,True,args.max_width)
