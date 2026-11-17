------------------------------------------------------------------------
--  Quantify SARLock's exponential query lower bound. SARLock-resist states
--  that two unprobed distinct applied keys prevent recovery. Here every
--  non-adaptive budget q+2 ≤ 2ⁿ necessarily leaves such a pair, giving
--  2ⁿ-scale recovery cost and the quantitative SAT-resistance counterpart
--  to FunctionalAnalysis.FALL-recovers-key-full's n-query SFLL recovery.
--  Use a pigeonhole argument over allVecs, whose universe has 2ⁿ elements.
--  count-eq counts each vector exactly once, complementing allVecs-count-pos
--  without list-membership or no-duplicate infrastructure. At most q
--  vectors are probed, leaving at least 2ⁿ−q ≥ 2 missed keys. Boolean
--  eqVec serves as decidable vector equality.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.SARLockQueryBound where

open import Data.Nat using (ℕ; zero; suc; _+_; _^_; _≤_; s≤s; z≤n)
open import Data.Nat.Properties
  using (≤-trans; ≤-refl; ≤-reflexive; +-mono-≤; +-comm)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
import Data.Fin as Fin
open Fin using (Fin)
import Data.Vec as Vec
open Vec using (Vec; lookup)
open import Data.List using (List; []; _∷_; length)
open import Data.Product using (_×_; _,_; ∃; proj₁; proj₂)
open import Data.Empty using (⊥)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst; _≢_)
open import Relation.Nullary using (¬_)

open import Util.BoolVec using (eqB; eqVec; eqB-refl; eqVec-refl; eqVec-false→≢)
open import Util.Counting
  using (countT; allVecs; length-allVecs; countT-false; split-count; mid4)
open import Attack.Oracle using (QAdversary; Recovers)
open import Attack.QueryLowerBound using (resist-off-diag)
open import Attack.SARLockResist using (actSAR; actSAR-agree)

private
  variable
    n q : ℕ

------------------------------------------------------------------------
--  Collect Boolean identities supporting the counts.

bit-∨-≤ : (a b : Bool) →
          (if a ∨ b then 1 else 0) ≤ (if a then 1 else 0) + (if b then 1 else 0)
bit-∨-≤ false false = z≤n
bit-∨-≤ false true  = ≤-refl
bit-∨-≤ true  b     = s≤s z≤n

bit-∧-≤ʳ : (a b : Bool) → (if a ∧ b then 1 else 0) ≤ (if b then 1 else 0)
bit-∧-≤ʳ false b = z≤n
bit-∧-≤ʳ true  b = ≤-refl

bit-total : (a : Bool) → (if a then 1 else 0) + (if not a then 1 else 0) ≡ 1
bit-total true  = refl
bit-total false = refl

bit-split : (a c : Bool) →
            (if a then 1 else 0)
            ≡ (if a ∧ c then 1 else 0) + (if a ∧ not c then 1 else 0)
bit-split false c     = refl
bit-split true  true  = refl
bit-split true  false = refl

not-true→false : (c : Bool) → not c ≡ true → c ≡ false
not-true→false false _ = refl
not-true→false true  ()

∧-true : (a b : Bool) → (a ∧ b) ≡ true → (a ≡ true) × (b ≡ true)
∧-true true  b eq = refl , eq
∧-true false b ()

∨-false : (a b : Bool) → (a ∨ b) ≡ false → (a ≡ false) × (b ≡ false)
∨-false false b eq = refl , eq
∨-false true  b ()

------------------------------------------------------------------------
--  Prove counting facts over general lists wherever possible.

private
  variable
    A : Set

--  Bound disjunction count by the sum of individual counts.
countT-∨-≤ : (p r : A → Bool) (xs : List A) →
             countT (λ x → p x ∨ r x) xs ≤ countT p xs + countT r xs
countT-∨-≤ p r []       = z≤n
countT-∨-≤ p r (x ∷ xs) =
  ≤-trans (+-mono-≤ (bit-∨-≤ (p x) (r x)) (countT-∨-≤ p r xs))
          (≤-reflexive (mid4 (if p x then 1 else 0) (if r x then 1 else 0)
                             (countT p xs) (countT r xs)))

--  Bound count of p ∧ r by count of r.
countT-∧-≤ʳ : (p r : A → Bool) (xs : List A) →
              countT (λ x → p x ∧ r x) xs ≤ countT r xs
countT-∧-≤ʳ p r []       = z≤n
countT-∧-≤ʳ p r (x ∷ xs) = +-mono-≤ (bit-∧-≤ʳ (p x) (r x)) (countT-∧-≤ʳ p r xs)

--  Partition a list by a predicate and its negation.
count-total : (p : A → Bool) (xs : List A) →
              countT p xs + countT (λ x → not (p x)) xs ≡ length xs
count-total p []       = refl
count-total p (x ∷ xs) =
  trans (mid4 (if p x then 1 else 0) (countT p xs)
              (if not (p x) then 1 else 0) (countT (λ z → not (p z)) xs))
        (cong₂ _+_ (bit-total (p x)) (count-total p xs))

--  Split a predicate count using a second predicate.
count-split-eq : (p c : A → Bool) (xs : List A) →
                 countT p xs
                 ≡ countT (λ x → p x ∧ c x) xs + countT (λ x → p x ∧ not (c x)) xs
count-split-eq p c []       = refl
count-split-eq p c (x ∷ xs) =
  trans (cong₂ _+_ (bit-split (p x) (c x)) (count-split-eq p c xs))
        (mid4 (if p x ∧ c x then 1 else 0) (if p x ∧ not (c x) then 1 else 0)
              (countT (λ z → p z ∧ c z) xs) (countT (λ z → p z ∧ not (c z)) xs))

--  Extract a satisfying witness from a positive count.
countT-pos-witness : (p : A → Bool) (xs : List A) →
                     1 ≤ countT p xs → ∃ λ v → p v ≡ true
countT-pos-witness p []       ()
countT-pos-witness p (x ∷ xs) le with p x in eq
... | true  = x , eq
... | false = countT-pos-witness p xs le

------------------------------------------------------------------------
--  Prove eqVec counts each vector once in the complete enumeration,
--  complementing allVecs-count-pos.

count-eq : (p : Vec Bool n) → countT (λ v → eqVec p v) (allVecs n) ≡ 1
count-eq Vec.[]                   = refl
count-eq {suc m} (false Vec.∷ p') =
  trans (split-count (λ v → eqVec (false Vec.∷ p') v))
        (cong₂ _+_ (count-eq p') (countT-false (allVecs m)))
count-eq {suc m} (true Vec.∷ p') =
  trans (split-count (λ v → eqVec (true Vec.∷ p') v))
        (cong₂ _+_ (countT-false (allVecs m)) (count-eq p'))

------------------------------------------------------------------------
--  Represent queried inputs by a predicate and bound their count by q.

probedV : Vec (Vec Bool n) q → Vec Bool n → Bool
probedV Vec.[]         v = false
probedV (p Vec.∷ ps) v = eqVec p v ∨ probedV ps v

--  The number of distinct probed vectors cannot exceed the probe count.
probedV-count-≤ : (ps : Vec (Vec Bool n) q) → countT (probedV ps) (allVecs n) ≤ q
probedV-count-≤ {n = n} Vec.[]       = ≤-reflexive (countT-false (allVecs n))
probedV-count-≤ {n = n} (p Vec.∷ ps) =
  ≤-trans (countT-∨-≤ (λ v → eqVec p v) (probedV ps) (allVecs n))
          (+-mono-≤ (≤-reflexive (count-eq p)) (probedV-count-≤ ps))

--  Show a vector outside the probe set differs from each query.
probedV-false-lookup : (ps : Vec (Vec Bool n) q) (v : Vec Bool n) →
                       probedV ps v ≡ false →
                       (i : Fin q) → eqVec (lookup ps i) v ≡ false
probedV-false-lookup (p Vec.∷ ps) v eq Fin.zero =
  proj₁ (∨-false (eqVec p v) (probedV ps v) eq)
probedV-false-lookup (p Vec.∷ ps) v eq (Fin.suc j) =
  probedV-false-lookup ps v (proj₂ (∨-false (eqVec p v) (probedV ps v) eq)) j

------------------------------------------------------------------------
--  Extract distinct witnesses when a count is at least two.

2≤suc→1≤ : ∀ {m} → 2 ≤ suc m → 1 ≤ m
2≤suc→1≤ (s≤s h) = h

--  Cancel a shared left summand without relying on a stdlib lemma name.
cancel-+ : ∀ a {m k} → a + m ≤ a + k → m ≤ k
cancel-+ zero    le        = le
cancel-+ (suc a) (s≤s le)  = cancel-+ a le

two-distinct : (p : Vec Bool n → Bool) → 2 ≤ countT p (allVecs n) →
               ∃ λ v₁ → ∃ λ v₂ → (v₁ ≢ v₂) × (p v₁ ≡ true) × (p v₂ ≡ true)
two-distinct {n} p le
  with countT-pos-witness p (allVecs n) (≤-trans (s≤s z≤n) le)
... | v₁ , pv₁
  with countT-pos-witness (λ v → p v ∧ not (eqVec v₁ v)) (allVecs n)
         (2≤suc→1≤ (≤-trans (subst (2 ≤_) (count-split-eq p (λ v → eqVec v₁ v) (allVecs n)) le)
                            (+-mono-≤ (≤-trans (countT-∧-≤ʳ p (λ v → eqVec v₁ v) (allVecs n))
                                               (≤-reflexive (count-eq v₁)))
                                      ≤-refl)))
... | v₂ , w =
  v₁ , v₂ ,
  eqVec-false→≢ v₁ v₂ (not-true→false (eqVec v₁ v₂)
                        (proj₂ (∧-true (p v₂) (not (eqVec v₁ v₂)) w))) ,
  pv₁ ,
  proj₁ (∧-true (p v₂) (not (eqVec v₁ v₂)) w)

------------------------------------------------------------------------
--  Prove the general pigeonhole core: a Boolean P with count ≤ B over
--  2ⁿ vectors misses two distinct vectors whenever 2+B ≤ 2ⁿ. Only the count
--  matters, independent of probes or oracles. Both unprobed-pair and
--  Sequential.SeqLockMulti's visited-set bounds instantiate this result.

unvisited-pair :
  (P : Vec Bool n → Bool) {B : ℕ} →
  countT P (allVecs n) ≤ B → 2 + B ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ → (k₁ ≢ k₂) × (P k₁ ≡ false) × (P k₂ ≡ false)
unvisited-pair {n = n} P {B} cnt bound =
  v₁ , v₂ , proj₁ (proj₂ (proj₂ dd)) ,
  not-true→false (P v₁) np₁ , not-true→false (P v₂) np₂
  where
    N : ℕ
    N = countT (λ v → not (P v)) (allVecs n)

    T≡ : countT P (allVecs n) + N ≡ 2 ^ n
    T≡ = trans (count-total P (allVecs n)) (length-allVecs n)

    2≤N : 2 ≤ N
    2≤N = cancel-+ B
            (subst (_≤ B + N) (+-comm 2 B)
              (≤-trans (subst (2 + B ≤_) (sym T≡) bound)
                       (+-mono-≤ cnt ≤-refl)))

    dd : ∃ λ v₁ → ∃ λ v₂ →
         (v₁ ≢ v₂) × (not (P v₁) ≡ true) × (not (P v₂) ≡ true)
    dd = two-distinct (λ v → not (P v)) 2≤N

    v₁ v₂ : Vec Bool n
    v₁ = proj₁ dd
    v₂ = proj₁ (proj₂ dd)

    np₁ : not (P v₁) ≡ true
    np₁ = proj₁ (proj₂ (proj₂ (proj₂ dd)))
    np₂ : not (P v₂) ≡ true
    np₂ = proj₂ (proj₂ (proj₂ (proj₂ dd)))

------------------------------------------------------------------------
--  Instantiate with q probes under 2+q ≤ 2ⁿ to find two distinct missed
--  vectors. Both query-lb-off-diag and adaptive-query-lb-off-diag use it.

unprobed-pair :
  (ps : Vec (Vec Bool n) q) → 2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ → (k₁ ≢ k₂)
    × ((i : Fin q) → lookup ps i ≢ k₁)
    × ((i : Fin q) → lookup ps i ≢ k₂)
unprobed-pair ps bound =
  k₁ , k₂ , ne ,
  (λ i → eqVec-false→≢ (lookup ps i) k₁ (probedV-false-lookup ps k₁ h₁ i)) ,
  (λ i → eqVec-false→≢ (lookup ps i) k₂ (probedV-false-lookup ps k₂ h₂ i))
  where
    up = unvisited-pair (probedV ps) (probedV-count-≤ ps) bound
    k₁ = proj₁ up
    k₂ = proj₁ (proj₂ up)
    ne = proj₁ (proj₂ (proj₂ up))
    h₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    h₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))

------------------------------------------------------------------------
--  Derive a quantitative generic bound for diagonal-distinguishing families
--  whose agree premise permits differences only at the two key inputs.
--  unprobed-pair is oracle-independent; resist-off-diag consumes its pair.
--  SARLock instantiates the result below.

query-lb-off-diag :
  ∀ {Y : Set} (act : Vec Bool n → Vec Bool n → Y)
    (agree : (k₁ k₂ x : Vec Bool n) → x ≢ k₁ → x ≢ k₂ → act k₁ x ≡ act k₂ x)
    (A : QAdversary (Vec Bool n) Y (Vec Bool n) q) →
    2 + q ≤ 2 ^ n →
    ¬ Recovers A act
query-lb-off-diag act agree A bound rec =
  resist-off-diag act agree A ne p₁ p₂ rec
  where
    up = unprobed-pair (QAdversary.probes A) bound
    ne = proj₁ (proj₂ (proj₂ up))
    p₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    p₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))

------------------------------------------------------------------------
--  Apply actSAR-agree to SARLock, excluding recovery at budgets below 2ⁿ−1.

SARLock-query-lb :
  (s : Vec Bool n) (f : Vec Bool n → Bool)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  2 + q ≤ 2 ^ n →
  ¬ Recovers A (actSAR s f)
SARLock-query-lb s f A bound =
  query-lb-off-diag (actSAR s f) (actSAR-agree s f) A bound
