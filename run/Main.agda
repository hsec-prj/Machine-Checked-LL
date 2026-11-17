------------------------------------------------------------------------
--  Command-line interface to the checked point-family executable witness.
--
--  The currently supported command, `dipminus <n> <idxApp> <idxSec>`, executes
--  the optimal point-DIP adversary and displays its typed budget and result.
--  Its winning budget is `2 ^ n ∸ 1`, one query below exhaustive search. The
--  indices independently select the applied lock gadget and the planted key:
--  equal choices cancel the gadgets and leave all answers uninformative.
--  See `Attack.PointDIPMinusRun` for this distinction. The queries field
--  prints the type's budget; it is not an instrumented runtime oracle count.
--
--  The checked library module `Attack.PointDIPMinusRun`, compiled with
--  --safe --without-K, computes every displayed result. This file supplies
--  only IO; its remaining error boundary is argument reading and line output.
------------------------------------------------------------------------
{-# OPTIONS --guardedness --without-K #-}

module Main where

open import Data.List using (List; []; _∷_)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Nat using (ℕ)
open import Data.Nat.Show using (readMaybe)
open import Data.String using (String; _++_)
open import Data.Unit.Polymorphic using (⊤)
open import IO using (Main; IO; run; putStrLn; _>>=_)
open import System.Environment using (getArgs)

open import Attack.PointDIPMinusRun using (dipMinusReport)

usage : String
usage = "usage: Main dipminus <n> <idxApp> <idxSec>\n\
        \  runs the verified 2^n-1 point-DIP adversary at width n, with the\n\
        \  idxApp-th candidate as the lock's applied key and the idxSec-th as\n\
        \  the planted secret, and prints\n\
        \  n, queries, kapp, ksec, recovered, nonconst, match (queries = typed budget)"

dispatch : List String → String
dispatch ("dipminus" ∷ n ∷ a ∷ i ∷ []) with readMaybe 10 n | readMaybe 10 a | readMaybe 10 i
... | just N | just A | just I = dipMinusReport N A I
... | _      | _      | _      = "# ERROR: n, idxApp and idxSec must be decimal naturals\n" ++ usage
dispatch _ = usage

main : Main
main = run (getArgs >>= λ args → putStrLn (dispatch args))
