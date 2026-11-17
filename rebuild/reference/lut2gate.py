#!/usr/bin/env python3
"""lut2gate.py -- rewrite an ABC `.bench` from LUT form into gate form.

Backlog P4.12 (Route A), concern E-01(b).

ABC writes `.bench` as `w = LUT 0x8 ( a, b )` -- a truth-table mask over the
listed inputs.  The SAT attack's parser accepts named gates (`and`, `or`,
`not`, ...) and not LUTs, so a cone ABC extracted cannot be handed to it as the
unlocked reference until it is expanded.

The expansion is a sum of products over the mask's true rows: exact, and needing
no library.  The BIT ORDER of the mask -- whether the first listed input is the
high bit -- is not documented where we can see it, so it is not guessed.  The
caller checks the result with `abc cec` against the LUT original and
`--msb-first/--lsb-first` selects the convention; a wrong choice fails that
check rather than silently producing a different circuit.
"""
import argparse, pathlib, re

LUT = re.compile(r"^\s*(\S+)\s*=\s*LUT\s+0x([0-9a-fA-F]+)\s*\(\s*([^)]*)\)\s*$")


def expand(name, mask, ins, msb_first, fresh):
    k = len(ins)
    rows = [i for i in range(1 << k) if (mask >> i) & 1]
    out = []
    if not rows:                                    # constant 0
        nv = fresh("z")
        out.append(f"{nv} = not({ins[0]})")
        out.append(f"{name} = and({ins[0]}, {nv})")
        return out
    if len(rows) == (1 << k):                       # constant 1
        nv = fresh("z")
        out.append(f"{nv} = not({ins[0]})")
        out.append(f"{name} = or({ins[0]}, {nv})")
        return out

    negs = {}
    def lit(i, positive):
        if positive:
            return ins[i]
        if i not in negs:
            w = fresh("n")
            out.append(f"{w} = not({ins[i]})")
            negs[i] = w
        return negs[i]

    terms = []
    for r in rows:
        lits = []
        for j in range(k):
            pos = (k - 1 - j) if msb_first else j
            lits.append(lit(pos, bool((r >> j) & 1)))
        if len(lits) == 1:
            terms.append(lits[0])
        else:
            w = fresh("p")
            out.append(f"{w} = and({', '.join(lits)})")
            terms.append(w)
    if len(terms) == 1:
        out.append(f"{name} = or({terms[0]}, {terms[0]})")
    else:
        out.append(f"{name} = or({', '.join(terms)})")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--msb-first", action="store_true", default=True)
    g.add_argument("--lsb-first", dest="msb_first", action="store_false")
    a = ap.parse_args()

    counter = {"i": 0}
    def fresh(tag):
        counter["i"] += 1
        return f"lg_{tag}{counter['i']}"

    out, luts = [], 0
    for line in pathlib.Path(a.src).read_text(encoding="utf-8").splitlines():
        m = LUT.match(line)
        if not m:
            out.append(line); continue
        luts += 1
        ins = [x.strip() for x in m.group(3).split(",") if x.strip()]
        out += expand(m.group(1), int(m.group(2), 16), ins, a.msb_first, fresh)
    pathlib.Path(a.dst).write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"expanded {luts} LUT(s) ({'msb' if a.msb_first else 'lsb'}-first)")


if __name__ == "__main__":
    main()
