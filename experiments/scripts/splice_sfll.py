#!/usr/bin/env python3
# Use the verified popcount block to splice an SFLL-HD lock
# into an original ISCAS host, emitting a keyed SFLL-HD^h .bench.
#
# The structure follows locked-circuit in src/SFLL/Netlist.agda:
# locked(x) = f(x) XOR [HD(x, ksec)==h] XOR [HD(x, key)==h].
# f is the original circuit, protecting one primary output under D3.
# ksec is the hard-coded protected cube; all-zero ksec makes HD equal weight(x).
# key uses keyinput0..n-1, recognized by sld through the keyinput prefix.
# When key equals ksec, the masks cancel and restore f(x).
#
# Emit sld-compatible lowercase and/or/not/xor/buf gates; sld normalizes case.
# Remove unsupported vdd/gnd sources by constant propagation.
#
# Invocation: splice_sfll.py <origin.bench> <popcount_n_h.bench> <n> <h> [out_index]
# Write the locked .bench to stdout; the correct-key original remains origin.
import sys, re, argparse, json
from pathlib import Path

def parse_bench(path):
    ins, outs, gates = [], [], []
    for line in open(path):
        line = line.split('#')[0].strip()
        if not line: continue
        m = re.match(r'INPUT\((\w+)\)', line);  m and ins.append(m.group(1))
        if m: continue
        m = re.match(r'OUTPUT\((\w+)\)', line);  m and outs.append(m.group(1))
        if m: continue
        m = re.match(r'(\w+)\s*=\s*(\w+)\s*\((.*)\)', line)
        if m:
            gates.append((m.group(1), m.group(2).lower(),
                          [a.strip() for a in m.group(3).split(',') if a.strip()]))
    return ins, outs, gates

# Fold vdd/gnd constants, returning folded gates and the wire-to-0/1 map.
def fold(gates):
    const, out = {}, []
    for name, f, args in gates:
        if f in ('vdd', 'one'):  const[name] = 1; continue
        if f in ('gnd', 'zero'): const[name] = 0; continue
        av = [const.get(a) for a in args]
        if f == 'not':
            if av[0] is not None: const[name] = 1 - av[0]; continue
        elif f == 'buf':
            if av[0] is not None: const[name] = av[0]; continue
        elif f in ('and', 'nand'):
            inv = (f == 'nand')
            if 0 in av: const[name] = (1 if inv else 0); continue
            na = [a for a, v in zip(args, av) if v != 1]
            if not na: const[name] = (0 if inv else 1); continue
            f, args = ('not' if inv else 'buf') if len(na) == 1 else ('nand' if inv else 'and'), na
        elif f in ('or', 'nor'):
            inv = (f == 'nor')
            if 1 in av: const[name] = (0 if inv else 1); continue
            na = [a for a, v in zip(args, av) if v != 0]
            if not na: const[name] = (1 if inv else 0); continue
            f, args = ('not' if inv else 'buf') if len(na) == 1 else ('nor' if inv else 'or'), na
        elif f in ('xor', 'xnor'):
            par = sum(v for v in av if v is not None) % 2
            if f == 'xnor': par ^= 1
            na = [a for a, v in zip(args, av) if v is None]
            if not na: const[name] = par; continue
            if len(na) == 1: f, args = ('not' if par else 'buf'), na
            else: f, args = ('xnor' if par else 'xor'), na
        out.append((name, f, args))
    return out, const

# Prefix popcount gate names and reconnect its inputs through input_map.
# Return the renamed gates and output wire or constant.
def instance(pc_gates, pc_ins, pc_out, prefix, input_map):
    folded, const = fold(pc_gates)
    ren = lambda w: input_map[w] if w in input_map else (prefix + w)
    gates = [(prefix + nm, f, [ren(a) for a in args]) for nm, f, args in folded]
    if pc_out in const:                       # Handle the rare case where the output folds to a constant.
        c = prefix + "const"; gates.append((c, 'one' if const[pc_out] else 'gnd', []))
        return gates, c
    if pc_out in input_map: return gates, input_map[pc_out]
    return gates, prefix + pc_out

def gen_ksec(n, seed):
    # Generate a reproducible pseudorandom n-bit secret cube, representing
    # a defender’s protected cube and determined by seed.
    import hashlib
    d = hashlib.sha256(seed.encode()).digest()
    return [(d[i % len(d)] >> (i % 8)) & 1 for i in range(n)]

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('origin'); ap.add_argument('popcount')
    ap.add_argument('n', type=int); ap.add_argument('h', type=int)
    ap.add_argument('out_idx', type=int, nargs='?', default=0)
    ap.add_argument('ksec_bits', nargs='?', default='')
    ap.add_argument('--protected-inputs', type=Path, help='JSON ordered list: entry i is paired with keyinputi')
    ap.add_argument('--output-name', help='Gate-driven primary output to protect')
    opts = ap.parse_args()
    origin, pcpath, n, h, out_idx = opts.origin, opts.popcount, opts.n, opts.h, opts.out_idx
    if n < 1 or not 0 <= h <= n or out_idx < 0:
        ap.error('require n >= 1, 0 <= h <= n and out_idx >= 0')
    # Use an explicit secret bit string or a deterministic benchmark-derived
    # pseudorandom cube. A short explicit string is zero-padded for compatibility.
    if opts.ksec_bits:
        if len(opts.ksec_bits) > n or set(opts.ksec_bits) - {'0', '1'}:
            ap.error('ksec_bits must contain at most n binary digits')
        ksec = [int(c) for c in opts.ksec_bits]
        ksec += [0] * (n - len(ksec))
    else:
        ksec = gen_ksec(n, f"{origin}:{n}:{h}")

    oin, oout, ogates = parse_bench(origin)
    pin, pout_l, pgates = parse_bench(pcpath)
    if len(pin) != n or len(pout_l) != 1:
        ap.error('popcount block must have exactly n inputs and one output')
    pc_in, pc_out = pin, pout_l[0]
    if len(oin) < n:
        print(f"ERROR: origin has {len(oin)} PIs < n={n}", file=sys.stderr); sys.exit(1)
    protected = json.loads(opts.protected_inputs.read_text()) if opts.protected_inputs else oin[:n]
    if not isinstance(protected, list) or any(not isinstance(w, str) for w in protected):
        ap.error('protected inputs must be a JSON list of wire names')
    if len(protected) != n or len(set(protected)) != n or set(protected) - set(oin):
        ap.error('protected inputs must be n distinct original primary inputs')
    # Choose a gate-driven protected PO. A primary-input passthrough has no driver
    # to internalize as __f and would leave an undefined wire; c2670/c7552 contain such outputs.
    gate_names = {nm for nm, _, _ in ogates}
    gate_outs = [w for w in oout if w in gate_names]
    if not gate_outs:
        print("ERROR: no gate-driven output to protect", file=sys.stderr); sys.exit(1)
    if opts.output_name:
        if opts.output_name not in gate_outs:
            ap.error('output-name must name a gate-driven primary output')
        po = opts.output_name
    else:
        if out_idx >= len(gate_outs):
            ap.error('out_idx exceeds the gate-driven output list')
        po = gate_outs[out_idx]
    pof = po + "__f"   # Internalize the original protected output; reserve its PO name for the lock, as sld requires matching names.

    ksec_str = "".join(str(b) for b in ksec)
    lines = [f"# SFLL-HD^{h} locked (splice_sfll.py): f XOR [HD(x,ksec)==h] XOR [HD(x,key)==h]",
             f"# secret cube ksec = {ksec_str} (correct key); weight = {sum(ksec)}",
             f"# ordered protected inputs = {json.dumps(protected)}; protected output = {po}"]
    # Append keyinput0..n-1 after the original primary inputs.
    for w in oin:            lines.append(f"INPUT({w})")
    keys = [f"keyinput{i}" for i in range(n)]
    for k in keys:           lines.append(f"INPUT({k})")
    # Retain all original output names, including the protected PO now driven by the lock.
    for w in oout:
        lines.append(f"OUTPUT({w})")

    body = []
    # Rename original definitions and uses of the protected PO to pof, leaving po for the final lock.
    for nm, f, args in ogates:
        nm2 = pof if nm == po else nm
        args2 = [pof if a == po else a for a in args]
        body.append(f"{nm2} = {f}({', '.join(args2)})")
    # Perturb by XORing each protected bit with ksec; use NOT where the secret bit is 1.
    pmap = {}
    for i in range(n):
        if ksec[i]:
            body.append(f"P_xin{i} = not({protected[i]})")
            pmap[pc_in[i]] = f"P_xin{i}"
        else:
            pmap[pc_in[i]] = protected[i]
    pg, p_out = instance(pgates, pc_in, pc_out, "P_", pmap)
    for nm, f, args in pg: body.append(f"{nm} = {f}({', '.join(args)})")
    # Restore by XORing protected[i] with keyinput_i and feeding rxor_i to the comparator.
    for i in range(n):
        body.append(f"R_xin{i} = xor({protected[i]}, {keys[i]})")
    rmap = {pc_in[i]: f"R_xin{i}" for i in range(n)}
    rg, r_out = instance(pgates, pc_in, pc_out, "R_", rmap)
    for nm, f, args in rg: body.append(f"{nm} = {f}({', '.join(args)})")
    # Drive the original output name po with f XOR perturb XOR restore.
    body.append(f"sfll_t0 = xor({pof}, {p_out})")
    body.append(f"{po} = xor(sfll_t0, {r_out})")

    print("\n".join(lines + body))

if __name__ == "__main__":
    main()
