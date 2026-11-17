"""Construct both proof instances from the reader's pinned structural inputs."""
import hashlib
import re
from string import Template
from pathlib import Path

HERE = Path(__file__).resolve().parent
RTL_SHA = "656bf0f1dbb02adb5cb9452d9c2031201a0c7c655441b1d47d111d8744d00f3c"
NORM_BODY_SHA = "c10a26ecebe245a80c9888426cf6505d6e0ba4bd4c7aa74c930b99e3f1ebd97b"

# Constructors describe supported two-input Boolean operators, independent of the design.
GADGET = {"AND": "And2", "OR": "Or2", "ANDNOT": "(Seq (Par (Id {1}) Not1) And2)", "NAND": "nandG"}
LUT_OP = {0x8: "AND", 0xe: "OR", 0x2: "ANDNOT"}


def check_pin(data, expected, path):
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"Unexpected source bytes in {path}")


def verilog(path):
    data = path.read_bytes()
    check_pin(data, RTL_SHA, path)
    text = data.decode()
    inputs = re.search(r"(?m)^input (.+);$", text)[1].split(",")
    outputs = re.search(r"(?m)^output (.+);$", text)[1].split(",")
    gates = []
    for dest, a, b in re.findall(r"(?m)^nand \w+ \((\w+), (\w+), (\w+)\);$", text):
        gates.append((dest, "NAND", (a, b)))
    return inputs, outputs, gates


def output_cone(inputs, output, gates):
    needed = {output}
    selected = []
    for gate in reversed(gates):
        dest, _, arguments = gate
        if dest in needed:
            selected.append(gate)
            needed.update(arguments)
    return [p for p in inputs if p in needed], list(reversed(selected))


def vector(items):
    return " ∷ ".join([*items, "[]"])


def netlist(name, inputs, outputs, gates):
    bus = inputs.copy()
    records = []
    for dest, op, args in gates:
        a, b = [bus.index(pin) for pin in args]
        records.append(f"  gate (# {a}) (# {b}) {GADGET[op]}")
        bus.insert(0, dest)
    declaration = f"{name} : Netlist {len(inputs)} {len(gates)}\n{name} =\n"
    return declaration + " ∷\n".join(reversed(records)) + " ∷ []", [bus.index(o) for o in outputs]


def formulas(inputs, gates):
    values = {p: f"x{i}" for i, p in enumerate(inputs)}
    for dest, op, (left, right) in gates:
        a, b = values[left], values[right]
        if op == "AND":
            value = f"({a} ∧ {b})"
        elif op == "OR":
            value = f"({a} ∨ {b})"
        elif op == "ANDNOT":
            value = f"({a} ∧ not {b})"
        elif op == "NAND":
            value = f"(not ({a} ∧ {b}))"
        else:
            raise ValueError(f"Unsupported operator {op}")
        values[dest] = value
    return values


def compose(constructor, stages):
    result = stages[-1]
    for stage in reversed(stages[:-1]):
        result = f"({constructor} {stage} {result})"
    return result


def dsl(inputs, output, gates):
    # Expand compound LUT gadgets into primitive circuit layers before routing.
    pending = []
    for dest, op, args in gates:
        if op == "ANDNOT":
            negated = dest + "@not"
            pending.append((negated, "Not1", (args[1],)))
            pending.append((dest, "And2", (args[0], negated)))
        else:
            pending.append((dest, GADGET[op], args))
    bus = inputs.copy()
    stages, routes = [], []
    while pending:
        ready = [g for g in pending if all(x in bus for x in g[2])]
        if not ready:
            raise ValueError("Circuit is cyclic or has an undriven input")
        pending = [g for g in pending if g not in ready]
        live = {output} | {pin for _, _, args in pending for pin in args}
        carried = [(p, "(Id {1})", (p,)) for p in bus if p in live]
        # Gate outputs already computed lead the next layer; unused primary
        # inputs are carried at the end until their consuming gates are ready.
        layer = [g for g in carried if g[0] not in inputs] + ready + [g for g in carried if g[0] in inputs]
        source_order = [p for _, _, args in layer for p in args]
        if source_order != bus:
            route = f"route{len(routes) + 1}"
            indices = vector([f"# {bus.index(p)}" for p in source_order])
            routes.append(f"{route} : Fin {len(source_order)} → Fin {len(bus)}\n{route} i = lookup ({indices}) i")
            stages.append(f"(Plug {route})")
        stages.append(compose("Par", [op for _, op, _ in layer]))
        bus = [dest for dest, _, _ in layer]
    if bus != [output]:
        raise ValueError("Unexpected output interface")
    return "\n\n".join(routes + [f"c17C : Circuit {len(inputs)} 1\nc17C = " + compose("Seq", stages)])


def modules(rtl, norm, parse_bench):
    header, sep, body = norm.read_bytes().partition(b"\n")
    if not sep or not re.fullmatch(rb'# Benchmark "c17" written by ABC on [A-Za-z0-9 :]+', header):
        raise ValueError("Unrecognized normalized BENCH header")
    check_pin(body, NORM_BODY_SHA, norm)
    pins, ports, lut_gates = parse_bench(str(norm))
    gates = [(w, LUT_OP[lut], tuple(args)) for w, kind, args, lut in lut_gates if kind == "LUT"]
    if len(gates) != len(lut_gates):
        raise ValueError("Expected a LUT circuit")
    ins, cone = output_cone(pins, ports[0], gates)
    args = vector([f"x{i}" for i in range(len(ins))])
    single_data, _ = netlist("c17nl", ins, [ports[0]], cone)
    single = "\n\n".join([
        f"c17f : Vec Bool {len(ins)} → Bool\nc17f ({args}) = {formulas(ins, cone)[ports[0]]}",
        dsl(ins, ports[0], cone), single_data,
    ])
    inputs, outputs, gates = verilog(rtl)
    if inputs != pins or outputs != ports:
        raise ValueError("The upstream port orders disagree")
    data, indices = netlist("c17nl2", inputs, outputs, gates)
    args = vector([f"x{i}" for i in range(len(inputs))])
    values = formulas(inputs, gates)
    type_ = f"Vec Bool {len(inputs)} → Vec Bool {len(outputs)}"
    multi = "\n\n".join([
        data,
        f"outs : Vec (Fin {len(inputs) + len(gates)}) {len(outputs)}\nouts = " + vector([f"# {i}" for i in indices]),
        f"F2 : {type_}\nF2 = importMultiF c17nl2 outs",
        f"c17spec : {type_}\nc17spec ({args}) = " + vector([values[o] for o in outputs]),
    ])
    return {name: Template((HERE / template).read_text()).substitute(host=content).encode()
            for name, template, content in (("CompileISCAS", "single.template", single),
                                            ("CompileC17Multi", "multi.template", multi))}
