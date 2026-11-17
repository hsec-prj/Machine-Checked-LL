------------------------------------------------------------------------
--  Functional recovery by the complement at half radius.
--  HD-complement proves HD x (flipV k) + HD x k ≡ n. At the explicit
--  premise n ≡ h+h, prot-complement identifies the two protected sets;
--  complement-restores and complement-ocr-0 then give host restoration
--  and zero corruption. Additive distance avoids truncated subtraction.
--  These functional results do not assert exact equality of returned keys
--  or describe every solver return; empirical observations are separate.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.Complement where

open import Data.Bool using (Bool; true; false; not; _xor_; T; if_then_else_)
open import Data.Bool.Properties using (xor-assoc; xor-same; xor-identityʳ)
open import Data.Empty using (⊥-elim)
open import Data.Fin using (Fin; toℕ)
open import Data.List using (List; []; _∷_)
open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Nat using (_≡ᵇ_)
open import Data.Nat.Properties using (+-assoc; +-comm; +-cancelʳ-≡; ≡ᵇ⇒≡; ≡⇒≡ᵇ)
open import Data.Vec using (Vec; []; _∷_; map)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)
open import Relation.Nullary using (¬_)

open import SFLL.HammingDistance using (HD; b2n)
open import SFLL.HD using (prot)
open import SFLL.Flex using (OCR-gen)
open import Util.Counting using (countT; countT-≡0; allVecs)
open import Locking.GenericLock
  using (ProtGadget; locked-fun-gen; ocrGen-of; sfllGadget)
open ProtGadget using (pred)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Section 1: complement every key bit.

flipV : Vec Bool n → Vec Bool n
flipV = map not

------------------------------------------------------------------------
--  Section 2: relate complementary distances by their sum.

--  Regardless of bit values, a coordinate contributes exactly one across
--  the two distances, supplying the induction's essential fact.
b2n-xor-not : (x y : Bool) → b2n (x xor not y) + b2n (x xor y) ≡ 1
b2n-xor-not false false = refl
b2n-xor-not false true  = refl
b2n-xor-not true  false = refl
b2n-xor-not true  true  = refl

--  Isolate four-summand rearrangement to keep the induction's arithmetic clear.
shuffle : (a b c d : ℕ) → (a + b) + (c + d) ≡ (a + c) + (b + d)
shuffle a b c d =
  trans (+-assoc a b (c + d))
    (trans (cong (a +_) (trans (sym (+-assoc b c d))
                          (trans (cong (_+ d) (+-comm b c)) (+-assoc c b d))))
      (sym (+-assoc a c (b + d))))

--  Use HD x (flipV k) + HD x k ≡ n. A formulation with truncated ∸ would
--  clamp at zero and could make a false claim provable.
HD-complement : (xs ys : Vec Bool n) → HD xs (flipV ys) + HD xs ys ≡ n
HD-complement []       []       = refl
HD-complement (x ∷ xs) (y ∷ ys) =
  trans (shuffle (b2n (x xor not y)) (HD xs (flipV ys)) (b2n (x xor y)) (HD xs ys))
        (cong₂ _+_ (b2n-xor-not x y) (HD-complement xs ys))

------------------------------------------------------------------------
--  Section 3: identify the protected set of the complement at half radius.

--  Prove equality of the two spheres at every input by cancelling h on
--  the right of HD x (flipV k) + h ≡ h+h.
complement-sphere :
  (h : ℕ) (k x : Vec Bool (h + h)) →
  HD x k ≡ h → HD x (flipV k) ≡ h
complement-sphere h k x eq =
  +-cancelʳ-≡ h (HD x (flipV k)) h
    (trans (cong (HD x (flipV k) +_) (sym eq)) (HD-complement x k))

--  For the reverse direction, commute the sum before cancelling the same h.
complement-sphere⁻ :
  (h : ℕ) (k x : Vec Bool (h + h)) →
  HD x (flipV k) ≡ h → HD x k ≡ h
complement-sphere⁻ h k x eq =
  +-cancelʳ-≡ h (HD x k) h
    (trans (cong (HD x k +_) (sym eq))
      (trans (+-comm (HD x k) (HD x (flipV k))) (HD-complement x k)))

------------------------------------------------------------------------
--  Section 4: transfer distance equalities to predicates.

--  Mutual implication makes Booleans equal: mixed cases contradict empty
--  T false, while equal cases are refl. This avoids with-abstraction over
--  two decidable equalities.
boolEq : (p q : Bool) → (T p → T q) → (T q → T p) → p ≡ q
boolEq true  true  _ _ = refl
boolEq true  false f _ = ⊥-elim (f _)
boolEq false true  _ g = ⊥-elim (g _)
boolEq false false _ _ = refl

--  On n=h+h bits at radius h, a key and its complement have equal
--  protected predicates at every input, independently of gadget syntax.
prot-complement :
  (h : ℕ) (k x : Vec Bool (h + h)) →
  prot h k x ≡ prot h (flipV k) x
prot-complement h k x =
  boolEq (HD x k ≡ᵇ h) (HD x (flipV k) ≡ᵇ h)
    (λ t → ≡⇒≡ᵇ (HD x (flipV k)) h (complement-sphere  h k x (≡ᵇ⇒≡ (HD x k) h t)))
    (λ t → ≡⇒≡ᵇ (HD x k) h (complement-sphere⁻ h k x (≡ᵇ⇒≡ (HD x (flipV k)) h t)))

------------------------------------------------------------------------
--  Section 5: equal protected predicates restore the host.

--  Require only equality of predicates, not gadgets. locked-fun-gen-recover
--  is the equal-gadget special case, insufficient here because the secret
--  and complement use different circuits.
same-pred-restores :
  (f : Vec Bool n → Bool) (g₁ g₂ : ProtGadget n) →
  ((y : Vec Bool n) → pred g₁ y ≡ pred g₂ y) →
  (x : Vec Bool n) → locked-fun-gen f g₁ g₂ x ≡ f x
same-pred-restores f g₁ g₂ agree x =
  trans (cong (λ b → (f x xor pred g₁ x) xor b) (sym (agree x)))
    (trans (xor-assoc (f x) (pred g₁ x) (pred g₁ x))
      (trans (cong (f x xor_) (xor-same (pred g₁ x)))
             (xor-identityʳ (f x))))

--  Equal predicates also yield zero OCR-gen: there are no disagreeing inputs
--  for its count.
same-pred-ocr-0 :
  (g₁ g₂ : ProtGadget n) →
  ((y : Vec Bool n) → pred g₁ y ≡ pred g₂ y) →
  ocrGen-of g₁ g₂ ≡ 0
same-pred-ocr-0 {n} g₁ g₂ agree =
  countT-≡0 (λ x → pred g₁ x xor pred g₂ x)
    (λ x → trans (cong (pred g₁ x xor_) (sym (agree x))) (xor-same (pred g₁ x)))
    (allVecs n)

------------------------------------------------------------------------
--  Section 6: authorise the complement of an SFLL-HD secret. Since sfllGadget
--  uses a Fin (suc n) radius, express its value by toℕ hF ≡ h. Apply the
--  section-5 results to section 4's predicate equality for both conclusions.

complement-restores :
  (h : ℕ) (hF : Fin (suc (h + h))) → toℕ hF ≡ h →
  (f : Vec Bool (h + h) → Bool) (k x : Vec Bool (h + h)) →
  locked-fun-gen f (sfllGadget hF k) (sfllGadget hF (flipV k)) x ≡ f x
complement-restores h hF hEq f k =
  same-pred-restores f (sfllGadget hF k) (sfllGadget hF (flipV k))
    (λ y → trans (cong (λ r → prot r k y) hEq)
             (trans (prot-complement h k y)
                    (cong (λ r → prot r (flipV k) y) (sym hEq))))

complement-ocr-0 :
  (h : ℕ) (hF : Fin (suc (h + h))) → toℕ hF ≡ h →
  (k : Vec Bool (h + h)) →
  ocrGen-of (sfllGadget hF k) (sfllGadget hF (flipV k)) ≡ 0
complement-ocr-0 h hF hEq k =
  same-pred-ocr-0 (sfllGadget hF k) (sfllGadget hF (flipV k))
    (λ y → trans (cong (λ r → prot r k y) hEq)
             (trans (prot-complement h k y)
                    (cong (λ r → prot r (flipV k) y) (sym hEq))))
