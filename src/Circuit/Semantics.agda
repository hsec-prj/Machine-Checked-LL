------------------------------------------------------------------------
--  Denotations for the combinational circuit language
--  A circuit is interpreted as a pure function between bit vectors.
--  Parallel composition and wire swapping divide the input with `take`
--  and `drop` (definitionally `splitAt`). This avoids any postulate and
--  preserves the project's `--safe` status.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Circuit.Semantics where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; _xor_)
open import Data.Vec using (Vec; []; _∷_; _++_; take; drop; tabulate; lookup)

open import Circuit.Core

--  Count the wires set to `true` for use by `Thr`.
ones : ∀ {n} → Vec Bool n → ℕ
ones []           = 0
ones (true  ∷ bs) = suc (ones bs)
ones (false ∷ bs) = ones bs

--  A Boolean comparison for "at least": `t ≤b w` ≡ `t ≤ w`.
--  Recursion inspects both arguments, whereas stdlib `_≤ᵇ_` inspects only
--  the first. Consequently `suc t ≤b suc w` reduces to `t ≤b w`, allowing
--  the threshold lock's left-cancellation proof in `Locking.TLGLock` to
--  finish by structural recursion.
_≤b_ : ℕ → ℕ → Bool
zero  ≤b _     = true
suc _ ≤b zero  = false
suc t ≤b suc w = t ≤b w

⟦_⟧ : ∀ {n m} → Circuit n m → Vec Bool n → Vec Bool m
⟦ Id   ⟧ xs              = xs
⟦ Not1 ⟧ (x ∷ [])        = not x ∷ []
⟦ And2 ⟧ (x ∷ y ∷ [])    = (x ∧ y) ∷ []
⟦ Or2  ⟧ (x ∷ y ∷ [])    = (x ∨ y) ∷ []
⟦ Xor2 ⟧ (x ∷ y ∷ [])    = (x xor y) ∷ []
⟦ Mux21 ⟧ (s ∷ a ∷ b ∷ []) = ((a ∧ not s) ∨ (b ∧ s)) ∷ []
⟦ Seq c₁ c₂ ⟧ xs         = ⟦ c₂ ⟧ (⟦ c₁ ⟧ xs)
⟦ Par {n₁ = n₁} c₁ c₂ ⟧ xs =
  ⟦ c₁ ⟧ (take n₁ xs) ++ ⟦ c₂ ⟧ (drop n₁ xs)
⟦ Swap {n = n} ⟧ xs      = drop n xs ++ take n xs
⟦ Dup  ⟧ (x ∷ [])        = x ∷ x ∷ []
⟦ Plug f ⟧ xs            = tabulate (λ i → lookup xs (f i))
⟦ Const b ⟧ []           = b ∷ []
⟦ Thr t ⟧ xs             = (t ≤b ones xs) ∷ []
