------------------------------------------------------------------------
--  Import parametric netlists into verified circuits (item 2).
--  CompileISCAS handled c17 using a hand-built circuit and refl. Repeating
--  that pattern for each cone risks fragile Fin/Vec literal elaboration.
--  Instead define scoped two-input netlists and translate generically with
--  netlistToCircuit, proving once that
--  nl-correct : ⟦ netlistToCircuit nl ⟧ x ≡ busEval nl x.
--  Each gate includes its own Circuit 2 1 gadget, avoiding a universal LUT
--  realiser. Plug moves two fan-ins to the bus front, and Par g Id applies
--  the gadget while retaining the bus. Its width G+n puts gates first;
--  prepending each new output makes width equations definitional, requiring
--  no casts. Import any benchmark cone by supplying Netlist data alone.
--  nl-correct provides cf-ok independently of per-cone normalisation or
--  refl, supporting arbitrary sizes.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.NetlistToCircuit where

open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Bool using (Bool)
open import Data.Fin using (Fin) renaming (zero to fz)
open import Data.Vec using (Vec; []; _∷_; _++_; lookup; map; tabulate; allFin)
open import Data.Vec.Properties
  using (lookup-map; tabulate-cong; tabulate∘lookup; map-lookup-allFin)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

open import Circuit.Core using (Circuit; Id; Seq; Par; Plug)
open import Circuit.Semantics using (⟦_⟧)

private
  variable
    n G w : ℕ

------------------------------------------------------------------------
--  Represent a two-input gate on width w by its two wire indices and gadget.

record Gate (w : ℕ) : Set where
  constructor gate
  field
    a b : Fin w
    g   : Circuit 2 1
open Gate

--  Scope G gates over n inputs with the newest gate first. Its fan-ins
--  refer only to the older bus of width G+n.
data Netlist (n : ℕ) : ℕ → Set where
  []  : Netlist n 0
  _∷_ : Gate (G + n) → Netlist n G → Netlist n (suc G)

------------------------------------------------------------------------
--  Evaluate the complete bus, prepending gate output so widths reduce
--  to suc (G+n).

evalG : Gate w → Vec Bool w → Vec Bool 1
evalG gt bus = ⟦ g gt ⟧ (lookup bus (a gt) ∷ lookup bus (b gt) ∷ [])

busEval : Netlist n G → Vec Bool n → Vec Bool (G + n)
busEval []        x = x
busEval (gt ∷ nl) x = evalG gt (busEval nl x) ++ busEval nl x

------------------------------------------------------------------------
--  Translate each gate into a layer prepending its output. Plug places its
--  fan-ins before the retained bus; Par g Id consumes those first two wires
--  and keeps the rest. The 2+w and suc w indices align definitionally,
--  avoiding width casts.

consGate : Gate w → Circuit w (suc w)
consGate {w} gt =
  Seq (Plug (lookup (a gt ∷ b gt ∷ allFin w))) (Par (g gt) (Id {w}))

netlistToCircuit : Netlist n G → Circuit n (G + n)
netlistToCircuit []        = Id
netlistToCircuit (gt ∷ nl) = Seq (netlistToCircuit nl) (consGate gt)

------------------------------------------------------------------------
--  Prove correctness through the routing lemma that places fan-ins before
--  the retained bus.

--  Expose ⟦ Plug (lookup v) ⟧ bus = map (lookup bus) v, the tabulated
--  lookup route, for reuse by multi-output projection and EfficientLockMulti.
tab-map : ∀ {m} (f : Fin w → Bool) (v : Vec (Fin w) m) →
          tabulate (λ i → f (lookup v i)) ≡ map f v
tab-map f v = trans (tabulate-cong (λ i → sym (lookup-map i f v)))
                    (tabulate∘lookup (map f v))

private
  plug-route : (gt : Gate w) (bus : Vec Bool w) →
               ⟦ Plug (lookup (a gt ∷ b gt ∷ allFin w)) ⟧ bus
               ≡ lookup bus (a gt) ∷ lookup bus (b gt) ∷ bus
  plug-route {w} gt bus =
    trans (tab-map (lookup bus) (a gt ∷ b gt ∷ allFin w))
          (cong (λ z → lookup bus (a gt) ∷ lookup bus (b gt) ∷ z)
                (map-lookup-allFin bus))

  --  One layer prepends the gate result. After routing, Par g Id reduces
  --  through take/drop on the two-cons bus, leaving only the routing lemma.
  consGate-correct : (gt : Gate w) (bus : Vec Bool w) →
                     ⟦ consGate gt ⟧ bus ≡ evalG gt bus ++ bus
  consGate-correct {w} gt bus =
    cong ⟦ Par (g gt) (Id {w}) ⟧ (plug-route gt bus)

--  Establish that the imported circuit denotes the reference bus evaluator.
nl-correct : (nl : Netlist n G) (x : Vec Bool n) →
             ⟦ netlistToCircuit nl ⟧ x ≡ busEval nl x
nl-correct []        x = refl
nl-correct (gt ∷ nl) x =
  trans (cong ⟦ consGate gt ⟧ (nl-correct nl x))
        (consGate-correct gt (busEval nl x))

------------------------------------------------------------------------
--  For certified single-output compilation, select bus position zero, the
--  newest gate. Derive the host circuit, function, and denotation proof from
--  nl-correct, so importing a real cone requires only Netlist data.

importCone : Netlist n (suc G) → Circuit n 1
importCone nl = Seq (netlistToCircuit nl) (Plug (λ _ → fz))

importConeF : Netlist n (suc G) → Vec Bool n → Bool
importConeF nl x = lookup (busEval nl x) fz

import-correct : (nl : Netlist n (suc G)) (x : Vec Bool n) →
                 ⟦ importCone nl ⟧ x ≡ importConeF nl x ∷ []
import-correct nl x = cong ⟦ Plug (λ _ → fz) ⟧ (nl-correct nl x)

------------------------------------------------------------------------
--  For multiple outputs, importMulti projects k possibly shared bus
--  positions outs into one k-output circuit. import-multi-correct follows
--  from nl-correct and one tab-map step, requiring no per-output proof.
--  The full benchmark remains a shared-bus object; importCone specialises
--  outs to fz ∷ [].

importMulti : Netlist n G → ∀ {k} → Vec (Fin (G + n)) k → Circuit n k
importMulti nl outs = Seq (netlistToCircuit nl) (Plug (lookup outs))

importMultiF : Netlist n G → ∀ {k} → Vec (Fin (G + n)) k → Vec Bool n → Vec Bool k
importMultiF nl outs x = map (lookup (busEval nl x)) outs

import-multi-correct : (nl : Netlist n G) {k : ℕ} (outs : Vec (Fin (G + n)) k)
                       (x : Vec Bool n) →
                       ⟦ importMulti nl outs ⟧ x ≡ importMultiF nl outs x
import-multi-correct nl outs x =
  trans (cong ⟦ Plug (lookup outs) ⟧ (nl-correct nl x))
        (tab-map (lookup (busEval nl x)) outs)
