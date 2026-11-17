------------------------------------------------------------------------
--  Execute and report the verified FALL attack (E2). Attack.VerifiedFALL proves
--  distance-node key recovery in n+1 queries through fallPolyQA-recovers,
--  backed by recoverKeyPoly and fall-poly-recovers-key. Run that same
--  polynomial decoder against distNode ksec for a chosen secret, then emit
--  (n, query count, secret, recovered key) as TSV. Compiling via
--  experiments/extract/Main.agda yields the native `fall <N> <idx>` command.
--  Measured sweeps can therefore display actual recovery with n+1 queries
--  beside the 2ⁿ queries of Attack.PointDIPRun.dipReport. This closes E2's
--  DIP-only measurement connection. The --safe --without-K main track here
--  uses the theorem's recoverKeyPoly and distNode directly; only IO is in
--  the --guardedness extract-cli library. No unverified duplicate decoder
--  or postulates are added.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.VerifiedFALLRun where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Bool using (Bool; true; false; not; _∧_; if_then_else_)
open import Data.Vec using (Vec; []; _∷_)
open import Data.List using (List; []; _∷_)
open import Data.String using (String; _++_)
open import Data.Nat.Show using (show)

open import Util.Counting using (allVecs)
open import Attack.FunctionalAnalysis using (distNode)
open import Attack.FALLPoly using (recoverKeyPoly)

------------------------------------------------------------------------
--  Keep helpers local as in Attack.PointDIPRun to avoid API drift: an n-bit
--  zero reference, bitstring formatting, Boolean vector equality, and total
--  natural-indexed lookup with a default.

zeros : (m : ℕ) → Vec Bool m
zeros zero    = []
zeros (suc m) = false ∷ zeros m

showBits : {m : ℕ} → Vec Bool m → String
showBits []       = ""
showBits (b ∷ bs) = (if b then "1" else "0") ++ showBits bs

beq : Bool → Bool → Bool
beq a b = if a then b else not b

vecEqb : {m : ℕ} → Vec Bool m → Vec Bool m → Bool
vecEqb []       []       = true
vecEqb (a ∷ as) (b ∷ bs) = beq a b ∧ vecEqb as bs

nthD : {A : Set} → A → ℕ → List A → A
nthD d _       []        = d
nthD d zero    (x ∷ _)   = x
nthD d (suc i) (_ ∷ xs)  = nthD d i xs

------------------------------------------------------------------------
--  Select the idx-th candidate modulo 2ⁿ using total nthD, then execute
--  recoverKeyPoly (distNode ksec) from the zero reference. The theorem
--  Attack.FALLPoly.fall-poly-recovers-key gives exactly ksec, so match = 1.
--  Its polynomial budget suc n = n+1 contrasts with the DIP runner's 2ⁿ.

fallReport : (n idx : ℕ) → String
fallReport n idx =
  "n=" ++ show n
  ++ "\tqueries=" ++ show (suc n)
  ++ "\tksec=" ++ showBits ksec
  ++ "\trecovered=" ++ showBits recovered
  ++ "\tmatch=" ++ (if vecEqb recovered ksec then "1" else "0")
  where
    ksec : Vec Bool n
    ksec = nthD (zeros n) idx (allVecs n)
    recovered : Vec Bool n
    recovered = recoverKeyPoly (distNode ksec) (zeros n)
