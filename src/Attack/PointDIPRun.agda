------------------------------------------------------------------------
--  Execute the verified point-DIP attack and render its result (Layer B).
--  Attack.PointDIPAttack proves recovery in exactly 2ⁿ queries. Here the
--  same `survives` predicate checks all candidates in `allVecs n`, retains
--  consistent ones, and formats (n, query count, secret, recovered key) as
--  TSV. Compiling through experiments/extract/Main.agda provides the native
--  command `dip <N> <idx>`. experiments/sweep_duel.sh can then show actual
--  execution on a concrete key, including the realised 2ⁿ query count, beside
--  sld's average-case iteration count. The pruning logic remains in this
--  --safe --without-K main-track module and uses precisely the predicate of
--  the recovery theorem. Only IO resides outside it, in the --guardedness
--  extract-cli library; no second unverified pruning implementation or
--  postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.PointDIPRun where

open import Data.Nat using (ℕ; zero; suc; _≡ᵇ_)
open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Vec using (Vec; []; _∷_)
open import Data.List using (List; []; _∷_; length)
open import Data.String using (String; _++_)
open import Data.Nat.Show using (show)

open import Util.Counting using (allVecs)
open import Attack.PointDIPAttack using (survives)

------------------------------------------------------------------------
--  Keep helpers local to avoid API drift: Boolean filtering, an n-bit default
--  zero secret, bitstring formatting, and total natural-indexed lookup with a
--  default element.

bfilter : {A : Set} → (A → Bool) → List A → List A
bfilter p []       = []
bfilter p (x ∷ xs) = if p x then x ∷ bfilter p xs else bfilter p xs

zeros : (m : ℕ) → Vec Bool m
zeros zero    = []
zeros (suc m) = false ∷ zeros m

showBits : {m : ℕ} → Vec Bool m → String
showBits []           = ""
showBits (b ∷ bs)     = (if b then "1" else "0") ++ showBits bs

showVecs : {m : ℕ} → List (Vec Bool m) → String
showVecs []           = "-"
showVecs (v ∷ [])     = showBits v
showVecs (v ∷ w ∷ vs) = showBits v ++ "," ++ showVecs (w ∷ vs)

nthD : {A : Set} → A → ℕ → List A → A
nthD d _       []       = d
nthD d zero    (x ∷ _)  = x
nthD d (suc i) (_ ∷ xs) = nthD d i xs

------------------------------------------------------------------------
--  Choose candidate `idx` as the secret, modulo 2ⁿ through total `nthD`, and
--  apply the verified `survives` test to all 2ⁿ candidates. dipAttack-recovers
--  ensures the survivor list is exactly `[ksec]`, so recovered has that value
--  and match equals 1.

dipReport : (n idx : ℕ) → String
dipReport n idx =
  "n=" ++ show n
  ++ "\tqueries=" ++ show total
  ++ "\tksec=" ++ showBits ksec
  ++ "\trecovered=" ++ showVecs recovered
  ++ "\tmatch=" ++ (if length recovered ≡ᵇ 1 then "1" else "0")
  where
    cands : List (Vec Bool n)
    cands = allVecs n
    total : ℕ
    total = length cands
    ksec : Vec Bool n
    ksec = nthD (zeros n) idx cands
    recovered : List (Vec Bool n)
    recovered = bfilter (survives ksec cands) cands
