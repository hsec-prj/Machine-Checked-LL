"""Assemble historical P53 rows from the published scalar record projection."""
import csv
import json

TIERS = ("E", "B", "X", "S", "M")
RAW_MARK = "p53-iscas-configured/"
# Keys of the ``result`` text of the X, S, M and B index rows (RESULT_KEYS of run_configured_xsm.py).
RESULT_KEYS = {
    "perkey": ["keys", "mismatches", "perkey_ocr_bad", "positions_bad", "restore_ok", "corruption_sampled_keys"],
    "golden": ["S1", "S2", "S6_dc2", "S6_if6", "golden_extra", "golden_extra_independent"],
    "miter": ["Q0", "Q1", "Q2", "Q3", "P0", "P1", "P2", "P3"],
    "controls": ["neg_keys", "neg_NEQ", "neg_cex_in_sk", "neg_cex_unparsed", "neg_positions_EQ", "neg_sim_sk_ok",
                 "pos_k_eq_s", "flip_secret", "swap_pair", "swap_golden"],
    "sim": ["mismatches", "mismatches_targeted", "xcheck_sim_bench", "xcheck_sim_bench_bad", "xcheck_main", "xcheck_main_bad"],
    "pair": ["cec_unfused_fused", "decoded_eq_secret", "payload_full_ok", "fused_payload_ok"],
    "bridge": ["mismatches", "cone_vs_intprod", "golden_vs_intprod", "intprod_neg_bit", "intprod_neg_mismatches",
               "lut_expansion_cec"],
}
CALL_SUB = {"goldenU": "golden", "goldenF": "golden", "golden": "golden", "miter": "miter", "controls": "controls",
            "sim": "sim", "pair": "pair", "perkey": "perkey", "bridge": "bridge"}
E_FACTS = ["mismatches", "restore", "restore_expected", "corruption_total", "corruption_expected",
           "corruption_T_independent", "perkey_ocr_bad", "zero_corruption_wrong_keys", "zero_corruption_expected"]
# Facts that are read from the harness JSON row (they are not part of every ``result`` text).
JSON_FACTS = ["golden_kind", "golden_extra", "golden_extra_independent", "golden_unused_support", "failed_checks"]

COLUMNS = (
    ["tier", "config", "call", "attempt", "counted", "host", "out", "n", "h", "sid", "variant", "mutant",
     "status", "verdict", "failed_checks", "inconclusive_checks"]
    + ["golden_kind", "golden_extra", "golden_extra_independent", "golden_unused_support"]
    + ["restore", "restore_expected", "corruption_total", "corruption_expected", "corruption_T_independent",
       "zero_corruption_wrong_keys", "zero_corruption_expected"]
    + ["keys", "mismatches", "perkey_ocr_bad", "positions_bad", "restore_ok", "corruption_sampled_keys"]
    + ["S1", "S2", "S6_dc2", "S6_if6", "Q0", "Q1", "Q2", "Q3", "P0", "P1", "P2", "P3"]
    + ["mismatches_targeted", "xcheck_sim_bench", "xcheck_sim_bench_bad", "xcheck_main", "xcheck_main_bad"]
    + ["neg_keys", "neg_NEQ", "neg_cex_in_sk", "neg_cex_unparsed", "neg_positions_EQ", "neg_sim_sk_ok",
       "pos_k_eq_s", "flip_secret", "swap_pair", "swap_golden"]
    + ["cec_unfused_fused", "decoded_eq_secret", "payload_full_ok", "fused_payload_ok"]
    + ["cone_vs_intprod", "golden_vs_intprod", "intprod_neg_bit", "intprod_neg_mismatches", "lut_expansion_cec"]
    + ["mutant_constants_before", "mutant_constants_after", "mutant_edits"]
    + ["dut_source", "p40_equal", "dut_sha256", "dut_fused_sha256", "main_sha256", "harness_sha256"]
)


class RecordError(Exception):
    pass


def load_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        raise RecordError(f"cannot read {path}: {e}")


def find_index(raw, tier):
    found = sorted(raw.glob(f"index-tier{tier}-*.tsv"))
    if len(found) != 1:
        raise RecordError(f"tier {tier}: expected exactly one index-tier{tier}-*.tsv in {raw}, found {len(found)}")
    return found[0]


def read_index(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def attempt_path(raw, row):
    """Folder of the attempt: the part of attempt_dir after ``p53-iscas-configured/``, relative to --raw."""
    d = row["attempt_dir"].replace("\\", "/")
    i = d.find(RAW_MARK)
    if i < 0:
        raise RecordError(f"attempt_dir of {row['config']} does not contain {RAW_MARK}: {d}")
    return raw / d[i + len(RAW_MARK):]


def parse_result(text):
    out = {}
    for part in text.split(";"):
        if not part:
            continue
        if "=" not in part:
            raise RecordError(f"bad result item {part!r}")
        k, v = part.split("=", 1)
        out[k] = v
    return out


def sid_of(tier, row):
    parts = row["config"].split(".")
    if tier == "E":
        return row["sid"]
    if tier == "B":
        return ""
    if tier == "X":
        return parts[-1]
    if tier == "S":
        return parts[-1]
    return parts[-2]            # M.<host>.<out>.<sid>.<class>


def scalar(v):
    if isinstance(v, bool):
        return "True" if v else "False"
    if v is None:
        return ""
    return str(v)


def inconclusive_names(jrec):
    names = [c["name"] for c in jrec.get("checks", []) if c.get("observed") in ("TIMEOUT", "ERROR", "UNKNOWN")]
    return ",".join(dict.fromkeys(names))


def emission(raw, host, out, tier, sid, variant):
    path = raw / host / out / tier / sid / variant / "emit.json"
    if not path.is_file():
        raise RecordError(f"missing {path}")
    return load_json(path)


def p40_state(emit, sha):
    exp = emit.get("p40_sha256_expected")
    if exp is None:
        return ""
    return "yes" if exp == sha else "no"


def build_row(raw, tier, row):
    rec = {c: "" for c in COLUMNS}
    d = attempt_path(raw, row)
    code = tier
    rec.update(tier=tier, config=row["config"], counted=row["counted"], host=row["host"], out=row["out"],
               n=row["n"], h=row["h"], sid=sid_of(tier, row), status=row["status"], verdict=row["verdict"] if tier != "E" else row["status"],
               harness_sha256=row["harness_sha256"])
    if tier == "E":
        rec.update(call="exhaustive", attempt="", variant=row["variant"], dut_sha256=row["emitted_sha256"],
                   main_sha256=row["main_sha256"])
        for k in E_FACTS:
            rec[k] = row[k]
        emit = load_json(d / "emit.json")
        rec["dut_source"] = "main"
        rec["p40_equal"] = p40_state(emit, row["emitted_sha256"])
    else:
        rec.update(call=row["call"], attempt="r1" if d.name == "r1" else "")
        res = parse_result(row["result"])
        sub = CALL_SUB[row["call"]]
        want = RESULT_KEYS[sub]
        if list(res) != want:
            raise RecordError(f"{row['config']} {row['call']}: result keys {list(res)} differ from {want}")
        for k, v in res.items():
            rec[k] = v
        rec["dut_sha256"] = row["dut_sha256"]
    jrec = load_json(d / f"{code}.json")
    jrow = jrec["row"]
    if scalar(jrow["status"]) != row["status"]:
        raise RecordError(f"{row['config']}: index status {row['status']} differs from {code}.json status {jrow['status']}")
    for k in ("host", "out", "n"):
        if k == "out" and row.get("call") == "pair":
            continue                    # the pair row names the DUT output wire, not the cone
        if scalar(jrow[k]) != row[k]:
            raise RecordError(f"{row['config']}: index {k} {row[k]} differs from {code}.json {jrow[k]}")
    if jrow["harness_sha256"] != row["harness_sha256"]:
        raise RecordError(f"{row['config']}: harness_sha256 differs between index and {code}.json")
    for k in JSON_FACTS:
        if k in jrow:
            rec[k] = scalar(jrow[k])
    rec["inconclusive_checks"] = inconclusive_names(jrec)
    if rec["failed_checks"] == "-":
        rec["failed_checks"] = ""
    if tier == "E":
        return rec
    call, host, out, sid = row["call"], row["host"], row["out"], rec["sid"]
    if tier == "B":
        return rec
    if tier in ("X", "S"):
        need = {"perkey": ("unfused",), "goldenU": ("unfused",), "goldenF": ("fused",), "miter": ("unfused",),
                "controls": ("unfused",), "sim": ("unfused",), "pair": ("unfused", "fused")}[call]
        ems = [emission(raw, host, out, tier, sid, v) for v in need]
        rec["variant"] = need[0] if len(need) == 1 else ""
        sources = {e["source"] for e in ems}
        rec["dut_source"] = sources.pop() if len(sources) == 1 else "mixed"
        for e in ems:
            if e["main_sha256"] != ems[0]["main_sha256"]:
                raise RecordError(f"{row['config']}: emissions disagree on the Main binary")
        rec["main_sha256"] = ems[0]["main_sha256"]
        if ems[0]["dut_sha256"] != row["dut_sha256"]:
            raise RecordError(f"{row['config']}: index dut_sha256 differs from emit.json")
        states = {p40_state(e, e["dut_sha256"]) for e in ems} - {""}
        rec["p40_equal"] = "no" if "no" in states else ("yes" if states else "")
        if call == "pair":
            rec["dut_fused_sha256"] = ems[1]["dut_sha256"]
        return rec
    # tier M: the DUT is the mutant of the unfused Tier S emission; pair also reads the fused emission
    cls = row["config"].split(".")[-1]
    mut = load_json(raw / host / out / "M" / sid / cls / "mutate.json")
    rec.update(mutant=cls, variant="unfused" if call == "golden" else "")
    rec["dut_source"] = "mutant-of-" + mut["original"]["source"]
    if mut["mutant"]["sha256"] != row["dut_sha256"]:
        raise RecordError(f"{row['config']}: index dut_sha256 differs from mutate.json")
    rec["mutant_constants_before"] = scalar(mut["constants_before"])
    rec["mutant_constants_after"] = scalar(mut["constants_after"])
    rec["mutant_edits"] = scalar(mut["edit_count"])
    ue = emission(raw, host, out, "S", sid, "unfused")
    rec["main_sha256"] = ue["main_sha256"]
    if call == "pair":
        rec["dut_fused_sha256"] = emission(raw, host, out, "S", sid, "fused")["dut_sha256"]
    return rec


def build_rows(raw):
    rows = []
    for tier in TIERS:
        for r in read_index(find_index(raw, tier)):
            rows.append(build_row(raw, tier, r))
    return rows


def render(rows):
    lines = ["\t".join(COLUMNS)]
    for r in rows:
        lines.append("\t".join(r[c] for c in COLUMNS))
    return ("\n".join(lines) + "\n").encode("utf-8")
