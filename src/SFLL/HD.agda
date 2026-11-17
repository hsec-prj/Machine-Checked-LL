------------------------------------------------------------------------
--  SFLL-HD semantics: strip protected inputs and restore them
--  SFLL-HD^h protects precisely the inputs at Hamming distance `h` from
--  the secret key. Its semantic model uses `f : Vec Bool n → Bool` with
--  one output: Paper 2's corruption analysis is combinatorial and semantic,
--  independent of the gate-level popcount comparator implementing `prot`.
--  `prot h k x` asks whether `x` is protected for `k`, namely HD x k = h.
--  `stripped` is f x xor prot h ksec x, flipping the secret's protected inputs.
--  `restore` is prot h kapp x, supplying the applied key's correction.
--  The locked output is stripped xor restore.
--  `SFLL_correct` establishes the straightforward correct-key case:
--  when kapp = ksec, restoration cancels stripping and the output equals `f`.
--  The more difficult wrong-key corruption lower bound appears in `Security.OCR`.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.HD where

open import Data.Nat using (ℕ; _≡ᵇ_)
open import Data.Bool using (Bool; false; true; _xor_)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import SFLL.HammingDistance using (HD)

private
  variable
    n : ℕ

--  Test whether the Hamming distance from `x` to `k` is exactly `h`.
--  Using natural-number `_≡ᵇ_` instead of `⌊ _ ≟ _ ⌋` makes the sphere
--  counting steps in `Security.OCR` definitionally reducible: `suc m ≡ᵇ suc h`
--  reduces to `m ≡ᵇ h`, whereas the alternative comparison does not.
prot : ℕ → Vec Bool n → Vec Bool n → Bool
prot h k x = HD x k ≡ᵇ h

--  Compute the SFLL-HD output by stripping `f` on the secret's protected
--  inputs and applying the restoration selected by the supplied key.
locked : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
         Vec Bool n → Bool
locked h ksec kapp f x = (f x xor prot h ksec x) xor prot h kapp x

------------------------------------------------------------------------
--  Functional correctness with the matching key

--  When both keys coincide, `(a xor b) xor b ≡ a` cancels the stripping mask.
xor-cancel : (a b : Bool) → (a xor b) xor b ≡ a
xor-cancel false false = refl
xor-cancel false true  = refl
xor-cancel true  false = refl
xor-cancel true  true  = refl

SFLL_correct : (h : ℕ) (ksec : Vec Bool n) (f : Vec Bool n → Bool)
               (x : Vec Bool n) →
               locked h ksec ksec f x ≡ f x
SFLL_correct h ksec f x = xor-cancel (f x) (prot h ksec x)
