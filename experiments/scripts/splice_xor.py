#!/usr/bin/env python3
# Insert key-controlled XORs on deterministically selected internal gate nets.
# Each selected driver becomes net__xpre; net = XOR(net__xpre, keyinput_i).
# The all-zero key restores the original function by XOR identity.
# This baseline transformation implies no universal SAT/DIP recovery count.
# Invocation: splice_xor.py <origin.bench> <n> [seed] -> stdout.
import sys, re, hashlib

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

def main():
    if len(sys.argv) < 3:
        print("usage: splice_xor.py <origin.bench> <n> [seed]", file=sys.stderr); sys.exit(2)
    origin, n = sys.argv[1], int(sys.argv[2])
    seed = sys.argv[3] if len(sys.argv) > 3 else origin
    oin, oout, ogates = parse_bench(origin)

    # Select n gate-output nets in a deterministic pseudorandom order for locking.
    gate_outs = [nm for nm, _, _ in ogates]
    order = sorted(range(len(gate_outs)),
                   key=lambda i: hashlib.sha256(f"{seed}:{i}".encode()).hexdigest())
    if len(gate_outs) < n:
        print(f"ERROR: {len(gate_outs)} gate nets < n={n}", file=sys.stderr); sys.exit(1)
    locked = {gate_outs[i]: j for j, i in enumerate(order[:n])}   # associate each selected net with its key-bit index

    lines = [f"# random XOR locking baseline (splice_xor.py): {n}-bit key, correct key = 0…0"]
    for w in oin:  lines.append(f"INPUT({w})")
    keys = [f"keyinput{i}" for i in range(n)]
    for k in keys: lines.append(f"INPUT({k})")
    for w in oout: lines.append(f"OUTPUT({w})")

    body = []
    for nm, f, args in ogates:
        if nm in locked:
            # Move the original driver to nm__xpre; xor(nm__xpre, key) drives nm and its fan-out.
            body.append(f"{nm}__xpre = {f}({', '.join(args)})")
            body.append(f"{nm} = xor({nm}__xpre, {keys[locked[nm]]})")
        else:
            body.append(f"{nm} = {f}({', '.join(args)})")
    print("\n".join(lines + body))

if __name__ == "__main__":
    main()
