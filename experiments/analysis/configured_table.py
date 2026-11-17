#!/usr/bin/env python3
"""Render the configured ISCAS-85 validation (Tiers E/X/S/M and the c6288 bridge; Appendix B.3) as LaTeX.

The input, ``experiments/data/processed/p53-iscas-configured.tsv``, is written by
``configured_processed.py`` from the raw records.  Every number in the two tables and in their
captions is computed here from that TSV; a statement that the data do not support makes the
generator stop instead of printing it.

Two ``table`` environments go to one file:

* ``<label>-sim``: Tier E (all 2^(2n) input/key pairs) and Tier X (all 2^n inputs per sampled key),
  one row per cone, plus a totals row;
* ``<label>-sym``: Tier S (symbolic, ABC verdicts), Tier M (byte mutants) and the c6288 bridge,
  one row per maximum-support cone.

Usage: python3 -B configured_table.py TSV --tex OUT [--label tab:iscas-configured]
"""
import argparse
import re
import sys

from table_io import read_tsv, write_tex

GOLDEN_NAME = {
    "sld": r"\texttt{sld}",
    "sld+po_negated": r"\texttt{sld} + PO neg.",
    "mult16x16+bridge": r"int. product",
    "mult16x16": r"int. product",
    "c17-classic": r"classic",
}
S_ORDER = ("goldenU", "goldenF", "miter", "controls", "sim", "pair")
M_CLASSES = ("polarity-flip", "rail-delete", "host-constant")


def die(msg):
    sys.exit("configured_table: " + msg)


def require(cond, msg):
    if not cond:
        die("the data do not support the table text: " + msg)


def esc(text):
    """Escape the LaTeX specials that can occur in cell text."""
    return re.sub(r"([_%#&$])", r"\\\1", text)


def tt(text):
    return r"\texttt{" + esc(text) + "}"


def host_num(host):
    return int(re.sub(r"\D", "", host))


def num(x):
    return f"{int(x):,}"


def pow2(k):
    return f"$2^{{{k}}}$"


def pairs_str(n, keys=None):
    return pow2(2 * n) if keys is None else f"{pow2(n)}$\\times${keys}"


def uniform(values, what):
    vals = sorted(set(values), key=lambda v: int(v))
    if len(vals) == 1:
        return vals[0]
    return vals[0] + "--" + vals[-1]


def counted(rows):
    return [r for r in rows if r["counted"] == "yes"]


def select(rows, **kw):
    return [r for r in rows if all(r[k] == v for k, v in kw.items())]


# ------------------------------------------------------------------------------------------------ sim table
def sim_data(rows):
    """Per-cone aggregates of Tier E and Tier X."""
    cones = {}
    for r in counted(rows):
        if r["tier"] not in ("E", "X"):
            continue
        cones.setdefault((r["tier"], r["host"], r["out"]), []).append(r)
    out = []
    for (tier, host, o), rs in cones.items():
        n = int(rs[0]["n"])
        require(all(int(r["n"]) == n and r["status"] == "PASS" for r in rs), f"{host} {o}: mixed n or not PASS")
        d = {"tier": tier, "host": host, "out": o, "n": n, "cfg": len(rs),
             "mism": sum(int(r["mismatches"]) for r in rs),
             "golden_unused": max(int(r["golden_unused_support"] or 0) for r in rs)}
        if tier == "E":
            d["restore_ok"] = sum(1 for r in rs if int(r["restore"]) == int(r["restore_expected"]) == 2 ** n)
            h0 = [r for r in rs if r["h"] == "0"]
            d["h0"] = len(h0)
            d["obs"] = sum(int(r["corruption_total"]) for r in h0)
            d["exp"] = sum(2 * (2 ** n - 1) for r in h0)
            d["obs1"] = uniform([r["corruption_total"] for r in h0], "obs")
            d["exp1"] = str(2 * (2 ** n - 1))
            d["pairs_cfg"] = pairs_str(n)
            d["pairs_total"] = sum(2 ** (2 * n) for r in rs)
            hp = [r for r in rs if r["h"] != "0"]
            d["hpos"] = len(hp)
            d["hpos_T"] = sum(1 for r in hp if r["corruption_total"] == r["corruption_expected"] == r["corruption_T_independent"])
            d["h0_T"] = sum(1 for r in h0 if int(r["corruption_total"]) == int(r["corruption_expected"]) == int(r["corruption_T_independent"]) == 2 * (2 ** n - 1))
            d["zero_ok"] = all(r["zero_corruption_wrong_keys"] == r["zero_corruption_expected"] for r in rs)
            d["zero_only_half"] = all(int(r["zero_corruption_expected"]) == 0 or 2 * int(r["h"]) == n for r in rs)
            d["ocr_bad"] = sum(int(r["perkey_ocr_bad"]) for r in rs)
            d["fused"] = sum(1 for r in rs if r["variant"] == "fused")
        else:
            d["restore_ok"] = sum(1 for r in rs if r["restore_ok"] == "True")
            d["h0"] = len(rs)
            keys = [int(r["keys"]) for r in rs]
            require(all(k == n + 20 for k in keys), f"{host} {o}: key count is not n+20")
            d["obs"] = sum(int(r["corruption_sampled_keys"]) for r in rs)
            d["exp"] = sum(2 * (k - 1) for k in keys)
            d["obs1"] = uniform([r["corruption_sampled_keys"] for r in rs], "obs")
            d["exp1"] = uniform([str(2 * (k - 1)) for k in keys], "exp")
            d["keys"] = uniform([str(k) for k in keys], "keys")
            d["pairs_cfg"] = pairs_str(n, d["keys"])
            d["pairs_total"] = sum(2 ** n * k for k in keys)
            d["pos_bad"] = sum(int(r["positions_bad"]) for r in rs)
            d["ocr_bad"] = sum(int(r["perkey_ocr_bad"]) for r in rs)
        out.append(d)
    return out


def sim_table(rows, label):
    data = sim_data(rows)
    e = sorted([d for d in data if d["tier"] == "E"], key=lambda d: (d["n"], host_num(d["host"]), d["out"]))
    x = sorted([d for d in data if d["tier"] == "X"], key=lambda d: (host_num(d["host"]), d["n"]))
    require(e and x, "Tier E or Tier X rows are missing")
    ecfg, xcfg = sum(d["cfg"] for d in e), sum(d["cfg"] for d in x)
    require(sum(d["mism"] for d in e + x) == 0, "a simulation mismatch is recorded")
    require(all(d["restore_ok"] == d["cfg"] for d in e + x), "a correct key does not restore every input")
    require(all(d["obs"] == d["exp"] for d in e + x), "wrong-key corruption differs from its closed form at h=0")
    require(all(d["h0_T"] == d["h0"] for d in e), "h=0 corruption is not independently T(n,0)")
    require(all(d["ocr_bad"] == 0 for d in e + x) and all(d["pos_bad"] == 0 for d in x), "a per-key corruption count or position is wrong")
    require(all(d["zero_ok"] and d["zero_only_half"] for d in e), "zero-corruption wrong keys outside h = n/2")
    hpos, hpos_T = sum(d["hpos"] for d in e), sum(d["hpos_T"] for d in e)
    require(hpos == hpos_T, "a configuration with h>0 differs from T(n,h)")
    tot_pairs = sum(d["pairs_total"] for d in e + x)
    fused = sum(d["fused"] for d in e)
    unfused = ecfg - fused
    n23 = [d for d in e if d["golden_unused"] > 0]
    require(len(n23) == 1, "expected exactly one cone with unused golden support")

    lines = []
    for d in e + x:
        tier = "E" if d["tier"] == "E" else "X"
        mark = r"$^{\dagger}$" if d["golden_unused"] > 0 else ""
        lines.append(f"{tt(d['host'])} & {tt(d['out'])} & {d['n']}{mark} & {tier} & {d['cfg']} & {d['pairs_cfg']} & "
                     f"{d['mism']} & {d['restore_ok']}/{d['cfg']} & {num(d['obs1']) if d['obs1'].isdigit() else d['obs1']} & "
                     f"{num(d['exp1']) if d['exp1'].isdigit() else d['exp1']}\\\\")
    def total_row(name, ds):
        # The corruption sums of the two tiers measure different things (complete key space against sampled keys): no grand total.
        c = sum(d["cfg"] for d in ds)
        return (f"{name} & & & & {c} & & {sum(d['mism'] for d in ds)} & {sum(d['restore_ok'] for d in ds)}/{c} & "
                f"{num(sum(d['obs'] for d in ds))} & {num(sum(d['exp'] for d in ds))}\\\\")
    out = [r"\begin{table}[t]", r"\centering\small", r"\setlength{\tabcolsep}{3pt}",
           r"\resizebox{\linewidth}{!}{%",
           r"\begin{tabular}{l l r c r l r r r r}", r"\hline",
           r"host & cone & $n$ & tier & configs & pairs/config & mism. & restore & "
           r"\multicolumn{2}{c}{corruption at $h{=}0$}\\",
           r" & & & & & & (total) & (all $2^n$) & observed & expected\\", r"\hline"]
    out += lines
    out += [r"\hline", total_row(r"total, Tier~E", e), total_row(r"total, Tier~X", x), r"\hline", r"\end{tabular}}"]
    caption = (
        r"\caption{Configured-lock simulation against independent goldens, one row per cone; "
        r"tier and metric definitions are in Section~\ref{app:configured}. "
        f"All {ecfg} E configurations ({unfused} unfused, {fused} fused) and {xcfg} X configurations pass "
        f"({ecfg + xcfg} total; {num(tot_pairs)} input/key pairs). "
        f"The {hpos} E configurations at $h>0$ have corruption total $T(n,h)$ (not tabulated); "
        r"zero-corruption wrong keys occur only at $h=n/2$, as expected. "
        r"Coverage extends only to the listed cones and radii. "
        f"$^{{\\dagger}}$~Classic \\texttt{{c17}} calibration output: compile-time route, no fused emission; "
        f"the golden leaves {n23[0]['golden_unused']} of {n23[0]['n']} support positions unused. "
        r"}")
    out += [caption, f"\\label{{{label}-sim}}", r"\end{table}"]
    return out


# ------------------------------------------------------------------------------------------------ sym table
def frac(k, m):
    return f"{k}/{m}"


def sym_data(rows):
    s = counted([r for r in rows if r["tier"] == "S"])
    m = counted([r for r in rows if r["tier"] == "M"])
    b = counted([r for r in rows if r["tier"] == "B"])
    cones = {}
    for r in s:
        cones.setdefault((r["host"], r["out"]), []).append(r)
    res = []
    for (host, o), rs in cones.items():
        by = {c: select(rs, call=c) for c in S_ORDER}
        for c, v in by.items():
            require(len(v) == 2, f"{host} {o}: {len(v)} counted {c} rows, expected one per secret")
        d = {"host": host, "out": o, "n": int(rs[0]["n"])}
        kinds = {r["golden_kind"] for c in ("goldenU", "goldenF", "miter", "controls") for r in by[c]}
        require(len(kinds) == 1, f"{host} {o}: several golden kinds {kinds}")
        d["kind"] = kinds.pop()
        # simulation (S4) uses the plain product; the bridge only matters to the ABC checks
        require({r["golden_kind"] for r in by["sim"]} <= {d["kind"], d["kind"].replace("+bridge", "")}, f"{host} {o}: sim golden kind differs")
        require(d["kind"] in GOLDEN_NAME, f"{host} {o}: unknown golden kind {d['kind']}")
        d["extra"] = {(r["golden_extra"], r["golden_extra_independent"]) for c in ("goldenU", "goldenF", "miter", "controls", "sim") for r in by[c]}
        g = by["goldenU"] + by["goldenF"]
        d["s12"] = sum((r["S1"] == "EQ") + (r["S2"] == "EQ") for r in g)
        d["s12_all"] = 2 * len(g)
        d["s6"] = sum((r["S6_dc2"] == "EQ") + (r["S6_if6"] == "EQ") for r in g)
        d["s6_all"] = 2 * len(g)
        mi = by["miter"]
        d["s3"] = sum(all(r[q] == "UNSAT" for q in ("Q0", "Q1", "Q2", "Q3")) and all(r[p] == "SAT" for p in ("P0", "P1", "P2", "P3")) for r in mi)
        d["s3_all"] = len(mi)
        sm = by["sim"]
        d["s4_mism"] = sum(int(r["mismatches"]) + int(r["mismatches_targeted"]) for r in sm)
        d["s4_bad"] = sum(int(r["xcheck_sim_bench_bad"]) for r in sm)
        d["s4_sb"] = sum(int(r["xcheck_sim_bench"]) for r in sm)
        if all(r["xcheck_main"] == "NA" for r in sm):
            d["s4_main"] = None
        else:
            require(all(r["xcheck_main"] != "NA" and r["xcheck_main_bad"] == "0" for r in sm), f"{host} {o}: mixed Main cross-check")
            d["s4_main"] = sum(int(r["xcheck_main"]) for r in sm)
        require(d["s4_bad"] == 0, f"{host} {o}: sim_bench cross-check disagrees")
        co = by["controls"]
        d["neg"] = sum(int(r["neg_NEQ"]) for r in co)
        d["neg_all"] = sum(int(r["neg_keys"]) for r in co)
        d["cex_in"] = sum(int(r["neg_cex_in_sk"]) for r in co)
        d["cex_unparsed"] = sum(int(r["neg_cex_unparsed"]) for r in co)
        d["pos_eq"] = sum(int(r["neg_positions_EQ"]) for r in co)
        d["pos"] = sum(r["pos_k_eq_s"] == "EQ" for r in co)
        d["flip"] = sum(r["flip_secret"] == "NEQ" for r in co)
        d["swap_neq"] = sum(r["swap_golden"] == "NEQ" for r in co)
        d["swap_unknown"] = sum(r["swap_golden"] == "UNKNOWN" for r in co)
        d["swap_other"] = sorted({r["swap_golden"] for r in co} - {"NEQ", "UNKNOWN"})
        d["swap_status"] = sorted({r["status"] for r in co})
        d["co_n"] = len(co)
        pr = by["pair"]
        d["s7"] = sum(r["cec_unfused_fused"] == "EQ" and r["decoded_eq_secret"] == "True" for r in pr)
        d["s7_all"] = len(pr)
        mm = [r for r in m if r["host"] == host and r["out"] == o]
        cls = {}
        for r in mm:
            cls.setdefault((r["mutant"], r["sid"]), []).append(r)
        d["m_ok"] = sum(1 for v in cls.values() if len(v) == 2 and all(r["verdict"] == "AS_EXPECTED" for r in v))
        d["m_all"] = len(cls)
        d["bridge"] = [r for r in b if r["host"] == host and r["out"] == o]
        res.append(d)
    return res, m, b, s


def sym_table(rows, label):
    data, mrows, brows, srows = sym_data(rows)
    data.sort(key=lambda d: host_num(d["host"]))
    require(len(brows) == 1 and brows[0]["status"] == "PASS", "expected exactly one counted PASS bridge row")
    br = brows[0]
    require(br["mismatches"] == br["cone_vs_intprod"] == br["golden_vs_intprod"] == "0" and br["lut_expansion_cec"] == "EQ", "bridge is not clean")
    require(int(br["intprod_neg_mismatches"]) > 0, "bridge negative control found nothing")
    require(all(d["s12"] == d["s12_all"] and d["s3"] == d["s3_all"] and d["s7"] == d["s7_all"] and d["s6"] == d["s6_all"] for d in data), "S1/S2/S3/S6/S7 are not all as expected")
    require(all(d["neg"] == d["neg_all"] and d["pos"] == d["co_n"] and d["flip"] == d["co_n"] for d in data), "S5 negative/positive/flip controls are not all as expected")
    require(all(d["cex_in"] == d["neg_all"] and d["cex_unparsed"] == 0 and d["pos_eq"] == d["neg_all"] for d in data),
            "an S5 counterexample is unparsed or outside {s, k}, or a position check is not EQ")
    neg_tot = sum(d["neg_all"] for d in data)
    neg_cex = sum(d["cex_in"] for d in data)
    require(all(d["m_ok"] == d["m_all"] == len(M_CLASSES) for d in data), "a mutant is not as expected")
    require(all(not d["swap_other"] for d in data), "unexpected port-swap outcome")
    incon = [d for d in data if d["swap_unknown"]]
    require(all(d["swap_unknown"] == d["co_n"] and d["swap_status"] == ["INCONCLUSIVE"] for d in incon), "a mixed INCONCLUSIVE port-swap row")
    require(all(d["swap_neq"] == d["co_n"] for d in data if not d["swap_unknown"]), "port-swap neither NEQ nor UNKNOWN")
    ncones = len(data)
    require(len({d["s12_all"] for d in data}) == 1, "S1/S2 check counts differ between cones")
    s12n = data[0]["s12_all"]
    s6ok, s6all = sum(d["s6"] for d in data), sum(d["s6_all"] for d in data)
    n_ok = [d for d in data if d["swap_neq"] == d["co_n"]]
    n_main = [d for d in data if d["s4_main"] is not None]
    n_sol = len(srows)
    n_pass = sum(1 for r in srows if r["status"] == "PASS")
    n_inc = sum(1 for r in srows if r["status"] == "INCONCLUSIVE")
    require(n_pass + n_inc == n_sol, "Tier S rows other than PASS or INCONCLUSIVE")
    extra_cones = [d for d in data if d["extra"] != {("0", "NA")}]
    require(all(d["extra"] == {("3", "EQ")} for d in extra_cones) and len(extra_cones) == 1, "unexpected golden_extra")
    ex = extra_cones[0]
    ex_n = next(iter(ex["extra"]))[0]
    retry = [r for r in rows if r["tier"] == "S" and r["counted"] == "no"]
    require(all(r["status"] == "INCONCLUSIVE" for r in retry), "an uncounted Tier S row is not INCONCLUSIVE")
    require(all(r["status"] == "INCONCLUSIVE" and r["attempt"] == "r1" for r in srows if r["status"] != "PASS"), "counted INCONCLUSIVE row is not a retry")
    # mutants: effect per class
    eff = {}
    for r in mrows:
        if r["call"] == "golden":
            eff.setdefault(r["mutant"], set()).add(r["status"])
    require(eff == {"polarity-flip": {"FAIL"}, "rail-delete": {"FAIL"}, "host-constant": {"PASS"}}, f"unexpected golden outcomes of mutants {eff}")
    require(all(r["status"] == "FAIL" for r in mrows if r["call"] == "pair"), "a mutant passes pair")
    n_mut = len({(r["host"], r["out"], r["mutant"], r["sid"]) for r in mrows})

    def row(d):
        mark = ""
        if (d["host"], d["out"]) == (ex["host"], ex["out"]):
            mark = r"$^{\ddagger}$"
        gold = GOLDEN_NAME[d["kind"]]
        if d["bridge"]:
            gold += r"$^{\S}$"
        s3 = frac(d["s3"], d["s3_all"])
        main = "NA" if d["s4_main"] is None else str(d["s4_main"])
        s4 = f"{d['s4_mism']}"
        s4x = f"{d['s4_sb']}/{main}"
        if d["swap_unknown"]:
            swap = r"\textbf{INCONCLUSIVE}$^{\P}$"
        elif d["swap_neq"] == d["co_n"]:
            swap = frac(d["swap_neq"], d["co_n"])
        else:
            swap = "?"
        cells = [tt(d["host"]), tt(d["out"]) + mark, str(d["n"]), gold, frac(d["s12"], d["s12_all"]),
                 s3, s4, s4x,
                 frac(d["neg"], d["neg_all"]), frac(d["flip"], d["co_n"]), swap, frac(d["s7"], d["s7_all"]),
                 frac(d["m_ok"], d["m_all"])]
        return " & ".join(cells) + r"\\"

    out = [r"\begin{table}[t]", r"\centering\scriptsize", r"\setlength{\tabcolsep}{2.5pt}",
           r"\resizebox{\linewidth}{!}{%",
           r"\begin{tabular}{l l r l r r r r r r l r r}", r"\hline",
           r"host & cone & $n$ & golden & S1/S2 & S3 & \multicolumn{2}{c}{S4 sim} & "
           r"\multicolumn{3}{c}{S5 controls (NEQ)} & S7 & M\\",
           r" & & & & EQ & Q/P & mism. & x-check & wrong keys & flip & port swap & EQ & as exp.\\",
           r"\hline"]
    out += [row(d) for d in data]
    out += [r"\hline", r"\end{tabular}}"]
    bridge_txt = (f"$^{{\\S}}$~\\texttt{{{esc(br['host'])}}} product bridge: all {pow2(int(br['n']))} inputs, "
                  f"{br['cone_vs_intprod']} cone/product and {br['golden_vs_intprod']} golden/product mismatches; "
                  f"bit-{br['intprod_neg_bit']} negative control: {num(br['intprod_neg_mismatches'])} mismatches; "
                  f"LUT expansion: ABC {br['lut_expansion_cec']}. S1/S2/S3/S5 compare the lock with this bridged cone; "
                  r"only its S3 uses \texttt{strash; fraig; sat}.")
    caption = (
        f"\\caption{{Tier~S/M outcomes on {ncones} maximum-support cones; "
        r"Section~\ref{app:configured} defines S1--S7/M and their trust boundary. "
        f"S1/S2: {s12n} checks/cone; S6: {s6ok}/{s6all} EQ (not tabulated). "
        f"All {num(neg_cex)}/{num(neg_tot)} S5 counterexamples were parsed and lie in $\\{{s,k\\}}$. "
        f"M: {sum(d['m_ok'] for d in data)}/{sum(d['m_all'] for d in data)} as expected. "
        f"Tier~S: {n_pass} PASS, {n_inc} INCONCLUSIVE of {n_sol} counted calls. "
        r"$^{\P}$~Sampling found no asymmetric port pair: INCONCLUSIVE is not PASS. "
        f"The {len(retry)} first attempts and their retries agree; only retries count. "
        f"Other controls are as expected; port swaps give NEQ on {len(n_ok)}/{ncones} cones. "
        r"The text records a structural witness outside the harness. "
        f"$^{{\\ddagger}}$~\\texttt{{dc2}} mapping; ABC establishes independence from {ex_n} redundant golden source inputs. "
        + bridge_txt + r"}")
    out += [caption, f"\\label{{{label}-sym}}", r"\end{table}"]
    return out, n_mut, len(n_main)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("tsv")
    ap.add_argument("--tex", required=True)
    ap.add_argument("--label", default="tab:iscas-configured")
    a = ap.parse_args()
    rows = read_tsv(a.tsv)
    sim = sim_table(rows, a.label)
    sym, _, _ = sym_table(rows, a.label)
    out = []
    out += sim + [""] + sym
    write_tex(a.tex, "\n".join(out) + "\n")


if __name__ == "__main__":
    main()
