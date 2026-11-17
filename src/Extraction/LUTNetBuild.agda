------------------------------------------------------------------------
--  Build a scoped host netlist from parsed gates (option 1, phase 3).
--  Extraction.LUTNetParse supplies the phase-2 round trip between host text
--  and flat (a,b,code) gates. Assemble that list into the compiler's dependent
--  Fin-scoped representation with
--  fromFlat : (n : ℕ) → List FGate → Maybe (Σ[ G ] Netlist n G).
--  Process oldest gates first, over G existing gates plus n inputs. Accept a
--  gate only if both fan-ins are below G + n and its code is below 14. Thus
--  a just result is well-scoped by its type and uses only verified
--  Extraction.LUTGadget.lutCircuit gadgets. addGate-correct establishes that
--  an assembled gate computes lutFun for its code and fan-in values. With
--  phases 1 and 2, this verifies the complete path from text through flat
--  gates to scoped Netlist, with each gate's semantics checked. Instead of
--  trusting gen_netlist_data.py to emit Agda source, the importer can emit
--  (a,b,code) text for verified Agda decoding and assembly. No postulates
--  are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LUTNetBuild where

open import Data.Nat using (ℕ; suc; _+_; _<_; _<?_)
open import Data.Fin using (Fin; zero; fromℕ<)
open import Data.Bool using (Bool)
open import Data.List using (List; []; _∷_)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Product using (Σ-syntax; _,_; proj₁; proj₂)
open import Data.Vec using (Vec; lookup)
open import Relation.Nullary using (yes; no)
open import Relation.Binary.PropositionalEquality using (_≡_)

open import Circuit.Semantics using (⟦_⟧)
open import Locking.NetlistToCircuit using (Netlist; Gate; gate; []; _∷_; evalG; busEval)
open Gate
open import Extraction.LUTGadget using (lutCircuit; lutFun; lutCircuit-correct)
open import Extraction.LUTNetParse using (FGate)
open import Extraction.BenchRoundTrip using (_>>=_)

------------------------------------------------------------------------
--  Section 1: define netlist assembly.

NLΣ : ℕ → Set
NLΣ n = Σ[ G ∈ ℕ ] Netlist n G

--  Append a flat gate to the current netlist when its references are in range.
addGate : ∀ {n} → FGate → NLΣ n → Maybe (NLΣ n)
addGate {n} (a , b , code) (G , nl) with a <? (G + n) | b <? (G + n) | code <? 14
... | yes pa | yes pb | yes pc =
      just (suc G , gate (fromℕ< pa) (fromℕ< pb) (lutCircuit (fromℕ< pc)) ∷ nl)
... | _      | _      | _      = nothing

buildFrom : ∀ {n} → List FGate → NLΣ n → Maybe (NLΣ n)
buildFrom []       acc = just acc
buildFrom (g ∷ gs) acc = addGate g acc >>= λ acc′ → buildFrom gs acc′

--  Assemble the flat list oldest-first into Netlist n G; a successful just
--  result carries scope correctness in its dependent type.
fromFlat : (n : ℕ) → List FGate → Maybe (NLΣ n)
fromFlat n gs = buildFrom gs (0 , [])

------------------------------------------------------------------------
--  Section 2: use the phase-1 gadget proof to show that each assembled gate
--  computes the LUT function specified by its code.

addGate-correct : ∀ {n G} (a b code : ℕ)
  (pa : a < G + n) (pb : b < G + n) (pc : code < 14) (bus : Vec Bool (G + n)) →
  lookup (evalG (gate (fromℕ< pa) (fromℕ< pb) (lutCircuit (fromℕ< pc))) bus) zero
    ≡ lutFun (fromℕ< pc) (lookup bus (fromℕ< pa)) (lookup bus (fromℕ< pb))
addGate-correct a b code pa pb pc bus =
  lutCircuit-correct (fromℕ< pc) (lookup bus (fromℕ< pa)) (lookup bus (fromℕ< pb))

------------------------------------------------------------------------
--  Section 3: expose the verified pipeline through thin functions for a MAlonzo CLI.

--  Return the gate count after a well-scoped import with every code decoded,
--  or none on failure.
importGateCount : (n : ℕ) → List FGate → Maybe ℕ
importGateCount n gs with fromFlat n gs
... | just (G , _) = just G
... | nothing      = nothing

--  Evaluate the imported cone at bus position 0, the newest gate. Return
--  nothing if importing fails or the netlist contains no gates.
importConeBit : (n : ℕ) → List FGate → Vec Bool n → Maybe Bool
importConeBit n gs x with fromFlat n gs
... | just (suc G , nl) = just (lookup (busEval nl x) zero)
... | _                 = nothing
