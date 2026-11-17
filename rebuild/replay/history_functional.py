"""Verify restored hosts, standalone popcount comparators and historical known-input observations."""
import argparse
import csv
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def require(test, why):
    if not test:
        raise ValueError(why)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def samples(identity, width, n, h, planted):
    """64 primary-input samples, LSB = first ordinary port. The test configuration is fixed."""
    require(0 <= h <= n <= width <= 256 and len(planted) == n and set(planted) <= {"0","1"}, "probe dimensions")
    mask = (1 << width) - 1
    selected = (1 << n) - 1
    center = sum(int(c) << i for i, c in enumerate(planted))
    result = []
    for i in range(64):
        v = int.from_bytes(hashlib.sha256(f"history-functional-v1/{identity}/{i}".encode()).digest(), "little") & mask
        if i < 2:
            v = (0, mask)[i]
        elif i < 6:
            # Four chosen support assignments include the center and radius boundary.
            distance = (0, h, min(n,h+1), n)[i-2]
            v = (v & ~selected) | (center ^ ((1 << distance)-1))
        result.append(v)
    return result


def bit_planes(points, width):
    return [sum(((value >> bit) & 1) << i for i, value in enumerate(points)) for bit in range(width)]


def response_digest(planes):
    # 64 samples per primary output, in declaration order.
    return digest(b"".join(bits.to_bytes(8, "little") for bits in planes))


def header_rows(root):
    for campaign, name, key in (("P41","p41-dips.tsv","bench"),("P43","p43-recovery.tsv","host")):
        with (root/"experiments/data/processed"/name).open(newline="") as stream:
            for row in csv.DictReader(stream,delimiter="\t"):
                host, n, h, seed = row[key],int(row["n"]),int(row["h"]),int(row["seed"])
                identity = f"{campaign}.{host}.n{n}.h{h}.seed{seed}"
                yield identity,campaign,host,n,h,seed,row["ksec"]


def prove_comparator(bench, n, h):
    """Compare canonical BDDs for the isolated gate output and an independent cardinality recurrence."""
    require(bench.ins == [f"w{i}" for i in range(n)] and len(bench.outs)==1, "unexpected comparator ports")
    vertices = [(n,0,0),(n,1,1)]
    intern = {}
    def node(i, low, high):
        if low == high:
            return low
        key = i, low, high
        if key not in intern:
            intern[key] = len(vertices)
            vertices.append(key)
        return intern[key]
    @lru_cache(None)
    def apply(op, a, b):
        if a < 2 and b < 2:
            return (op >> (a+2*b)) & 1
        i=min(vertices[a][0],vertices[b][0])
        _,a0,a1=vertices[a] if vertices[a][0]==i else (i,a,a)
        _,b0,b1=vertices[b] if vertices[b][0]==i else (i,b,b)
        return node(i,apply(op,a0,b0),apply(op,a1,b1))
    @lru_cache(None)
    def expected(bit,remaining):
        if remaining < 0 or remaining > n-bit:
            return 0
        if bit==n:
            return 1
        return node(bit,expected(bit+1,remaining),expected(bit+1,remaining-1))
    values={name:node(i,0,1) for i,name in enumerate(bench.ins)}
    for name,op,args,_ in bench.gates:
        if op in ("VDD","GND"):
            v=int(op=="VDD")
        elif op in ("BUF","NOT"):
            v=values[args[0]]
            if op=="NOT":
                v=apply(6,v,1)
        else:
            code={"AND":8,"NAND":8,"OR":14,"NOR":14,"XOR":6,"XNOR":6}[op]
            v=values[args[0]]
            for arg in args[1:]:
                v=apply(code,v,values[arg])
            if op in ("NAND","NOR","XNOR"):
                v=apply(6,v,1)
        values[name]=v
    actual=values[bench.outs[0]]
    require(actual==expected(0,h) and actual!=expected(0,h+1), f"wrong comparator for {n}/{h}")
    apply.cache_clear()
    expected.cache_clear()
    return dict(input_assignments=1<<n, disagreement=0, adjacent_radius_distinguished=True)


def replay(main, output):
    require(not output.exists(),"choose a new output receipt")
    sys.path.insert(0,str(HERE.parent))
    import exhaustive as E
    pins=json.loads((HERE/"history-functional-pins.json").read_bytes())
    host_cache={}
    comparator_cache={}
    cases=[]
    for identity,campaign,host,n,h,seed,planted in header_rows(ROOT):
        row=pins["rows"][identity]
        if host not in host_cache:
            file=ROOT/"experiments/data/configured/sld"/(host+".bench")
            host_hash=digest(file.read_bytes())
            require(host_hash==pins["host_sha256"][host],f"upstream host differs: {host}")
            design=E.read_bench(str(file))
            design.check_closed()
            host_cache[host]=(design,[E.Cone(design.drv,o) for o in design.outs],host_hash)
        key=f"{n}/{h}"
        if key not in comparator_cache:
            cp=subprocess.run([main,"popcount",str(n),str(h)],capture_output=True,check=True)
            design_hash=digest(cp.stdout)
            require(design_hash==pins["gadget_sha256"][key],f"standalone comparator differs: {key}")
            comparator=E.parse_bench(cp.stdout.decode())
            comparator.check_closed()
            proof=prove_comparator(comparator,n,h)
            comparator_cache[key]=dict(n=n,h=h,sha256=design_hash,**proof)
        design,cones,host_hash=host_cache[host]
        points=samples(identity,len(design.ins),n,h,planted)
        p=bit_planes(points,len(design.ins))
        mask=(1<<64)-1
        signal=dict(zip(design.ins,p))
        actual=response_digest([cone.run(signal,mask) for cone in cones])
        require(len(design.outs)==row["primary_outputs"] and len(design.ins)==row["primary_inputs"] and
                actual==row["planted_response_sha256"],f"known-input response differs: {identity}")
        comparison=comparator_cache[key]
        cases.append(dict(case_id=identity,campaign=campaign,host=host,n=n,h=h,seed=seed,
                          host_sha256=host_hash,comparator_sha256=comparison["sha256"],
                          comparator_input_assignments=comparison["input_assignments"],comparator_disagreements=0,
                          planted_vectors=64,primary_outputs=len(cones),planted_output_observations=64*len(cones),
                          planted_response_sha256=actual,planted_response_match=True,
                          archived_locked_sha256=row["archived_locked_sha256"],
                          observation_baseline="fixed planted-key evaluation of archived locked bytes",
                          host_hash_source="shared upstream host reference",locked_hash_source="hashed archived file",
                          locked_design_regenerated=False))
    require(len(cases)==len(pins["rows"])==len({r["case_id"] for r in cases})==350,"case set differs")
    summary=dict(status="PASS",case_count=len(cases),host_count=len(host_cache),gadget_count=len(comparator_cache),
                 distinct_gadget_input_assignments=sum(p["input_assignments"] for p in comparator_cache.values()),
                 planted_vectors=sum(p["planted_vectors"] for p in cases),
                 planted_output_observations=sum(p["planted_output_observations"] for p in cases),
                 main_sha256=digest(main.read_bytes()),cases=cases,comparators=comparator_cache)
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open("x") as stream:
        json.dump(summary,stream,indent=2)
        stream.write("\n")
    print(json.dumps({k:v for k,v in summary.items() if k not in ("cases","comparators")}))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args()
    replay(args.main.resolve(),args.out.resolve())
