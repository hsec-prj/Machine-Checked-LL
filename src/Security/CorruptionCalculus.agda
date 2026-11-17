------------------------------------------------------------------------
--  Derive exact OCR from protected predicates through a generic calculus
--  (Tier 2, 2a). SFLL.Flex identifies any scheme's OCR with symmetric
--  difference and proves OCR(p,q)+2|p∧q|=|p|+|q|. Three rules now derive
--  catalogue entries by instantiation, extending the all-N closed-form
--  approach across schemes. The union rule ocr-≤-sum always gives
--  OCR(p,q) ≤ |p|+|q|. The disjoint rule ocr-disjoint gives equality when
--  p∧q ≡ ⊥. The point rule ocr-point-≤2 gives OCR ≤ 2 when each set has
--  size at most one. Hence calc-OCR-odd combines sphere size and
--  disjointness for SFLL-HD's 2·C(n,h), while calc-point-≤2 covers the
--  SARLock/Anti-SAT radius-zero singleton corner. These are generic-rule
--  derivations rather than bespoke proofs, with no primitives or postulates
--  added.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.CorruptionCalculus where

open import Data.Nat using (ℕ; suc; _+_; _*_; _≤_)
open import Data.Nat.Properties
  using (≤-trans; ≤-reflexive; +-mono-≤; +-identityʳ)
open import Data.Bool using (Bool; true; false; _∧_; _xor_)
open import Data.Bool.Properties using (xor-same)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; trans; sym)

open import Util.Counting
  using (countT; allVecs; binom; countT-false; countT-≡0; countT-cong; countT-xor-≤)
open import SFLL.HD using (prot)
open import SFLL.HammingDistance using (HD; parity)
open import Security.OCR using (OCR; sphere-count; prot-disjoint-odd)
open import SFLL.Flex
  using (OCR-gen; inter-gen; card; OCR-gen-incl-excl; OCR-is-gen; card-sphere; protList)
open import Data.List using (List; []; _∷_; length)
open import Attack.SARLockQueryBound using (countT-∨-≤)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  State the three scheme-independent derivation rules.

--  Rule 1 bounds corruption by the sum of protected-set sizes.
ocr-≤-sum : (p q : Vec Bool n → Bool) → OCR-gen p q ≤ card p + card q
ocr-≤-sum {n} p q = countT-xor-≤ p q (allVecs n)

--  Express emptiness of the intersection.
inter-gen-0 : (p q : Vec Bool n → Bool) → (∀ x → (p x ∧ q x) ≡ false) →
              inter-gen p q ≡ 0
inter-gen-0 {n} p q dis = countT-≡0 (λ x → p x ∧ q x) dis (allVecs n)

--  Rule 2 identifies corruption exactly with the union of disjoint protected sets.
ocr-disjoint : (p q : Vec Bool n → Bool) → (∀ x → (p x ∧ q x) ≡ false) →
               OCR-gen p q ≡ card p + card q
ocr-disjoint {n} p q dis =
  trans (sym (trans (cong (λ z → OCR-gen p q + 2 * z) (inter-gen-0 p q dis))
                    (+-identityʳ (OCR-gen p q))))
        (OCR-gen-incl-excl p q)

--  Rule 3 bounds corruption by two inputs when each protected set is a singleton.
ocr-point-≤2 : (p q : Vec Bool n → Bool) → card p ≤ 1 → card q ≤ 1 →
               OCR-gen p q ≤ 2
ocr-point-≤2 p q cp cq = ≤-trans (ocr-≤-sum p q) (+-mono-≤ cp cq)

------------------------------------------------------------------------
--  Derive immediate consequences.

--  Using a scheme's own key produces no corruption.
ocr-self : (p : Vec Bool n → Bool) → OCR-gen p p ≡ 0
ocr-self {n} p =
  trans (countT-cong (λ x → xor-same (p x)) (allVecs n)) (countT-false (allVecs n))

------------------------------------------------------------------------
--  Instantiate the rules to derive the catalogue.

--  Odd-distance SFLL-HD spheres are disjoint by parity. Rule 2 and Pascal
--  cardinality yield 2·C(n,h), recovering Security.OCR.OCR-odd generically.
calc-OCR-odd : (h : ℕ) (k k' : Vec Bool n) → parity (HD k k') ≡ true →
               OCR h k k' ≡ binom n h + binom n h
calc-OCR-odd h k k' odd =
  trans (OCR-is-gen h k k')
        (trans (ocr-disjoint (prot h k) (prot h k') (prot-disjoint-odd h odd))
               (cong₂ _+_ (card-sphere h k) (card-sphere h k')))

--  In the SARLock/Anti-SAT point corner, radius-zero SFLL protects {k},
--  with cardinality one. Rule 3 therefore gives corruption ≤ 2 for every n.
card-point : (k : Vec Bool n) → card (prot 0 k) ≡ 1
card-point k = sphere-count 0 k

calc-point-≤2 : (k k' : Vec Bool n) → OCR-gen (prot 0 k) (prot 0 k') ≤ 2
calc-point-≤2 k k' =
  ocr-point-≤2 (prot 0 k) (prot 0 k')
    (≤-reflexive (card-point k)) (≤-reflexive (card-point k'))

--  For flex, protList S has cardinality at most |S| because listed members
--  may repeat. Apply countT-∨-≤ to the OR tree and card-point to its
--  singletons. This completes the cardinality catalogue with card-point = 1
--  and card-sphere = C(n,h).
card-protList-≤ : (S : List (Vec Bool n)) → card (protList S) ≤ length S
card-protList-≤ {n} []  = ≤-reflexive (countT-false (allVecs n))
card-protList-≤ {n} (s ∷ S) =
  ≤-trans (countT-∨-≤ (prot 0 s) (protList S) (allVecs n))
          (+-mono-≤ (≤-reflexive (card-point s)) (card-protList-≤ S))

--  Instantiate Rule 1 with the flex cardinality bound to bound its corruption
--  by the sum of the two list sizes, deriving the third catalogue entry.
calc-flex-≤ : (S S' : List (Vec Bool n)) →
              OCR-gen (protList S) (protList S') ≤ length S + length S'
calc-flex-≤ S S' =
  ≤-trans (ocr-≤-sum (protList S) (protList S'))
          (+-mono-≤ (card-protList-≤ S) (card-protList-≤ S'))
