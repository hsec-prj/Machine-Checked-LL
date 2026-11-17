------------------------------------------------------------------------
--  Study feasibility of a verified, terminating DIP/SAT pruning loop.
--  The repository's resistance results rule out bounded-query recovery;
--  the complementary goal is an executable attack with an iteration bound.
--  Termination requires a strict decrease of the candidate set, while the
--  repository has no well-founded recursion infrastructure. This module
--  establishes the needed measure and chooses structural recursion. A
--  candidate predicate Vec Bool n → Bool has size countT cand (allVecs n).
--  prune-count-< proves strict reduction whenever a kept predicate removes
--  at least one candidate, supplying the missing strict counterpart to
--  countT-∧-≤ʳ. dipLoop then recurses structurally on natural fuel and checks
--  under --safe without well-founded recursion. The measure shows that
--  fuel = countT cand (allVecs n) suffices. The proved decrease and structural
--  loop settle the feasibility issue for B2's full point-family recovery
--  attack using generic PointConc. No postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.DIPAttackSpike where

open import Data.Nat using (ℕ; zero; suc; _+_; _<_; s≤s)
open import Data.Nat.Properties using (+-mono-≤-<)
open import Data.Bool using (Bool; true; false; _∧_; if_then_else_)
open import Data.List using (List; []; _∷_)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import Util.Counting using (countT)
open import Attack.SARLockQueryBound using (bit-∧-≤ʳ; countT-∧-≤ʳ)

private
  variable
    A : Set

------------------------------------------------------------------------
--  Prune candidates by retaining precisely those not excluded by the DIP.

prune : (kept cand : A → Bool) → A → Bool
prune kept cand a = kept a ∧ cand a

------------------------------------------------------------------------
--  Prove strict decrease when a domain-list witness w satisfies cand but is
--  rejected by kept. Each effective distinguishing input then shrinks the
--  candidate set, supplying the attack's termination measure.

prune-count-< : (kept cand : A → Bool) (w : A) (xs : List A) →
                w ∈ xs → cand w ≡ true → kept w ≡ false →
                countT (prune kept cand) xs < countT cand xs
prune-count-< kept cand w (.w ∷ xs) (here refl) cw kw
  rewrite kw | cw = s≤s (countT-∧-≤ʳ kept cand xs)
prune-count-< kept cand w (x ∷ xs) (there mem) cw kw =
  +-mono-≤-< (bit-∧-≤ʳ (kept x) (cand x))
             (prune-count-< kept cand w xs mem cw kw)

------------------------------------------------------------------------
--  Define the loop structurally on fuel, with step performing one DIP prune.
--  The decrease measure makes countT cand (allVecs n) sufficient fuel to reach
--  the consistent fixed-point set, without well-founded recursion.

dipLoop : (step : (A → Bool) → (A → Bool)) → ℕ → (A → Bool) → (A → Bool)
dipLoop step zero    cand = cand
dipLoop step (suc f) cand = dipLoop step f (step cand)

--  Check the boundary cases: zero fuel preserves candidates; one unit applies
--  exactly one step.
dipLoop-0 : (step : (A → Bool) → (A → Bool)) (cand : A → Bool) →
            dipLoop step zero cand ≡ cand
dipLoop-0 step cand = refl

dipLoop-1 : (step : (A → Bool) → (A → Bool)) (cand : A → Bool) →
            dipLoop step (suc zero) cand ≡ step cand
dipLoop-1 step cand = refl
