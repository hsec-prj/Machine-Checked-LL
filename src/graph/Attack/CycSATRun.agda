------------------------------------------------------------------------
--  Report the base-reading feedback scan on an empty acyclic base.
--  Attack.CycSATAttack proves its all-false survivor and the 2ᵏ candidate
--  count. This module executes that function with W=0 and k feedback
--  gates. The IO front-end is experiments/graph-cli/RunCycSAT.agda;
--  its RunCycSAT <k> command reports the computed key and typed scan count.
--  The logic here is --safe --without-K; IO stays outside this library.
--  This is the supported static scan, not a general topology analysis
--  or the published solver-based CycSAT implementation.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATRun where

open import Data.Nat using (ℕ; zero; suc; _^_)
open import Data.Bool using (Bool; true; false; not; _∧_; if_then_else_)
open import Data.Vec using (Vec; []; _∷_)
open import Data.String using (String; _++_)
open import Data.Nat.Show using (show)

open import Graph.Core using (Gate; cst)
open import Graph.Acyclic using (ANetlist; [])
open import Locking.CyclicMulti using (allFalse)
open import Attack.CycSATAttack using (cycSATAttack)

------------------------------------------------------------------------
--  Provide local helpers corresponding to the FALL/DIP runners: format
--  bitstrings, compare Boolean vectors, and construct constant gate vectors.

showBits : {m : ℕ} → Vec Bool m → String
showBits []       = ""
showBits (b ∷ bs) = (if b then "1" else "0") ++ showBits bs

beq : Bool → Bool → Bool
beq a b = if a then b else not b

vecEqb : {m : ℕ} → Vec Bool m → Vec Bool m → Bool
vecEqb []       []       = true
vecEqb (a ∷ as) (b ∷ bs) = beq a b ∧ vecEqb as bs

--  Construct k constant feedback gates in the empty wire space W = 0.
constGates : (k : ℕ) → Vec (Gate 0) k
constGates zero    = []
constGates (suc k) = cst false ∷ constGates k

------------------------------------------------------------------------
--  Execute the attack on an empty acyclic base with k feedback gates.
--  Attack.CycSATAttack.cycSATAttack-recovers gives allFalse k as the result,
--  hence match = 1; cycSATAttack-queries gives the 2ᵏ query count.

cycReport : (k : ℕ) → String
cycReport k =
  "k=" ++ show k
  ++ "\tqueries=" ++ show (2 ^ k)
  ++ "\tksec=" ++ showBits (allFalse k)
  ++ "\trecovered=" ++ showBits recovered
  ++ "\tmatch=" ++ (if vecEqb recovered (allFalse k) then "1" else "0")
  where
    recovered : Vec Bool k
    recovered = cycSATAttack (constGates k) []
