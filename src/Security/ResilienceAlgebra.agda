------------------------------------------------------------------------
--  Transport corruption weights through the SchemeAlgebra operations.
--  removalWeight≡ocr identifies the uniform-input numerator with OCR.
--  Sequential _⊚_ is symmetric difference: removal-⊚-≤ is subadditive,
--  and removal-⊚-disjoint is additive under disjointness. Parallel _⊗_
--  uses the conjunction/product law. removal-⊚-compose transports the
--  two supplied weight bounds to their sum. Names such as removable
--  refer only to those bounds; the algebra supplies no adversary or
--  attack-success guarantee. Small composite weight need not imply small
--  component weights, and the sum bound is not a monotonicity law.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.ResilienceAlgebra where

open import Data.Nat using (ℕ; _+_; _*_; _≤_)
open import Data.Nat.Properties using (≤-trans; ≤-reflexive; +-mono-≤)
open import Data.Bool using (Bool; true; false; _∧_)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong₂; subst)

open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (allVecs; binom)
open import Security.OCR using (OCR; OCR-odd)
open import Security.SARLock using (OCR-SARLock-≤2)
open import Security.Dist using (prob; unifInputs; prob-uniform)
open import Security.SchemeAlgebra
  using (Scheme; corruption; ocr; _⊚_; _⊗_;
         ocr-⊚-≤; ocr-⊚-disjoint; ocr-⊗; sfllScheme; sarScheme)

private
  variable
    n p d : ℕ

------------------------------------------------------------------------
--  Identify removal weight with the uniform-input corruption numerator and
--  hence the scheme's OCR.

removalWeight : Scheme n → ℕ
removalWeight {n} s = prob (corruption s) (unifInputs n)

removalWeight≡ocr : (s : Scheme n) → removalWeight s ≡ ocr s
removalWeight≡ocr {n} s = prob-uniform (corruption s) (allVecs n)

------------------------------------------------------------------------
--  Transport OCR composition identities to removal advantage.

--  Bound sequential stacking subadditively.
removal-⊚-≤ : (s t : Scheme n) →
              removalWeight (s ⊚ t) ≤ removalWeight s + removalWeight t
removal-⊚-≤ s t =
  ≤-trans (≤-reflexive (removalWeight≡ocr (s ⊚ t)))
  (≤-trans (ocr-⊚-≤ s t)
           (≤-reflexive (cong₂ _+_ (sym (removalWeight≡ocr s))
                                    (sym (removalWeight≡ocr t)))))

--  Obtain exact additivity for layers with disjoint corrupted inputs.
removal-⊚-disjoint : (s t : Scheme n) →
                     (∀ x → (corruption s x ∧ corruption t x) ≡ false) →
                     removalWeight (s ⊚ t) ≡ removalWeight s + removalWeight t
removal-⊚-disjoint s t dis =
  trans (removalWeight≡ocr (s ⊚ t))
        (trans (ocr-⊚-disjoint s t dis)
               (cong₂ _+_ (sym (removalWeight≡ocr s)) (sym (removalWeight≡ocr t))))

--  Use the Fubini homomorphism for multiplicative parallel advantage.
removal-⊗ : (s : Scheme p) (t : Scheme d) →
            removalWeight (s ⊗ t) ≡ removalWeight s * removalWeight t
removal-⊗ s t =
  trans (removalWeight≡ocr (s ⊗ t))
        (trans (ocr-⊗ s t)
               (cong₂ _*_ (sym (removalWeight≡ocr s)) (sym (removalWeight≡ocr t))))

------------------------------------------------------------------------
--  Removable means corruption weight at most ε. The composition lemma
--  adds two supplied upper bounds; actual weight may be smaller.

SchemeRemovable : Scheme n → ℕ → Set
SchemeRemovable s ε = removalWeight s ≤ ε

--  Combine ε₁- and ε₂-removability into (ε₁+ε₂)-removability of the stack.
removal-⊚-compose : (s t : Scheme n) {ε₁ ε₂ : ℕ} →
                    SchemeRemovable s ε₁ → SchemeRemovable t ε₂ →
                    SchemeRemovable (s ⊚ t) (ε₁ + ε₂)
removal-⊚-compose s t w₁ w₂ = ≤-trans (removal-⊚-≤ s t) (+-mono-≤ w₁ w₂)

------------------------------------------------------------------------
--  Instantiate the algebra for catalogue schemes.

--  For every n, one SARLock layer is 2-removable.
SARLock-removal-≤2 : (ksec kapp : Vec Bool n) →
                     SchemeRemovable (sarScheme ksec kapp) 2
SARLock-removal-≤2 ksec kapp =
  subst (_≤ 2) (sym (removalWeight≡ocr (sarScheme ksec kapp)))
        (OCR-SARLock-≤2 ksec kapp)

--  Two SARLock layers have corruption weight at most four by
--  ocr²-SARLock-≤4; this is a weight bound, not a security conclusion.
stack-SARLock-removal-≤4 : (k₁ k₂ k₃ k₄ : Vec Bool n) →
                           SchemeRemovable (sarScheme k₁ k₂ ⊚ sarScheme k₃ k₄) 4
stack-SARLock-removal-≤4 k₁ k₂ k₃ k₄ =
  removal-⊚-compose (sarScheme k₁ k₂) (sarScheme k₃ k₄)
                    (SARLock-removal-≤2 k₁ k₂) (SARLock-removal-≤2 k₃ k₄)

--  At odd key distance, an SFLL-HD layer is exactly 2·C(n,h)-removable.
SFLL-removal-odd : (h : ℕ) (ksec kapp : Vec Bool n) →
                   parity (HD ksec kapp) ≡ true →
                   removalWeight (sfllScheme h ksec kapp) ≡ binom n h + binom n h
SFLL-removal-odd h ksec kapp odd =
  trans (removalWeight≡ocr (sfllScheme h ksec kapp)) (OCR-odd h ksec kapp odd)
