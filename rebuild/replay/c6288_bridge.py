"""Verify the documented full-domain c6288 arithmetic bridge in the hydrated artifact."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import exhaustive as E

PINS = {'portmap': '9c3075d59b3a731a89c2371a2a7b17591ffd428f564a9e0c71d83b4c55109900', 'corr': 'acaa8826c10d4ca34f52851e63fb76cd5939fbb938eb8ee285cf82a1423bb0f3', 'cone_bench': '5480d9ec0fd2cb195dfca37550e2da99ae24d39bd422fa8e8f40ff3ab801b571', 'norm': '99e2a151506bdadaa88dd027ef05531684a1a672a934a30f9c9dd3db7d9340d5'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sim_function(name, gates, leaves, out):
    """Construct ordinary C Boolean operations. Keep concrete local connectivity in scratch."""
    symbols = {v:f"x[{i}]" for i,v in enumerate(leaves)}
    lines = [f"static __attribute__((noinline)) V {name}(const V x[32]) {{"]
    for i, (wire, op, inputs, code) in enumerate(gates):
        a,b = (symbols[v] for v in inputs)
        if op == "LUT":
            key = code
        else:
            key = {"AND":8, "OR":14, "XOR":6}[op]
        expr = {1:f"~({a} | {b})", 2:f"({a} & ~{b})", 6:f"({a} ^ {b})",
                8:f"({a} & {b})", 9:f"~({a} ^ {b})", 14:f"({a} | {b})"}[key]
        symbols[wire] = f"v{i}"
        lines.append(f"    V v{i} = {expr};")
    lines.extend((f"    return {symbols[out]};","}"))
    return "\n".join(lines)


def verify_bridge(artifact: Path):
    root = artifact.resolve()/'experiments/data'
    paths = dict(portmap=root/'configured/portmaps/c6288_N6123.json', corr=root/'configured/corr/c6288.json',
                 cone_bench=root/'benchmarks/iscas85/c6288_lut2.bench', norm=root/'configured/norm/c6288.bench')
    hashes = {role:hashlib.sha256(path.read_bytes()).hexdigest() for role,path in paths.items()}
    require(hashes == PINS,'c6288 bridge input hashes differ')
    expected = dict(vectors=1<<32, cone_vs_intprod=0, golden_vs_intprod=0, mismatches=0, norm_vs_intprod=0,
                    intprod_neg_mismatches=2147450880, inverted_output_mismatches=1<<32)
    corr=json.loads(paths['corr'].read_bytes())
    pm=json.loads(paths['portmap'].read_bytes())
    target=pm['out']
    order=corr['A']+corr['B']
    require(len(corr['A'])==len(corr['B'])==16 and set(order)==set(pm['support']) and len(set(order))==32
            and corr['P'].index(target)==15,'c6288 operand binding')
    with tempfile.TemporaryDirectory() as folder:
        work=Path(folder)
        lut=E.read_bench(str(paths["cone_bench"]))
        norm=E.read_bench(str(paths["norm"]))
        result=[]
        for name,bench in (("lut_cone",lut),("norm_cone",norm)):
            bench.check_closed()
            cone=E.Cone(bench.drv,target)
            require(set(cone.leaves)==set(order),"wrong cone leaves")
            result.append(sim_function(name,cone.order,order,target))
        gold,out=E.mult_column(corr["A"],corr["B"],15)
        result.append(sim_function("golden_cone",gold,order,out))
        source=(HERE/"bridge.c.in").read_text().replace("/* FUNCTION DEFINITIONS */","\n".join(result))
        (work/"bridge.c").write_text(source)
        full=work/"expanded.bench"
        lines=[f"INPUT({x})" for x in lut.ins]+[f"OUTPUT({x})" for x in lut.outs]
        for wire,op,args,code in lut.gates:
            require(op=="LUT" and len(args)==2,"unexpected original LUT shape")
            prim={1:"NOR",6:"XOR",8:"AND",9:"XNOR"}[code]
            lines.append(f"{wire} = {prim}({','.join(args)})")
        full.write_text("\n".join(lines)+"\n")
        shutil.copyfile(paths["cone_bench"],work/"lut2.bench")
        cec=subprocess.run(['yosys-abc','-c','cec lut2.bench expanded.bench'],cwd=work,text=True,
                           stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=True)
        require('Networks are equivalent' in cec.stdout and 'NOT EQUIVALENT' not in cec.stdout,
                'c6288 expanded LUTs failed CEC')
        subprocess.run(['clang','-O3','-march=native','-std=c11','bridge.c','-o','bridge'],cwd=work,check=True)
        observed=json.loads(subprocess.check_output([work/'bridge'],cwd=work))
        require(observed==expected,'c6288 all-input arithmetic comparison differs')
    return dict(status='PASS',observed=observed,lut_expansion_cec='EQ',local_inputs=hashes)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    if args.output.exists():
        parser.error('Choose a new output path')
    receipt=verify_bridge(HERE.parents[1])
    with args.output.open('x') as stream:
        json.dump(receipt,stream,indent=2)
        stream.write('\n')
    print(json.dumps(receipt))
