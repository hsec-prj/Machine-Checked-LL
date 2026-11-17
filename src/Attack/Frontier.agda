------------------------------------------------------------------------
--  Describe an achievable region for the two-sided corruption trade-off.
--  Attack.Tradeoff combines exact resistance with trivial approximation at
--  the SARLock endpoint, and approximation resistance with broken exact
--  recovery at SFLL. Extend those examples to realised cost profiles.
--  For one secret/applied-key pair, OCR h ksec kapp, bypass-cost h ksec kapp,
--  and disagreeCount h ksec kapp f express corruption, removal-table size,
--  and approximate disagreement. bypass-cost≡OCR and disagreeCount≡OCR
--  identify all three definitionally; CostProfile stores their common rate.
--  For off-diagonal schemes, FrontierPoint also carries ExactResist from
--  query-lb-off-diag and removalSound from bypass-correct. Thus a correction
--  table with rate entries restores f on every input, giving an achievable
--  removal upper bound, while exact key recovery has a 2ⁿ-scale lower bound.
--  SARLock-rate-≤2 places SARLock at the cheap-removal, exponential-recovery
--  corner. At odd distance, SFLL-rate-odd gives rate = 2·C(n,h), with costly
--  removal and approximation; FALL-recovers-key-full breaks exact recovery
--  there, so the SFLL profile lacks the exact field. As inherited from –12,
--  the implication is only from low corruption to exact resistance under
--  the stated premises. These triples are achievable; no global biconditional
--  or converse from high exact resistance to low corruption is asserted.
--  Package established equalities without new primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.Frontier where

open import Data.Nat using (ℕ; _+_; _^_; _≤_)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (binom)
open import Security.OCR using (OCR; OCR-odd)
open import Security.SARLock using (OCR-SARLock-≤2)
open import Attack.SARLockResist using (actSAR; actSAR-agree)
open import Attack.AppSAT using (disagreeCount; disagreeCount≡OCR)
open import Attack.Bypass using (bypass; bypass-cost; bypass-cost≡OCR; bypass-correct)
open import Attack.Tradeoff using (ExactResist; offdiag→ExactResist)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Store one OCR value for corruption, removal-table size, and approximate
--  disagreement.

record CostProfile (h : ℕ) (ksec kapp : Vec Bool n)
                   (f : Vec Bool n → Bool) : Set where
  constructor mk-profile
  field
    rate        : ℕ                                  --  shared OCR quantity
    corruption  : OCR h ksec kapp ≡ rate             --  first quantity: corruption rate
    removal     : bypass-cost h ksec kapp ≡ rate     --  second quantity: correction-table size
    approxDisag : disagreeCount h ksec kapp f ≡ rate --  third quantity: approximation floor

--  Construct a profile for every key pair by choosing rate = OCR via refl
--  and transporting the other two quantities through the established bridges.
profile-of : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
             CostProfile h ksec kapp f
profile-of h ksec kapp f = mk-profile
  (OCR h ksec kapp)
  refl
  (bypass-cost≡OCR h ksec kapp)
  (disagreeCount≡OCR h ksec kapp f)

------------------------------------------------------------------------
--  Augment the OCR cost profile with exact-recovery resistance and a
--  witness that a correction of size rate restores f.

record FrontierPoint (act : Vec Bool n → Vec Bool n → Bool)
                     (h : ℕ) (ksec kapp : Vec Bool n)
                     (f : Vec Bool n → Bool) : Set where
  field
    costs        : CostProfile h ksec kapp f
    --  A correction table with rate entries exactly removes the lock,
    --  so the removal upper bound is attained.
    removalSound : (x : Vec Bool n) → bypass h ksec kapp f x ≡ f x
    --  Require a 2ⁿ-scale query budget for exact key recovery.
    exact        : ExactResist act

  --  Expose the common rate used to read the two sides.
  rate : ℕ
  rate = CostProfile.rate costs

------------------------------------------------------------------------
--  Use SARLock at radius zero as the low-corruption endpoint. actSAR-agree
--  supplies off-diagonality and exact resistance, while at most two correction
--  entries restore f: cheap removal coexists with exponential exact recovery.

SARLock-point : (s kapp : Vec Bool n) (f : Vec Bool n → Bool) →
                FrontierPoint (actSAR s f) 0 s kapp f
SARLock-point s kapp f = record
  { costs        = profile-of 0 s kapp f
  ; removalSound = bypass-correct 0 s kapp f
  ; exact        = offdiag→ExactResist (actSAR s f) (actSAR-agree s f)
  }

--  For every width n, SARLock has rate ≤ 2, so its correction table
--  has constant size independent of input width.
SARLock-rate-≤2 : (s kapp : Vec Bool n) (f : Vec Bool n → Bool) →
                  FrontierPoint.rate (SARLock-point s kapp f) ≤ 2
SARLock-rate-≤2 s kapp f = OCR-SARLock-≤2 s kapp

------------------------------------------------------------------------
--  Use odd-distance SFLL-HD as the high-corruption endpoint. Its
--  radius-dependent rate = 2·C(n,h) makes removal and approximation costly.
--  FALL breaks exact recovery, so this endpoint carries only a profile,
--  without an exact field.

SFLL-rate-odd : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
                parity (HD ksec kapp) ≡ true →
                CostProfile.rate (profile-of h ksec kapp f) ≡ binom n h + binom n h
SFLL-rate-odd h ksec kapp f odd = OCR-odd h ksec kapp odd

------------------------------------------------------------------------
--  At n = 4, SARLock has rate 2 with constant removal cost and exponential
--  exact recovery; radius-two SFLL-HD has rate 12 with costly removal and
--  broken exact recovery. These endpoints illustrate the achievable trade-off
--  between exact resistance and cheap removal or approximation.

_ : binom 4 0 + binom 4 0 ≡ 2
_ = refl

_ : binom 4 2 + binom 4 2 ≡ 12
_ = refl
