------------------------------------------------------------------------
--  Verify a point-family DIP/SAT recovery attack matching the resistance
--  scale. DIPAttackSpike justified a while-DIP loop by decreasing candidate
--  count. For point locks, a fold over the finite allVecs n query list
--  instead terminates structurally, requiring neither fuel nor well-founded
--  recursion. SARLock/Anti-SAT radius-zero SFLL depends on the applied key
--  only through prot 0 k, so consist compares candidate and secret point
--  indicators at each input. The secret survives every query by survives-ksec.
--  Any wrong k is excluded at x = k, present by ∈-allVecs: its indicator
--  is true and the secret's false, proving survives-only-ksec. Exhaustive
--  pruning thus leaves exactly the secret. dipAttack-queries gives the
--  upper bound |allVecs n| = 2ⁿ, complementing offdiag-SAT-lb and gen-SAT-lb
--  from SATComplexity/GenericSAT, which exclude budgets below 2ⁿ−1. Together
--  the bounds establish Θ(2ⁿ) query complexity for the same family. The
--  proof uses structural recursion alone and no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.PointDIPAttack where

open import Data.Nat using (ℕ; zero; suc; _^_; _≡ᵇ_)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_)
open import Data.Bool.Properties using (∧-zeroʳ)
open import Data.Vec using (Vec; []; _∷_)
open import Data.List using (List; []; _∷_; length)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.List.Membership.Propositional.Properties using (∈-++⁺ˡ; ∈-++⁺ʳ; ∈-map⁺)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans; cong; cong₂; _≢_)

open import SFLL.HD using (prot)
open import SFLL.HammingDistance using (HD-refl; xor-self)
open import Security.AntiSat using (prot0-false)
open import Util.Counting using (allVecs; length-allVecs)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Define consistency by agreement of candidate and secret point indicators
--  at x, the sole key-dependent part of a point lock.

consist : (ksec x k : Vec Bool n) → Bool
consist ksec x k = not (prot 0 k x xor prot 0 ksec x)

--  Represent candidates remaining after pruning with a queried-input list.
andMap : (Vec Bool n → Bool) → List (Vec Bool n) → Bool
andMap f []       = true
andMap f (x ∷ xs) = f x ∧ andMap f xs

survives : (ksec : Vec Bool n) (qs : List (Vec Bool n)) (k : Vec Bool n) → Bool
survives ksec qs k = andMap (λ x → consist ksec x k) qs

------------------------------------------------------------------------
--  Prove general facts about conjunction over lists.

andMap-true : (f : Vec Bool n → Bool) (qs : List (Vec Bool n)) →
              (∀ x → f x ≡ true) → andMap f qs ≡ true
andMap-true f []       h = refl
andMap-true f (x ∷ xs) h rewrite h x = andMap-true f xs h

andMap-false : (f : Vec Bool n → Bool) (qs : List (Vec Bool n)) (w : Vec Bool n) →
               w ∈ qs → f w ≡ false → andMap f qs ≡ false
andMap-false f (x ∷ xs) w (here refl) fw rewrite fw = refl
andMap-false f (x ∷ xs) w (there mem) fw =
  trans (cong (f x ∧_) (andMap-false f xs w mem fw)) (∧-zeroʳ (f x))

--  Characterise andMap in both directions through list membership. Unlike
--  andMap-true's global premise, these lemmas require the predicate only on
--  the query list, enabling CorruptionTriangle's converse agreement bridge
--  for survives.

∧-both : (a b : Bool) → (a ∧ b) ≡ true → (a ≡ true) × (b ≡ true)
∧-both true  b eq = refl , eq
∧-both false b ()

andMap-true→∈ : (f : Vec Bool n → Bool) (qs : List (Vec Bool n)) →
                andMap f qs ≡ true → (w : Vec Bool n) → w ∈ qs → f w ≡ true
andMap-true→∈ f (x ∷ xs) eq w (here refl) =
  proj₁ (∧-both (f x) (andMap f xs) eq)
andMap-true→∈ f (x ∷ xs) eq w (there mem) =
  andMap-true→∈ f xs (proj₂ (∧-both (f x) (andMap f xs) eq)) w mem

andMap-∈→true : (f : Vec Bool n → Bool) (qs : List (Vec Bool n)) →
                ((w : Vec Bool n) → w ∈ qs → f w ≡ true) → andMap f qs ≡ true
andMap-∈→true f []       h = refl
andMap-∈→true f (x ∷ xs) h rewrite h x (here refl) =
  andMap-∈→true f xs (λ w mem → h w (there mem))

------------------------------------------------------------------------
--  Establish properties of point indicators.

prot0-self : (k : Vec Bool n) → prot 0 k k ≡ true
prot0-self k = cong (_≡ᵇ 0) (HD-refl k)

--  The secret agrees with itself on every input.
consist-self : (ksec x : Vec Bool n) → consist ksec x ksec ≡ true
consist-self ksec x = cong not (xor-self (prot 0 ksec x))

--  Querying a wrong candidate's own key makes it inconsistent.
consist-kill : (ksec k : Vec Bool n) → k ≢ ksec → consist ksec k k ≡ false
consist-kill ksec k k≢ksec =
  cong not (cong₂ _xor_ (prot0-self k) (prot0-false k ksec k≢ksec))

------------------------------------------------------------------------
--  Show allVecs contains every input vector, ensuring the query x = k occurs.

∈-allVecs : (v : Vec Bool n) → v ∈ allVecs n
∈-allVecs {zero}  []           = here refl
∈-allVecs {suc n} (false ∷ v)  = ∈-++⁺ˡ (∈-map⁺ (false ∷_) (∈-allVecs v))
∈-allVecs {suc n} (true  ∷ v)  = ∈-++⁺ʳ _ (∈-map⁺ (true ∷_) (∈-allVecs v))

------------------------------------------------------------------------
--  Pruning over the entire input enumeration leaves only the secret.

survives-ksec : (ksec : Vec Bool n) → survives ksec (allVecs n) ksec ≡ true
survives-ksec ksec =
  andMap-true (λ x → consist ksec x ksec) (allVecs _) (consist-self ksec)

survives-only-ksec : (ksec k : Vec Bool n) → k ≢ ksec →
                     survives ksec (allVecs n) k ≡ false
survives-only-ksec ksec k k≢ksec =
  andMap-false (λ x → consist ksec x k) (allVecs _) k
               (∈-allVecs k) (consist-kill ksec k k≢ksec)

--  Prove the secret is the unique surviving candidate of the verified attack.
dipAttack-recovers :
  (ksec k : Vec Bool n) →
  (k ≡ ksec → survives ksec (allVecs n) k ≡ true) ×
  (k ≢ ksec → survives ksec (allVecs n) k ≡ false)
dipAttack-recovers ksec k = recoverEq , survives-only-ksec ksec k
  where
    recoverEq : k ≡ ksec → survives ksec (allVecs _) k ≡ true
    recoverEq refl = survives-ksec ksec

--  Count |allVecs n| = 2ⁿ queries. Combined with the ≥ 2ⁿ−1 lower bound,
--  this establishes Θ(2ⁿ) point-lock recovery complexity.
dipAttack-queries : (m : ℕ) → length (allVecs m) ≡ 2 ^ m
dipAttack-queries m = length-allVecs m
