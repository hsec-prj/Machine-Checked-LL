#!/usr/bin/env python3
"""Shared benchmark parsing and cone support for gen_netlist_data.py."""
import re

def parse(path):
    # Represent a gate as (out, op, [args], lutval-or-None), accepting ABC LUT
    # syntax w = LUT 0xHH ( a, b ) and standard syntax w = AND(a,b).
    ins, outs, gates = [], [], []
    for line in open(path):
        line = line.split('#')[0].strip()
        if not line: continue
        m = re.match(r'INPUT\((\w+)\)', line)
        if m: ins.append(m.group(1)); continue
        m = re.match(r'OUTPUT\((\w+)\)', line)
        if m: outs.append(m.group(1)); continue
        m = re.match(r'(\w+)\s*=\s*LUT\s+(0x[0-9a-fA-F]+)\s*\(([^)]*)\)', line)
        if m:
            args = [a.strip() for a in m.group(3).split(',') if a.strip()]
            gates.append((m.group(1), 'LUT', args, int(m.group(2), 16))); continue
        m = re.match(r'(\w+)\s*=\s*(\w+)\s*\(([^)]*)\)', line)
        if m:
            args = [a.strip() for a in m.group(3).split(',') if a.strip()]
            gates.append((m.group(1), m.group(2).upper(), args, None))
    return ins, outs, gates

def driver_map(gates):
    return {w: (op, a, lut) for (w, op, a, lut) in gates}

def cone_support(out, drv, ins_set):
    """Find primary inputs in the transitive fan-in cone of out."""
    seen, stack, support = set(), [out], []
    while stack:
        w = stack.pop()
        if w in seen: continue
        seen.add(w)
        if w in ins_set:
            if w not in support: support.append(w)
        elif w in drv:
            stack.extend(drv[w][1])
    return support
