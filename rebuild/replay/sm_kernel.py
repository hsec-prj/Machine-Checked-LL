"""Functional golden/miter/controls/pair checks for the registered, known test configurations."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from exhaustive import InputError, Golden, Cone, read_bench, var_tt, int_to_bits, sha256_file
from s4_sampler import seeded_rng
DEFAULT_ABC = "yosys-abc"


INCONCLUSIVE = ("TIMEOUT", "ERROR", "UNKNOWN")

def gate_lines(name, op, args, code):
    """One gate in the bench dialect ABC reads. ABC aborts on n-ary XOR, so XOR/XNOR with more
    than two inputs become 2-input chains; 1-input AND/OR/NAND/NOR become BUFF/NOT."""
    if op == "LUT":
        return [f"{name} = LUT 0x{code:x} ( {', '.join(args)} )"]
    if op in ("VDD", "GND"):
        return [f"{name} = {op.lower()}()"]
    if len(args) == 1 and op in ("AND", "OR"):
        return [f"{name} = BUFF({args[0]})"]
    if len(args) == 1 and op in ("NAND", "NOR"):
        return [f"{name} = NOT({args[0]})"]
    if op in ("XOR", "XNOR") and len(args) > 2:
        lines, acc = [], args[0]
        for i, a in enumerate(args[1:-1]):
            lines.append(f"{name}__x{i} = XOR({acc}, {a})")
            acc = f"{name}__x{i}"
        return lines + [f"{name} = {op}({acc}, {args[-1]})"]
    return [f"{name} = {'BUFF' if op == 'BUF' else op}({', '.join(args)})"]

class Lines:
    """Gate lines under construction. Helper nets are tag+counter; tags end in a letter or _,
    so helper names never collide (golden nets use F_, emitted copies L_)."""

    def __init__(self):
        self.lines, self.k = [], 0

    def fresh(self, tag):
        self.k += 1
        return f"{tag}{self.k}"

    def gate(self, name, op, args):
        self.lines += gate_lines(name, op, args, None)
        return name

def and_tree(B, sigs, tag):
    sigs = list(sigs)
    while len(sigs) > 1:
        nxt = [B.gate(B.fresh(tag), "AND", [sigs[i], sigs[i + 1]]) for i in range(0, len(sigs) - 1, 2)]
        if len(sigs) % 2:
            nxt.append(sigs[-1])
        sigs = nxt
    return sigs[0]

def cube(B, sigs, bits, tag):
    """[sigs == bits] as one AND of literals (bits: 0/1 constants)."""
    lits = [s if b else B.gate(B.fresh(tag + "n"), "NOT", [s]) for s, b in zip(sigs, bits)]
    return and_tree(B, lits, tag)

def xnor_and(B, xs, ks, tag):
    """[xs == ks] as an AND of XNOR(x_i, k_i)."""
    return and_tree(B, [B.gate(B.fresh(tag + "e"), "XNOR", [x, k]) for x, k in zip(xs, ks)], tag)

def golden_lines(B, golden, leafsig, extrasig=None):
    """Write f into B with the leaf at x position i wired to leafsig(i); returns f's signal.
    Extra (redundant) source inputs are tied to 0, or wired to extrasig(name) if given."""
    if not golden.extra:
        tie = {}
    elif extrasig:
        tie = {e: extrasig(e) for e in golden.extra}
    else:
        zero = B.gate(B.fresh("H_tie"), "GND", [])
        tie = {e: zero for e in golden.extra}

    def ren(net):
        if net in golden.leaf_pos:
            return leafsig(golden.leaf_pos[net])
        return tie[net] if net in tie else "F_" + net
    for (w, op, args, code) in golden.gates:
        B.lines += gate_lines(ren(w), op, [ren(a) for a in args], code)
    sig = ren(golden.target)
    if golden.negate:
        sig = B.gate(B.fresh("H_fneg"), "NOT", [sig])
    return sig

def bench_text(header, ins, outs, lines):
    """Assemble a bench; a net defined twice (a helper-name collision) is an error."""
    defined = list(ins) + [l.split(" = ", 1)[0] for l in lines]
    if len(set(defined)) != len(defined):
        raise InputError("generated bench defines a net twice (name collision)")
    return "\n".join([f"# {h}" for h in header] + [f"INPUT({i})" for i in ins]
                     + [f"OUTPUT({o})" for o in outs] + lines) + "\n"

def xk_names(n):
    return [f"w{i}" for i in range(n)], [f"w{n + i}" for i in range(n)]

def golden_bench(case, sbits, swap=None, header=()):
    """G(x,k) = f(x) ^ [x=s] ^ [x=k] over all 2n inputs, output named like the emitted PO.
    swap=(i,j) wires f's leaves i and j crosswise (port-swap control)."""
    xs, ks = xk_names(case.n)
    perm = list(range(case.n))
    if swap:
        perm[swap[0]], perm[swap[1]] = swap[1], swap[0]
    B = Lines()
    f = golden_lines(B, case.abc_golden, lambda i: xs[perm[i]])
    t = B.gate("H_t", "XOR", [f, cube(B, xs, sbits, "T_xs")])
    B.gate(case.out, "XOR", [t, xnor_and(B, xs, ks, "T_xk")])
    return bench_text(header, xs + ks, [case.out], B.lines)

def f_bench(case, points=(), header=()):
    """f(x) ^ XOR_p [x = p] for constant points p, over inputs w0..w(n-1)."""
    xs, _ = xk_names(case.n)
    B = Lines()
    sig = golden_lines(B, case.abc_golden, lambda i: xs[i])
    for idx, p in enumerate(points):
        e = cube(B, xs, [(p >> i) & 1 for i in range(case.n)], f"T_p{idx}_")
        sig = B.gate(B.fresh("H_x"), "XOR", [sig, e])
    B.gate(case.out, "BUFF", [sig])
    return bench_text(header, xs, [case.out], B.lines)

def fixed_key_bench(case, K, header=()):
    """The emitted gates unchanged, with key input w(n+i) replaced by the constant K_i."""
    xs, ks = xk_names(case.n)
    lines = [f"{ks[i]} = {'vdd' if (K >> i) & 1 else 'gnd'}()" for i in range(case.n)]
    for g in case.emitted.gates:
        lines += gate_lines(*g)
    return bench_text(header, xs, [case.out], lines)

QUERIES = {
    "Q0": ("exists x. D(x,s)=1", ["eks", "d"]),
    "Q1": ("exists x,k. D(x,k)=1, x!=s, x!=k", ["d", "nexs", "nexk"]),
    "Q2": ("exists k!=s. D(s,k)=0", ["exs", "neks", "nd"]),
    "Q3": ("exists k!=s. D(k,k)=0", ["exk", "neks", "nd"]),
    "P0": ("exists x. D(x,s)=0", ["eks", "nd"]),
    "P1": ("exists x,k. D(x,k)=0, x!=s, x!=k", ["nd", "nexs", "nexk"]),
    "P2": ("exists k!=s. D(s,k)=1", ["exs", "neks", "d"]),
    "P3": ("exists k!=s. D(k,k)=1", ["exk", "neks", "d"]),
}

def miter_bench(case, query, header=()):
    xs, ks = xk_names(case.n)
    inputs = set(case.emitted.ins)

    def ren(net):
        return net if net in inputs else "L_" + net
    B = Lines()
    for (w, op, args, code) in case.emitted.gates:
        B.lines += gate_lines(ren(w), op, [ren(a) for a in args], code)
    f = golden_lines(B, case.abc_golden, lambda i: xs[i])
    sig = {"d": B.gate("Q_d", "XOR", [ren(case.out), f])}
    sig["nd"] = B.gate("Q_nd", "NOT", [sig["d"]])
    sig["exs"] = cube(B, xs, case.sbits, "T_xs")
    sig["exk"] = xnor_and(B, xs, ks, "T_xk")
    sig["eks"] = cube(B, ks, case.sbits, "T_ks")
    for t in ("exs", "exk", "eks"):
        sig["n" + t] = B.gate(f"Q_n{t}", "NOT", [sig[t]])
    root = and_tree(B, [sig[t] for t in QUERIES[query][1]], "Q_a")
    B.gate("Q_out", "BUFF", [root])
    return bench_text(header, xs + ks, ["Q_out"], B.lines)

ABC_ERROR_MARKERS = ("CANNOT OPEN", "HAS FAILED", "ERROR", "WARNING", "NON-DRIVEN",
                     "UNKNOWN COMMAND", "ASSERTION", "CANNOT DETERMINE", "SEGMENTATION", "ABORT")

def cec_verdict(text):
    """Verdict of `cec` from the WHOLE output. ABC errors and warnings come first (an undriven
    net is silently tied to 0 with a warning), then NOT EQUIVALENT, then equivalent."""
    if text is None:
        return "TIMEOUT"
    u = text.upper()
    if any(m in u for m in ABC_ERROR_MARKERS):
        return "ERROR"
    if "NOT EQUIVALENT" in u:
        return "NEQ"
    if "ARE EQUIVALENT" in u:
        return "EQ"
    return "UNKNOWN"

def sat_verdict(text):
    """Verdict of `sat` from the whole output: errors/warnings, then UNSATISFIABLE, then
    SATISFIABLE (the latter is a substring of the former)."""
    if text is None:
        return "TIMEOUT"
    u = text.upper()
    if any(m in u for m in ABC_ERROR_MARKERS):
        return "ERROR"
    if "UNSATISFIABLE" in u:
        return "UNSAT"
    if "SATISFIABLE" in u:
        return "SAT"
    return "UNKNOWN"

def cex_inputs(text):
    """ABC's counterexample line 'Input pattern:  w0=1 w1=0 ...' as {name: bit}, or None."""
    for line in (text or "").splitlines():
        if line.strip().startswith("Input pattern:"):
            return {k: int(v) for k, v in re.findall(r"(\S+)=([01])\b", line.split(":", 1)[1])}
    return None

def _abc_safe(path):
    if re.search(r"[\s;\"']", path):
        raise InputError(f"path not usable in an ABC command: {path!r}")
    return path

class Abc:
    def __init__(self, path=DEFAULT_ABC, timeout=300):
        self.path, self.timeout, self._version = path, timeout, None
        self.log = []                   # (command, verdict, seconds)

    def version(self):
        if self._version is None:
            try:
                p = subprocess.run([self.path, "-q", "version"], capture_output=True, text=True, timeout=60)
                lines = (p.stdout + p.stderr).strip().splitlines()
                self._version = lines[0].strip() if lines else "unavailable"
            except (OSError, subprocess.TimeoutExpired):
                self._version = "unavailable"
        return self._version

    def available(self):
        return self.version() != "unavailable"

    def run(self, cmd):
        t0 = time.time()
        try:
            p = subprocess.run([self.path, "-q", cmd], capture_output=True, text=True, timeout=self.timeout)
            return (("" if p.returncode == 0 else "ERROR: ABC process failed\n") + p.stdout + p.stderr), time.time() - t0
        except subprocess.TimeoutExpired:
            return None, time.time() - t0
        except OSError as e:            # ABC missing or not executable: an ERROR verdict, not a crash
            return f"ERROR: cannot run {self.path}: {e}", time.time() - t0

    def cec(self, a, b):
        text, dt = self.run(f"cec {_abc_safe(a)} {_abc_safe(b)}")
        v = cec_verdict(text)
        self.log.append((f"cec {a} {b}", v, round(dt, 3)))
        return v, text, dt

    def sat(self, path, fraig=False):
        text, dt = self.run(f"read_bench {_abc_safe(path)}; strash; {'fraig; ' if fraig else ''}sat")
        v = sat_verdict(text)
        self.log.append((f"sat {path}", v, round(dt, 3)))
        return v, text, dt

def ensure_new(path):
    if path and os.path.lexists(path):
        raise InputError(f"refusing to overwrite existing output {path}")

def write_new(path, text):
    with open(path, "x", encoding="utf-8", newline="\n") as fh:
        fh.write(text)

class Work:
    """Directory for generated benches; every file is created new (mode 'x')."""

    def __init__(self, root, label, prune=False):
        if not re.fullmatch(r"[A-Za-z0-9_.+=-]+", label):
            raise InputError(f"label {label!r}: use letters, digits and _ . + = -")
        os.makedirs(root, exist_ok=True)
        self.root, self.label, self.prune, self.files = root, label, prune, []

    def path(self, role):
        p = os.path.join(self.root, f"{self.label}.{role}.bench")
        ensure_new(p)
        return _abc_safe(p)

    def write(self, role, text):
        p = self.path(role)
        write_new(p, text)
        self.files.append((role, p, sha256_file(p)))
        return p

    def adopt(self, role, p):
        """Record a bench ABC wrote."""
        if not os.path.isfile(p):
            return False
        self.files.append((role, p, sha256_file(p)))
        return True

    def done(self, *paths):
        if self.prune:
            for p in paths:
                if os.path.isfile(p):
                    os.remove(p)

def judge(checks):
    """checks: (name, observed, expected). FAIL if any definite violation, INCONCLUSIVE if
    only ABC errors/timeouts/unknowns are left, else PASS."""
    bad = [c for c in checks if c[1] != c[2]]
    hard = [c for c in bad if not (isinstance(c[1], str) and c[1] in INCONCLUSIVE)]
    return ("FAIL" if hard else "INCONCLUSIVE" if bad else "PASS"), [c[0] for c in bad]

def require_h0(case):
    if case.h != 0:
        raise InputError("golden, miter and controls are defined for h=0 only")

def run_golden(case, abc, work, emitted_path):
    _registered_case(emitted_path, case.secret, "golden")
    require_h0(case)
    hdr = [f"configured_check.py golden {work.label}", f"golden f: {case.golden.kind} {case.golden.note}",
           f"f written for ABC: {case.abc_golden.note}"]
    res, checks, det = {}, [], {}
    g = work.write("S1-golden", golden_bench(case, case.sbits, header=hdr + ["G = f ^ [x=s] ^ [x=k]"]))
    v, _, dt = abc.cec(emitted_path, g)
    res.update(S1=v, S1_sec=f"{dt:.2f}")
    checks.append(("S1", v, "EQ"))
    fixed = work.write("S2-fixed-s", fixed_key_bench(case, case.S, header=hdr + ["L(x, s)"]))
    fonly = work.write("S2-f", f_bench(case, header=hdr + ["f(x)"]))
    v, _, dt = abc.cec(fixed, fonly)
    res.update(S2=v, S2_sec=f"{dt:.2f}")
    checks.append(("S2", v, "EQ"))
    work.done(fixed)
    # S6: the same ABC commands as verify-netlist.sh cec_check (dc2 twice; LUT-6 mapping)
    for key, role, script in (("S6_dc2", "S6-dc2", "strash; dc2; dc2"), ("S6_if6", "S6-if6", "strash; if -K 6")):
        p = work.path(role)
        text, dt0 = abc.run(f"read_bench {_abc_safe(emitted_path)}; {script}; write_bench {p}")
        if text is None or cec_verdict(text) == "ERROR" or not work.adopt(role, p):
            v, dt = ("TIMEOUT" if text is None else "ERROR"), dt0
            det[key + "_abc_output"] = (text or "TIMEOUT")[-400:]
        else:
            v, _, dt = abc.cec(emitted_path, p)
            work.done(p)
        res.update({key: v, key + "_sec": f"{dt:.2f}"})
        checks.append((key, v, "EQ"))
    det["S6_commands"] = {"S6_dc2": "strash; dc2; dc2", "S6_if6": "strash; if -K 6"}
    return res, checks, det

def run_miter(case, abc, work, fraig=False):
    _registered_case(case.emitted.path, case.secret, "miter")
    require_h0(case)
    res, checks, mx = {}, [], 0.0
    for q, (meaning, _) in QUERIES.items():
        p = work.write(f"S3-{q}", miter_bench(case, q, header=[f"configured_check.py miter {work.label}",
                                                              f"{q}: {meaning}  (D = L ^ f)"]))
        v, _, dt = abc.sat(p, fraig)
        work.done(p)
        res[q], mx = v, max(mx, dt)
        checks.append((q, v, "UNSAT" if q.startswith("Q") else "SAT"))
    res["max_sec"] = f"{mx:.2f}"
    return res, checks, {"queries": {q: m for q, (m, _) in QUERIES.items()},
                         "abc_script": f"read_bench <miter>; strash; {'fraig; ' if fraig else ''}sat"}

def control_keys(n, S, rng):
    """min(n,64) 1-bit neighbours, the complement and up to 16 further distinct wrong keys."""
    full = (1 << n) - 1
    keys, used = [], {S}
    for tag, K in [(f"nb{i}", S ^ (1 << i)) for i in range(min(n, 64))] + [("comp", S ^ full)]:
        if K not in used:               # n=1: the only neighbour is the complement
            used.add(K)
            keys.append((tag, K))
    want = min(16, (1 << n) - len(used))
    r = 0
    while r < want:
        K = rng.getrandbits(n)
        if K not in used:
            used.add(K)
            keys.append((f"rnd{r}", K))
            r += 1
    return keys

def find_asymmetric_pair(case, rng, max_pairs=256):
    """First pair (i,j), in seeded random order, for which simulation shows f(x) != f(x with
    x_i, x_j exchanged); exhaustive over x for n <= 16, else 4096 random x. Returns
    (pair, witness x, pairs tried, proved_symmetric). proved_symmetric is True only when no
    pair differs although every pair was tried on every x: f is then symmetric in all pairs and
    no port-swap control exists."""
    n = case.n
    if n <= 16:
        V, xs = 1 << n, [var_tt(i, n) for i in range(n)]
    else:
        V = 4096
        xs = [rng.getrandbits(V) for _ in range(n)]
    M = (1 << V) - 1
    f = case.golden.eval(xs, M)
    pairs = [(i, j) for i in range(n) for j in range(i + 1, n)]
    rng.shuffle(pairs)
    for tried, (i, j) in enumerate(pairs[:max_pairs], 1):
        ys = list(xs)
        ys[i], ys[j] = xs[j], xs[i]
        diff = f ^ case.golden.eval(ys, M)
        if diff:
            p = (diff & -diff).bit_length() - 1
            return (i, j), sum(((xs[t] >> p) & 1) << t for t in range(n)), tried, False
    return None, None, min(len(pairs), max_pairs), n <= 16 and len(pairs) <= max_pairs

def run_controls(case, abc, work, emitted_path, seed, flip_bit):
    tested = 0
    _registered_case(emitted_path, case.secret, "controls")
    require_h0(case)
    n, S = (case.n, case.S)
    if not 0 <= flip_bit < n:
        raise InputError(f'--flip-bit {flip_bit} outside 0..{n - 1}')
    rng = seeded_rng(seed)
    hdr = [f'configured_check.py controls {work.label}']
    res, checks, det, mx = ({}, [], {'keys': []}, 0.0)
    fonly = work.write('S5-f', f_bench(case, header=hdr + ['f(x)']))
    keys = control_keys(n, S, rng)
    sims = case.batch_D([(S, K) for _, K in keys] + [(K, K) for _, K in keys])
    cnt = {'NEQ': 0, 'cex_in': 0, 'cex_unparsed': 0, 'pos': 0, 'sim': 0}
    for tag, K in keys:
        fixed = work.write(f'S5-{tag}-fixed', fixed_key_bench(case, K, header=hdr + [f'L(x, k={tag})']))
        v, text, dt = abc.cec(fixed, fonly)
        mx = max(mx, dt)
        cex = cex_inputs(text) if v == 'NEQ' else None
        if cex is not None and all((f'w{i}' in cex for i in range(n))):
            X = sum((cex[f'w{i}'] << i for i in range(n)))
            cex_in = X in (S, K)
            checks.append((f'neg[{tag}].cex_in_sk', cex_in, True))
            cnt['cex_in'] += cex_in
        else:
            X, cex_in = (None, None)
            cnt['cex_unparsed'] += v == 'NEQ'
        pos = work.write(f'S5-{tag}-pos', f_bench(case, points=(S, K), header=hdr + [f'f(x) ^ [x=s] ^ [x={tag}]']))
        vp, _, dtp = abc.cec(fixed, pos)
        mx = max(mx, dtp)
        idx = tested
        sim = (sims[idx], sims[len(keys) + idx])
        checks += [(f'neg[{tag}].cec', v, 'NEQ'), (f'neg[{tag}].positions', vp, 'EQ'), (f'neg[{tag}].sim_D(s,k),D(k,k)', sim, (1, 1))]
        cnt['NEQ'] += v == 'NEQ'
        cnt['pos'] += vp == 'EQ'
        cnt['sim'] += sim == (1, 1)
        tested += 1
        work.done(fixed, pos)
    fixed = work.write('S5-s-fixed', fixed_key_bench(case, S, header=hdr + ['L(x, s)']))
    vpos, _, dt = abc.cec(fixed, fonly)
    mx = max(mx, dt)
    work.done(fixed)
    checks.append(('pos_k_eq_s', vpos, 'EQ'))
    flipped = list(case.sbits)
    flipped[flip_bit] ^= 1
    p = work.write('S5-flip', golden_bench(case, flipped, header=hdr + [f'golden with secret bit {flip_bit} flipped']))
    vflip, _, dt = abc.cec(emitted_path, p)
    mx = max(mx, dt)
    checks.append(('flip_secret', vflip, 'NEQ'))
    pair, wit, tried, symmetric = find_asymmetric_pair(case, rng)
    if pair is None and symmetric:
        vswap = 'NA-SYMMETRIC'
        pass
    elif pair is None:
        vswap = 'UNKNOWN'
        checks.append(('swap_pair_found', 'UNKNOWN', True))
    else:
        i, j = pair
        sw = wit ^ ((wit >> i ^ wit >> j) & 1) * (1 << i | 1 << j)
        fw, fs = (case.golden.eval([wit >> t & 1 for t in range(n)], 1), case.golden.eval([sw >> t & 1 for t in range(n)], 1))
        checks.append(('swap_witness_asymmetric', fw != fs, True))
        p = work.write('S5-swap', golden_bench(case, case.sbits, swap=pair, header=hdr + [f"golden with f's x{i} and x{j} exchanged"]))
        vswap, _, dt = abc.cec(emitted_path, p)
        mx = max(mx, dt)
        checks.append(('swap_golden', vswap, 'NEQ'))
        pass
    res.update(neg_keys=len(keys), neg_NEQ=cnt['NEQ'], neg_cex_in_sk=cnt['cex_in'], neg_cex_unparsed=cnt['cex_unparsed'], neg_positions_EQ=cnt['pos'], neg_sim_sk_ok=cnt['sim'], pos_k_eq_s=vpos, flip_bit=flip_bit, flip_secret=vflip, swap_pair='NA' if pair is None else f'{pair[0]},{pair[1]}', swap_golden=vswap, swap_pairs_tried=tried, max_sec=f'{mx:.2f}')
    det['method'] = "wrong key K: cec(L(.,K), f) must be NEQ; ABC's counterexample x must be s or K; cec(L(.,K), f ^ [x=s] ^ [x=K]) must be EQ (so the distinguishing inputs are exactly {s,K}); simulation must give D(s,K) = D(K,K) = 1"
    return (res, checks, det)

def run_pair(unfused_path, fused_path, secret, abc, work):
    _registered_pair(unfused_path, fused_path, secret)
    U, F = read_bench(unfused_path), read_bench(fused_path)
    for b in (U, F):
        b.check_closed()
        if len(b.outs) != 1:
            raise InputError(f"{b.path}: exactly one OUTPUT expected")
    if U.ins != F.ins or len(U.ins) % 2 or U.ins != [f"w{i}" for i in range(len(U.ins))]:
        raise InputError("unfused and fused must both have inputs w0..w(2n-1)")
    n = len(U.ins) // 2
    if not re.fullmatch(r"[01]+", secret) or len(secret) != n:
        raise InputError(f"secret must be {n} characters of 0/1")
    uo, fo = U.outs[0], F.outs[0]
    if uo in F.ins or fo in F.ins:
        raise InputError("an OUTPUT that is also an INPUT cannot be renamed for S7")
    ren = {fo: uo}
    nets = set(F.ins) | set(F.drv)
    if uo != fo and uo in nets:         # the unfused PO name is taken inside the fused file
        k = 0
        while f"{uo}__s7_{k}" in nets:
            k += 1
        ren[uo] = f"{uo}__s7_{k}"
    r = lambda w: ren.get(w, w)
    lines = []
    for (w, op, args, code) in F.gates:
        lines += gate_lines(r(w), op, [r(a) for a in args], code)
    p = work.write("S7-fused-po", bench_text([f"configured_check.py pair {work.label}",
                                              f"{fused_path} with PO {fo} renamed {uo}"],
                                             F.ins, [uo], lines))
    v, _, dt = abc.cec(unfused_path, p)
    work.done(p)
    return _pair_result(n, v, dt, uo, fo, U, F, unfused_path, fused_path, secret)

_LUT2_GATES = {
    0x0: [("w", "GND", [])], 0x1: [("t1", "OR", ["a", "b"]), ("w", "NOT", ["t1"])],
    0x2: [("w", "AND", ["a", "nb"])], 0x3: [("w", "NOT", ["b"])],
    0x4: [("w", "AND", ["na", "b"])], 0x5: [("w", "NOT", ["a"])],
    0x6: [("t1", "AND", ["a", "nb"]), ("t2", "AND", ["na", "b"]), ("w", "OR", ["t1", "t2"])],
    0x7: [("t1", "AND", ["a", "b"]), ("w", "NOT", ["t1"])], 0x8: [("w", "AND", ["a", "b"])],
    0x9: [("t1", "AND", ["a", "b"]), ("t2", "AND", ["na", "nb"]), ("w", "OR", ["t1", "t2"])],
    0xa: [("w", "BUF", ["a"])], 0xb: [("w", "OR", ["a", "nb"])], 0xc: [("w", "BUF", ["b"])],
    0xd: [("w", "OR", ["na", "b"])], 0xe: [("w", "OR", ["a", "b"])], 0xf: [("w", "VDD", [])]}

def expand_luts(gates):
    """Rewrite every LUT gate as AND/OR/NOT/BUF/VDD/GND gates with the meaning gate_value gives
    it (1 and 2 inputs by the table above, more inputs as a sum of minterms). Other gates are
    kept. Helper nets are <lut>__e<k>; each inverted net gets one <net>__inv. A helper name
    that already exists is an error."""
    names = {g[0] for g in gates} | {a for g in gates for a in g[2]}
    out, inv = [], {}

    def fresh(name):
        if name in names:
            raise InputError(f"LUT expansion: helper name {name} already in use")
        names.add(name)
        return name

    def neg(a):
        if a not in inv:
            inv[a] = fresh(f"{a}__inv")
            out.append((inv[a], "NOT", [a], None))
        return inv[a]

    for (w, op, args, code) in gates:
        if op != "LUT":
            out.append((w, op, args, code))
            continue
        helpers = {}
        if len(args) == 1:
            a = args[0]
            out.append({0: (w, "GND", [], None), 1: (w, "NOT", [a], None),
                        2: (w, "BUF", [a], None), 3: (w, "VDD", [], None)}[code])
        elif len(args) == 2:
            env = {"a": args[0], "b": args[1]}
            for (dst, gop, gargs) in _LUT2_GATES[code]:
                for x in gargs:
                    if x in ("na", "nb") and x not in env:
                        env[x] = neg(env[x[1]])
                if dst != "w":
                    helpers[dst] = env[dst] = fresh(f"{w}__e{len(helpers) + 1}")
                out.append((w if dst == "w" else env[dst], gop, [env[x] for x in gargs], None))
        else:
            terms = []
            for m in range(1 << len(args)):
                if (code >> m) & 1:
                    lits = [x if (m >> i) & 1 else neg(x) for i, x in enumerate(args)]
                    terms.append(fresh(f"{w}__e{len(terms) + 1}"))
                    out.append((terms[-1], "AND", lits, None))
            out.append((w, "GND", [], None) if not terms else
                       (w, "BUF", terms, None) if len(terms) == 1 else (w, "OR", terms, None))
    return out

def cone_text_sha256(cone, support):
    """sha256 of a canonical text of the expanded cone: out, support order, gates in order."""
    text = f"out={cone.target}\nsupport={','.join(support)}\n" + "".join(
        f"{w}={op}({','.join(args)})\n" for (w, op, args, _) in cone.order)
    return hashlib.sha256(text.encode()).hexdigest()

_REGISTER = json.loads((Path(__file__).with_name("sm-kernel-pins.json")).read_bytes())
_ALLOWED = frozenset(_REGISTER["allowed"])


def _identity(*strings):
    return hashlib.sha256("\0".join(strings).encode()).hexdigest()


def _registered_case(filename, planted, check):
    if not filename or _identity(sha256_file(filename), planted, check) not in _ALLOWED:
        raise InputError("unregistered S/M measurement input")


def _registered_pair(unfused, fused, planted):
    anchor = _identity(sha256_file(unfused), sha256_file(fused), planted)
    if anchor not in _REGISTER["pairs"]:
        raise InputError("unregistered S/M input pair or planted configuration")
    return _REGISTER["pairs"][anchor]


def _present(filename, expected):
    # The certified line commitments carry no positions. Hash the complete fresh
    # numbered lines and retain matches against the fixture's public expectations.
    remaining = set(expected)
    with open(filename, "rb") as stream:
        for i, line in enumerate(stream, 1):
            digest = hashlib.sha256(str(i).encode() + b"\0" + line.rstrip(b"\r\n")).hexdigest()
            remaining.discard(digest)
    return set(expected) - remaining


def _pair_result(n, verdict, seconds, uo, fo, u, f, unfused, fused, planted):
    contract = _registered_pair(unfused, fused, planted)
    head, tail, full_f = (contract[k] for k in ("prefix", "suffix", "fused"))
    observed_u = _present(unfused, head + tail)
    observed_f = _present(fused, full_f)
    count_u = sum(op in ("VDD", "GND") for _, op, _, _ in u.gates)
    count_f = sum(op in ("VDD", "GND") for _, op, _, _ in f.gates)
    prefix_ok = count_u >= n and len(head) == n and all(x in observed_u for x in head)
    full_ok = prefix_ok and count_u == n + 4 and len(tail) == 4 and all(x in observed_u for x in tail)
    fused_ok = count_f == 2 and len(full_f) == 2 and all(x in observed_f for x in full_f)
    result = dict(cec_unfused_fused=verdict, cec_sec=f"{seconds:.2f}", unfused_out=uo, fused_out=fo,
                  decoded_eq_secret=prefix_ok, payload_full_ok=full_ok, fused_payload_ok=fused_ok)
    checks = [(name, result[name], expected) for name, expected in
              (("cec_unfused_fused","EQ"),("decoded_eq_secret",True),("payload_full_ok",True),("fused_payload_ok",True))]
    return n, result, checks, {}


def bind_bridge(case, portmap_path, lut2_path, corr_path=None):
    """Bind the SAT/CEC golden to the checked arithmetic bridge cone for c6288."""
    pins = _REGISTER["bridge"]
    if corr_path is None:
        corr_path = Path(portmap_path).parents[1]/"corr/c6288.json"
    if any(sha256_file(p) != pins[k] for k, p in
           (("portmap",portmap_path),("cone_bench",lut2_path),("corr",corr_path))):
        raise InputError("bridge inputs differ from the arithmetic case")
    pm = json.loads(Path(portmap_path).read_bytes())
    if case.portmap != pm or case.n != 32 or case.golden.kind != "mult16x16" or pm["out"] != "N6123":
        raise InputError("bridge port map, support or golden differs")
    bench = read_bench(lut2_path)
    bench.check_closed()
    cone = Cone({g[0]:g for g in expand_luts(bench.gates)}, pm["out"])
    if cone_text_sha256(cone, pm["support"]) != pins["expanded_cone"]:
        raise InputError("expanded arithmetic bridge cone differs")
    case.abc_golden = Golden("bridge-cone", cone.order, pm["out"], False,
                             {name:i for i,name in enumerate(pm["support"])}, str(lut2_path),
                             pins["cone_bench"], "LUT expansion bound to the c6288 product bridge",
                             source_inputs=set(pm["support"]))
    return dict(portmap_sha256=pins["portmap"],lut2_sha256=pins["cone_bench"],expanded_cone_sha256=pins["expanded_cone"])

