"""Check four rebuilt single-output data functions and compare eight historical fixed-key fingerprints."""
import argparse
from functools import reduce
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import exhaustive as E

ROW_PIN = 'd4fd7f0d71a7df4a53fe2f5423bdc975111536c8e7913e09632666f0ba3d59ed'
VECTORS = 1024


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked(path, expected):
    data = path.read_bytes()
    if sha(data) != expected:
        raise ValueError('Input digest differs: '+str(path))
    return data


class DataFunction:
    """A single-output data-only circuit with structural sharing and constant simplification."""
    def __init__(self, pins):
        self.width = len(pins)
        self.inputs = {pin:2*(i+1) for i,pin in enumerate(pins)}
        self.nodes = []
        self.shared = {}

    def binary(self, op, a, b):
        if op == 'or':
            return self.binary('and', a^1, b^1)^1
        if op == 'xor':
            parity = (a^b)&1
            a,b = a&~1,b&~1
            if a==b: return parity
            if min(a,b)==0: return max(a,b)^parity
        else:
            if 0 in (a,b) or a==(b^1): return 0
            if a==b: return a
            if 1 in (a,b): return b if a==1 else a
            parity = 0
        record = (op,min(a,b),max(a,b))
        if record not in self.shared:
            self.nodes.append(record)
            self.shared[record] = 2*(self.width+len(self.nodes))
        return self.shared[record]^parity

    def gate(self, op, xs, mask):
        if op in ('GND','VDD'): return int(op=='VDD')
        if op in ('NOT','BUF'): return xs[0]^int(op=='NOT')
        if op=='LUT':
            if len(xs)!=2: raise ValueError('Expected a two-input LUT')
            # Convert the 16 complete two-input truth tables to primitive gates.
            a,b=xs
            lut=(0,lambda:self.binary('and',a^1,b^1),lambda:self.binary('and',a,b^1),b^1,
                 lambda:self.binary('and',a^1,b),a^1,lambda:self.binary('xor',a,b),lambda:self.binary('and',a,b)^1,
                 lambda:self.binary('and',a,b),lambda:self.binary('xor',a,b)^1,a,lambda:self.binary('or',a,b^1),
                 b,lambda:self.binary('or',a^1,b),lambda:self.binary('or',a,b),1)
            value=lut[mask]
            return value() if callable(value) else value
        kind={'AND':'and','NAND':'and','OR':'or','NOR':'or','XOR':'xor','XNOR':'xor'}[op]
        return reduce(lambda a,b:self.binary(kind,a,b),xs)^int(op in ('NAND','NOR','XNOR'))

    def evaluate(self, cone, leaves, negate=False):
        values = dict(leaves)
        for wire,op,args,mask in cone.order:
            values[wire] = self.gate(op,[values[a] for a in args],mask)
        return values[cone.target]^int(negate)

    def inspect(self, root, tag):
        # Digests use child digests, never internal allocation identifiers. The sample
        # signature evaluates the same deterministic 1,024 data vectors on each route.
        allbits=(1<<VECTORS)-1
        hashes=[hashlib.sha256(b'false').digest()]; bits=[0]
        for i in range(self.width):
            name=f'{tag}:data:{i}'.encode()
            hashes.append(hashlib.sha256(b'input:'+str(i).encode()).digest())
            bits.append(int.from_bytes(hashlib.shake_256(name).digest(VECTORS//8),'little'))
        def signed(v):
            h=hashes[v>>1]
            return hashlib.sha256(b'not:'+h).digest() if v&1 else h
        def value(v): return bits[v>>1] ^ (allbits if v&1 else 0)
        for op,a,b in self.nodes:
            pair=sorted((signed(a),signed(b)))
            hashes.append(hashlib.sha256(op.encode()+b':'+pair[0]+pair[1]).digest())
            bits.append(value(a)&value(b) if op=='and' else value(a)^value(b))
        output=value(root)
        return dict(structure_sha256=signed(root).hex(), vectors=VECTORS,
                    outputs_sha256=sha(output.to_bytes(VECTORS//8,'little')), ones=output.bit_count())

    def write_data(self, path, root):
        live=set(); pending=[root>>1]
        while pending:
            index=pending.pop()
            if index in live or index<=self.width: continue
            live.add(index)
            _,a,b=self.nodes[index-self.width-1]
            pending.extend((a>>1,b>>1))
        lines=[f'INPUT(n{i})' for i in range(1,self.width+1)]+['OUTPUT(y)']
        lines.append('n0 = XOR(n1,n1)')
        neg=set()
        def wire(v):
            i=v>>1
            if v&1:
                if i not in neg: lines.append(f'v{i} = NOT(n{i})'); neg.add(i)
                return f'v{i}'
            return f'n{i}'
        for i in sorted(live):
            op,a,b=self.nodes[i-self.width-1]
            lines.append(f'n{i} = {op.upper()}({wire(a)}, {wire(b)})')
        lines.append(f'y = BUF({wire(root)})')
        path.write_text('\n'.join(lines)+'\n')


def compare(directory, left, right, equivalent):
    # Both files have only data PIs, a single fixed output and no external-key interface.
    if Path(left).name!=left or Path(right).name!=right:
        raise ValueError('Expected temporary data-only basenames')
    result=subprocess.run(['yosys-abc','-c',f'cec {left} {right}'],cwd=directory,check=True,
                          stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    verdict='Networks are equivalent' in result.stdout
    rejected='Networks are NOT EQUIVALENT' in result.stdout
    if verdict==rejected or verdict!=equivalent:
        raise ValueError((left,right,result.stdout))
    return 'EQ' if verdict else 'INEQ'


def source_functions(artifact, row):
    d=artifact/'experiments/data'; host,out=row['host'],row['output']
    paths={'portmap':d/f'configured/portmaps/{host}_{out}.json','correspondence':d/f'configured/corr/{host}.json',
           'normalized_bench':d/f'configured/norm/{host}.bench','literal_bench':d/f'benchmarks/iscas85/{host}_lut2.bench'}
    if host!='c6288': paths['independent_bench']=d/f'configured/sld/{host}.bench'
    for role,path in paths.items(): checked(path,row['source_sha256'][role])
    pm=json.loads(paths['portmap'].read_bytes()); corr=json.loads(paths['correspondence'].read_bytes())
    if pm['out']!=out or len(pm['support'])!=row['width'] or sha(json.dumps(pm['support'],indent=2).encode()+b'\n')!=row['ordered_support_sha256']:
        raise ValueError('Unexpected output or ordered support: '+host)
    literal=E.read_bench(str(paths['literal_bench'])); norm=E.read_bench(str(paths['normalized_bench']))
    if set(literal.ins)!=set(norm.ins): raise ValueError('Data port sets differ: '+host)
    dag=DataFunction(literal.ins); roots={}
    for name,src in [('literal',literal),('normalized',norm)]:
        src.check_closed()
        roots[name]=dag.evaluate(E.Cone(src.drv,out),dag.inputs)
    g=E.load_golden(corr,pm,str(paths.get('independent_bench','')))
    if g.extra: raise ValueError('Golden has unmapped inputs: '+host)
    roots['external']=dag.evaluate(g.cone,{w:dag.inputs[pm['support'][idx]] for w,idx in g.leaf_pos.items()},g.negate)
    scripts=artifact/'experiments/scripts'
    flat=subprocess.check_output([sys.executable,'-B','gen_netlist_data.py','--flat',pm['bench'],'--out',out],cwd=scripts)
    if sha(flat)!=row['flat_sha256']: raise ValueError('Historical host.flat differs: '+host)
    return dag,roots,{**{role:sha(path.read_bytes()) for role,path in paths.items()},'fresh_host_flat':sha(flat)}


def run(artifact):
    cases=json.loads(checked(HERE/'paired-functions.json',ROW_PIN))
    rows=[]; unique=[]
    for row in cases:
        h=row['host'];dag,roots,pins=source_functions(artifact,row)
        source=dag.inspect(roots['literal'],h)
        if h=='c6288':
            from c6288_bridge import verify_bridge
            bridge=verify_bridge(artifact)
            counts=bridge['observed']
            checks={'literal_vs_normalized':'EQ','literal_vs_external':'EQ','inverted_vs_external':'INEQ',
                    'method':'all 2^32 inputs versus independent integer multiplication', 'bridge':counts}
        else:
            with tempfile.TemporaryDirectory() as tmp:
                d=Path(tmp)
                for name,root in roots.items(): dag.write_data(d/(name+'.bench'),root)
                dag.write_data(d/'inverted.bench',roots['literal']^1)
                checks={'literal_vs_normalized':compare(d,'literal.bench','normalized.bench',True),
                        'literal_vs_external':compare(d,'literal.bench','external.bench',True),
                        'inverted_vs_external':compare(d,'inverted.bench','external.bench',False)}
        unique.append(dict(host=h,data_inputs=dag.width,protected_inputs=row['width'],checks=checks,
                           external_reference='integer multiplication' if h=='c6288' else 'separately sourced BENCH',
                           measured_sha256=pins,signature=source))
        for route,spec in row['routes'].items():
            historic=spec['fixed_key_signature']
            if (source['outputs_sha256'],source['ones'])!=(historic['outputs_sha256'],historic['ones']):
                raise ValueError('Historical planted-key signature differs: '+h+'/'+route)
            rows.append(dict(host=h,path=route,historical_input_sha256=spec['input_sha256'],full_route_bytes_regenerated=False,
                             measured={'host_measurement':h,'data_outputs_sha256':source['outputs_sha256']},
                             fixed_key_checks={'historical_outputs_sha256':historic['outputs_sha256'],
                                               'historical_fixed_structure_sha256':historic['structure_sha256'],
                                               'literal_fixed_structure_equal':source['structure_sha256']==historic['structure_sha256'],
                                               'vectors':VECTORS,'historical_signature_matches':True}))
    return dict(status='PASS',fresh_hosts=len(unique),positive_comparisons=len(unique)*2,negative_comparisons=len(unique),
                direct_positive_cec=6,direct_negative_cec=3,arithmetic_bridge_hosts=1,
                unique_vector_assignments=len(unique)*VECTORS,host_measurements=unique,rows=rows)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True,type=Path);args=p.parse_args()
    if args.output.exists():p.error('Choose a new output path')
    result=run(HERE.parents[1]);
    with args.output.open('x') as f: json.dump(result,f,indent=2);f.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('rows','host_measurements')}))
