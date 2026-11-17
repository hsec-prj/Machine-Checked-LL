------------------------------------------------------------------------
--  Gate distance-oracle recovery by a supplied visibility predicate.
--  FALLPoly compares integer distances at a reference and its bit flips.
--  recoverKeyVis-correct proves recovery when vis is true at the reference
--  and every flip. This is a sufficient condition for the defined routine,
--  conditional on access to distNode's integer values. The module neither
--  extracts those values from Boolean primary outputs nor constructs vis
--  for an arbitrary host. Boolean derivative counts in POCorruption are
--  a separate host-slice model. recoverBitVis-masked describes the routine's
--  default false result; it proves no general attack impossibility.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.FALLObservability where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; true; false; _∧_; if_then_else_)
open import Data.Bool.Properties using (∧-zeroʳ)
open import Data.Fin using (Fin)
open import Data.Vec using (Vec; lookup; tabulate)
open import Data.Vec.Properties using (tabulate-cong; tabulate∘lookup)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; trans; cong; cong₂)

open import Attack.FunctionalAnalysis using (distNode)
open import Attack.FALLPoly using (flipAt; recoverBitPoly; recoverBitPoly-correct)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  vis is a supplied gate on the integer-distance comparisons, not a proof
--  of primary-output access. Compare only when both points are visible;
--  otherwise return the default false (which may equal a secret bit).

recoverBitVis : (vis : Vec Bool n → Bool) (dist : Vec Bool n → ℕ)
                (x : Vec Bool n) (i : Fin n) → Bool
recoverBitVis vis dist x i =
  if (vis x ∧ vis (flipAt i x)) then recoverBitPoly dist x i else false

------------------------------------------------------------------------
--  If both points are visible, masked recovery reduces to recoverBitPoly
--  and returns the exact key bit.

recoverBitVis-correct :
  (vis : Vec Bool n → Bool) (k x : Vec Bool n) (i : Fin n) →
  vis x ≡ true → vis (flipAt i x) ≡ true →
  recoverBitVis vis (distNode k) x i ≡ lookup k i
recoverBitVis-correct vis k x i vx vfx =
  trans (cong (λ c → if c then recoverBitPoly (distNode k) x i else false)
              (cong₂ _∧_ vx vfx))
        (recoverBitPoly-correct k x i)

------------------------------------------------------------------------
--  An invisible flip makes this routine return its default independently
--  of kᵢ; no claim about other procedures follows.

recoverBitVis-masked :
  (vis : Vec Bool n → Bool) (dist : Vec Bool n → ℕ)
  (x : Vec Bool n) (i : Fin n) →
  vis (flipAt i x) ≡ false →
  recoverBitVis vis dist x i ≡ false
recoverBitVis-masked vis dist x i vfx =
  cong (λ c → if c then recoverBitPoly dist x i else false)
       (trans (cong (vis x ∧_) vfx) (∧-zeroʳ (vis x)))

------------------------------------------------------------------------
--  Derive recovery under the supplied distance and visibility premises.

recoverKeyVis : (vis : Vec Bool n → Bool) (dist : Vec Bool n → ℕ)
                (x : Vec Bool n) → Vec Bool n
recoverKeyVis {n} vis dist x = tabulate (recoverBitVis vis dist x)

--  Visibility of the reference and every flip is sufficient for this
--  distance-oracle routine; it is not asserted to be necessary.
recoverKeyVis-correct :
  (vis : Vec Bool n → Bool) (k x : Vec Bool n) →
  vis x ≡ true → ((i : Fin n) → vis (flipAt i x) ≡ true) →
  recoverKeyVis vis (distNode k) x ≡ k
recoverKeyVis-correct vis k x vx vfx =
  trans (tabulate-cong (λ i → recoverBitVis-correct vis k x i vx (vfx i)))
        (tabulate∘lookup k)
