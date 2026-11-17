"""Independent scalar BENCH parser and evaluator."""
import re

def parse(path):
    ins, outs, gates = [], [], []
    for line in open(path):
        line = line.split('#')[0].strip()
        if not line: continue
        m = re.match(r'INPUT\((\w+)\)', line)
        if m: ins.append(m.group(1)); continue
        m = re.match(r'OUTPUT\((\w+)\)', line)
        if m: outs.append(m.group(1)); continue
        m = re.match(r'(\w+)\s*=\s*(\w+)\((.*)\)', line)
        if m:
            gates.append((m.group(1), m.group(2).upper(),
                          [a.strip() for a in m.group(3).split(',') if a.strip()]))
    return ins, outs, gates

def evaluate(ins, outs, gates, x):
    v = {ins[i]: (x >> i) & 1 for i in range(len(ins))}
    for w, op, a in gates:
        g = [v[t] for t in a]
        v[w] = {'NOT': lambda: 1-g[0], 'AND': lambda: g[0]&g[1], 'OR': lambda: g[0]|g[1],
                'XOR': lambda: g[0]^g[1], 'BUF': lambda: g[0],
                'VDD': lambda: 1, 'GND': lambda: 0}[op]()
    return [v[o] for o in outs]
