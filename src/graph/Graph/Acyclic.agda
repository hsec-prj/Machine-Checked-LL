------------------------------------------------------------------------
--  Unique fixed points for acyclic netlists (graph track G2)
--  Graph.Core defines arbitrary netlists by step; Graph.Stable shows
--  that a cyclic self-loop may have no stable state or multiple states.
--  In the acyclic case, prove existence and uniqueness, the well-defined
--  behavior that an incorrect cyclic-lock key destroys.
--  Avoid Fin-index manipulations by presenting acyclicity structurally:
--  ANetlist (suc W) has a head gate over the W earlier tail wires, with
--  the tail recursively acyclic. Neither self-reference nor later-node
--  reference is allowed, excluding Graph.Stable.selfLoop. A topological
--  sort puts any DAG into this form.
--  astep synchronously recomputes nodes from the current valuation;
--  asolve uses forward substitution. asolve-stable proves its stability,
--  and astable-unique identifies every fixed point with it. Together
--  acyclic-unique-fixpoint packages existence and uniqueness without
--  postulates. G2b subsequently embeds ANetlist W into Graph.Core.Netlist W
--  by shifting wire references and identifies astep with step.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Graph.Acyclic where

open import Data.Nat using (ℕ; suc)
open import Data.Bool using (Bool)
open import Data.Vec using (Vec; []; _∷_; head; tail)
open import Data.Product using (Σ; _×_; _,_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

open import Graph.Core using (Gate; evalGate)

private
  variable
    W : ℕ

------------------------------------------------------------------------
--  Present an acyclic netlist topologically: its head gate reads only
--  the W earlier wires in the tail.

data ANetlist : ℕ → Set where
  []  : ANetlist 0
  _∷_ : Gate W → ANetlist W → ANetlist (suc W)

--  Synchronously update each node from the current tail valuation,
--  recursing through the topological presentation.
astep : ANetlist W → Vec Bool W → Vec Bool W
astep []       []       = []
astep (g ∷ ns) (b ∷ vs) = evalGate vs g ∷ astep ns vs

--  Forward-substitute the unique solution by evaluating each gate on
--  the already-solved earlier wires.
asolve : ANetlist W → Vec Bool W
asolve []       = []
asolve (g ∷ ns) = evalGate (asolve ns) g ∷ asolve ns

--  Call a valuation stable when one update preserves it.
AStable : ANetlist W → Vec Bool W → Set
AStable ns v = astep ns v ≡ v

------------------------------------------------------------------------
--  Prove stability of the forward-substituted valuation.

asolve-stable : (ns : ANetlist W) → AStable ns (asolve ns)
asolve-stable []       = refl
asolve-stable (g ∷ ns) = cong (evalGate (asolve ns) g ∷_) (asolve-stable ns)

------------------------------------------------------------------------
--  Prove that any stable valuation equals the forward-substituted one.

astable-unique : (ns : ANetlist W) (v : Vec Bool W) →
                 AStable ns v → v ≡ asolve ns
astable-unique []       []       eq = refl
astable-unique (g ∷ ns) (b ∷ vs) eq =
  cong₂ _∷_ (trans (sym (cong head eq)) (cong (λ w → evalGate w g) rec)) rec
  where
    rec : vs ≡ asolve ns
    rec = astable-unique ns vs (cong tail eq)

------------------------------------------------------------------------
--  Combine existence and uniqueness for acyclic netlists, establishing
--  the well-definedness lost under a cyclic wrong key.

acyclic-unique-fixpoint :
  (ns : ANetlist W) →
  Σ (Vec Bool W) (λ v → AStable ns v × ((u : Vec Bool W) → AStable ns u → u ≡ v))
acyclic-unique-fixpoint ns =
  asolve ns , asolve-stable ns , (λ u su → astable-unique ns u su)
