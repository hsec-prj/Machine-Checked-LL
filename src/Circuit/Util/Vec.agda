------------------------------------------------------------------------
--  Vector identities used in circuit interpretation
--  Both `⟦ Par ⟧` and `⟦ Swap ⟧` divide their inputs using `take` and `drop`.
--  For an input `kc ++ xs`, with the key bus preceding the data bus, the
--  two rules below compute the resulting parts. These lemmas replace
--  `postulate split`, so the project remains `--safe`.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Circuit.Util.Vec where

open import Level using (Level)
open import Data.Nat using (ℕ)
open import Data.Vec using (Vec; []; _∷_; _++_; take; drop)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)

private
  variable
    a : Level
    A : Set a
    n m : ℕ

--  Taking the left vector's length from an append returns that vector.
take-++ : (xs : Vec A n) (ys : Vec A m) → take n (xs ++ ys) ≡ xs
take-++ []       ys = refl
take-++ (x ∷ xs) ys = cong (x ∷_) (take-++ xs ys)

--  Dropping the left vector's length from an append returns the right vector.
drop-++ : (xs : Vec A n) (ys : Vec A m) → drop n (xs ++ ys) ≡ ys
drop-++ []       ys = refl
drop-++ (x ∷ xs) ys = drop-++ xs ys
