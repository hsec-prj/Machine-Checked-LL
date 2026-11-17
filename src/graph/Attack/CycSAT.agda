------------------------------------------------------------------------
--  Formalise the CycSAT obstruction (graph track, G4). SAT and its cyclic-aware
--  variant CycSAT constrain candidate keys by treating the corresponding
--  locked netlist as combinational, requiring a well-defined output and thus
--  a stable wire valuation as in Graph.Stable. At a wrong key, G3's inserted
--  feedback wire oscillates, so Locking.Cyclic excludes stability and leaves
--  no combinational model to analyse. Make this prerequisite explicit as
--  SATModel k = existence of a stable valuation, then establish
--  SATModel k out base ⟺ k ≡ false. good-model supplies the correct-key
--  model; good-model-unique makes it unique, with the feedback wire holding
--  the recovered base output. cycSAT-obstruction excludes models at every
--  wrong key. This exact correct-key characterisation expresses the SAT
--  resistance of cyclic locking by directly reusing G3, without postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSAT where

open import Data.Nat using (ℕ; suc)
open import Data.Bool using (Bool; true; false)
open import Data.Vec using (Vec; _∷_)
open import Data.Product using (∃; _,_)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Relation.Nullary using (¬_)

open import Graph.Core using (Gate; evalGate)
open import Graph.Acyclic using (ANetlist; asolve)
open import Locking.Cyclic
  using (LStable; lock-correct-stable; lock-correct-unique; lock-wrong-no-stable)

private
  variable
    W : ℕ

------------------------------------------------------------------------
--  Express the SAT precondition: at key k the lock has a stable valuation,
--  providing a well-defined combinational model for constraints.

SATModel : Bool → Gate W → ANetlist W → Set
SATModel k out base = ∃ (LStable k out base)

------------------------------------------------------------------------
--  Supply the correct-key model, whose uniquely stable feedback wire holds
--  the recovered base output.

good-model : (out : Gate W) (base : ANetlist W) → SATModel false out base
good-model out base =
  evalGate (asolve base) out ∷ asolve base , lock-correct-stable out base

good-model-unique : (out : Gate W) (base : ANetlist W) (v : Vec Bool (suc W)) →
                    LStable false out base v →
                    v ≡ (evalGate (asolve base) out ∷ asolve base)
good-model-unique = lock-correct-unique

------------------------------------------------------------------------
--  Exclude every wrong-key model through oscillation of its feedback wire.

cycSAT-obstruction : (out : Gate W) (base : ANetlist W) →
                     ¬ SATModel true out base
cycSAT-obstruction = lock-wrong-no-stable

------------------------------------------------------------------------
--  Characterise model existence exactly by correctness of the key. good-model
--  gives the reverse implication, and the forward implication follows below.

model→good : (k : Bool) (out : Gate W) (base : ANetlist W) →
             SATModel k out base → k ≡ false
model→good false out base _   = refl
model→good true  out base sat = ⊥-elim (cycSAT-obstruction out base sat)
