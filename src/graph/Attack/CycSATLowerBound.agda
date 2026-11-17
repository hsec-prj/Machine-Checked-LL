------------------------------------------------------------------------
--  Match point-residual recovery with a universal adversarial lower bound
--  (graph track, D8-II frontier 2). CycSATComposeDIP.dipScanCount-exact gives
--  one algorithm, dipScan, exactly 2ᵐ−1 effective queries. Here any q-probe
--  set with 2 + q ≤ 2ᵐ leaves two distinct keys consistent with the secret,
--  excluding q-query recovery and yielding exact complexity 2ᵐ−1 wholly
--  inside the graph library. The observable act k x = eqVec k x is
--  off-diagonal: ≢→eqVec-false makes it false away from k. Distinct keys
--  thus agree on probes missing both. The unprobed-pair pigeonhole lemma
--  finds two missed keys among 2ᵐ possibilities when 2 + q ≤ 2ᵐ. Since the
--  graph library cannot import ../src, this translates the bound from
--  src/Attack/{SARLockQueryBound,SATComplexity} locally, using countT,
--  countEq-one, mid4, and countT-∧-≤ʳ from CycSATComposeDIP. No postulates
--  are used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATLowerBound where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; s≤s; z≤n; _^_)
open import Data.Nat.Properties using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; +-comm)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.List using (List; []; _∷_; length)
open import Data.Fin using (Fin; zero; suc)
open import Data.Product using (_×_; _,_; ∃; proj₁; proj₂)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst; _≢_)
open import Relation.Nullary using (¬_)

open import Graph.Util using (allVecsK; length-allVecsK)
open import Attack.CycSATCompose
  using (eqB; eqVec; eqVec-complete; eqVec-false→≢; ∧true→)
open import Attack.CycSATComposeDIP
  using (countT; countEq-one; mid4; countT-cong; countT-const-false; countT-∧-≤ʳ)

private
  variable
    m q : ℕ
    A : Set

------------------------------------------------------------------------
--  Translate the required Boolean and counting helpers into the graph library.

not-true→false : (c : Bool) → not c ≡ true → c ≡ false
not-true→false false _ = refl
not-true→false true  ()

bit-total : (a : Bool) → (if a then 1 else 0) + (if not a then 1 else 0) ≡ 1
bit-total true  = refl
bit-total false = refl

count-total : (p : A → Bool) (xs : List A) →
              countT p xs + countT (λ x → not (p x)) xs ≡ length xs
count-total p []       = refl
count-total p (x ∷ xs) =
  trans (mid4 (if p x then 1 else 0) (countT p xs)
              (if not (p x) then 1 else 0) (countT (λ z → not (p z)) xs))
        (cong₂ _+_ (bit-total (p x)) (count-total p xs))

bit-split-pc : (p c : Bool) →
               (if p then 1 else 0)
               ≡ (if p ∧ c then 1 else 0) + (if p ∧ not c then 1 else 0)
bit-split-pc true  true  = refl
bit-split-pc true  false = refl
bit-split-pc false c     = refl

count-split-eq : (p c : A → Bool) (xs : List A) →
                 countT p xs
                 ≡ countT (λ x → p x ∧ c x) xs + countT (λ x → p x ∧ not (c x)) xs
count-split-eq p c []       = refl
count-split-eq p c (x ∷ xs) =
  trans (cong₂ _+_ (bit-split-pc (p x) (c x)) (count-split-eq p c xs))
        (mid4 (if p x ∧ c x then 1 else 0) (if p x ∧ not (c x) then 1 else 0)
              (countT (λ z → p z ∧ c z) xs) (countT (λ z → p z ∧ not (c z)) xs))

countT-pos-witness : (p : A → Bool) (xs : List A) →
                     1 ≤ countT p xs → ∃ λ v → p v ≡ true
countT-pos-witness p []       ()
countT-pos-witness p (x ∷ xs) le with p x in eq
... | true  = x , eq
... | false = countT-pos-witness p xs le

--  Use symmetry of eqVec to count exactly one enumerated vector equal to p.
eqB-sym : (a b : Bool) → eqB a b ≡ eqB b a
eqB-sym true  true  = refl
eqB-sym true  false = refl
eqB-sym false true  = refl
eqB-sym false false = refl

eqVec-sym : (a b : Vec Bool m) → eqVec a b ≡ eqVec b a
eqVec-sym []       []       = refl
eqVec-sym (a ∷ as) (b ∷ bs) = cong₂ _∧_ (eqB-sym a b) (eqVec-sym as bs)

count-eq : (p : Vec Bool m) → countT (λ v → eqVec p v) (allVecsK m) ≡ 1
count-eq {m = m} p = trans (countT-cong (λ v → eqVec-sym p v) (allVecsK m)) (countEq-one p)

------------------------------------------------------------------------
--  Bound disjunction counts and represent the probe set by a predicate.

∨-false : (a b : Bool) → a ∨ b ≡ false → (a ≡ false) × (b ≡ false)
∨-false false b eq = refl , eq
∨-false true  b ()

bit-∨-≤ : (a b : Bool) → (if a ∨ b then 1 else 0) ≤ (if a then 1 else 0) + (if b then 1 else 0)
bit-∨-≤ false false = z≤n
bit-∨-≤ false true  = ≤-refl
bit-∨-≤ true  b     = s≤s z≤n

countT-∨-≤ : (p r : A → Bool) (xs : List A) →
             countT (λ x → p x ∨ r x) xs ≤ countT p xs + countT r xs
countT-∨-≤ p r []       = z≤n
countT-∨-≤ p r (x ∷ xs) =
  ≤-trans (+-mono-≤ (bit-∨-≤ (p x) (r x)) (countT-∨-≤ p r xs))
          (≤-reflexive (mid4 (if p x then 1 else 0) (if r x then 1 else 0)
                             (countT p xs) (countT r xs)))

probedV : Vec (Vec Bool m) q → Vec Bool m → Bool
probedV []       v = false
probedV (p ∷ ps) v = eqVec p v ∨ probedV ps v

probedV-count-≤ : (ps : Vec (Vec Bool m) q) → countT (probedV ps) (allVecsK m) ≤ q
probedV-count-≤ {m = m} []       = ≤-reflexive (countT-const-false (allVecsK m))
probedV-count-≤ {m = m} (p ∷ ps) =
  ≤-trans (countT-∨-≤ (λ v → eqVec p v) (probedV ps) (allVecsK m))
          (+-mono-≤ (≤-reflexive (count-eq p)) (probedV-count-≤ ps))

probedV-false-lookup : (ps : Vec (Vec Bool m) q) (v : Vec Bool m) →
                       probedV ps v ≡ false →
                       (i : Fin q) → eqVec (lookup ps i) v ≡ false
probedV-false-lookup (p ∷ ps) v eq zero    = proj₁ (∨-false (eqVec p v) (probedV ps v) eq)
probedV-false-lookup (p ∷ ps) v eq (suc j) =
  probedV-false-lookup ps v (proj₂ (∨-false (eqVec p v) (probedV ps v) eq)) j

------------------------------------------------------------------------
--  Use pigeonhole reasoning: a count ≥2 yields distinct witnesses, and a
--  count ≤B with 2+B≤2ᵐ leaves two missed values.

2≤suc→1≤ : 2 ≤ suc m → 1 ≤ m
2≤suc→1≤ (s≤s h) = h

cancel-+ : ∀ a {x y} → a + x ≤ a + y → x ≤ y
cancel-+ zero    le       = le
cancel-+ (suc a) (s≤s le) = cancel-+ a le

two-distinct : (p : Vec Bool m → Bool) → 2 ≤ countT p (allVecsK m) →
               ∃ λ v₁ → ∃ λ v₂ → (v₁ ≢ v₂) × (p v₁ ≡ true) × (p v₂ ≡ true)
two-distinct {m = m} p le
  with countT-pos-witness p (allVecsK m) (≤-trans (s≤s z≤n) le)
... | v₁ , pv₁
  with countT-pos-witness (λ v → p v ∧ not (eqVec v₁ v)) (allVecsK m)
         (2≤suc→1≤ (≤-trans (subst (2 ≤_) (count-split-eq p (λ v → eqVec v₁ v) (allVecsK m)) le)
                            (+-mono-≤ (≤-trans (countT-∧-≤ʳ p (λ v → eqVec v₁ v) (allVecsK m))
                                               (≤-reflexive (count-eq v₁)))
                                      ≤-refl)))
... | v₂ , w =
  v₁ , v₂ ,
  eqVec-false→≢ (not-true→false (eqVec v₁ v₂)
                  (proj₂ (∧true→ (p v₂) (not (eqVec v₁ v₂)) w))) ,
  pv₁ ,
  proj₁ (∧true→ (p v₂) (not (eqVec v₁ v₂)) w)

unvisited-pair : (P : Vec Bool m → Bool) {B : ℕ} →
                 countT P (allVecsK m) ≤ B → 2 + B ≤ 2 ^ m →
                 ∃ λ k₁ → ∃ λ k₂ → (k₁ ≢ k₂) × (P k₁ ≡ false) × (P k₂ ≡ false)
unvisited-pair {m = m} P {B} cnt bound =
  v₁ , v₂ , proj₁ (proj₂ (proj₂ dd)) ,
  not-true→false (P v₁) np₁ , not-true→false (P v₂) np₂
  where
    N : ℕ
    N = countT (λ v → not (P v)) (allVecsK m)
    T≡ : countT P (allVecsK m) + N ≡ 2 ^ m
    T≡ = trans (count-total P (allVecsK m)) (length-allVecsK m)
    2≤N : 2 ≤ N
    2≤N = cancel-+ B
            (subst (_≤ B + N) (+-comm 2 B)
              (≤-trans (subst (2 + B ≤_) (sym T≡) bound) (+-mono-≤ cnt ≤-refl)))
    dd : ∃ λ v₁ → ∃ λ v₂ →
         (v₁ ≢ v₂) × (not (P v₁) ≡ true) × (not (P v₂) ≡ true)
    dd = two-distinct (λ v → not (P v)) 2≤N
    v₁ v₂ : Vec Bool m
    v₁ = proj₁ dd
    v₂ = proj₁ (proj₂ dd)
    np₁ : not (P v₁) ≡ true
    np₁ = proj₁ (proj₂ (proj₂ (proj₂ dd)))
    np₂ : not (P v₂) ≡ true
    np₂ = proj₂ (proj₂ (proj₂ (proj₂ dd)))

--  Find two distinct unprobed keys after q probes satisfying 2+q ≤ 2ᵐ.
unprobed-pair :
  (ps : Vec (Vec Bool m) q) → 2 + q ≤ 2 ^ m →
  ∃ λ k₁ → ∃ λ k₂ → (k₁ ≢ k₂)
    × ((i : Fin q) → lookup ps i ≢ k₁)
    × ((i : Fin q) → lookup ps i ≢ k₂)
unprobed-pair ps bound =
  k₁ , k₂ , ne ,
  (λ i → eqVec-false→≢ (probedV-false-lookup ps k₁ h₁ i)) ,
  (λ i → eqVec-false→≢ (probedV-false-lookup ps k₂ h₂ i))
  where
    up = unvisited-pair (probedV ps) (probedV-count-≤ ps) bound
    k₁ = proj₁ up
    k₂ = proj₁ (proj₂ up)
    ne = proj₁ (proj₂ (proj₂ up))
    h₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    h₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))

------------------------------------------------------------------------
--  Derive the universal bound from off-diagonal eqVec: fewer than 2ᵐ−1
--  probes leave two consistent keys and prevent recovery.

consistentOn : (act : Vec Bool m → Vec Bool m → Bool) (ksec : Vec Bool m)
               (xs : Vec (Vec Bool m) q) (k : Vec Bool m) → Set
consistentOn {q = q} act ksec xs k =
  (i : Fin q) → act k (lookup xs i) ≡ act ksec (lookup xs i)

--  Show that the indicator is false away from the diagonal x = k.
≢→eqVec-false : (k x : Vec Bool m) → x ≢ k → eqVec k x ≡ false
≢→eqVec-false k x x≢k with eqVec k x in e
... | false = refl
... | true  = ⊥-elim (x≢k (sym (eqVec-complete k x e)))

--  On each probe, an unqueried candidate agrees with the secret because
--  both indicators vanish.
offdiag-consistent :
  (ksec : Vec Bool m) (xs : Vec (Vec Bool m) q) (k : Vec Bool m) →
  ((i : Fin q) → lookup xs i ≢ ksec) → ((i : Fin q) → lookup xs i ≢ k) →
  consistentOn eqVec ksec xs k
offdiag-consistent ksec xs k avoid-sec avoid-k i =
  trans (≢→eqVec-false k (lookup xs i) (avoid-k i))
        (sym (≢→eqVec-false ksec (lookup xs i) (avoid-sec i)))

--  After q < 2ᵐ−1 probes avoiding the secret, two distinct candidates remain
--  consistent, requiring at least 2ᵐ−1 queries. dipScanCount-exact attains
--  that number, making the bound tight with Θ(2ᵐ) complexity.
cycSAT-universal-lb :
  (ksec : Vec Bool m) (xs : Vec (Vec Bool m) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) → 2 + q ≤ 2 ^ m →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂) × consistentOn eqVec ksec xs k₁ × consistentOn eqVec ksec xs k₂
cycSAT-universal-lb ksec xs avoid-sec bound =
  k₁ , k₂ , ne ,
  offdiag-consistent ksec xs k₁ avoid-sec p₁ ,
  offdiag-consistent ksec xs k₂ avoid-sec p₂
  where
    up = unprobed-pair xs bound
    k₁ = proj₁ up
    k₂ = proj₁ (proj₂ up)
    ne = proj₁ (proj₂ (proj₂ up))
    p₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    p₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))
