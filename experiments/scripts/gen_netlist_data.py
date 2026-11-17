import sys, json
sys.path.insert(0,'.')
from sim_po_cone import parse, driver_map, cone_support

# Translate a two-input LUT value V into Circuit 2 1, fixing Id widths explicitly.
GAD={
 0x1:"(Seq Or2 Not1)", 0x2:"(Seq (Par (Id {1}) Not1) And2)",
 0x3:"(Seq (Plug (λ _ → F.suc F.zero)) Not1)", 0x4:"(Seq (Par Not1 (Id {1})) And2)",
 0x5:"(Seq (Plug (λ _ → F.zero)) Not1)", 0x6:"Xor2", 0x7:"(Seq And2 Not1)", 0x8:"And2",
 0x9:"(Seq Xor2 Not1)", 0xa:"(Plug (λ _ → F.zero))", 0xb:"(Seq (Par (Id {1}) Not1) Or2)",
 0xc:"(Plug (λ _ → F.suc F.zero))", 0xd:"(Seq (Par Not1 (Id {1})) Or2)", 0xe:"Or2",
}
def emit(path, modname, prefix, H):
    ins,outs,gates=parse(path); ins_set=set(ins); drv=driver_map(gates)
    out=max(outs,key=lambda o: len(cone_support(o,drv,ins_set)))
    support=cone_support(out,drv,ins_set); sset=set(support)
    order=[]; seen=set()
    def visit(w):
        if w in seen: return
        seen.add(w)
        if w in drv:
            for a in drv[w][1]: visit(a)
            order.append(w)
    visit(out)
    n=len(support); G=len(order)
    inpos={p:i for i,p in enumerate(support)}
    topo={w:k for k,w in enumerate(order)}
    def pos(net,k):   # Locate fan-in net in the below-bus of the gate at topological position k.
        if net in topo: return k-1-topo[net]   # refer to an earlier gate
        return k + inpos[net]                   # refer to a primary input
    L=[]
    L.append("{-# OPTIONS --safe --without-K #-}")
    L.append(f"module {modname} where")
    L.append("open import Data.Nat using (ℕ)")
    L.append("open import Data.Bool using (Bool; true; false)")
    L.append("open import Data.Fin using (Fin; #_)")
    L.append("import Data.Fin as F")
    L.append("open import Data.Vec using (Vec; []; _∷_)")
    L.append("open import Relation.Binary.PropositionalEquality using (_≡_; refl)")
    L.append("open import Circuit.Core using (Circuit; Id; Not1; And2; Or2; Xor2; Seq; Par; Plug)")
    L.append("open import SFLL.HammingDistance using (HD; parity)")
    L.append("open import Locking.CertifiedCompiler using (compileSFLL; CompiledLock)")
    L.append("open import Locking.NetlistToCircuit using (Gate; gate; Netlist; []; _∷_; importCone; importConeF; import-correct)")
    L.append("")
    nm=f"{prefix}nl"
    L.append(f"{nm} : Netlist {n} {G}")
    glines=[]
    for w in reversed(order):       # use reverse topological order, starting with the youngest output gate
        k=topo[w]; op,a,V=drv[w]
        if V not in GAD: sys.stderr.write(f"unsupported LUT 0x{V:x}\n"); sys.exit(1)
        glines.append(f"  gate (# {pos(a[0],k)}) (# {pos(a[1],k)}) {GAD[V]}")
    L.append(f"{nm} =")
    L.append(" ∷\n".join(glines)+" ∷ []")
    L.append("")
    k0=" ∷ ".join(["false"]*n); k1=" ∷ ".join(["true"]+["false"]*(n-1))
    L.append(f"ksec kapp : Vec Bool {n}")
    L.append(f"ksec = {k0} ∷ []"); L.append(f"kapp = {k1} ∷ []")
    L.append("odd : parity (HD ksec kapp) ≡ true")
    L.append("odd = refl")
    L.append(f"{nm}-locked : CompiledLock {H} ksec kapp (importConeF {nm})")
    L.append(f"{nm}-locked = compileSFLL (importCone {nm}) (importConeF {nm}) (import-correct {nm}) {H} ksec kapp odd")
    sys.stderr.write(f"{modname}: out={out} n={n} G={G}\n")
    print("\n".join(L))

# --flat writes text for the verified importer Extraction.LUTNetParse / LUTNetBuild,
# invoked by Main importnet: header "n G", followed by G records "a b code".
# Records are oldest first, so verified Agda parses and constructs the host Netlist
# instead of relying on this script to emit Agda source. The index code = V-1
# selects one of 14 verified lutCircuit gadgets, matching GAD via lutCircuit-correct.
# Optional arguments: pick output `sel` instead of the maximum-support one (ties keep
# the first declared output) and write the port map (support order = port order x_i).
def emit_flat(path, sel=None, portmap=None):
    ins, outs, gates = parse(path); ins_set = set(ins)
    # ABC LUT-2 files may hold 1-input LUTs, which the flat format rejects. Duplicate the
    # fan-in: NOT a = LUT 0x1 (a,a) (NOR), BUF a = LUT 0x8 (a,a) (AND).
    gates = [(w, op, [a[0], a[0]], {0x1: 0x1, 0x2: 0x8}[V]) if op == 'LUT' and len(a) == 1
             else (w, op, a, V) for (w, op, a, V) in gates]
    drv = driver_map(gates)
    if sel is not None and sel not in outs:
        sys.stderr.write("not a primary output: %s\n" % sel); sys.exit(1)
    out = sel if sel is not None else max(outs, key=lambda o: len(cone_support(o, drv, ins_set)))
    support = cone_support(out, drv, ins_set)
    order = []; seen = set()
    def visit(w):
        if w in seen: return
        seen.add(w)
        if w in drv:
            for a in drv[w][1]: visit(a)
            order.append(w)
    visit(out)
    n = len(support); G = len(order)
    inpos = {p: i for i, p in enumerate(support)}
    topo = {w: k for k, w in enumerate(order)}
    def pos(net, k):
        if net in topo: return k - 1 - topo[net]
        return k + inpos[net]
    # Extraction.LUTNetParse reuses BenchRoundTrip number parsing and reads decimal
    # digits least significant first, following the repository .bench convention
    # of the observation-scope discussion. Reverse each printed number, such as 167 to "761".
    def lsb(x):
        return str(x)[::-1]
    lines = ["%s %s" % (lsb(n), lsb(G))]
    for w in order:                       # order gates oldest first for fromFlat
        k = topo[w]; op, a, V = drv[w]
        if V not in GAD:
            sys.stderr.write("unsupported LUT 0x%x\n" % V); sys.exit(1)
        lines.append("%s %s %s" % (lsb(pos(a[0], k)), lsb(pos(a[1], k)), lsb(V - 1)))
    sys.stderr.write("flat: out=%s n=%d G=%d\n" % (out, n, G))
    print("\n".join(lines))
    if portmap:
        json.dump({"bench": path, "out": out, "n": n, "gates": G, "support": support}, open(portmap, "w"))

# Usage: gen_netlist_data.py --flat <bench> [--out <PO>] [--portmap <file.json>]
def flat_opt(name):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None

if len(sys.argv) >= 3 and sys.argv[1] == "--flat":
    emit_flat(sys.argv[2], flat_opt("--out"), flat_opt("--portmap"))
else:
    emit(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]))
