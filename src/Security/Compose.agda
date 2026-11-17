------------------------------------------------------------------------
--  Analyse output corruption of stacked locking layers (catalogue extension 3).
--  Security.OCR and Security.SARLock treat one layer; here compose two
--  transforms on the same host: locked² = locked h₂ ks₂ kap₂ ∘
--  locked h₁ ks₁ kap₁. compose-disagree cancels the host and inner terms
--  by XOR algebra, identifying disagreement with f as corrupt₁ ⊕ corrupt₂.
--  Existing countT-and-xor, countT-xor-≤, and countT-xor-disjoint then give
--  ocr²-≤-sum: OCR(comp) ≤ OCR₁+OCR₂; ocr²-incl-excl:
--  OCR(comp)+2·|overlap| = OCR₁+OCR₂; and ocr²-disjoint's additivity on
--  disjoint corruption sets. No new counting argument is needed. In
--  particular ocr²-SARLock-≤4 bounds two SARLock layers by four corrupted
--  inputs for every n. Stacking therefore remains in the constant,
--  low-corruption regime identified as approximately recoverable by
--  Attack.AppSAT. Reuse the OCR catalogue and counting core without new
--  primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.Compose where

open import Data.Nat using (ℕ; _+_; _*_; _≤_)
open import Data.Nat.Properties using (≤-trans; +-mono-≤)
open import Data.Bool using (Bool; true; false; _xor_; _∧_)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst)

open import SFLL.HD using (prot; locked)
open import Security.OCR using (corrupt; OCR)
open import Security.SARLock using (OCR-SARLock-≤2)
open import Util.Counting
  using (countT; allVecs; countT-cong; countT-xor-≤; countT-and-xor;
         countT-xor-disjoint)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Prove elementary XOR identities by case analysis.

--  XOR a lock with the function it protects to cancel that function and
--  leave its corruption predicate. This extends Attack.AppSAT's xor-mix
--  to an inner function that may itself already be locked.
xor-mix : (a b c : Bool) → ((a xor b) xor c) xor a ≡ b xor c
xor-mix true  true  true  = refl
xor-mix true  true  false = refl
xor-mix true  false true  = refl
xor-mix true  false false = refl
xor-mix false true  true  = refl
xor-mix false true  false = refl
xor-mix false false true  = refl
xor-mix false false false = refl

--  Insert a cancelling midpoint: X ⊕ Z = (X ⊕ Y) ⊕ (Y ⊕ Z).
xor-bridge : (X Y Z : Bool) → X xor Z ≡ (X xor Y) xor (Y xor Z)
xor-bridge true  true  true  = refl
xor-bridge true  true  false = refl
xor-bridge true  false true  = refl
xor-bridge true  false false = refl
xor-bridge false true  true  = refl
xor-bridge false true  false = refl
xor-bridge false false true  = refl
xor-bridge false false false = refl

xor-comm : (a b : Bool) → a xor b ≡ b xor a
xor-comm true  true  = refl
xor-comm true  false = refl
xor-comm false true  = refl
xor-comm false false = refl

------------------------------------------------------------------------
--  Define two-layer SFLL composition and its disagreement with f.

--  Apply the ks₁/kap₁ lock first, followed by the ks₂/kap₂ lock.
locked² : (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) →
          Vec Bool n → Bool
locked² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f =
  locked h₂ ks₂ kap₂ (locked h₁ ks₁ kap₁ f)

--  XOR of one layer with its underlying function is that layer's corruption.
locked-xor-self : (h : ℕ) (ksec kapp : Vec Bool n) (g : Vec Bool n → Bool)
                  (x : Vec Bool n) →
                  locked h ksec kapp g x xor g x ≡ corrupt h ksec kapp x
locked-xor-self h ksec kapp g x =
  xor-mix (g x) (prot h ksec x) (prot h kapp x)

--  The cascade differs from f precisely where the two corruption predicates
--  have different values.
compose-disagree :
  (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool)
  (x : Vec Bool n) →
  locked² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f x xor f x
  ≡ corrupt h₁ ks₁ kap₁ x xor corrupt h₂ ks₂ kap₂ x
compose-disagree h₁ h₂ ks₁ kap₁ ks₂ kap₂ f x =
  trans (xor-bridge (locked² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f x) (g x) (f x))
        (trans (cong₂ _xor_ (locked-xor-self h₂ ks₂ kap₂ g x)
                            (locked-xor-self h₁ ks₁ kap₁ f x))
               (xor-comm (corrupt h₂ ks₂ kap₂ x) (corrupt h₁ ks₁ kap₁ x)))
  where g = locked h₁ ks₁ kap₁ f

------------------------------------------------------------------------
--  Define composite OCR and derive its bounds.

--  Count inputs where the cascade disagrees with f.
ocr² : (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) → ℕ
ocr² {n = n} h₁ h₂ ks₁ kap₁ ks₂ kap₂ f =
  countT (λ x → locked² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f x xor f x) (allVecs n)

--  Equate that disagreement count with the composite corruption count.
ocr²≡ : (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) →
        ocr² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f
        ≡ countT (λ x → corrupt h₁ ks₁ kap₁ x xor corrupt h₂ ks₂ kap₂ x) (allVecs n)
ocr²≡ {n = n} h₁ h₂ ks₁ kap₁ ks₂ kap₂ f =
  countT-cong (compose-disagree h₁ h₂ ks₁ kap₁ ks₂ kap₂ f) (allVecs n)

--  Bound stacked corruption by the sum of the layer counts.
ocr²-≤-sum :
  (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) →
  ocr² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f ≤ OCR h₁ ks₁ kap₁ + OCR h₂ ks₂ kap₂
ocr²-≤-sum {n = n} h₁ h₂ ks₁ kap₁ ks₂ kap₂ f =
  subst (_≤ OCR h₁ ks₁ kap₁ + OCR h₂ ks₂ kap₂)
        (sym (ocr²≡ h₁ h₂ ks₁ kap₁ ks₂ kap₂ f))
        (countT-xor-≤ (corrupt h₁ ks₁ kap₁) (corrupt h₂ ks₂ kap₂) (allVecs n))

--  Prove exact inclusion–exclusion: composite count plus twice the overlap
--  equals the sum.
ocr²-incl-excl :
  (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) →
  ocr² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f
  + 2 * countT (λ x → corrupt h₁ ks₁ kap₁ x ∧ corrupt h₂ ks₂ kap₂ x) (allVecs n)
  ≡ OCR h₁ ks₁ kap₁ + OCR h₂ ks₂ kap₂
ocr²-incl-excl {n = n} h₁ h₂ ks₁ kap₁ ks₂ kap₂ f =
  trans (cong (_+ 2 * countT (λ x → corrupt h₁ ks₁ kap₁ x ∧ corrupt h₂ ks₂ kap₂ x)
                             (allVecs n))
              (ocr²≡ h₁ h₂ ks₁ kap₁ ks₂ kap₂ f))
        (countT-and-xor (corrupt h₁ ks₁ kap₁) (corrupt h₂ ks₂ kap₂) (allVecs n))

--  Obtain equality of the sum when layers corrupt disjoint input sets.
ocr²-disjoint :
  (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) →
  (∀ x → (corrupt h₁ ks₁ kap₁ x ∧ corrupt h₂ ks₂ kap₂ x) ≡ false) →
  ocr² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f ≡ OCR h₁ ks₁ kap₁ + OCR h₂ ks₂ kap₂
ocr²-disjoint {n = n} h₁ h₂ ks₁ kap₁ ks₂ kap₂ f dis =
  trans (ocr²≡ h₁ h₂ ks₁ kap₁ ks₂ kap₂ f)
        (countT-xor-disjoint (corrupt h₁ ks₁ kap₁) (corrupt h₂ ks₂ kap₂) dis
                             (allVecs n))

------------------------------------------------------------------------
--  Instantiate the bound to show two SARLock layers corrupt at most four
--  inputs, uniformly in n.

ocr²-SARLock-≤4 :
  (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) →
  ocr² 0 0 ks₁ kap₁ ks₂ kap₂ f ≤ 4
ocr²-SARLock-≤4 ks₁ kap₁ ks₂ kap₂ f =
  ≤-trans (ocr²-≤-sum 0 0 ks₁ kap₁ ks₂ kap₂ f)
          (+-mono-≤ (OCR-SARLock-≤2 ks₁ kap₁) (OCR-SARLock-≤2 ks₂ kap₂))
