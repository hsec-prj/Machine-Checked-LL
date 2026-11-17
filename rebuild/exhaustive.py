import hashlib, math, os, re

from pathlib import Path

HERE = str(Path(__file__).resolve().parent)

BLOCK_LOG2 = 24                         # truth-table block: 2^24 bits = 2 MiB per signal

class InputError(Exception):
    """Malformed or inconsistent input: exit status 2, no TSV row."""

ARITY = {"AND": (1, None), "NAND": (1, None), "OR": (1, None), "NOR": (1, None),
         "XOR": (2, None), "XNOR": (2, None), "NOT": (1, 1), "BUF": (1, 1),
         "VDD": (0, 0), "GND": (0, 0)}

_NAME = r"[^\s(),=#]+"

_PORT = re.compile(r"(INPUT|OUTPUT)\s*\(\s*(%s)\s*\)" % _NAME, re.I)

_LUT = re.compile(r"(%s)\s*=\s*LUT\s+0x([0-9a-fA-F]+)\s*\(([^()]*)\)" % _NAME)

_GATE = re.compile(r"(%s)\s*=\s*([A-Za-z]+)\s*\(([^()]*)\)" % _NAME)

_CONST = re.compile(r"(%s)\s*=\s*(vdd|gnd)" % _NAME, re.I)

class Bench:
    """Parsed .bench: ordered inputs, outputs and gates (name, op, args, lut_code)."""

    def __init__(self, ins, outs, gates, path=None):
        self.ins, self.outs, self.gates, self.path = ins, outs, gates, path
        self.drv = {g[0]: g for g in gates}

    def check_closed(self):
        """Every referenced net and every OUTPUT is an INPUT or driven by a gate."""
        defined = set(self.ins) | set(self.drv)
        missing = {a for g in self.gates for a in g[2] if a not in defined}
        missing |= {o for o in self.outs if o not in defined}
        if missing:
            raise InputError(f"{self.path}: undriven nets {sorted(missing)[:8]}")

def _split_args(text, where):
    if not text.strip():
        return []
    args = [a.strip() for a in text.split(",")]
    if any(not a for a in args):
        raise InputError(f"{where}: empty gate argument")
    return args

def parse_bench(text, where="<bench>"):
    """Strict reader. Unknown syntax or operators, bad arity, a net driven twice and an INPUT
    that is also driven are errors; nothing is skipped silently."""
    ins, outs, gates, driven, outset = [], [], [], set(), set()

    def add(name, op, args, code, no):
        if name in driven:
            raise InputError(f"{where}:{no}: {name} is driven twice")
        driven.add(name)
        gates.append((name, op, args, code))

    for no, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        m = _PORT.fullmatch(line)
        if m:
            kind, name = m.group(1).upper(), m.group(2)
            if kind == "INPUT":
                if name in driven:
                    raise InputError(f"{where}:{no}: INPUT {name} declared twice or driven")
                driven.add(name)
                ins.append(name)
            else:
                if name in outset:
                    raise InputError(f"{where}:{no}: OUTPUT {name} declared twice")
                outset.add(name)
                outs.append(name)
            continue
        m = _LUT.fullmatch(line)
        if m:
            args, code = _split_args(m.group(3), f"{where}:{no}"), int(m.group(2), 16)
            if not args or code >> (1 << len(args)):
                raise InputError(f"{where}:{no}: bad LUT")
            add(m.group(1), "LUT", args, code, no)
            continue
        m = _GATE.fullmatch(line)
        if m:
            op = m.group(2).upper()
            op = "BUF" if op == "BUFF" else op
            if op not in ARITY:
                raise InputError(f"{where}:{no}: unsupported operator {m.group(2)}")
            args = _split_args(m.group(3), f"{where}:{no}")
            lo, hi = ARITY[op]
            if len(args) < lo or (hi is not None and len(args) > hi):
                raise InputError(f"{where}:{no}: {op} with {len(args)} inputs")
            add(m.group(1), op, args, None, no)
            continue
        m = _CONST.fullmatch(line)
        if m:
            add(m.group(1), m.group(2).upper(), [], None, no)
            continue
        raise InputError(f"{where}:{no}: unsupported syntax: {line[:100]}")
    if not outs:
        raise InputError(f"{where}: no OUTPUT")
    return Bench(ins, outs, gates, where)

def read_bench(path):
    with open(path, encoding="utf-8") as fh:
        return parse_bench(fh.read(), path)

def gate_value(op, xs, code, M):
    """Value of one gate on truth tables (Python ints whose live bits are the bits of M)."""
    if op in ("AND", "NAND"):
        r = M
        for t in xs:
            r &= t
        return r if op == "AND" else r ^ M
    if op in ("OR", "NOR"):
        r = 0
        for t in xs:
            r |= t
        return r if op == "OR" else r ^ M
    if op in ("XOR", "XNOR"):
        r = 0
        for t in xs:
            r ^= t
        return r if op == "XOR" else r ^ M
    if op == "NOT":
        return xs[0] ^ M
    if op == "BUF":
        return xs[0]
    if op == "VDD":
        return M
    if op == "GND":
        return 0
    if op == "LUT" and len(xs) == 2:    # direct forms of the 16 two-input codes (a = arg 0)
        return _LUT2[code](xs[0], xs[1], M)
    if op == "LUT" and len(xs) == 1:
        return (0, xs[0] ^ M, xs[0], M)[code]
    if op == "LUT":                     # bit m of code = output at minterm m; argument i = bit i of m
        r = 0
        for m in range(1 << len(xs)):
            if (code >> m) & 1:
                t = M
                for i, x in enumerate(xs):
                    t &= x if (m >> i) & 1 else x ^ M
                r |= t
        return r
    raise InputError(f"unknown operator {op}")

_LUT2 = (lambda a, b, M: 0, lambda a, b, M: (a | b) ^ M, lambda a, b, M: a & (b ^ M),
         lambda a, b, M: b ^ M, lambda a, b, M: (a ^ M) & b, lambda a, b, M: a ^ M,
         lambda a, b, M: a ^ b, lambda a, b, M: (a & b) ^ M, lambda a, b, M: a & b,
         lambda a, b, M: a ^ b ^ M, lambda a, b, M: a, lambda a, b, M: a | (b ^ M),
         lambda a, b, M: b, lambda a, b, M: (a ^ M) | b, lambda a, b, M: a | b, lambda a, b, M: M)

class Cone:
    """Transitive fan-in of `target`, topologically ordered. Undriven nets reached are the
    leaves. Each net is freed right after its last use (liveness), so 2^24-bit tables do
    not accumulate."""

    def __init__(self, drv, target):
        order, state, leaves = [], {}, []
        stack = [(target, False)]
        while stack:
            w, done = stack.pop()
            if done:
                state[w] = 2
                order.append(drv[w])
                continue
            if w in state:
                if state[w] == 1:       # reached again while still open: a back edge
                    raise InputError(f"combinational cycle through {w}")
                continue
            if w not in drv:
                state[w] = 2
                leaves.append(w)
                continue
            state[w] = 1
            stack.append((w, True))
            for a in reversed(drv[w][2]):
                if state.get(a) != 2:
                    stack.append((a, False))
        self.target, self.order, self.leaves = target, order, leaves
        last = {}
        for i, g in enumerate(order):
            for a in g[2]:
                last[a] = i
        self.frees = [[] for _ in order]
        for a, i in last.items():
            if a != target:
                self.frees[i].append(a)

    def run(self, inval, M):
        val = {}
        for leaf in self.leaves:
            if leaf not in inval:
                raise InputError(f"no value for net {leaf} in the cone of {self.target}")
            val[leaf] = inval[leaf]
        for i, (w, op, args, code) in enumerate(self.order):
            val[w] = gate_value(op, [val[a] for a in args], code, M)
            for a in self.frees[i]:
                del val[a]
        return val[self.target]

def var_tt(j, nv):
    """Truth table of variable j over nv variables: bit t is (t >> j) & 1."""
    size, w = 1 << nv, 1 << j
    t, width = ((1 << w) - 1) << w, 2 * w
    while width < size:
        t |= t << width
        width *= 2
    return t

def segment_counts(D, seg, count):
    """Popcount of each consecutive seg-bit field of D (field r = bits r*seg .. r*seg+seg-1)."""
    if seg % 8 == 0:
        sb = seg // 8
        raw = D.to_bytes(sb * count, "little")
        return [int.from_bytes(raw[r * sb:(r + 1) * sb], "little").bit_count() for r in range(count)]
    mask = (1 << seg) - 1
    return [((D >> (r * seg)) & mask).bit_count() for r in range(count)]

def eq_count(diffs, h, M):
    """[popcount(diffs) == h] by a bit-sliced ripple counter of half adders over the n
    difference signals; structurally unrelated to the emitted popcount comparator."""
    n = len(diffs)
    if not 0 <= h <= n:
        raise InputError(f"h={h} outside 0..{n}")
    width = max(1, n.bit_length())
    c = [0] * width
    for d in diffs:
        carry = d
        for b in range(width):
            if not carry:
                break
            c[b], carry = c[b] ^ carry, c[b] & carry
    r = M
    for b in range(width):
        r &= c[b] if (h >> b) & 1 else c[b] ^ M
    return r

def ocr(n, h, d):
    """Corrupted inputs of one key at Hamming distance d from the secret (closed form):
    2*C(n,h) - 2*#{x : HD(x,s) = HD(x,k) = h}."""
    both = (math.comb(d, d // 2) * math.comb(n - d, h - d // 2)
            if d % 2 == 0 and 0 <= h - d // 2 <= n - d else 0)
    return 2 * math.comb(n, h) - 2 * both

def total_corruption(n, h):
    """T(n,h): corruptions summed over all 2^n - 1 wrong keys."""
    return sum(math.comb(n, d) * ocr(n, h, d) for d in range(1, n + 1))

def bits_to_int(bits):
    """Character i of a bit string is bit i (LSB first): the secret / CLI convention."""
    return sum(1 << i for i, c in enumerate(bits) if c == "1")

def int_to_bits(v, n):
    return "".join("1" if (v >> i) & 1 else "0" for i in range(n))

def mult_column(a, b, j):
    """Gates of bit j of the unsigned product A*B (a, b: input names, lsb first). AND partial
    products a_i b_k with i+k <= j; each column is reduced with full/half adders in FIFO order,
    carries going to the next column. Returns (gates, target)."""
    gates = []

    def g(op, *args):
        name = f"m{len(gates)}"
        gates.append((name, op, list(args), None))
        return name

    cols = [[] for _ in range(j + 2)]
    for i in range(len(a)):
        for k in range(len(b)):
            if i + k <= j:
                cols[i + k].append(g("AND", a[i], b[k]))
    for c in range(j + 1):
        bits = cols[c]
        while len(bits) > 1:
            if len(bits) >= 3:
                x, y, z = bits.pop(0), bits.pop(0), bits.pop(0)
                t = g("XOR", x, y)
                bits.append(g("XOR", t, z))
                cols[c + 1].append(g("OR", g("AND", x, y), g("AND", t, z)))
            else:
                x, y = bits.pop(0), bits.pop(0)
                bits.append(g("XOR", x, y))
                cols[c + 1].append(g("AND", x, y))
    if not cols[j]:
        gates.append(("m_zero", "GND", [], None))
        return gates, "m_zero"
    return gates, cols[j][0]

class Golden:
    """f of one protected output from a source independent of the emission path.
    gates: topological gate list over leaf names; leaf_pos: leaf name -> position i of x.
    `extra` lists source inputs the cone reads structurally but the port-map support lacks
    (the emission path's mapping removed them as redundant). They are tied to 0, and every
    case using such a golden must first pass prove_extra_independent (f(x,e) == f(x,0))."""

    def __init__(self, kind, gates, target, negate, leaf_pos, source, source_sha256, note,
                 source_inputs=None):
        drv = {g[0]: g for g in gates}
        if set(drv) & set(leaf_pos):
            raise InputError("golden: a support name is also a gate name")
        self.cone = Cone(drv, target)
        self.extra = sorted(l for l in self.cone.leaves if l not in leaf_pos)
        stray = [l for l in self.extra if source_inputs is None or l not in source_inputs]
        if stray:
            raise InputError(f"golden cone of {target} reads nets that are not source inputs: {stray[:8]}")
        self.kind, self.gates, self.target, self.negate = kind, self.cone.order, target, negate
        self.leaf_pos, self.source, self.source_sha256, self.note = leaf_pos, source, source_sha256, note
        used = set(self.cone.leaves)
        self.unused = sorted(i for l, i in leaf_pos.items() if l not in used)

    def eval(self, xs, M):
        inval = {l: xs[i] for l, i in self.leaf_pos.items()}
        inval.update({l: 0 for l in self.extra})
        v = self.cone.run(inval, M)
        return v ^ M if self.negate else v

def _invert(m, what):
    inv = {}
    for k, v in m.items():
        if v in inv:
            raise InputError(f"correspondence {what} map is not injective at {v}")
        inv[v] = k
    return inv

def _resolve(p):
    """P1 port maps store committed inputs relative to experiments/scripts."""
    return p if not p or os.path.isabs(p) else os.path.normpath(os.path.join(HERE, p))

def load_golden(corr, portmap, sld_override=None, guard_paths=()):
    kind = corr.get('golden', 'sld')
    out, support = (portmap['out'], portmap['support'])
    if kind == 'sld':
        path = sld_override or corr.get('sld')
        if not path or not os.path.isfile(path):
            raise InputError(f'sld original not found: {path}')
        digest = sha256_file(path)
        for gp in guard_paths:
            gp = _resolve(gp)
            if gp and os.path.isfile(gp) and (os.path.realpath(gp) == os.path.realpath(path) or sha256_file(gp) == digest):
                raise InputError(f'golden source {path} is an emission-path file ({gp})')
        src = read_bench(path)
        src.check_closed()
        if any((g[1] == 'LUT' for g in src.gates)):
            raise InputError(f'golden source {path} has LUT gates: not a gate-level original')
        pi, po = (corr['pi'], corr['po'])
        if set(pi) != set(src.ins) or set(po) != set(src.outs):
            raise InputError('correspondence JSON does not cover exactly the sld PIs and POs')
        inv_pi, inv_po = (_invert(pi, 'pi'), _invert(po, 'po'))
        if out not in inv_po:
            raise InputError(f'port-map output {out} has no sld PO in the correspondence')
        leaf_pos = {}
        for i, name in enumerate(support):
            if name not in inv_pi:
                raise InputError(f'support input {name} has no sld PI in the correspondence')
            leaf_pos[inv_pi[name]] = i
        target, neg = (inv_po[out], bool(corr.get('po_negated', False)))
        cone = Cone(src.drv, target)
        return Golden('sld+po_negated' if neg else 'sld', cone.order, target, neg, leaf_pos, path, digest, f'sld {target} for {out}' + (', negated' if neg else ''), source_inputs=set(src.ins))
    if kind == 'mult16x16':
        A, B, P = (corr['A'], corr['B'], corr['P'])
        if len(A) != 16 or len(B) != 16 or len(P) != 32 or (len(set(A + B)) != 32) or (len(set(P)) != 32):
            raise InputError('mult16x16 needs 16 A, 16 B and 32 P port names, all distinct')
        if out not in P:
            raise InputError(f'{out} is not a product bit of the mult16x16 correspondence')
        j = P.index(out)
        gates, target = mult_column(A, B, j)
        return Golden(kind, gates, target, False, {p: i for i, p in enumerate(support)}, 'builtin:mult_column', 'harness', f'bit {j} of the unsigned product A*B', source_inputs=set(A + B))
    raise InputError(f'unknown golden kind {kind!r}')

class Case:
    """One emitted lock: its bench, port map, golden f, secret and h."""

    def __init__(self, emitted, portmap, golden, secret, h):
        support = portmap["support"]
        n = len(support)
        if n == 0 or len(set(support)) != n or portmap.get("n", n) != n:
            raise InputError("port map support is empty, repeated or disagrees with its n")
        if emitted.ins != [f"w{i}" for i in range(2 * n)]:
            raise InputError(f"emitted inputs are not w0..w{2 * n - 1} in order "
                             f"({len(emitted.ins)} inputs for n={n})")
        if len(emitted.outs) != 1:
            raise InputError("emitted bench must have exactly one OUTPUT")
        emitted.check_closed()
        if not re.fullmatch(r"[01]+", secret or "") or len(secret) != n:
            raise InputError(f"secret must be {n} characters of 0/1")
        if not 0 <= h <= n:
            raise InputError(f"h={h} outside 0..{n}")
        self.emitted, self.portmap, self.golden = emitted, portmap, golden
        self.n, self.h, self.secret = n, h, secret
        self.sbits = [int(c) for c in secret]
        self.S = bits_to_int(secret)
        self.out = emitted.outs[0]
        self.cone = Cone(emitted.drv, self.out)
        self.abc_golden = golden         # f written into ABC benches; a bridged cone with --bridge

    def lock_inputs(self, xs, ks):
        d = {f"w{i}": xs[i] for i in range(self.n)}
        d.update({f"w{self.n + i}": ks[i] for i in range(self.n)})
        return d

    def batch_D(self, points):
        """D(x,k) = L(x,k) ^ f(x) at each (X, K) of `points` (ints, bit-string convention),
        evaluated in one bit-parallel pass (vector v = bit v)."""
        M = (1 << len(points)) - 1
        xs = [sum(((X >> i) & 1) << v for v, (X, _) in enumerate(points)) for i in range(self.n)]
        ks = [sum(((K >> i) & 1) << v for v, (_, K) in enumerate(points)) for i in range(self.n)]
        D = self.cone.run(self.lock_inputs(xs, ks), M) ^ self.golden.eval(xs, M)
        return [(D >> v) & 1 for v in range(len(points))]

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def run_exhaustive(case):
    n, h, S = case.n, case.h, case.S
    if n > BLOCK_LOG2:
        raise InputError(f"exhaustive needs n <= {BLOCK_LOG2} (all x in one block)")
    nv, full = 2 * n, (1 << n) - 1
    low = min(nv, BLOCK_LOG2)
    M = (1 << (1 << low)) - 1
    base = [var_tt(j, low) for j in range(low)]
    xs = base[:n]
    f = case.golden.eval(xs, M)
    exs = eq_count([xs[i] ^ (M if case.sbits[i] else 0) for i in range(n)], h, M)
    kpb, seg = 1 << (low - n), 1 << n          # keys per block; inputs per key
    want = [ocr(n, h, d) for d in range(n + 1)]
    mism = total = ocr_bad = 0
    restore, zero = None, []
    for blk in range(1 << (nv - low)):         # key bits n+i >= low are constant per block
        ks = [base[n + i] if n + i < low else (M if (blk >> (n + i - low)) & 1 else 0) for i in range(n)]
        L = case.cone.run(case.lock_inputs(xs, ks), M)
        exk = eq_count([xs[i] ^ ks[i] for i in range(n)], h, M)
        mism += (L ^ f ^ exs ^ exk).bit_count()
        D = L ^ f
        del L, exk, ks
        for r, c in enumerate(segment_counts(D, seg, kpb)):
            K = r + (blk << (low - n))
            if K == S:
                restore = seg - c
                continue
            total += c
            ocr_bad += c != want[(K ^ S).bit_count()]
            if c == 0:
                zero.append(K)
        del D
    zero_expected = [S ^ full] if n % 2 == 0 and h == n // 2 else []
    res = {"pairs_log2": nv, "blocks": 1 << (nv - low), "mismatches": mism, "restore": restore,
           "restore_expected": 1 << n, "corruption_total": total,
           "corruption_expected": total_corruption(n, h), "perkey_ocr_bad": ocr_bad,
           "zero_corruption_wrong_keys": len(zero), "zero_corruption_expected": len(zero_expected)}
    checks = [("mismatches", mism, 0), ("restore", restore, 1 << n),
              ("corruption_total", total, res["corruption_expected"]), ("perkey_ocr_bad", ocr_bad, 0),
              ("zero_corruption_keys", [int_to_bits(k, n) for k in zero],
               [int_to_bits(k, n) for k in zero_expected])]
    return res, checks, {"zero_corruption_keys": [int_to_bits(k, n) for k in zero]}
