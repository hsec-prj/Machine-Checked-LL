"""Historical S4 random/targeted I/O sampling and cross-checks."""
import hashlib
import random
import subprocess
import sim_bench
from exhaustive import eq_count, int_to_bits

def seeded_rng(seed):
    return random.Random(int.from_bytes(hashlib.sha256(seed.encode()).digest()[:8], "big"))

def run_sim(case, seed, nrand, nxcheck, main_bin=None, main_samples=4, emitted_path=None):
    n, h, S = case.n, case.h, case.S
    full = (1 << n) - 1
    rng = seeded_rng(seed)
    targ = [(S, S, "x=s,k=s")]
    for i in range(n):
        e = S ^ (1 << i)
        targ += [(S, e, f"x=s,k=nb{i}"), (e, e, f"x=k=nb{i}"), (e, S, f"x=nb{i},k=s")]
    c = S ^ full
    targ += [(S, c, "x=s,k=comp"), (c, c, "x=k=comp"), (c, S, "x=comp,k=s")]
    for r in range(16):
        K, X = rng.getrandbits(n), rng.getrandbits(n)
        targ += [(S, K, f"x=s,k=rnd{r}"), (K, K, f"x=k=rnd{r}"), (X, S, f"x=rnd,k=s"), (X, K, f"x=rnd,k=rnd{r}")]
    V = nrand + len(targ)
    M = (1 << V) - 1
    xv = [rng.getrandbits(nrand) if nrand else 0 for _ in range(n)]
    kv = [rng.getrandbits(nrand) if nrand else 0 for _ in range(n)]
    for t, (X, K, _) in enumerate(targ):
        bit = 1 << (nrand + t)
        for i in range(n):
            if (X >> i) & 1:
                xv[i] |= bit
            if (K >> i) & 1:
                kv[i] |= bit
    L = case.cone.run(case.lock_inputs(xv, kv), M)
    f = case.golden.eval(xv, M)
    exs = eq_count([xv[i] ^ (M if case.sbits[i] else 0) for i in range(n)], h, M)
    exk = eq_count([xv[i] ^ kv[i] for i in range(n)], h, M)
    bad = L ^ f ^ exs ^ exk
    mism, mism_t = bad.bit_count(), (bad >> nrand).bit_count()
    # cross-check the bit-parallel evaluator of L with the artifact's scalar simulator
    picks = list(range(nrand, nrand + min(len(targ), max(1, nxcheck // 2))))
    picks += [rng.randrange(nrand) for _ in range(max(0, nxcheck - len(picks)))] if nrand else []
    picks = picks[:nxcheck]

    def word(p):
        X = sum(((xv[i] >> p) & 1) << i for i in range(n))
        K = sum(((kv[i] >> p) & 1) << i for i in range(n))
        return X | (K << n)
    xbad, xerr, det = 0, None, {"targeted": len(targ), "xcheck_positions": picks}
    try:
        ins, outs, gates = sim_bench.parse(emitted_path)
        for p in picks:
            xbad += sim_bench.evaluate(ins, outs, gates, word(p))[0] != (L >> p) & 1
    except Exception as e:              # e.g. an operator sim_bench does not implement
        xerr = f"{type(e).__name__}: {e}"
    mbad, merr, mdone = 0, None, 0
    if main_bin:
        try:
            for p in picks[:main_samples]:
                bits = int_to_bits(word(p), 2 * n)
                r = subprocess.run([main_bin, "simbench", emitted_path, bits], capture_output=True,
                                   text=True, timeout=600)
                if r.returncode != 0 or r.stdout.strip() not in ("0", "1"):
                    raise ValueError(f"Main simbench printed {r.stdout.strip()[:80]!r}")
                mbad += r.stdout.strip() != str((L >> p) & 1)
                mdone += 1
        except Exception as e:
            merr = f"{type(e).__name__}: {e}"
    res = {"vectors_random": nrand, "vectors_targeted": len(targ), "mismatches": mism,
           "mismatches_targeted": mism_t, "xcheck_sim_bench": len(picks) if not xerr else "ERROR",
           "xcheck_sim_bench_bad": xbad if not xerr else "NA",
           "xcheck_main": (mdone if not merr else "ERROR") if main_bin else "NA",
           "xcheck_main_bad": (mbad if not merr else "NA") if main_bin else "NA"}
    checks = [("mismatches", mism, 0), ("xcheck_sim_bench", "ERROR" if xerr else xbad, 0)]
    if main_bin:
        checks.append(("xcheck_main", "ERROR" if merr else mbad, 0))
    det.update(xcheck_error=xerr, main_error=merr)
    return res, checks, det
