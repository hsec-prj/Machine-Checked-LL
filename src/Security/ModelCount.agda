------------------------------------------------------------------------
--  Closed-form OCR as exact #SAT model counting (Tier 1, 1b)
--  By definition, the corruption rate here counts inputs among all 2ⁿ
--  assignments satisfying `corrupt h ksec kapp`. This is model counting,
--  or #SAT, a #P-complete problem in general. `OCR-odd`, `OCR-far`, and
--  `OCR-even` supply exact closed forms, avoiding a model counter that
--  would time out at the relevant cube widths.
--  The module exposes that interpretation through three results:
--  * `OCR-is-modelCount` identifies OCR with the model count of `corrupt`.
--  * `modelCount-corrupt-odd` gives `2·C(n,h)` without a solver at odd
--  distance, with the far-distance counterpart supplied below.
--  * `modelCount-corrupt-far` gives the same count for centres separated
--  by more than `2h`.
--  These results require neither a new primitive nor a postulate.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.ModelCount where

open import Data.Nat using (ℕ; _+_; _≤_; _<_)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import Util.Counting using (countT; allVecs; binom)
open import SFLL.HammingDistance using (HD; parity)
open import Security.OCR using (corrupt; OCR; OCR-odd; OCR-far)

private
  variable
    n : ℕ

--  Count all satisfying assignments of a Boolean predicate on the 2ⁿ-input cube (#SAT).
modelCount : (Vec Bool n → Bool) → ℕ
modelCount {n} p = countT p (allVecs n)

--  Counting corrupted inputs is precisely counting models of `corrupt`:
--  the OCR and this model count are equal by definition.
OCR-is-modelCount : (h : ℕ) (ksec kapp : Vec Bool n) →
                    OCR h ksec kapp ≡ modelCount (corrupt h ksec kapp)
OCR-is-modelCount h ksec kapp = refl

--  At odd distance the exact #SAT count is `2·C(n,h)`, with no model
--  counter required because modelCount(corrupt) is definitionally OCR.
modelCount-corrupt-odd : (h : ℕ) (k k' : Vec Bool n) → parity (HD k k') ≡ true →
                         modelCount (corrupt h k k') ≡ binom n h + binom n h
modelCount-corrupt-odd h k k' odd = OCR-odd h k k' odd

--  The same count holds in the disjoint far case, where the distance exceeds `2h`.
modelCount-corrupt-far : (h : ℕ) (k k' : Vec Bool n) → h + h < HD k k' →
                         modelCount (corrupt h k k') ≡ binom n h + binom n h
modelCount-corrupt-far h k k' far = OCR-far h k k' far
