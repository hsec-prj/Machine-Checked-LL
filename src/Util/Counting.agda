------------------------------------------------------------------------
--  Provide the deterministic counting core for OCR lower bounds. countT p xs
--  counts list elements satisfying a Boolean predicate, and allVecs n lists
--  all n-bit vectors. allVecs-count-pos converts a witness p v ≡ true into
--  a positive enumeration count using only computation rules for countT,
--  append, and map, without list-membership infrastructure.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Util.Counting where

open import Level using (Level)
open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _^_; _≤_; s≤s; z≤n)
open import Data.Nat.Properties
  using (≤-trans; ≤-refl; ≤-reflexive; +-assoc; +-comm; +-identityʳ; +-mono-≤;
         *-identityˡ; *-distribˡ-+; *-distribʳ-+; m≤m+n; m≤n+m; +-commutativeSemigroup)
import Algebra.Properties.CommutativeSemigroup as CommutativeSemigroup
open import Data.Bool using (Bool; true; false; _∧_; _xor_; if_then_else_)
open import Data.List using (List; []; _∷_; _++_; map; length)
open import Data.List.Properties using (length-++; length-map)
import Data.Vec as Vec
open Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; trans; sym; subst)

private
  variable
    a : Level
    A B : Set a
    n : ℕ

------------------------------------------------------------------------
--  Count Boolean predicate successes in a list.

countT : (A → Bool) → List A → ℕ
countT p []       = 0
countT p (x ∷ xs) = (if p x then 1 else 0) + countT p xs

--  Split countT across list concatenation.
countT-++ : (p : A → Bool) (xs ys : List A) →
            countT p (xs ++ ys) ≡ countT p xs + countT p ys
countT-++ p []       ys = refl
countT-++ p (x ∷ xs) ys =
  trans (cong ((if p x then 1 else 0) +_) (countT-++ p xs ys))
        (sym (+-assoc (if p x then 1 else 0) (countT p xs) (countT p ys)))

--  Move map into the counted predicate by composition.
countT-map : (p : B → Bool) (f : A → B) (xs : List A) →
             countT p (map f xs) ≡ countT (λ x → p (f x)) xs
countT-map p f []       = refl
countT-map p f (x ∷ xs) = cong ((if p (f x) then 1 else 0) +_) (countT-map p f xs)

--  An everywhere-false predicate has zero contribution.
countT-false : (xs : List A) → countT (λ _ → false) xs ≡ 0
countT-false []       = refl
countT-false (x ∷ xs) = countT-false xs

--  When predicates never hold together, each element's XOR contribution
--  equals the sum of its two separate contributions.
bit-xor-disjoint : (a b : Bool) → (a ∧ b) ≡ false →
                   (if a xor b then 1 else 0)
                   ≡ (if a then 1 else 0) + (if b then 1 else 0)
bit-xor-disjoint false false _ = refl
bit-xor-disjoint false true  _ = refl
bit-xor-disjoint true  false _ = refl
bit-xor-disjoint true  true  ()

--  Use middle-four exchange to rearrange the following induction step.
mid4 : (a b c d : ℕ) → (a + b) + (c + d) ≡ (a + c) + (b + d)
mid4 = CommutativeSemigroup.interchange +-commutativeSemigroup

--  For disjoint predicates, XOR counts add because symmetric difference
--  equals union.
countT-xor-disjoint : (p q : A → Bool) → (∀ x → (p x ∧ q x) ≡ false) →
                      (xs : List A) →
                      countT (λ x → p x xor q x) xs ≡ countT p xs + countT q xs
countT-xor-disjoint p q dis []       = refl
countT-xor-disjoint p q dis (x ∷ xs) =
  trans (cong₂ _+_ (bit-xor-disjoint (p x) (q x) (dis x))
                   (countT-xor-disjoint p q dis xs))
        (mid4 (if p x then 1 else 0) (if q x then 1 else 0)
              (countT p xs) (countT q xs))

------------------------------------------------------------------------
--  Define binomial coefficients by Pascal recurrence for sphere cardinalities.

binom : ℕ → ℕ → ℕ
binom n       zero    = 1
binom zero    (suc _) = 0
binom (suc n) (suc k) = binom n (suc k) + binom n k

------------------------------------------------------------------------
--  Enumerate Boolean vectors of each width.

--  The allVecs n enumeration contains all 2ⁿ vectors of length n.
allVecs : (n : ℕ) → List (Vec Bool n)
allVecs zero    = Vec.[] ∷ []
allVecs (suc n) = map (Vec._∷_ false) (allVecs n) ++ map (Vec._∷_ true) (allVecs n)

--  Split counting on allVecs (suc n) according to the first bit.
split-count : (P : Vec Bool (suc n) → Bool) →
              countT P (allVecs (suc n))
              ≡ countT (λ x → P (false Vec.∷ x)) (allVecs n)
              + countT (λ x → P (true Vec.∷ x)) (allVecs n)
split-count {n = n} P =
  trans (countT-++ P (map (Vec._∷_ false) (allVecs n)) (map (Vec._∷_ true) (allVecs n)))
        (cong₂ _+_ (countT-map P (Vec._∷_ false) (allVecs n))
                   (countT-map P (Vec._∷_ true)  (allVecs n)))

------------------------------------------------------------------------
--  Derive positive count from one satisfying witness.

1≤if : (b : Bool) → b ≡ true → 1 ≤ (if b then 1 else 0)
1≤if true  _  = s≤s z≤n
1≤if false ()

--  A vector satisfying p forces the full enumeration count to be at least
--  one. Induct on that witness following allVecs' recursive construction.
allVecs-count-pos : (p : Vec Bool n → Bool) (v : Vec Bool n) →
                    p v ≡ true → 1 ≤ countT p (allVecs n)
allVecs-count-pos p Vec.[] pv =
  ≤-trans (1≤if (p Vec.[]) pv) (m≤m+n (if p Vec.[] then 1 else 0) 0)
allVecs-count-pos {n = suc n} p (false Vec.∷ v) pv =
  subst (1 ≤_) (sym split)
        (≤-trans (allVecs-count-pos (λ w → p (false Vec.∷ w)) v pv)
                 (m≤m+n L R))
  where
    L = countT (λ w → p (false Vec.∷ w)) (allVecs n)
    R = countT (λ w → p (true  Vec.∷ w)) (allVecs n)
    split : countT p (allVecs (suc n)) ≡ L + R
    split = trans (countT-++ p (map (Vec._∷_ false) (allVecs n))
                                (map (Vec._∷_ true)  (allVecs n)))
                  (cong₂ _+_ (countT-map p (Vec._∷_ false) (allVecs n))
                             (countT-map p (Vec._∷_ true)  (allVecs n)))
allVecs-count-pos {n = suc n} p (true Vec.∷ v) pv =
  subst (1 ≤_) (sym split)
        (≤-trans (allVecs-count-pos (λ w → p (true Vec.∷ w)) v pv)
                 (m≤n+m R L))
  where
    L = countT (λ w → p (false Vec.∷ w)) (allVecs n)
    R = countT (λ w → p (true  Vec.∷ w)) (allVecs n)
    split : countT p (allVecs (suc n)) ≡ L + R
    split = trans (countT-++ p (map (Vec._∷_ false) (allVecs n))
                                (map (Vec._∷_ true)  (allVecs n)))
                  (cong₂ _+_ (countT-map p (Vec._∷_ false) (allVecs n))
                             (countT-map p (Vec._∷_ true)  (allVecs n)))

------------------------------------------------------------------------
--  Prove a product/Fubini count, the Vandermonde-convolution core. Independent
--  conditions on the first p and final d wires factor the count over p+d
--  bits into the product of regional counts. This splits protected-sphere
--  intersections across a key pair's agreement region n−d and disagreement
--  region d into a binomial product.

--  A fixed left conjunct scales the predicate count.
countT-const-∧ : (c : Bool) (q : A → Bool) (xs : List A) →
                 countT (λ x → c ∧ q x) xs ≡ (if c then 1 else 0) * countT q xs
countT-const-∧ true  q xs = sym (*-identityˡ (countT q xs))
countT-const-∧ false q xs = countT-false xs

countT-prod : (p : ℕ) {d : ℕ} (P : Vec Bool p → Bool) (Q : Vec Bool d → Bool) →
              countT (λ x → P (Vec.take p x) ∧ Q (Vec.drop p x)) (allVecs (p + d))
              ≡ countT P (allVecs p) * countT Q (allVecs d)
countT-prod zero {d} P Q =
  trans (countT-const-∧ (P Vec.[]) Q (allVecs d))
        (cong (_* countT Q (allVecs d)) (sym (+-identityʳ (if P Vec.[] then 1 else 0))))
countT-prod (suc p) {d} P Q =
  trans (split-count (λ x → P (Vec.take (suc p) x) ∧ Q (Vec.drop (suc p) x)))
  (trans (cong₂ _+_ (countT-prod p (λ y → P (false Vec.∷ y)) Q)
                    (countT-prod p (λ y → P (true Vec.∷ y)) Q))
  (trans (sym (*-distribʳ-+ (countT Q (allVecs d))
                            (countT (λ y → P (false Vec.∷ y)) (allVecs p))
                            (countT (λ y → P (true Vec.∷ y)) (allVecs p))))
         (cong (_* countT Q (allVecs d)) (sym (split-count P)))))

------------------------------------------------------------------------
--  Bound XOR counts without assuming disjointness.

bit-xor-≤ : (a b : Bool) →
            (if a xor b then 1 else 0) ≤ (if a then 1 else 0) + (if b then 1 else 0)
bit-xor-≤ false false = z≤n
bit-xor-≤ false true  = ≤-refl
bit-xor-≤ true  false = ≤-refl
bit-xor-≤ true  true  = z≤n

--  Bound symmetric-difference size by the multiset-union count.
countT-xor-≤ : (p q : A → Bool) (xs : List A) →
               countT (λ x → p x xor q x) xs ≤ countT p xs + countT q xs
countT-xor-≤ p q []       = z≤n
countT-xor-≤ p q (x ∷ xs) =
  ≤-trans (+-mono-≤ (bit-xor-≤ (p x) (q x)) (countT-xor-≤ p q xs))
          (≤-reflexive (mid4 (if p x then 1 else 0) (if q x then 1 else 0)
                             (countT p xs) (countT q xs)))

------------------------------------------------------------------------
--  Prove enumeration length 2ⁿ, the OCR fraction's denominator.

length-allVecs : (n : ℕ) → length (allVecs n) ≡ 2 ^ n
length-allVecs zero    = refl
length-allVecs (suc n) =
  trans (length-++ (map (Vec._∷_ false) (allVecs n)) {map (Vec._∷_ true) (allVecs n)})
        (trans (cong₂ _+_ (length-map (Vec._∷_ false) (allVecs n))
                          (length-map (Vec._∷_ true)  (allVecs n)))
               (trans (cong₂ _+_ (length-allVecs n) (length-allVecs n))
                      (cong (2 ^ n +_) (sym (+-identityʳ (2 ^ n))))))

------------------------------------------------------------------------
--  Establish symmetric-difference inclusion–exclusion: the XOR count plus
--  twice the intersection count equals the two individual counts. Together
--  with sphere sizes, this reduces distance-d OCR to one intersection count;
--  odd-distance disjointness specialises it to zero intersection.

bit-and-xor : (a b : Bool) →
              (if a xor b then 1 else 0) + 2 * (if a ∧ b then 1 else 0)
              ≡ (if a then 1 else 0) + (if b then 1 else 0)
bit-and-xor false false = refl
bit-and-xor false true  = refl
bit-and-xor true  false = refl
bit-and-xor true  true  = refl

countT-and-xor : (p q : A → Bool) (xs : List A) →
                 countT (λ x → p x xor q x) xs + 2 * countT (λ x → p x ∧ q x) xs
                 ≡ countT p xs + countT q xs
countT-and-xor p q []       = refl
countT-and-xor p q (x ∷ xs) =
  trans (cong ((bx + Cxor) +_) (*-distribˡ-+ 2 ba Cand))
  (trans (mid4 bx Cxor (2 * ba) (2 * Cand))
  (trans (cong₂ _+_ (bit-and-xor (p x) (q x)) (countT-and-xor p q xs))
         (mid4 bp bq Cp Cq)))
  where
    bx   = if p x xor q x then 1 else 0
    ba   = if p x ∧ q x   then 1 else 0
    bp   = if p x then 1 else 0
    bq   = if q x then 1 else 0
    Cxor = countT (λ z → p z xor q z) xs
    Cand = countT (λ z → p z ∧ q z) xs
    Cp   = countT p xs
    Cq   = countT q xs

--  Count zero for a predicate false on every input.
countT-≡0 : (p : A → Bool) → (∀ x → p x ≡ false) → (xs : List A) → countT p xs ≡ 0
countT-≡0 p z []       = refl
countT-≡0 p z (x ∷ xs) rewrite z x = countT-≡0 p z xs

private
  bit-mono : (left right : Bool) → (left ≡ true → right ≡ true) →
             (if left then 1 else 0) ≤ (if right then 1 else 0)
  bit-mono false right implication = z≤n
  bit-mono true right implication rewrite implication refl = s≤s z≤n

countT-mono : (predicate superset : A → Bool) (values : List A) →
              (∀ value → predicate value ≡ true → superset value ≡ true) →
              countT predicate values ≤ countT superset values
countT-mono predicate superset [] implication = z≤n
countT-mono predicate superset (value ∷ values) implication =
  +-mono-≤ (bit-mono (predicate value) (superset value) (implication value))
           (countT-mono predicate superset values implication)

--  Pointwise predicate equality preserves counts.
countT-cong : {p q : A → Bool} → (∀ x → p x ≡ q x) →
              (xs : List A) → countT p xs ≡ countT q xs
countT-cong eq []       = refl
countT-cong eq (x ∷ xs) =
  cong₂ _+_ (cong (λ b → if b then 1 else 0) (eq x)) (countT-cong eq xs)
