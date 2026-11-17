------------------------------------------------------------------------
--  Instantiate vector-oracle recovery on a concrete multi-output lock
--  (D8-II frontier 3). MultiPointDIP.multiDIP-recovers uses 2ⁿ queries for
--  any distinguishing vector oracle, independently of output width m. Apply
--  it to SFLL.EfficientLockMulti.lockedVec j at radius zero: output j is
--  protected and lockedVec-pass preserves the other k−1 outputs. The same
--  2ⁿ fold recovers its key, proving the earlier prose observation that
--  protecting one output reduces to single-output recovery. Distinguish
--  query cost from output distortion. multiDIP-queries is 2ⁿ for every
--  width k, while Security.MultiOCR.mocr-setK-bound ≤ Σᵢ OCRᵢ scales with
--  per-output corruption. These metrics concern different data: recovery
--  depends on distinguishability, not combined mocr. Additional outputs
--  supply more bits per query without reducing this 2ⁿ query count; this
--  instance is single-output point recovery. Reuse lockedVec, lockedVec-prot,
--  prot0-self, prot0-false, and locked. Only two small Boolean facts and
--  the Distinguishing proof are new; no postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.MultiPointDIPInstance where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; true; false; not; _xor_)
open import Data.Vec using (Vec; lookup)
open import Data.Fin using (Fin)
open import Data.Product using (_×_; _,_; ∃)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; trans; sym; cong; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HD using (prot; locked)
open import SFLL.EfficientLockMulti using (lockedVec; lockedVec-prot)
open import Security.AntiSat using (prot0-false)
open import Attack.PointDIPAttack using (prot0-self)
open import Util.Counting using (allVecs)
open import Attack.MultiPointDIP using (Distinguishing; survivesV; multiDIP-recovers)

private
  variable
    n k : ℕ

------------------------------------------------------------------------
--  Supporting elementary Boolean identities.

b≢not-b : (b : Bool) → not b ≢ b
b≢not-b true  ()
b≢not-b false ()

--  At the secret input with a different applied key, (b xor true) xor false ≡ not b.
xorTF : (b : Bool) → (b xor true) xor false ≡ not b
xorTF true  = refl
xorTF false = refl

--  At the secret input with the correct applied key, (b xor true) xor true ≡ b.
xorTT : (b : Bool) → (b xor true) xor true ≡ b
xorTT true  = refl
xorTT false = refl

------------------------------------------------------------------------
--  Define the h=0 lockedVec j oracle on applied key kapp and input x, with
--  k output bits and key dependence only at slot j.

omLockJ : (F : Vec Bool n → Vec Bool k) (j : Fin k) (ksec : Vec Bool n) →
          Vec Bool n → Vec Bool n → Vec Bool k
omLockJ F j ksec kapp x = lockedVec j 0 ksec kapp F x

--  Establish Distinguishing: at input ksec, a wrong applied key changes
--  slot j, the only key-dependent output.
omLockJ-distinguishing :
  (F : Vec Bool n → Vec Bool k) (j : Fin k) (ksec : Vec Bool n) →
  Distinguishing (omLockJ F j ksec) ksec
omLockJ-distinguishing F j ksec kapp kapp≢ksec = ksec , vneq
  where
    gj : Bool
    gj = lookup (F ksec) j

    --  For kapp ≠ ksec, point cancellation leaves not gj at output j.
    lhs : lookup (omLockJ F j ksec kapp ksec) j ≡ not gj
    lhs = trans (lockedVec-prot j 0 ksec kapp F ksec) eval
      where
        eval : locked 0 ksec kapp (λ y → lookup (F y) j) ksec ≡ not gj
        eval rewrite prot0-self ksec
                   | prot0-false ksec kapp (λ e → kapp≢ksec (sym e)) = xorTF gj

    --  For kapp = ksec, output j is gj.
    rhs : lookup (omLockJ F j ksec ksec ksec) j ≡ gj
    rhs = trans (lockedVec-prot j 0 ksec ksec F ksec) eval′
      where
        eval′ : locked 0 ksec ksec (λ y → lookup (F y) j) ksec ≡ gj
        eval′ rewrite prot0-self ksec = xorTT gj

    vneq : omLockJ F j ksec kapp ksec ≢ omLockJ F j ksec ksec ksec
    vneq eq = b≢not-b gj (trans (sym lhs) (trans (cong (λ v → lookup v j) eq) rhs))

--  Use multiDIP-recovers to recover this lock in 2ⁿ queries regardless of
--  output width k. Recovery is the single-output point problem; the
--  k-dependent mocr-setK corruption metric is a separate axis and adds no
--  recovery hardness here.
omLockJ-recovers :
  (F : Vec Bool n → Vec Bool k) (j : Fin k) (ksec : Vec Bool n) (k* : Vec Bool n) →
  (k* ≡ ksec → survivesV (omLockJ F j ksec) ksec (allVecs n) k* ≡ true)
  × (k* ≢ ksec → survivesV (omLockJ F j ksec) ksec (allVecs n) k* ≡ false)
omLockJ-recovers F j ksec =
  multiDIP-recovers (omLockJ F j ksec) ksec (omLockJ-distinguishing F j ksec)
