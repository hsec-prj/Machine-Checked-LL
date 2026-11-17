#!/usr/bin/env python3
"""Wire a contiguous bus of positional inputs to the supplied constant bits."""
import re, sys

INP = re.compile(r"^\s*INPUT\(\s*w(\d+)\s*\)\s*$")


def main(argv):
    if len(argv) != 5:
        sys.exit("usage: fix_wires.py <in.bench> <first-index> <bits> <out.bench>")
    src, first, bits, dst = argv[1], int(argv[2]), argv[3], argv[4]
    lines = open(src, encoding="utf-8", errors="replace").read().splitlines()

    want = {first + i: b for i, b in enumerate(bits)}
    consts, out, seen = [], [], set()
    for line in lines:
        m = INP.match(line)
        if m and int(m.group(1)) in want:
            i = int(m.group(1)); seen.add(i)
            consts.append(f"w{i} = {'vdd' if want[i] == '1' else 'gnd'}()")
        else:
            out.append(line)

    missing = set(want) - seen
    if missing:
        sys.exit(f"inputs not found: {sorted(missing)[:5]}")

    last_io = max(i for i, l in enumerate(out)
                  if l.strip().startswith(("INPUT(", "OUTPUT(")))
    out[last_io + 1:last_io + 1] = consts
    open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")


if __name__ == "__main__":
    main(sys.argv)
