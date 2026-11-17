"""Strict parser for the generic gate dialect used by the experiment checks.

This is an experimental reader, not the certified Agda parser. Unknown syntax
is an error; it must never become an empty circuit or a successful decode.
"""
from dataclasses import dataclass
import hashlib
from pathlib import Path
import re


@dataclass
class Bench:
    inputs: list
    outputs: list
    gates: list


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def parse(text):
    inputs, outputs, gates, driven = [], [], [], set()
    arities = {"NOT": (1, 1), "BUF": (1, 1), "AND": (1, None),
               "NAND": (1, None), "OR": (1, None), "NOR": (1, None),
               "XOR": (2, None), "XNOR": (2, None), "VDD": (0, 0),
               "GND": (0, 0), "ONE": (0, 0), "ZERO": (0, 0)}
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        port = re.fullmatch(r"(INPUT|OUTPUT)\s*\(\s*([^\s(),=]+)\s*\)", line, re.I)
        if port:
            kind, name = port[1].upper(), port[2]
            destination = inputs if kind == "INPUT" else outputs
            if name in destination or (kind == "INPUT" and name in driven):
                raise ValueError(f"line {number}: duplicate {kind} {name}")
            destination.append(name)
            if kind == "INPUT":
                driven.add(name)
            continue
        gate = re.fullmatch(r"([^\s(),=]+)\s*=\s*([A-Za-z]+)\s*\(([^()]*)\)", line)
        if not gate:
            raise ValueError(f"line {number}: unsupported syntax: {line[:120]}")
        name, op = gate[1], gate[2].upper()
        op = "BUF" if op == "BUFF" else op
        args = [part.strip() for part in gate[3].split(",")] if gate[3].strip() else []
        if op not in arities:
            raise ValueError(f"line {number}: unsupported operator {op}")
        lo, hi = arities[op]
        if len(args) < lo or (hi is not None and len(args) > hi) or any(not a for a in args):
            raise ValueError(f"line {number}: invalid {op} arity")
        if name in driven:
            raise ValueError(f"line {number}: multiple drivers for {name}")
        driven.add(name)
        gates.append((name, op, args))
    missing = ({a for _, _, args in gates for a in args} | set(outputs)) - driven
    if missing or not outputs:
        raise ValueError(f"missing outputs/drivers: {sorted(missing)[:12]}")
    return Bench(inputs, outputs, gates)


def constant_payload(net):
    return "".join("1" if op in {"VDD", "ONE"} else "0"
                   for _, op, _ in net.gates if op in {"VDD", "ONE", "GND", "ZERO"})


def protection_map(net):
    mapping = {}
    for _, op, args in net.gates:
        if op == "XOR" and len(args) == 2:
            for i in (0, 1):
                match = re.fullmatch(r"keyinput(\d+)", args[i])
                if match:
                    index = int(match[1])
                    if index in mapping:
                        raise ValueError(f"ambiguous keyinput{index} protection map")
                    mapping[index] = args[1 - i]
    if sorted(mapping) != list(range(len(mapping))):
        raise ValueError("noncontiguous protected key indices")
    return [mapping[i] for i in range(len(mapping))]
