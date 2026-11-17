"""Replay the 18 prescribed radius-zero Tier X functional equivalence tests using CUDD."""
import argparse
import ctypes
from functools import reduce
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CONF = ROOT/'experiments/data/configured'
sys.path.insert(0, str(HERE.parent))
import exhaustive as E

ROWS_SHA256 = '1fac868897e7c8343a4d32d774bc7e47593aad117ca7258fe08c1dfcfc4110fc'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(value):
    return sha(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def prescribed(row):
    bits = row['secret']
    n = len(bits)
    s = E.bits_to_int(bits)
    mask = (1 << n) - 1
    seed = hashlib.sha256(row['seed'].encode()).digest()[:8]
    rng = random.Random(int.from_bytes(seed, 'big'))
    vectors = [('s', s)] + [(f'nb{i}', s ^ (1 << i)) for i in range(n)]
    vectors.extend([('comp', s ^ mask), ('zeros', 0), ('ones', mask)])
    vectors.extend((f'rnd{i}', rng.getrandbits(n)) for i in range(16))
    seen = set()
    keys = []
    for tag, key in vectors:
        if key not in seen:
            seen.add(key)
            keys.append([tag, E.int_to_bits(key,n)])
    if keys != row['ordered_keys'] or digest(keys) != row['keys_sha256']:
        raise ValueError('Prescribed key list differs: '+row['label'])
    return row['ordered_keys']


class BDD:
    """One independent Boolean variable per data input. Test keys are constants."""
    def __init__(self, library, n):
        self.lib = ctypes.CDLL(str(library))
        ptr, uint = ctypes.c_void_p, ctypes.c_uint
        abi = {'Cudd_Init':(ptr,[uint,uint,uint,uint,ctypes.c_size_t]), 'Cudd_Quit':(None,[ptr]),
               'Cudd_ReadOne':(ptr,[ptr]), 'Cudd_bddIthVar':(ptr,[ptr,ctypes.c_int]), 'Cudd_Ref':(None,[ptr]),
               'Cudd_CountMinterm':(ctypes.c_double,[ptr,ptr,ctypes.c_int])}
        for op in ('And','Or','Xor'):
            abi['Cudd_bdd'+op] = ptr, [ptr,ptr,ptr]
        for name, (result, args) in abi.items():
            fn = getattr(self.lib,name)
            fn.restype, fn.argtypes = result, args
        self.dd = self.lib.Cudd_Init(n, 0, 256, 262144, 384*1024*1024)
        if not self.dd:
            raise MemoryError('CUDD manager')
        self.one = self.lib.Cudd_ReadOne(self.dd)
        self.zero = self.one ^ 1
        self.x = [self.lib.Cudd_bddIthVar(self.dd,i) for i in range(n)]

    def apply(self, op, a, b):
        node = getattr(self.lib,'Cudd_bdd'+op)(self.dd,a,b)
        if not node:
            raise MemoryError('CUDD '+op)
        self.lib.Cudd_Ref(node)
        return node

    def gate(self, op, args, code):
        if op in ('VDD','GND'):
            return self.one if op == 'VDD' else self.zero
        if op in ('NOT','BUF'):
            return args[0] ^ (op == 'NOT')
        if op == 'LUT':
            terms = [self.gate('AND', [v ^ (1-((pattern>>i)&1)) for i,v in enumerate(args)], None)
                     for pattern in range(1<<len(args)) if (code>>pattern)&1]
            return reduce(lambda a,b:self.apply('Or',a,b),terms,self.zero)
        operator = {'AND':'And','NAND':'And','OR':'Or','NOR':'Or','XOR':'Xor','XNOR':'Xor'}[op]
        return reduce(lambda a,b:self.apply(operator,a,b),args) ^ (op in ('NAND','NOR','XNOR'))

    def cone(self, cone, inputs):
        values = dict(inputs)
        for wire, op, args, code in cone.order:
            values[wire] = self.gate(op, [values[a] for a in args], code)
        return values[cone.target]

    def point(self, bits):
        return self.gate('AND', [v ^ int(b=='0') for v,b in zip(self.x,bits,strict=True)], None)

    def count(self, bdd):
        v = self.lib.Cudd_CountMinterm(self.dd,bdd,len(self.x))
        if not v.is_integer() or not 0 <= v <= 1 << len(self.x):
            raise ValueError(f'Invalid CUDD count {v}')
        return int(v)


def checked_bytes(path, pin):
    data = path.read_bytes()
    if sha(data) != pin:
        raise ValueError('Unexpected input digest: '+str(path))
    return data


def make_case(row, maps, bench_pins, main, tmp):
    pins = row['pins']
    pm = maps[pins['portmap']]
    if pm['out'] != row['out'] or pm['n'] != len(row['secret']):
        raise ValueError('Port map identity differs')
    scripts = ROOT/'experiments/scripts'
    bench = (scripts/pm['bench']).resolve()
    bench_key = bench.relative_to(ROOT/'experiments/data').as_posix()
    checked_bytes(bench,bench_pins[bench_key]['archive_sha256'])
    flat = tmp/'host.flat'
    with flat.open('wb') as out:
        subprocess.run([sys.executable,'-B','gen_netlist_data.py','--flat',pm['bench'],'--out',pm['out']],
                       cwd=scripts,stdout=out,check=True)
    checked_bytes(flat,pins['flat'])
    dut = subprocess.check_output([main,'emitlockhostflat',flat,'0',row['secret']])
    if sha(dut) != pins['emitted']:
        raise ValueError('Unexpected emitted BENCH for '+row['label'])
    corr = json.loads(checked_bytes(CONF/'corr'/(row['host']+'.json'),pins['corr']))
    golden_path = CONF/'sld'/(row['host']+'.bench')
    if pins['golden_source'] == 'harness':
        if corr.get('golden') != 'mult16x16':
            raise ValueError('Expected independent multiplier arithmetic')
    else:
        checked_bytes(golden_path,pins['golden_source'])
    gold = E.load_golden(corr,pm,str(golden_path))
    if gold.extra:
        raise ValueError('Golden has uncovered primary inputs')
    return E.Case(E.parse_bench(dut.decode()),pm,gold,row['secret'],0)


def measure(case, keys, lib):
    bdd = BDD(lib,case.n)
    try:
        gold = case.golden
        golden = bdd.cone(gold.cone,{w:bdd.x[i] for w,i in gold.leaf_pos.items()}) ^ gold.negate
        planted = bdd.point(case.secret)
        records = []
        positions_bad = 0
        inverted_count = None
        for tag, key in keys:
            fixed = [bdd.one if b=='1' else bdd.zero for b in key]
            emitted = bdd.cone(case.cone,case.lock_inputs(bdd.x,fixed))
            delta = bdd.apply('Xor',emitted,golden)
            expected_positions = bdd.apply('Xor',planted,bdd.point(key))
            mismatches = bdd.count(bdd.apply('Xor',delta,expected_positions))
            positions_bad += delta != expected_positions
            hd = sum(a!=b for a,b in zip(case.secret,key,strict=True))
            records.append(dict(tag=tag,key=key,hd=hd,corruption=bdd.count(delta),mismatches=mismatches,
                                expected=E.ocr(case.n,0,hd) if hd else 0))
            if tag=='s':
                inverted_count = bdd.count(bdd.apply('Xor',emitted ^ 1,golden))
        observed = dict(keys=len(records), x_space_log2=case.n, mismatches=sum(r['mismatches'] for r in records),
                        perkey_ocr_bad=sum(r['corruption']!=r['expected'] for r in records), positions_bad=positions_bad,
                        restore_ok=records[0]['tag']=='s' and records[0]['corruption']==0,
                        corruption_sampled_keys=sum(r['corruption'] for r in records if r['key']!=case.secret),
                        emitted_gates=len(case.emitted.gates),golden_gates=len(gold.cone.order))
        return observed, records, inverted_count
    finally:
        bdd.lib.Cudd_Quit(bdd.dd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('main','lib','output'):
        parser.add_argument('--'+name,required=True,type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Choose a new output file')
    rows = json.loads(checked_bytes(HERE/'x-rows.json',ROWS_SHA256))
    maps = {sha(p.read_bytes()):json.loads(p.read_bytes()) for p in (CONF/'portmaps').glob('*.json')}
    inventory = json.loads(checked_bytes(HERE.parent/'inputs/pins.json',
                                        'ec9535867f1db6ea927240e95f4a19d60c0b2af0c9b33be141bbc496aea67d2e'))
    report = []
    with tempfile.TemporaryDirectory() as tmp:
        for row in rows:
            keys = prescribed(row)
            case = make_case(row,maps,inventory['benchmarks'],args.main.resolve(),Path(tmp))
            observed, records, inverted = measure(case,keys,args.lib.resolve())
            if observed != row['expected'] or digest(records)!=row['measured_keys_sha256'] or inverted!=1<<case.n:
                raise ValueError((row['label'],observed,inverted))
            report.append(dict(label=row['label'],counters=observed,ordered_keys=records,inverted_planted_mismatches=inverted))
    result = dict(configurations=len(report),keys=sum(r['counters']['keys'] for r in report),
                  inputs_times_keys=sum(r['counters']['keys'] << r['counters']['x_space_log2'] for r in report),
                  sampled_corruptions=sum(r['counters']['corruption_sampled_keys'] for r in report),
                  output_inversion_controls=len(report), rows=report)
    with args.output.open('x') as stream:
        json.dump(result,stream,indent=2)
        stream.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k!='rows'}))


if __name__ == '__main__':
    main()
