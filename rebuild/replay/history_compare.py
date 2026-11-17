"""Join each archived observation with its separate, freshly measured functional control."""
import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
TABLES={"P41":"p41-dips.tsv","P43":"p43-recovery.tsv","paired":"p412-paired.tsv"}
POPULATION=Counter({"P41":30,"P43":320,"paired":8})


def require(value, reason):
    if not value:
        raise ValueError(reason)


def read(path):
    return json.loads(path.read_bytes())


def identity(group,row):
    if group=="paired":
        return f"paired.{row['host']}.{row['path']}"
    host=row["bench"] if group=="P41" and "bench" in row else row["host"]
    return f"{group}.{host}.n{row['n']}.h{row['h']}.seed{row['seed']}"


def indexed(rows, key):
    result={}
    for row in rows:
        name=key(row)
        require(name not in result,"duplicate case "+name)
        result[name]=row
    return result


def scalar_equal(text, value):
    if value is None:
        return text in {"","-","NA"}
    if type(value) in (int,float):
        return float(text)==value
    return text==value


def compare(functional, paired):
    old=read(HERE/"sat-history.json")
    pins=read(HERE/"history-functional-pins.json")
    route_pins=indexed(read(HERE/"paired-functions.json"),lambda r:r["host"])
    host_checks=indexed(paired["host_measurements"],lambda r:r["host"])
    require(set(host_checks)==set(route_pins),"paired host set")
    require(old["kind"]=="archival-scalar-recount","unexpected historical schema")
    rows=old["rows"]
    require(Counter(r["campaign"] for r in rows)==POPULATION,"unexpected historical denominators")
    ids=indexed(rows,lambda r:r["id"])
    require(functional["status"]==paired["status"]=="PASS","incomplete functional tests")
    measured=indexed(functional["cases"]+paired["rows"],
                     lambda r:r["case_id"] if "case_id" in r else identity("paired",r))
    require(set(measured)==set(ids),"incomplete fresh measurements")
    result=[]
    for group,filename in TABLES.items():
        source=HERE.parents[1]/"experiments/data/processed"/filename
        require(hashlib.sha256(source.read_bytes()).hexdigest()==old["processed_sha256"][group],filename)
        with source.open(newline="") as stream:
            original=indexed(csv.DictReader(stream,delimiter="\t"),lambda r:identity(group,r))
        require(set(original)=={r["id"] for r in rows if r["campaign"]==group},"table population "+group)
        for name,raw in original.items():
            row,obs=ids[name],measured[name]
            history=row["historical"]
            require(all(scalar_equal(raw[k],v) for k,v in history.items()),"processed table difference "+name)
            require(all(history[k]==v for k,v in row["recount"].items()),"archive recount difference "+name)
            if group=="paired":
                hash_ref=row["evidence_sha256"]["paired_input"]
                require(hash_ref==obs["historical_input_sha256"]==history["input_sha256"],"route identity "+name)
                fixed=obs["fixed_key_checks"]
                host=row["host"]
                expected=route_pins[host]["routes"][row["path"]]
                actual=host_checks[host]
                require(expected["input_sha256"]==hash_ref and fixed["vectors"]==expected["fixed_key_signature"]["vectors"]
                        and fixed["historical_outputs_sha256"]==expected["fixed_key_signature"]["outputs_sha256"]
                        and obs["measured"]["data_outputs_sha256"]==actual["signature"]["outputs_sha256"]
                        and actual["measured_sha256"]["fresh_host_flat"]==route_pins[host]["flat_sha256"],
                        "paired measurement binding "+name)
                require(fixed["historical_signature_matches"] and
                        fixed["historical_outputs_sha256"]==obs["measured"]["data_outputs_sha256"],"functional difference "+name)
                fresh_sha=obs["measured"]["data_outputs_sha256"]
                vectors=fixed["vectors"]
                require(not obs["full_route_bytes_regenerated"],"scope differs")
            else:
                hash_ref=row["evidence_sha256"]["locked_artifact"]
                expected=pins["rows"][name]
                require(obs["host_sha256"]==pins["host_sha256"][row["host"]]
                        and obs["comparator_sha256"]==pins["gadget_sha256"][f"{row['n']}/{row['h']}"]
                        and obs["planted_response_sha256"]==expected["planted_response_sha256"]
                        and obs["planted_vectors"]==64 and obs["primary_outputs"]==expected["primary_outputs"]
                        and obs["comparator_input_assignments"]==1<<row["n"],"host measurement binding "+name)
                require(hash_ref==obs["archived_locked_sha256"] and identity(group,obs)==name,"input binding "+name)
                require(obs["planted_response_match"] and obs["comparator_disagreements"]==0,"functional difference "+name)
                fresh_sha=obs["planted_response_sha256"]
                vectors=obs["planted_vectors"]
                require(not obs["locked_design_regenerated"],"scope differs")
            result.append(dict(case_id=name,campaign=group,host=row["host"],width=row["n"],route=row.get("path",""),
                               radius=row.get("h",""),seed=row.get("seed",""),historical_status=history["sld_status"],
                               historical_iterations=history["sld_iters"],historical_outcome=history.get("outcome",""),
                               historical_wall_s=history["wall_s"],archived_full_input_sha256=hash_ref,
                               archive_fields_recounted=json.dumps(row["recount"],sort_keys=True,separators=(",",":")),
                               archive_field_limits=json.dumps(row["observability"],sort_keys=True,separators=(",",":")),
                               fresh_fixed_key_vectors=vectors,fresh_data_output_sha256=fresh_sha,
                               fixed_key_response_matches=True,full_locked_bytes_freshly_verified=False,
                               fresh_key_recovery="not_run"))
    return result


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for arg in ("functional","paired","output"):
        p.add_argument("--"+arg,type=Path,required=True)
    a=p.parse_args()
    rows=compare(read(a.functional),read(a.paired))
    with a.output.open("x",newline="") as out:
        writer=csv.DictWriter(out,fieldnames=list(rows[0]),delimiter="\t",lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps(dict(rows=len(rows),campaigns=dict(POPULATION),fresh_functional_matches=len(rows),fresh_key_recovery_runs=0)))
