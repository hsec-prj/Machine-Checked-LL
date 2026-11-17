{-# OPTIONS --guardedness --without-K #-}
module RunCycSAT where

open import Data.List using ([]; _∷_)
open import Data.Maybe using (just; nothing)
open import Data.Nat.Show using (readMaybe)
open import Data.String using (String)
open import IO using (Main; run; putStrLn; _>>=_)
open import System.Environment using (getArgs)
open import Attack.CycSATRun using (cycReport)

dispatch : Data.List.List String → String
dispatch (width ∷ []) with readMaybe 10 width
... | just n = cycReport n
... | nothing = "ERROR: width must be a decimal natural"
dispatch _ = "usage: RunCycSAT <width>"

main : Main
main = run (getArgs >>= λ args → putStrLn (dispatch args))
