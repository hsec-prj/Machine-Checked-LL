------------------------------------------------------------------------
--  Model SAT consistency under DIP pruning and prove SARLock's exponential
--  DIP lower bound. Abstract QAdversary bounds do not directly describe
--  the Subramanyan et al. 2015 loop: maintain candidates, find an input
--  where two disagree, query it, remove inconsistent keys, and stop when
--  no DIP remains. This module formalises its queried-input consistency
--  invariant for actSAR s f ksec. SARLock-DIP-removes-one proves that a
--  non-secret query x can reject only k=x, so each such DIP removes exactly
--  one candidate. SARLock-SAT-lb combines unprobed-pair with actSAR-agree:
--  t queries avoiding the secret with 2+t ≤ 2ⁿ leave at least two distinct
--  keys consistent with all answers. Recovery thus requires ≥ 2ⁿ−1 DIPs,
--  an algorithm-level refinement of SARLock-query-lb. The result relies on
--  SARLock's point-function structure. SFLL-HD distinguishes keys on entire
--  spheres, allowing a DIP to prune many candidates and explaining its FALL
--  vulnerability; no converse claim is made. Reuse off-diagonal agreement
--  and pigeonhole reasoning without new primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.SATAttack where

open import Data.Nat using (ℕ; _+_; _^_; _≤_)
open import Data.Bool using (Bool; true; false; _∧_)
open import Data.Fin using (Fin)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.Product using (_×_; _,_; ∃; proj₁; proj₂)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; cong₂; _≢_)
open import Relation.Nullary using (¬_)

open import Util.BoolVec using (eqVec-sound)
open import Util.BoolVec using (eqVec; eqB; eqVec-false→≢)
open import Attack.SARLockResist using (actSAR; actSAR-agree)
open import Attack.SARLockQueryBound using (∧-true; unprobed-pair)

private
  variable
    n q : ℕ

------------------------------------------------------------------------
--  A candidate is consistent with activated oracle eval ksec on xs when
--  it reproduces every recorded answer. The attack retains exactly these
--  candidates and determines the key when only one remains.

consistentOn : (eval : Vec Bool n → Vec Bool n → Bool) (ksec : Vec Bool n)
               (xs : Vec (Vec Bool n) q) (k : Vec Bool n) → Set
consistentOn eval ksec xs k =
  (i : Fin _) → eval k (lookup xs i) ≡ eval ksec (lookup xs i)

------------------------------------------------------------------------
--  At x ≠ ksec, an inconsistent candidate must equal x. Hence each
--  non-secret DIP removes exactly that point-function key.

SARLock-DIP-removes-one :
  (s : Vec Bool n) (f : Vec Bool n → Bool) (ksec x k : Vec Bool n) →
  x ≢ ksec → actSAR s f k x ≢ actSAR s f ksec x → k ≡ x
SARLock-DIP-removes-one s f ksec x k x≢ksec incon with eqVec x k in eq
... | true  = sym (eqVec-sound x k eq)
... | false =
  ⊥-elim (incon (actSAR-agree s f k ksec x (eqVec-false→≢ x k eq) x≢ksec))

------------------------------------------------------------------------
--  When probes also avoid the secret, off-diagonal agreement preserves
--  every unprobed candidate's consistency.

SARLock-unprobed-consistent :
  (s : Vec Bool n) (f : Vec Bool n → Bool) (ksec : Vec Bool n)
  (xs : Vec (Vec Bool n) q) (k : Vec Bool n) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  ((i : Fin q) → lookup xs i ≢ k) →
  consistentOn (actSAR s f) ksec xs k
SARLock-unprobed-consistent s f ksec xs k avoid-sec avoid-k i =
  actSAR-agree s f k ksec (lookup xs i) (avoid-k i) (avoid-sec i)

------------------------------------------------------------------------
--  After t secret-avoiding DIPs with 2+t ≤ 2ⁿ, retain at least two distinct
--  consistent keys. Since each DIP eliminates one wrong candidate, determining
--  the secret requires exponentially many queries.

SARLock-SAT-lb :
  (s : Vec Bool n) (f : Vec Bool n → Bool) (ksec : Vec Bool n)
  (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOn (actSAR s f) ksec xs k₁
    × consistentOn (actSAR s f) ksec xs k₂
SARLock-SAT-lb s f ksec xs avoid-sec bound =
  k₁ , k₂ , ne ,
  SARLock-unprobed-consistent s f ksec xs k₁ avoid-sec p₁ ,
  SARLock-unprobed-consistent s f ksec xs k₂ avoid-sec p₂
  where
    up = unprobed-pair xs bound
    k₁ = proj₁ up
    k₂ = proj₁ (proj₂ up)
    ne = proj₁ (proj₂ (proj₂ up))
    p₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    p₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))
