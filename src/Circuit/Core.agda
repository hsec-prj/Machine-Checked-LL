------------------------------------------------------------------------
--  A deeply embedded language for combinational circuits
--  This small, well-typed combinator language uses `Circuit n m` for an
--  `n`-bit input bus and an `m`-bit output bus. The sequential constructor
--  `Seq` and parallel constructor `Par` support the structural induction
--  used in Paper 1's functional-equivalence proofs. A deep embedding is
--  necessary because locking operates by transforming circuit syntax.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Circuit.Core where

open import Data.Nat using (ℕ; _+_)
open import Data.Fin using (Fin)
open import Data.Bool using (Bool)

------------------------------------------------------------------------
--  Circuit syntax

data Circuit : ℕ → ℕ → Set where
  --  Basic gate constructors
  Id    : ∀ {n} → Circuit n n
  Not1  : Circuit 1 1
  And2  : Circuit 2 1
  Or2   : Circuit 2 1
  Xor2  : Circuit 2 1
  --  A 2-to-1 multiplexer takes (sel ∷ a ∷ b ∷ []) and returns the selected
  --  data wire. This constructor supports MUX locking (P1 step 2).
  Mux21 : Circuit 3 1

  --  Constructors for circuit structure
  Seq  : ∀ {n m p} → Circuit n m → Circuit m p → Circuit n p
  Par  : ∀ {n₁ m₁ n₂ m₂} →
         Circuit n₁ m₁ → Circuit n₂ m₂ →
         Circuit (n₁ + n₂) (m₁ + m₂)
  Swap : ∀ {n m} → Circuit (n + m) (m + n)
  --  Duplicate one wire to provide fan-out. A multiplexer may need the same
  --  signal on multiple inputs; the permutations provided by `Par` and `Swap`
  --  cannot express that duplication (P1 step 2).
  Dup  : Circuit 1 2
  --  A general wire connection: output `i : Fin m` receives input `f i : Fin n`.
  --  This single constructor handles routing, projection, and fan-out,
  --  including the behavior of `Swap` and `Dup`. It was added for Tier B
  --  gate-level netlists alongside the older combinators, leaving the Paper
  --  1/2 theorems intact.
  Plug : ∀ {n m} → (Fin m → Fin n) → Circuit n m
  --  A fixed-bit source with no inputs, representing tie-high or tie-low.
  --  Tier C's gate-level popcount needs it for the base case and carry padding;
  --  constant sources also occur in actual netlists.
  Const : Bool → Circuit 0 1
  --  A threshold gate emits 1 exactly when at least `t` of its `n` inputs
  --  are 1. TLGLock uses this primitive with a key-controlled effective
  --  threshold. Boolean gates alone cannot express it without a popcount,
  --  so it adds a primitive in its own right, as `Plug` and `Const` do.
  Thr  : ∀ {n} → ℕ → Circuit n 1
