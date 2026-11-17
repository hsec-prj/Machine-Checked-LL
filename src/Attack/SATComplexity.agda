------------------------------------------------------------------------
--  Derive SAT-attack cost from corruption structure (Tier 1, 1b).
--  Attack.SATAttack.SARLock-SAT-lb requires approximately 2ⁿ-key enumeration
--  for SARLock. This module identifies the sufficient generic property:
--  off-diagonal agreement, meaning act k equals a reference base except
--  possibly at k. This formalises point-concentrated, low-OCR corruption as
--  in SARLock/Anti-SAT. Each DIP can remove at most the key equal to its
--  input, requiring enumeration. offdiag-SAT-lb proves that q DIP queries
--  avoiding the secret leave at least two distinct keys consistent with
--  every answer when 2 + q ≤ 2ⁿ. Eliminating at most one wrong key per DIP
--  requires at least 2ⁿ − 1 DIPs for recovery; SARLock-SAT-lb instantiates
--  this result. This proves one direction of the corruption/resistance
--  trade-off: off-diagonal point corruption implies exponential SAT cost.
--  No converse is claimed. SFLL-HD's high-corruption spheres let DIPs prune
--  many keys, explaining its FALL vulnerability; see Attack.SATAttack.
--  No primitives or postulates are added.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.SATComplexity where

open import Data.Nat using (ℕ; _+_; _^_; _≤_)
open import Data.Bool using (Bool)
open import Data.Fin using (Fin)
open import Data.Vec using (Vec; lookup)
open import Data.Product using (_×_; _,_; ∃; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; trans; sym; _≢_)

open import Attack.SATAttack using (consistentOn)
open import Attack.SARLockResist using (actSAR)
open import Attack.Adaptive using (baseSAR; baseSAR-off)
open import Attack.SARLockQueryBound using (unprobed-pair)

private
  variable
    n q : ℕ

------------------------------------------------------------------------
--  Off-diagonal agreement preserves an unqueried candidate k. Each probe xᵢ
--  avoids k and the secret, so both act k xᵢ and act ksec xᵢ equal base xᵢ.

offdiag-consistent :
  (act : Vec Bool n → Vec Bool n → Bool) (base : Vec Bool n → Bool) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (ksec : Vec Bool n) (xs : Vec (Vec Bool n) q) (k : Vec Bool n) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  ((i : Fin q) → lookup xs i ≢ k) →
  consistentOn act ksec xs k
offdiag-consistent act base off ksec xs k avoid-sec avoid-k i =
  trans (sym (off k    (lookup xs i) (avoid-k   i)))
        (     off ksec (lookup xs i) (avoid-sec i))

------------------------------------------------------------------------
--  For an off-diagonal point-corruption family, the generic bound leaves at
--  least two SAT-consistent keys after q < 2ⁿ − 1 distinguishing probes.

offdiag-SAT-lb :
  (act : Vec Bool n → Vec Bool n → Bool) (base : Vec Bool n → Bool) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (ksec : Vec Bool n) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOn act ksec xs k₁
    × consistentOn act ksec xs k₂
offdiag-SAT-lb act base off ksec xs avoid-sec bound =
  k₁ , k₂ , ne ,
  offdiag-consistent act base off ksec xs k₁ avoid-sec p₁ ,
  offdiag-consistent act base off ksec xs k₂ avoid-sec p₂
  where
    up = unprobed-pair xs bound
    k₁ = proj₁ up
    k₂ = proj₁ (proj₂ up)
    ne = proj₁ (proj₂ (proj₂ up))
    p₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    p₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))

------------------------------------------------------------------------
--  Instantiate the generic theorem with SARLock: baseSAR-off establishes
--  off-diagonal agreement from its point-function corruption.

SARLock-SAT-lb-offdiag :
  (s : Vec Bool n) (f : Vec Bool n → Bool) (ksec : Vec Bool n)
  (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOn (actSAR s f) ksec xs k₁
    × consistentOn (actSAR s f) ksec xs k₂
SARLock-SAT-lb-offdiag s f ksec xs avoid-sec bound =
  offdiag-SAT-lb (actSAR s f) (baseSAR s f) (baseSAR-off s f) ksec xs avoid-sec bound
