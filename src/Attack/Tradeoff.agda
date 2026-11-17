------------------------------------------------------------------------
--  Connect scheme-wide OCR calculations with query lower bounds to state
--  the corruption no-free-lunch principle. The two endpoint constructions
--  read OCR in opposing ways for exact and approximate recovery. Low
--  corruption hides wrong keys and, with off-diagonality, yields the
--  exponential ExactResist bound through query-lb-off-diag. It also makes
--  every key an ε-approximate key for small ε, so NoFreeLunch.approx
--  gives recovery by every zero-query adversary. At the SFLL-HD endpoint,
--  SFLL-approx-floor uses SFLL-approx-needs to require 2·C(n,h) ≤ ε,
--  while FALL sensitises the same spheres to recover the exact key in n
--  queries (Attack.FunctionalAnalysis.FALL-recovers-key-full). These are
--  opposite corners: approximate resistance versus exact vulnerability.
--  NoFreeLunch packages the conjunction. mkNoFreeLunch accepts an
--  off-diagonal scheme and uniform corruption bound c, making SARLock
--  with c = 2 one instance of a reusable schema for Anti-SAT and other
--  radius-zero corners. Reuse disagreeCount≡OCR and query-lb-off-diag
--  without another proof engine. Only the stated one-way implication
--  from low corruption to exact resistance and trivial approximation is
--  claimed under these hypotheses. High exact resistance need not imply
--  low corruption generally, so the conjunction at the endpoints is not
--  a global biconditional. Keep off-diagonality and the corruption bound
--  separate, although both reflect SARLock's minimal-corruption structure.
--  Introduce neither primitives nor postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.Tradeoff where

open import Data.Nat using (ℕ; _+_; _^_; _≤_)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec; [])
open import Relation.Binary.PropositionalEquality using (_≡_; refl; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (binom)
open import Attack.Oracle using (QAdversary; Recovers)
open import Attack.SARLockQueryBound using (query-lb-off-diag)
open import Attack.SARLockResist using (actSAR; actSAR-agree)
open import Attack.AppSAT
  using (ApproxKey; disagreeCount; SARLock-approx-any; SFLL-approx-needs)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Package query-lb-off-diag as an oracle-family property suitable for
--  NoFreeLunch: no adversary recovers the exact key when 2 + q ≤ 2ⁿ
--  leaves two keys unprobed.

ExactResist : (Vec Bool n → Vec Bool n → Bool) → Set
ExactResist {n} act =
  ∀ {q} (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
    2 + q ≤ 2 ^ n → ¬ Recovers A act

--  Apply the bound directly to an off-diagonal family, where distinct
--  keys can differ only on the two inputs equal to those keys.
offdiag→ExactResist :
  (act : Vec Bool n → Vec Bool n → Bool)
  (agree : (k₁ k₂ x : Vec Bool n) → x ≢ k₁ → x ≢ k₂ → act k₁ x ≡ act k₂ x) →
  ExactResist act
offdiag→ExactResist act agree A bound = query-lb-off-diag act agree A bound

------------------------------------------------------------------------
--  Extract the fixed output of a zero-query adversary. Its decoder sees
--  only an empty answer vector and ignores the oracle, yet this cheapest
--  attacker suffices for the approximate-recovery side.

guess0 : QAdversary (Vec Bool n) Bool (Vec Bool n) 0 → Vec Bool n
guess0 A = QAdversary.decode A []

------------------------------------------------------------------------
--  Combine exact resistance with free c-approximate recovery by every
--  zero-query adversary under corruption bound c.

record NoFreeLunch (act : Vec Bool n → Vec Bool n → Bool)
                   (h : ℕ) (f : Vec Bool n → Bool) (c : ℕ) : Set where
  field
    --  Exact recovery requires exponentially many queries.
    exact  : ExactResist act
    --  All zero-query adversaries recover all secrets up to tolerance c.
    approx : (A : QAdversary (Vec Bool n) Bool (Vec Bool n) 0)
             (ksec : Vec Bool n) → ApproxKey h ksec (guess0 A) f c

--  Build both properties from two separate premises: off-diagonality
--  gives exact resistance, and ∀ ksec kapp → disagreeCount h ksec kapp f ≤ c
--  makes every guess c-approximate. Keep these aspects of minimal corruption
--  as hypotheses rather than asserting a biconditional.
mkNoFreeLunch :
  (act : Vec Bool n → Vec Bool n → Bool)
  (agree : (k₁ k₂ x : Vec Bool n) → x ≢ k₁ → x ≢ k₂ → act k₁ x ≡ act k₂ x)
  {h : ℕ} {f : Vec Bool n → Bool} {c : ℕ}
  (bound : (ksec kapp : Vec Bool n) → ApproxKey h ksec kapp f c) →
  NoFreeLunch act h f c
mkNoFreeLunch act agree bound = record
  { exact  = offdiag→ExactResist act agree
  ; approx = λ A ksec → bound ksec (guess0 A)
  }

------------------------------------------------------------------------
--  Instantiate the first endpoint with radius-zero SARLock and c = 2.
--  actSAR-agree proves off-diagonality; SARLock-approx-any makes every
--  key 2-approximate by reading OCR ≤ 2 through disagreeCount≡OCR.
--  Exact resistance therefore accompanies free approximate recovery.

SARLock-no-free-lunch :
  (s : Vec Bool n) (f : Vec Bool n → Bool) → NoFreeLunch (actSAR s f) 0 f 2
SARLock-no-free-lunch s f =
  mkNoFreeLunch (actSAR s f) (actSAR-agree s f)
                (λ ksec kapp → SARLock-approx-any ksec kapp f)

------------------------------------------------------------------------
--  At the opposite endpoint, odd-distance SFLL-HD with radius h requires
--  2·C(n,h) ≤ ε for an ε-approximate key. FALL-recovers-key-full still
--  breaks exact recovery, giving the approximation-resistant,
--  exact-vulnerable counterpart to SARLock.

SFLL-approx-floor :
  (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
  parity (HD ksec kapp) ≡ true →
  {ε : ℕ} → ApproxKey h ksec kapp f ε → binom n h + binom n h ≤ ε
SFLL-approx-floor = SFLL-approx-needs

------------------------------------------------------------------------
--  For n = 4, SARLock admits constant tolerance 2, whereas radius-two
--  SFLL-HD requires tolerance at least 12. The endpoints trade exact
--  resistance against trivial approximate recovery as corruption changes.

_ : binom 4 0 + binom 4 0 ≡ 2
_ = refl

_ : binom 4 2 + binom 4 2 ≡ 12
_ = refl
