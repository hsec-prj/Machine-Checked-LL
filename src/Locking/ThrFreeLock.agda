------------------------------------------------------------------------
--  Threshold-freedom along verified locking compilation
--  `Circuit.ThrFree` states the premise needed for gateCount to agree with
--  emission: `Thr` must be absent, since `Extraction.Bench.emit` expands
--  that primitive instead of producing one node. Establish the premise
--  throughout the emission path, making the locked-netlist area claims
--  unconditional. The proof proceeds from components to complete hosts:
--  §1 SFLL.Netlist uses only Boolean gates, muxes, and routing for its key
--  XOR layer, exactlyH comparator, protected test, and three-way XOR.
--  §2 The synthesizable SFLL.PopcountCircuit / SFLL.EfficientLock variant
--  likewise has a threshold-free popcount comparator.
--  §3 The Locking.GenericLock skeleton adds no Thr, so it is threshold-free
--  exactly when its host and two gadgets are.
--  §4 Locking.NetlistToCircuit preserves the property gate by gate because
--  import adds only routing and Par.
--  §5 Each of Extraction.LUTGadget's 14 verified gadgets is threshold-free.
--  Consequently every netlist accepted by Extraction.LUTNetBuild.fromFlat
--  satisfies the premise by theorem, without a side condition.
--  §6 Combining these results makes an SFLL-locked host parsed from flat
--  text unconditionally threshold-free.
--  §7 demonstrates why the premise matters: a concrete Thr costs one
--  symbolic cell but expands to six expression cells. No postulates are used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.ThrFreeLock where

open import Data.Bool using (Bool; false; true)
open import Data.Empty using (⊥)
open import Data.Fin using (Fin; fromℕ<) renaming (suc to fsuc)
open import Data.Fin.Patterns using (0F; 1F; 2F; 3F; 4F; 5F; 6F; 7F; 8F; 9F)
open import Data.List using (List; []; _∷_)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Maybe.Properties using (just-injective)
open import Data.Nat using (ℕ; zero; suc; _+_; _<?_)
open import Data.Product using (_×_; _,_)
open import Data.Unit using (⊤; tt)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Function using (case_of_)
open import Relation.Nullary using (yes; no)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; subst)

open import Circuit.Core using (Circuit; Thr)
open import Circuit.GateCount using (gateCount)
open import Circuit.ThrFree using (ThrFree)
open import Extraction.Bench using
  (Expr; var; con; gnot; gand; gor; gxor; gmux; emit)
open import Extraction.LUTGadget using (lutCircuit)
open import Extraction.LUTNetBuild using (NLΣ; addGate; buildFrom; fromFlat)
open import Extraction.LUTNetParse using (FGate)
open import Locking.GenericLock using (ProtGadget; locked-circuit-gen)
open import Locking.NetlistToCircuit using
  (Netlist; Gate; netlistToCircuit; importCone)
  renaming ([] to nilNL; _∷_ to consNL)
open import SFLL.EfficientLock using (prot-circuit-eff; locked-circuit-eff)
open import SFLL.Netlist using
  (gateXor; xorK; cFalse; mkLevel; exactlyH; prot-circuit;
   dupAll; tripleAll; xor3; locked-circuit)
open import SFLL.PopcountCircuit using (shiftFC; distC; popcountEqC)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  §1 Establish the SFLL-HD skeleton's property.

--  Each per-wire key element is routing or inversion, with no threshold gate.
ThrFree-gateXor : (b : Bool) → ThrFree (gateXor b)
ThrFree-gateXor false = tt
ThrFree-gateXor true  = tt

ThrFree-xorK : (k : Vec Bool n) → ThrFree (xorK k)
ThrFree-xorK []       = tt
ThrFree-xorK (b ∷ ks) = ThrFree-gateXor b , ThrFree-xorK ks

--  Implement the constant-false source with routing and a Const cell.
ThrFree-cFalse : (n : ℕ) → ThrFree (cFalse n)
ThrFree-cFalse n = tt , tt

--  A comparator level fans out and multiplexes its two sub-counters.
ThrFree-mkLevel : (n : ℕ) (sf st : Circuit n 1) →
                  ThrFree sf → ThrFree st → ThrFree (mkLevel n sf st)
ThrFree-mkLevel n sf st tf ts = (tt , tt) , ((tt , (tf , ts)) , tt)

--  The exact-weight comparator consists of a mux tree with Const leaves.
ThrFree-exactlyH : (n h : ℕ) → ThrFree (exactlyH n h)
ThrFree-exactlyH zero    zero    = tt
ThrFree-exactlyH zero    (suc h) = tt
ThrFree-exactlyH (suc n) zero    =
  ThrFree-mkLevel n (exactlyH n zero) (cFalse n)
    (ThrFree-exactlyH n zero) (ThrFree-cFalse n)
ThrFree-exactlyH (suc n) (suc h) =
  ThrFree-mkLevel n (exactlyH n (suc h)) (exactlyH n h)
    (ThrFree-exactlyH n (suc h)) (ThrFree-exactlyH n h)

ThrFree-prot-circuit : (h : ℕ) (k : Vec Bool n) → ThrFree (prot-circuit h k)
ThrFree-prot-circuit {n} h k = ThrFree-xorK k , ThrFree-exactlyH n h

ThrFree-dupAll : (n : ℕ) → ThrFree (dupAll n)
ThrFree-dupAll n = tt

ThrFree-tripleAll : (n : ℕ) → ThrFree (tripleAll n)
ThrFree-tripleAll n = tt

ThrFree-xor3 : ThrFree xor3
ThrFree-xor3 = (tt , tt) , tt

--  The lock adds no threshold primitive. Thus the assembled circuit has
--  the property precisely when its host does; only that host premise remains.
ThrFree-locked-circuit :
  (Cf : Circuit n 1) (h : ℕ) (ksec kapp : Vec Bool n) →
  ThrFree Cf → ThrFree (locked-circuit Cf h ksec kapp)
ThrFree-locked-circuit Cf h ksec kapp tCf =
  tt , ((tCf , (ThrFree-prot-circuit h ksec , ThrFree-prot-circuit h kapp))
       , ThrFree-xor3)

------------------------------------------------------------------------
--  §2 Establish the synthesizable popcount variant's property.

ThrFree-shiftFC : (m : ℕ) → ThrFree (shiftFC m)
ThrFree-shiftFC zero    = tt , tt
ThrFree-shiftFC (suc m) = tt , (tt , ThrFree-shiftFC m)

ThrFree-distC : (N : ℕ) → ThrFree (distC N)
ThrFree-distC zero    = tt
ThrFree-distC (suc N) =
  ((tt , ThrFree-distC N) , (tt , (tt , tt))) , ThrFree-shiftFC (suc N)

ThrFree-popcountEqC : (N : ℕ) (k : Fin (suc N)) → ThrFree (popcountEqC N k)
ThrFree-popcountEqC N k = ThrFree-distC N , tt

ThrFree-prot-circuit-eff : (hF : Fin (suc n)) (k : Vec Bool n) →
                           ThrFree (prot-circuit-eff hF k)
ThrFree-prot-circuit-eff {n} hF k = ThrFree-xorK k , ThrFree-popcountEqC n hF

ThrFree-locked-circuit-eff :
  (Cf : Circuit n 1) (hF : Fin (suc n)) (ksec kapp : Vec Bool n) →
  ThrFree Cf → ThrFree (locked-circuit-eff Cf hF ksec kapp)
ThrFree-locked-circuit-eff Cf hF ksec kapp tCf =
  tt , ((tCf , (ThrFree-prot-circuit-eff hF ksec
              , ThrFree-prot-circuit-eff hF kapp))
       , ThrFree-xor3)

------------------------------------------------------------------------
--  §3 Handle the scheme-generic construction.
--  Its fan-out, parallel host and gadget evaluation, and three-way XOR
--  contain no threshold gate. The property depends only on those three
--  components.

ThrFree-locked-circuit-gen :
  (Cf : Circuit n 1) (gS gA : ProtGadget n) →
  ThrFree Cf → ThrFree (ProtGadget.gadget gS) → ThrFree (ProtGadget.gadget gA) →
  ThrFree (locked-circuit-gen Cf gS gA)
ThrFree-locked-circuit-gen Cf gS gA tCf tS tA =
  tt , ((tCf , (tS , tA)) , ThrFree-xor3)

------------------------------------------------------------------------
--  §4 Handle verified netlist import.
--  Require every gate gadget in the netlist to be threshold-free.

ThrFreeNL : ∀ {G} → Netlist n G → Set
ThrFreeNL nilNL          = ⊤
ThrFreeNL (consNL gt nl) = ThrFree (Gate.g gt) × ThrFreeNL nl

--  Each imported gate gains a routing Plug and a Par _ Id, introducing
--  no additional primitive beyond its gadget.
ThrFree-netlistToCircuit : ∀ {G} (nl : Netlist n G) →
                           ThrFreeNL nl → ThrFree (netlistToCircuit nl)
ThrFree-netlistToCircuit nilNL          tf        = tt
ThrFree-netlistToCircuit (consNL gt nl) (tg , tn) =
  ThrFree-netlistToCircuit nl tn , (tt , (tg , tt))

ThrFree-importCone : ∀ {G} (nl : Netlist n (suc G)) →
                     ThrFreeNL nl → ThrFree (importCone nl)
ThrFree-importCone nl tf = ThrFree-netlistToCircuit nl tf , tt

------------------------------------------------------------------------
--  §5 Discharge the premise for LUT import.
--  fromFlat chooses only from the 14 verified lutCircuit gadgets, all of
--  which are threshold-free. Its assembled netlist therefore has the
--  property by construction; the real-host route proves §4's condition.

private
  --  Data.Fin.Patterns provides names only through 9F, but LUT codes extend to 13.
  pattern 10F = fsuc 9F
  pattern 11F = fsuc 10F
  pattern 12F = fsuc 11F
  pattern 13F = fsuc 12F

ThrFree-lutCircuit : (i : Fin 14) → ThrFree (lutCircuit i)
ThrFree-lutCircuit 0F  = tt , tt
ThrFree-lutCircuit 1F  = (tt , tt) , tt
ThrFree-lutCircuit 2F  = tt , tt
ThrFree-lutCircuit 3F  = (tt , tt) , tt
ThrFree-lutCircuit 4F  = tt , tt
ThrFree-lutCircuit 5F  = tt
ThrFree-lutCircuit 6F  = tt , tt
ThrFree-lutCircuit 7F  = tt
ThrFree-lutCircuit 8F  = tt , tt
ThrFree-lutCircuit 9F  = tt
ThrFree-lutCircuit 10F = (tt , tt) , tt
ThrFree-lutCircuit 11F = tt
ThrFree-lutCircuit 12F = (tt , tt) , tt
ThrFree-lutCircuit 13F = tt

--  Package the assembler accumulator as one induction invariant.
ThrFreeNLΣ : NLΣ n → Set
ThrFreeNLΣ (G , nl) = ThrFreeNL nl

--  An accepted gate preserves the invariant by installing a threshold-free lutCircuit.
ThrFreeNLΣ-addGate : (fg : FGate) (acc acc′ : NLΣ n) →
                     ThrFreeNLΣ acc → addGate fg acc ≡ just acc′ →
                     ThrFreeNLΣ acc′
ThrFreeNLΣ-addGate {n} (a , b , code) (G , nl) acc′ tf eq
  with a <? (G + n) | b <? (G + n) | code <? 14
... | yes pa | yes pb | yes pc =
      subst ThrFreeNLΣ (just-injective eq)
            (ThrFree-lutCircuit (fromℕ< pc) , tf)
... | yes pa | yes pb | no _    = case eq of λ ()
... | yes pa | no _   | _       = case eq of λ ()
... | no _   | _      | _       = case eq of λ ()

--  The complete fold consequently preserves that invariant.
ThrFreeNLΣ-buildFrom : (gs : List FGate) (acc acc′ : NLΣ n) →
                       ThrFreeNLΣ acc → buildFrom gs acc ≡ just acc′ →
                       ThrFreeNLΣ acc′
ThrFreeNLΣ-buildFrom []       acc acc′ tf eq =
  subst ThrFreeNLΣ (just-injective eq) tf
ThrFreeNLΣ-buildFrom (g ∷ gs) acc acc′ tf eq with addGate g acc in eqA
... | just acc″ =
      ThrFreeNLΣ-buildFrom gs acc″ acc′
        (ThrFreeNLΣ-addGate g acc acc″ tf eqA) eq
... | nothing   = case eq of λ ()

--  Every successful import is threshold-free without further assumptions.
ThrFreeNLΣ-fromFlat : (n : ℕ) (gs : List FGate) (acc′ : NLΣ n) →
                      fromFlat n gs ≡ just acc′ → ThrFreeNLΣ acc′
ThrFreeNLΣ-fromFlat n gs acc′ eq =
  ThrFreeNLΣ-buildFrom gs (0 , nilNL) acc′ tt eq

--  Split the returned pair to present the same result in the form used by §6.
ThrFreeNL-fromFlat : (n : ℕ) (gs : List FGate) {G : ℕ} {nl : Netlist n G} →
                     fromFlat n gs ≡ just (G , nl) → ThrFreeNL nl
ThrFreeNL-fromFlat n gs {G} {nl} eq = ThrFreeNLΣ-fromFlat n gs (G , nl) eq

------------------------------------------------------------------------
--  §6 Conclude threshold-freedom for the locked imported host.
--  fromFlat supplies the host property by §5, and the lock adds no Thr by
--  §1. Thus every flat-text-host compiler output satisfies the premise
--  identifying gateCount with emitted cell count, without an extra hypothesis.

ThrFree-compiled :
  (n : ℕ) (gs : List FGate) {G : ℕ} {nl : Netlist n (suc G)} →
  fromFlat n gs ≡ just (suc G , nl) →
  (h : ℕ) (ksec kapp : Vec Bool n) →
  ThrFree (locked-circuit (importCone nl) h ksec kapp)
ThrFree-compiled n gs {G} {nl} eq h ksec kapp =
  ThrFree-locked-circuit (importCone nl) h ksec kapp
    (ThrFree-importCone nl (ThrFreeNL-fromFlat n gs eq))

------------------------------------------------------------------------
--  §7 Exhibit the undercount when Thr is present.
--  exprGates counts emitted operator nodes, one cell each, excluding
--  variables and constants. Comparing it with gateCount on the same
--  circuit measures the exact expansion introduced by the emitter.

exprGates : Expr n → ℕ
exprGates (var _)     = 0
exprGates (con _)     = 0
exprGates (gnot e)    = suc (exprGates e)
exprGates (gand a b)  = suc (exprGates a + exprGates b)
exprGates (gor a b)   = suc (exprGates a + exprGates b)
exprGates (gxor a b)  = suc (exprGates a + exprGates b)
exprGates (gmux s a b) = suc (exprGates s + exprGates a + exprGates b)

--  The static measure assigns one cell to the 2-of-3 threshold gate.
thr-gateCount-one : gateCount (Thr {3} 2) ≡ 1
thr-gateCount-one = refl

--  Emission instead produces a tree of six muxes. This is why the area
--  interpretation of gateCount needs threshold-freedom, established for
--  compiler outputs in §1–§6.
thr-emit-blowup : exprGates (lookup (emit (Thr {3} 2)) 0F) ≡ 6
thr-emit-blowup = refl

--  For a positive comparison, the two counts coincide on threshold-free
--  xor3, the lock's output combiner.
xor3-emit-exact : exprGates (lookup (emit xor3) 0F) ≡ gateCount xor3
xor3-emit-exact = refl
