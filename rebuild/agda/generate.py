"""Generate eight Agda modules in a new, reader-local src overlay."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import c17

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("artifact", "rtl", "norm", "literals", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    scripts = (args.artifact / "experiments/scripts").resolve()
    sys.path.insert(0, str(scripts))
    from sim_po_cone import parse

    if args.output.exists() or args.output.is_symlink():
        parser.error("Output already exists. Use a new local directory.")
    built = c17.modules(args.rtl, args.norm, parse)
    for item in json.loads((HERE / "recipe.json").read_text()):
        cmd = [sys.executable, "-B", "-X", "utf8", str(scripts / "gen_netlist_data.py"),
               str((args.literals / item["input"]).resolve()), item["module"], item["prefix"], str(item["radius"])]
        code = subprocess.check_output(cmd, cwd=scripts)
        if item["line_ending"] == "CRLF":
            code = code.replace(b"\n", b"\r\n")
        data = item["comment_prefix"].encode() + code
        if hashlib.sha256(data).hexdigest() != item["module_sha256"]:
            raise ValueError(f"Regeneration differs for {item['module']}")
        built[item["module"].split(".")[-1]] = data
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as tmp:
        overlay = Path(tmp) / "overlay"
        dest = overlay / "Locking"
        dest.mkdir(parents=True)
        for name, data in built.items():
            (dest / (name + ".agda")).write_bytes(data)
        if args.output.exists() or args.output.is_symlink():
            parser.error("Output appeared during generation")
        overlay.rename(args.output)
    print(json.dumps({name: hashlib.sha256(data).hexdigest() for name, data in sorted(built.items())}, indent=2))


if __name__ == "__main__":
    main()
