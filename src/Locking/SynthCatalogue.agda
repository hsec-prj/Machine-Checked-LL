------------------------------------------------------------------------
--  Synthesize certified locks across the catalogue. Locking.Synthesis
--  generates SFLL-HD netlists with soundness, OCR, and resistance proofs.
--  Give the remaining schemes, whose circuits and counts already appear in
--  NetlistCatalogue and Security.{SARLock,AntiSat,OCR}, a shared interface.
--  CertifiedLock contains a gate-level netlist, soundness
--  ⟦ netlist ⟧ ≡ denotes, and ocrBound/meetsOCR for a closed corruption
--  bound. The bounds are Anti-SAT 1 via OCR-AntiSat, SARLock 2 via
--  OCR-SARLock-≤2, and SFLL-HD 2·C(n,h) via unconditional OCR-upper over
--  all key pairs. These are corruption bounds for the constructed terms.
--  Resistance statements remain separate and family-specific:
--  certSARLock-resist uses the bounded Boolean-oracle ExactResist model;
--  certSFLL-approx-resist is an odd-distance corruption floor for the
--  supplied key pair. Neither asserts general attack resistance.
--  This catalogue builds SFLL-HD, SARLock, and Anti-SAT; it includes no
--  compiler for SFLL.Flex's arbitrary semantic predicate.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.SynthCatalogue where

open import Data.Nat using (ℕ; _+_; _^_; _≤_)
open import Data.Nat.Properties using (≤-reflexive)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_)
open import Relation.Nullary using (¬_)

open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import SFLL.HD using (locked)
open import SFLL.HammingDistance using (HD; parity)
open import SFLL.Netlist using (locked-circuit; locked-circuit-correct)
open import Locking.NetlistCatalogue
  using (sarLocked-circuit; sarLocked-circuit-correct;
         antiSat-circuit; antiSat-circuit-correct)
open import Util.Counting using (countT; allVecs; binom)
open import Security.OCR using (corrupt; OCR; OCR-upper)
open import Security.SARLock using (sarLocked; OCR-SARLock-≤2)
open import Security.AntiSat using (antiSat; OCR-AntiSat)
open import Attack.AppSAT using (ApproxKey; SFLL-approx-needs)
open import Attack.Oracle using (QAdversary; Recovers)
open import Attack.SARLockResist using (actSAR)
open import Attack.SARLockQueryBound using (SARLock-query-lb)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Define the common interface: circuit, denoted function, soundness proof,
--  and a closed corruption-count bound.

record CertifiedLock (n : ℕ) : Set where
  field
    netlist  : Circuit n 1
    denotes  : Vec Bool n → Bool
    sound    : (x : Vec Bool n) → ⟦ netlist ⟧ x ≡ denotes x ∷ []
    corrupts : Vec Bool n → Bool
    ocrBound : ℕ
    meetsOCR : countT corrupts (allVecs n) ≤ ocrBound

------------------------------------------------------------------------
--  Place SFLL-HD in the common interface with OCR-upper for every key pair,
--  achieving equality at odd distance.

certSFLL : (Cf : Circuit n 1) (f : Vec Bool n → Bool)
           (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
           (h : ℕ) (ksec kapp : Vec Bool n) → CertifiedLock n
certSFLL {n} Cf f cf-ok h ksec kapp = record
  { netlist  = locked-circuit Cf h ksec kapp
  ; denotes  = locked h ksec kapp f
  ; sound    = locked-circuit-correct Cf f cf-ok h ksec kapp
  ; corrupts = corrupt h ksec kapp
  ; ocrBound = binom n h + binom n h
  ; meetsOCR = OCR-upper h ksec kapp
  }

------------------------------------------------------------------------
--  Generate SARLock as radius-zero SFLL, bounded by two corrupted inputs
--  for every n.

certSARLock : (Cf : Circuit n 1) (f : Vec Bool n → Bool)
              (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
              (ksec kapp : Vec Bool n) → CertifiedLock n
certSARLock Cf f cf-ok ksec kapp = record
  { netlist  = sarLocked-circuit Cf ksec kapp
  ; denotes  = sarLocked ksec kapp f
  ; sound    = sarLocked-circuit-correct Cf f cf-ok ksec kapp
  ; corrupts = corrupt 0 ksec kapp
  ; ocrBound = 2
  ; meetsOCR = OCR-SARLock-≤2 ksec kapp
  }

------------------------------------------------------------------------
--  Generate the Anti-SAT complement-pair AND block. Distinct keys corrupt
--  one input, the catalogue's smallest corruption value.

certAntiSat : (k1 k2 : Vec Bool n) → k1 ≢ k2 → CertifiedLock n
certAntiSat k1 k2 ne = record
  { netlist  = antiSat-circuit k1 k2
  ; denotes  = antiSat k1 k2
  ; sound    = antiSat-circuit-correct k1 k2
  ; corrupts = antiSat k1 k2
  ; ocrBound = 1
  ; meetsOCR = ≤-reflexive (OCR-AntiSat k1 k2 ne)
  }

------------------------------------------------------------------------
--  Provide resistance results separately with their family-specific types.

--  Use SARLock's off-diagonal structure to exclude exact recovery whenever
--  the budget leaves two keys unprobed, giving the exponential bound.
certSARLock-resist :
  ∀ {q} (ksec : Vec Bool n) (f : Vec Bool n → Bool)
    (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
    2 + q ≤ 2 ^ n → ¬ Recovers A (actSAR ksec f)
certSARLock-resist ksec f A bound = SARLock-query-lb ksec f A bound

--  For odd-distance SFLL-HD, require every ε-approximate key to tolerate
--  at least 2·C(n,h) corruption.
certSFLL-approx-resist :
  (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
  parity (HD ksec kapp) ≡ true →
  {ε : ℕ} → ApproxKey h ksec kapp f ε → binom n h + binom n h ≤ ε
certSFLL-approx-resist h ksec kapp f odd = SFLL-approx-needs h ksec kapp f odd
