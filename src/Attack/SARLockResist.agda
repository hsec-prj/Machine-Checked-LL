------------------------------------------------------------------------
--  Prove a SARLock query lower bound complementary to FALL recovery.
--  Attack.FunctionalAnalysis recovers SFLL-HD keys in n queries. Here SARLock
--  resists the same budget-indexed adversary, quantifying the contrasting
--  behaviour. With fixed design secret s and host f,
--  actSAR s f k x = locked 0 s k f x = (f x xor prot 0 s x) xor prot 0 k x.
--  The applied key influences only prot 0 k x = (x = k). Thus two distinct
--  applied keys yield oracles differing only at those two key inputs,
--  matching Security.SARLock's OCR ≤ 2. Probes avoiding both cannot
--  distinguish them; QueryLowerBound turns this into failed recovery.
--  A non-adaptive SARLock adversary must therefore probe all but at most one
--  key, an exponential 2ⁿ-scale budget expressing SAT resistance.
--  SARLock-resist is structural and unconditional in n. zeroQueryFails
--  shows even a one-bit secret cannot be uniformly recovered with no queries.
--  The quantitative implication q < 2ⁿ − 1 → an unprobed pair exists remains
--  the next pigeonhole step over Util.Counting.allVecs/length-allVecs.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.SARLockResist where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; false; true; _xor_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality
  using (_≡_; cong; sym; trans; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HD using (locked; prot)
open import Security.AntiSat using (prot0-false)
open import Attack.Oracle using (QAdversary; Recovers)
open import Attack.QueryLowerBound using (resist-off-diag)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  View the SARLock function as an oracle family indexed by applied key,
--  with design secret s and base function f fixed in the netlist.

actSAR : (s : Vec Bool n) (f : Vec Bool n → Bool) →
         Vec Bool n → Vec Bool n → Bool
actSAR s f k x = locked 0 s k f x

------------------------------------------------------------------------
--  Applied keys agree outside their singleton points {k₁, k₂}, because their
--  sole key-dependent term prot 0 k x is false whenever x differs from k.

actSAR-agree : (s : Vec Bool n) (f : Vec Bool n → Bool) (k₁ k₂ x : Vec Bool n) →
               x ≢ k₁ → x ≢ k₂ →
               actSAR s f k₁ x ≡ actSAR s f k₂ x
actSAR-agree s f k₁ k₂ x x≢k₁ x≢k₂ =
  cong (λ b → (f x xor prot 0 s x) xor b)
       (trans (prot0-false x k₁ x≢k₁) (sym (prot0-false x k₂ x≢k₂)))

------------------------------------------------------------------------
--  Structurally, two distinct unprobed applied keys prevent recovery by any
--  non-adaptive adversary with that q-probe set.

SARLock-resist :
  ∀ {q} (s : Vec Bool n) (f : Vec Bool n → Bool)
    (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) {k₁ k₂ : Vec Bool n} →
    k₁ ≢ k₂ →
    (∀ i → lookup (QAdversary.probes A) i ≢ k₁) →
    (∀ i → lookup (QAdversary.probes A) i ≢ k₂) →
    ¬ Recovers A (actSAR s f)
SARLock-resist s f A ne p₁ p₂ =
  resist-off-diag (actSAR s f) (actSAR-agree s f) A ne p₁ p₂

------------------------------------------------------------------------
--  With no probes, the distinct one-bit keys 0 and 1 are both unqueried,
--  so even a one-bit secret cannot be recovered by a zero-query adversary.

zeroQueryFails : (s : Vec Bool 1) (f : Vec Bool 1 → Bool)
                 (A : QAdversary (Vec Bool 1) Bool (Vec Bool 1) 0) →
                 ¬ Recovers A (actSAR s f)
zeroQueryFails s f A =
  SARLock-resist s f A {false ∷ []} {true ∷ []} 0≢1 (λ ()) (λ ())
  where
    0≢1 : (false ∷ []) ≢ (true ∷ [])
    0≢1 ()
