------------------------------------------------------------------------
--  Extend point recovery to vector-output oracles (D8 frontier 1).
--  PointDIPAttack uses 2ⁿ queries for a single-output key. A multi-output
--  oracle om : key → input → Vec Bool m returns m bits per query. Here
--  consistV uses eqVec to compare the full candidate and secret vectors;
--  pruning over every input recovers exactly the secret when Distinguishing
--  ensures distinct keys differ somewhere. multiDIP-recovers establishes
--  recovery, and multiDIP-queries fixes its cost at 2ⁿ independently of m.
--  More answer bits do not lower this worst-case query count. The combined
--  distortion metric mocr from Security.MultiOCR is a separate axis:
--  recovery depends on key distinguishability rather than the count of
--  inputs flipping an output, so high mocr can accompany hard recovery and
--  low mocr easy recovery. If several keys induce the same vector function,
--  only their observational class is recoverable, analogous to graph-track
--  CycSATComposeFibre; that limit is not reproved here. EfficientLockMulti's
--  lockedVec j has key dependence on one output only and reduces to
--  single-output dipAttack. Distinguishing matters for distinct keys across
--  several outputs. Reuse PointDIPAttack's andMap, andMap-true, andMap-false,
--  and ∈-allVecs, plus Counting's allVecs and length-allVecs.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.MultiPointDIP where

open import Data.Nat using (ℕ; _^_)
open import Data.Bool using (Bool; true; false)
open import Data.Vec using (Vec)
open import Data.List using (List; length)
open import Data.Product using (_×_; _,_; ∃)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong₂; _≢_)
open import Relation.Nullary using (¬_)

open import Util.BoolVec using (eqVec; eqVec-refl; ≢→eqVec-false)
open import Util.Counting using (allVecs; length-allVecs)
open import Attack.PointDIPAttack using (andMap; andMap-true; andMap-false; ∈-allVecs)

private
  variable
    n m : ℕ

------------------------------------------------------------------------
--  Prune multi-output candidates by equality of oracle answer vectors.

--  A candidate k is consistent at x exactly when its entire m-bit answer
--  equals the secret's answer.
consistV : (om : Vec Bool n → Vec Bool n → Vec Bool m) (ksec x k : Vec Bool n) → Bool
consistV om ksec x k = eqVec (om k x) (om ksec x)

survivesV : (om : Vec Bool n → Vec Bool n → Vec Bool m) (ksec : Vec Bool n)
            (qs : List (Vec Bool n)) (k : Vec Bool n) → Bool
survivesV om ksec qs k = andMap (λ x → consistV om ksec x k) qs

--  Require distinct keys to differ at some input, generalising point
--  injectivity to vector observations.
Distinguishing : (om : Vec Bool n → Vec Bool n → Vec Bool m) (ksec : Vec Bool n) → Set
Distinguishing {n = n} om ksec = (k : Vec Bool n) → k ≢ ksec → ∃ λ x → om k x ≢ om ksec x

--  eqVec-refl keeps the secret consistent at every query.
multiDIP-sec : (om : Vec Bool n → Vec Bool n → Vec Bool m) (ksec : Vec Bool n) →
               survivesV om ksec (allVecs n) ksec ≡ true
multiDIP-sec om ksec =
  andMap-true (λ x → consistV om ksec x ksec) (allVecs _) (λ x → eqVec-refl (om ksec x))

--  Exclude a wrong key using its distinguishing input from the enumeration.
multiDIP-kill : (om : Vec Bool n → Vec Bool n → Vec Bool m) (ksec : Vec Bool n) →
                Distinguishing om ksec → (k : Vec Bool n) → k ≢ ksec →
                survivesV om ksec (allVecs n) k ≡ false
multiDIP-kill om ksec dist k k≢ with dist k k≢
... | (x , neq) =
  andMap-false (λ y → consistV om ksec y k) (allVecs _) x (∈-allVecs x)
               (≢→eqVec-false (om k x) (om ksec x) neq)

--  For any distinguishing vector oracle, prove the secret is the only
--  surviving candidate.
multiDIP-recovers : (om : Vec Bool n → Vec Bool n → Vec Bool m) (ksec : Vec Bool n) →
                    Distinguishing om ksec → (k : Vec Bool n) →
                    (k ≡ ksec → survivesV om ksec (allVecs n) k ≡ true)
                    × (k ≢ ksec → survivesV om ksec (allVecs n) k ≡ false)
multiDIP-recovers om ksec dist k = rec , multiDIP-kill om ksec dist k
  where
    rec : k ≡ ksec → survivesV om ksec (allVecs _) k ≡ true
    rec refl = multiDIP-sec om ksec

--  Count 2ⁿ queries independently of m. Extra outputs increase answer width
--  without reducing this worst-case count; Distinguishing governs recovery,
--  while mocr measures a different property.
multiDIP-queries : (w : ℕ) → length (allVecs w) ≡ 2 ^ w
multiDIP-queries = length-allVecs
