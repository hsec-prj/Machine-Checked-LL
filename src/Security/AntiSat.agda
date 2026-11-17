------------------------------------------------------------------------
--  Exact corruption for the complementary Anti-SAT block
--  The AND-type comparator is antiSat k1 k2 x = [x = k1] ∧ ¬[x = k2],
--  with exact matching represented by prot 0 k. This gives the smallest
--  low-corruption example in the analysis. If k1=k2, b ∧ ¬b never fires,
--  so antiSat-correct establishes zero corruption. If k1≠k2, the block
--  fires only at x=k1: there x differs from k2, making the expression
--  pointwise identical to [x=k1]. OCR-AntiSat therefore gives exactly
--  one corrupted input. This is below SARLock's two and far below
--  SFLL-HD's 2inom{n}{h}, illustrating the SAT-resistance/corruption
--  trade-off. The count ≡1 reuses the radius-zero sphere count inom{n}{0}.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.AntiSat where

open import Data.Nat using (ℕ; zero; suc; _≡ᵇ_)
open import Data.Bool using (Bool; true; false; not; _∧_)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; trans; cong)
open import Data.Empty using (⊥-elim)

open import SFLL.HD using (prot)
open import SFLL.HammingDistance using (HD; HD0→≡)
open import Util.Counting using (countT; allVecs; binom; countT-cong)
open import Security.OCR using (sphere-count)
open import Security.SARLock using (≡ᵇ0→0)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Define the complementary AND-type block.

antiSat : (k1 k2 : Vec Bool n) → Vec Bool n → Bool
antiSat k1 k2 x = prot 0 k1 x ∧ not (prot 0 k2 x)

--  At the correct key, b ∧ ¬b ≡ false prevents every trigger.
b∧¬b : (b : Bool) → (b ∧ not b) ≡ false
b∧¬b true  = refl
b∧¬b false = refl

antiSat-correct : (k x : Vec Bool n) → antiSat k k x ≡ false
antiSat-correct k x = b∧¬b (prot 0 k x)

------------------------------------------------------------------------
--  At a wrong key, the block is the singleton {k1} and OCR is 1.

--  A nonzero natural fails the ≡ᵇ 0 comparison.
≢0→≡ᵇ0-false : (m : ℕ) → m ≢ 0 → (m ≡ᵇ 0) ≡ false
≢0→≡ᵇ0-false zero    ne = ⊥-elim (ne refl)
≢0→≡ᵇ0-false (suc m) _  = refl

--  Distinct vectors fail one another's exact-match predicate.
prot0-false : (a b : Vec Bool n) → a ≢ b → prot 0 b a ≡ false
prot0-false a b ne = ≢0→≡ᵇ0-false (HD a b) (λ h0 → ne (HD0→≡ a b h0))

--  If a being true forces b false, then a ∧ ¬b ≡ a.
and-not-absorb : (a b : Bool) → (a ≡ true → b ≡ false) → (a ∧ not b) ≡ a
and-not-absorb false b _ = refl
and-not-absorb true  b h = cong not (h refl)

--  Identify the block pointwise with k1's radius-zero predicate.
antiSat≡prot0 : (k1 k2 : Vec Bool n) → k1 ≢ k2 → (x : Vec Bool n) →
                antiSat k1 k2 x ≡ prot 0 k1 x
antiSat≡prot0 k1 k2 ne x =
  and-not-absorb (prot 0 k1 x) (prot 0 k2 x)
    (λ p1 → trans (cong (prot 0 k2) (HD0→≡ x k1 (≡ᵇ0→0 (HD x k1) p1)))
                  (prot0-false k1 k2 ne))

--  Use binom n 0 = 1 to count exactly one corrupted input.
OCR-AntiSat : (k1 k2 : Vec Bool n) → k1 ≢ k2 →
              countT (antiSat k1 k2) (allVecs n) ≡ 1
OCR-AntiSat {n} k1 k2 ne =
  trans (countT-cong (antiSat≡prot0 k1 k2 ne) (allVecs n))
        (sphere-count 0 k1)
