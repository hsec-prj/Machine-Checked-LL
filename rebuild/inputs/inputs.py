"""Fetch or verify pinned originals, then rebuild an ISCAS input overlay offline."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

import metadata

HERE = Path(__file__).resolve().parent
CATALOG = (HERE / "pins.json").read_bytes()
CATALOG_SHA256 = "ec9535867f1db6ea927240e95f4a19d60c0b2af0c9b33be141bbc496aea67d2e"
if hashlib.sha256(CATALOG).hexdigest() != CATALOG_SHA256:
    sys.exit("The ISCAS input recipe differs from its pinned release version")
PINS = json.loads(CATALOG)
RAW = "https://raw.githubusercontent.com"
VERILOG = "santoshsmalagi/Benchmarks/8a0b4d2ca0e85e9d2425a96212605e5327a22c61"
GOLDEN = "descyphy/Modified_SAT_Attack_on_Logic_Locking/ea169e5643d62b88da13f840a211e27c10590190"
ABC_HEADER = re.compile(rb'# Benchmark "[^"\r\n]+" written by ABC on (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) [A-Z][a-z]{2} [ 0-9][0-9] [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4}')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check_hash(data, expected, name):
    if sha(data) != expected:
        raise ValueError(f"SHA-256 mismatch: {name}")


def url(name):
    host = Path(name).stem
    if name.startswith("v/"):
        return f"{RAW}/{VERILOG}/ISCAS85/{host}/{host}.v"
    return f"{RAW}/{GOLDEN}/benchmarks/original/{host}.bench"


def checked(data, name):
    pin = PINS["sources"][name]
    check_hash(data, pin["sha256"], name)
    blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
    if len(data) != pin["bytes"] or blob != pin["git_blob"]:
        raise ValueError(f"Size or Git blob mismatch: {name}")
    return data


def local_inputs(cache):
    result = {}
    for name in PINS["sources"]:
        path = cache/name
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Expected a regular source file: {name}")
        result[name] = checked(path.read_bytes(), name)
    return result


def fetch(target):
    for name in PINS["sources"]:
        proc = subprocess.run(["curl", "--proto", "=https", "--proto-redir", "=https", "-fsSL",
                               "--retry", "2", "--max-time", "90", url(name)], capture_output=True)
        if proc.returncode:
            raise RuntimeError(f"curl failed for {name} (exit {proc.returncode})")
        path = target/name
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(checked(proc.stdout, name))


def install_bench(generated, target, key, record):
    pin = PINS["benchmarks"][key]
    raw = generated.read_bytes()
    header, lf, body = raw.partition(b"\n")
    if not lf or not ABC_HEADER.fullmatch(header):
        raise ValueError(f"Unexpected generated ABC header: {key}")
    check_hash(body, pin["body_sha256"], key + " body")
    prior = pin["archived_header"].encode()
    if not ABC_HEADER.fullmatch(prior):
        raise ValueError(f"Unexpected archival ABC header: {key}")
    restored = prior + b"\n" + body
    check_hash(restored, pin["archive_sha256"], key)
    out = target/key
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(restored)
    record.append(dict(path=key, fresh_sha256=sha(raw), body_sha256=sha(body), restored_sha256=sha(restored),
                       fresh_header=header.decode()))


def build(stage, scratch, release, cache):
    inputs = local_inputs(cache)
    yosys, abc = [shutil.which(tool) for tool in ("yosys", "yosys-abc")]
    if not all((yosys, abc)):
        raise ValueError("Both yosys and yosys-abc are required on PATH")
    versions = {}
    for exe, args in ((yosys, ["-V"]), (abc, ["-q", "version"])):
        versions[Path(exe).name] = dict(path=exe, sha256=sha(Path(exe).read_bytes()),
                                        version=subprocess.check_output([exe, *args], text=True).strip())
    data = stage/"experiments/data"
    (stage/"experiments/scripts").mkdir(parents=True)
    golden = data/"configured/sld"
    golden.mkdir(parents=True)
    records = []
    for name, content in inputs.items():
        host = Path(name).stem
        if name.startswith("sld/"):
            (golden/Path(name).name).write_bytes(content)
            continue
        (scratch/f"{host}.v").write_bytes(content)
        subprocess.run([yosys, "-q", "-p", f"read_verilog {host}.v; hierarchy -auto-top; proc; flatten; aigmap; write_blif {host}.blif"],
                       cwd=scratch, check=True)
        subprocess.run([abc, "-q", f"read_blif {host}.blif; strash; write_bench {host}.bench"], cwd=scratch, check=True)
        install_bench(scratch/f"{host}.bench", data, f"configured/norm/{host}.bench", records)
    for key in PINS["benchmarks"]:
        if key.startswith("configured/norm/"):
            continue
        host = Path(key).stem.split("_")[0]
        if Path(key).name.endswith("_lut2.bench"):
            opt = " dc2;" if "_dc2_" in key else ""
            output = scratch/"mapped.bench"
            output.unlink(missing_ok=True)
            subprocess.run([abc,"-q",f"read_bench {host}.bench; strash;{opt} if -K 2; write_bench mapped.bench"],
                           cwd=scratch, check=True)
        else:
            output = scratch/f"{host}.bench"
        install_bench(output, data, key, records)
    metadata.rebuild(data, stage, release, PINS["metadata"], inputs["v/c17.v"], check_hash)
    receipt = dict(sources={k:sha(v) for k,v in inputs.items()}, tools=versions, benches=records,
                   verified_archived_interface_files=len(PINS["metadata"]),
                   note="Restored hashes refer to the previous public archive; fresh hashes refer to this conversion.")
    (stage/"inputs-receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")


def publish(path, release, writer):
    if path.is_symlink() or path.exists():
        raise ValueError(f"Destination already exists: {path}")
    dest = path.resolve()
    if dest.is_relative_to(release) or release.is_relative_to(dest):
        raise ValueError("Choose a destination outside the release directory")
    if HERE.parent.name == "rebuild" and dest.is_relative_to(HERE.parents[1]):
        raise ValueError("Choose a destination outside the reader-tool installation")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".iscas-", dir=dest.parent) as temp:
        tmp = Path(temp)
        stage = tmp/"stage"
        stage.mkdir()
        writer(stage,tmp)
        if dest.is_symlink() or dest.exists():
            raise ValueError(f"Destination already exists: {path}")
        stage.rename(dest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode",required=True)
    for mode in ("fetch","check","build"):
        command = commands.add_parser(mode)
        command.add_argument("--cache",type=Path,required=True,help="directory with v/ and sld/ inputs")
        command.add_argument("--release",type=Path,default=HERE.parents[1],help="pristine artifact root")
        if mode=="build":
            command.add_argument("--output",type=Path,required=True,help="fresh local overlay outside the release")
    args = parser.parse_args()
    release = args.release.resolve()
    if args.mode=="fetch":
        publish(args.cache,release,lambda stage,tmp: fetch(stage))
    elif args.mode=="check":
        local_inputs(args.cache)
    else:
        cache = args.cache.resolve()
        out = args.output.resolve()
        if out.is_relative_to(cache) or cache.is_relative_to(out):
            raise ValueError("Cache and output directories must be separate")
        publish(args.output,release,lambda stage,tmp: build(stage,tmp,release,cache))
    print(f"{args.mode}: PASS")


if __name__=="__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
