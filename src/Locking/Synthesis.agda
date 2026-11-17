------------------------------------------------------------------------
--  Construct CertifiedScheme from a supplied Circuit denoting f, a
--  radius h, and a secret/applied key pair at odd Hamming distance.
--  SFLL.Netlist supplies denotation correctness; OCR-odd supplies exact
--  corruption 2·C(n,h). The resist field is the corresponding minimum
--  tolerance for ApproxKey at this supplied pair, not an adversary bound.
--  synth-meets-spec projects soundness. synth-on-frontier equates
--  CostProfile.rate with the certified ocrValue; it does not prove global
--  optimality over lock implementations, attacks, or synthesis tools.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.Synthesis where

open import Data.Nat using (ℕ; _+_; _≤_)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import SFLL.HD using (locked)
open import SFLL.HammingDistance using (HD; parity)
open import SFLL.Netlist using (locked-circuit; locked-circuit-correct)
open import Util.Counting using (binom)
open import Security.OCR using (OCR; OCR-odd)
open import Attack.AppSAT using (ApproxKey; SFLL-approx-needs)
open import Attack.Frontier using (profile-of; CostProfile)
open import Attack.Frontier using (SFLL-rate-odd)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Bundle a locked netlist, its denotation and exact corruption count,
--  and the associated tolerance floor for this supplied key pair.

record CertifiedScheme (h : ℕ) (ksec kapp : Vec Bool n)
                       (f : Vec Bool n → Bool) : Set where
  field
    --  Store the synthesised gate-level circuit.
    netlist  : Circuit n 1
    --  Prove its denotation equals the SFLL-HD locked function.
    sound    : (x : Vec Bool n) → ⟦ netlist ⟧ x ≡ locked h ksec kapp f x ∷ []
    --  Record the certified output corruption rate.
    ocrValue : ℕ
    --  Establish exact agreement with that rate.
    meetsOCR : OCR h ksec kapp ≡ ocrValue
    --  Require ApproxKey at this supplied pair to tolerate at least ocrValue.
    resist   : {ε : ℕ} → ApproxKey h ksec kapp f ε → ocrValue ≤ ε

------------------------------------------------------------------------
--  Generate a certified SFLL-HD scheme with radius h.

synthSFLL :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp : Vec Bool n) →
  parity (HD ksec kapp) ≡ true →
  CertifiedScheme h ksec kapp f
synthSFLL {n} Cf f cf-ok h ksec kapp odd = record
  { netlist  = locked-circuit Cf h ksec kapp
  ; sound    = locked-circuit-correct Cf f cf-ok h ksec kapp
  ; ocrValue = binom n h + binom n h
  ; meetsOCR = OCR-odd h ksec kapp odd
  ; resist   = SFLL-approx-needs h ksec kapp f odd
  }

------------------------------------------------------------------------
--  Expose soundness: synthesis satisfies the specification by construction.

synth-meets-spec :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp : Vec Bool n) (odd : parity (HD ksec kapp) ≡ true)
  (x : Vec Bool n) →
  ⟦ CertifiedScheme.netlist (synthSFLL Cf f cf-ok h ksec kapp odd) ⟧ x
  ≡ locked h ksec kapp f x ∷ []
synth-meets-spec Cf f cf-ok h ksec kapp odd =
  CertifiedScheme.sound (synthSFLL Cf f cf-ok h ksec kapp odd)

------------------------------------------------------------------------
--  Identify CostProfile.rate with the generated record's certified OCR value.

synth-on-frontier :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp : Vec Bool n) (odd : parity (HD ksec kapp) ≡ true) →
  CostProfile.rate (profile-of h ksec kapp f)
  ≡ CertifiedScheme.ocrValue (synthSFLL Cf f cf-ok h ksec kapp odd)
synth-on-frontier Cf f cf-ok h ksec kapp odd = SFLL-rate-odd h ksec kapp f odd
