------------------------------------------------------------------------
--  Conditional recovery for the emitted integer-distance oracle.
--  distOracleEmit-≡ identifies that oracle with distNode. Transporting
--  recoverBitPoly along this equality proves recoverKeyVis-emitted for
--  a supplied visibility predicate vis, assuming vis x and vis (flipAt i x)
--  for every i. These are sufficient premises for this recovery function.
--  No construction here obtains integer distances or vis from actual
--  primary outputs. Boolean host-slice observability alone does not
--  establish that access, nor universal attack success or failure.
--  recoverBitVis-masked returns the function's default false; it is not
--  an impossibility theorem for other recovery methods (Appendix A.4.4; docs/RESULTS.md#formal-model-and-observations).
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.FALLEmittedObs where

open import Data.Nat using (ℕ; suc; _≡ᵇ_)
open import Data.Bool using (Bool; true; false; not; _∧_; if_then_else_)
open import Data.Fin using (Fin)
open import Data.Vec using (Vec; lookup; tabulate)
open import Data.Vec.Properties using (tabulate-cong)
open import Relation.Binary.PropositionalEquality using (_≡_; trans; cong; cong₂)

open import Attack.FunctionalAnalysis using (distNode)
open import Attack.FALLPoly using (flipAt; recoverBitPoly)
open import Attack.FALLEmitted using (distOracleEmit; distOracleEmit-≡)
open import Attack.FALLObservability using (recoverBitVis; recoverKeyVis; recoverKeyVis-correct)

private
  variable
    n : ℕ

--  Because recoverBitPoly queries distances only at x and flipAt i x, the
--  emitted oracle and abstract distance node recover the same bit.
recoverBitPoly-emit-≡ : (k x : Vec Bool n) (i : Fin n) →
  recoverBitPoly (distOracleEmit k) x i ≡ recoverBitPoly (distNode k) x i
recoverBitPoly-emit-≡ k x i =
  cong₂ (λ a b → if (a ≡ᵇ suc b) then lookup x i else not (lookup x i))
        (distOracleEmit-≡ k (flipAt i x)) (distOracleEmit-≡ k x)

recoverBitVis-emit-≡ : (vis : Vec Bool n → Bool) (k x : Vec Bool n) (i : Fin n) →
  recoverBitVis vis (distOracleEmit k) x i ≡ recoverBitVis vis (distNode k) x i
recoverBitVis-emit-≡ vis k x i =
  cong (λ r → if (vis x ∧ vis (flipAt i x)) then r else false)
       (recoverBitPoly-emit-≡ k x i)

recoverKeyVis-emit-≡ : (vis : Vec Bool n → Bool) (k x : Vec Bool n) →
  recoverKeyVis vis (distOracleEmit k) x ≡ recoverKeyVis vis (distNode k) x
recoverKeyVis-emit-≡ vis k x = tabulate-cong (recoverBitVis-emit-≡ vis k x)

--  Supplied integer-distance access plus both visibility premises suffice
--  for this function to recover the key; actual PO access is not established.
recoverKeyVis-emitted :
  (vis : Vec Bool n → Bool) (k x : Vec Bool n) →
  vis x ≡ true → ((i : Fin n) → vis (flipAt i x) ≡ true) →
  recoverKeyVis vis (distOracleEmit k) x ≡ k
recoverKeyVis-emitted vis k x vx vfx =
  trans (recoverKeyVis-emit-≡ vis k x) (recoverKeyVis-correct vis k x vx vfx)
