#!/usr/bin/env python3
# Convert ABC write_bench LUT .bench files to sld-compatible and/or/not/buf/vdd/gnd gates.
# Convert ABC-mapped circuits, including ITC-99 inputs, to gate syntax.
# Expand each k-input LUT into a truth-table SOP, caching negated literals and
# building binary AND/OR trees. After abc strash most LUTs have one or two inputs,
# so expansion is small; the splice constant-folding pass absorbs vdd/gnd sources.
# Invocation: lut2gate.py < in.bench > out.bench
import sys, re

gc = [0]
def nw():
    gc[0] += 1; return f"_lg{gc[0]}"

def expand(out, val, args):
    k = len(args); n = 1 << k
    ms = [i for i in range(n) if (val >> i) & 1]
    if not ms:        return [(out, 'gnd', [])]
    if len(ms) == n:  return [(out, 'vdd', [])]
    gates, neg = [], {}
    def lit(a, pos):                       # return the literal, caching its negation when needed
        if pos: return a
        if a not in neg:
            w = nw(); gates.append((w, 'not', [a])); neg[a] = w
        return neg[a]
    terms = []
    for m in ms:                           # form each minterm as a conjunction of literals
        ls = [lit(args[j], (m >> j) & 1) for j in range(k)]
        cur = ls[0]
        for x in ls[1:]:
            w = nw(); gates.append((w, 'and', [cur, x])); cur = w
        terms.append(cur)
    if len(terms) == 1:                    # combine SOP terms through a binary OR tree
        gates.append((out, 'buf', [terms[0]]))
    else:
        cur = terms[0]
        for i, t in enumerate(terms[1:]):
            w = out if i == len(terms) - 2 else nw()
            gates.append((w, 'or', [cur, t])); cur = w
    return gates

LUTRE = re.compile(r'(\S+)\s*=\s*LUT\s+0x([0-9A-Fa-f]+)\s*\((.*)\)')
# ABC fills undriven nets with unparenthesized constants: `wire = gnd` or `wire = vdd`.
CONRE = re.compile(r'(\S+)\s*=\s*(gnd|vdd|VDD|GND)\s*\(?\s*\)?\s*$')
INRE  = re.compile(r'INPUT\((\w+)\)')

lines = [ln.rstrip('\n') for ln in sys.stdin]
first_pi = next((INRE.search(l).group(1) for l in lines if INRE.search(l)), None)
notpi = None  # lazily create NOT(first_pi) for synthesizing constants

out_lines = []
for l in lines:
    s = l.strip()
    m = LUTRE.match(s)
    if m:
        out = m.group(1); val = int(m.group(2), 16)
        args = [a.strip() for a in m.group(3).split(',') if a.strip()]
        for nm, f, ar in expand(out, val, args):
            out_lines.append(f"{nm} = {f}({', '.join(ar)})" if ar else f"{nm} = {f}()")
        continue
    c = CONRE.match(s)
    if c and first_pi:                         # realize constants with a PI and its complement for sld compatibility
        out = c.group(1); lo = c.group(2).lower()
        if notpi is None:
            notpi = "_const_npi"; out_lines.append(f"{notpi} = not({first_pi})")
        out_lines.append(f"{out} = {'or' if lo=='vdd' else 'and'}({first_pi}, {notpi})")
        continue
    out_lines.append(l)

# One/two-input LUT expansion should not emit vdd/gnd; retain this defensive conversion.
print("\n".join(out_lines))
