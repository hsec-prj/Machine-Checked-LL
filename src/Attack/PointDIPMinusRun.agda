------------------------------------------------------------------------
--  Execute the optimal point-DIP adversary (E-09). ExactQuery shows dipQA
--  succeeds with 2^n queries and dipQA⁻ with one fewer, 2^n ∸ 1. The latter
--  makes the budget least sufficient, but only the exhaustive PointDIPRun
--  had an executable witness in the comparison table. Here run
--  ask (dipQA⁻ f gS) (actGen f gS pointGadget ksec), directly applying
--  the verified adversary to its verified oracle. Execution concerns the
--  same term as dipQA⁻-recovers, not a separate implementation. The
--  adversary holds the lock gadget gS and seeks the oracle's unknown ksec.
--  Choosing gS=pointGadget ksec would recover but is degenerate: in
--  locked-fun-gen f gS gA x = (f x xor pred gS x) xor pred gA x, equal
--  gadgets cancel, leaving only host answers and recovery from gS itself.
--  Use a separate applied-key index and report nonconst to expose whether
--  answers differ from the bare host, identifying degenerate rows. The
--  constant-false host is a valid instance of universally quantified f;
--  the run demonstrates recovery and query count rather than a property
--  of a particular host. probesMinus's type fixes 2^n ∸ 1, and reporting
--  it allows comparison with the theorem. Since dipQA⁻-recovers gives
--  ask A (act k) ≡ k for every k, match can only be 1 unless compilation
--  is unsound. It is a cross-check; execution adds evidence that the
--  verified term compiles, terminates, and realises its typed budget. This
--  is the same contribution PointDIPRun makes at 2^n. Compile through
--  run/Main.agda in its separate --guardedness IO library,
--  since IO cannot be --safe. No postulates are introduced.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}

module Attack.PointDIPMinusRun where

open import Data.Nat using (ℕ; zero; suc; _∸_; _^_)
open import Data.Bool using (Bool; true; false; if_then_else_; _∨_)
open import Data.Vec using (Vec; []; _∷_; map; foldr′)
open import Data.List using (List; []; _∷_)
open import Data.String using (String; _++_)
open import Data.Nat.Show using (show)
open import Data.Bool.Properties using (_≟_)
open import Data.Vec.Properties using (≡-dec)
open import Relation.Nullary using (yes; no)

open import Util.Counting using (allVecs)
open import Locking.GenericLock using (pointGadget)
open import Attack.Oracle using (ask)
open import Attack.GenericSAT using (actGen)
open import Attack.ExactQuery using (dipQA⁻; probesMinus)

------------------------------------------------------------------------
--  Keep rendering helpers local to avoid changes from unrelated module APIs.

zeros : (n : ℕ) → Vec Bool n
zeros zero    = []
zeros (suc n) = false ∷ zeros n

showBits : {n : ℕ} → Vec Bool n → String
showBits []           = ""
showBits (true  ∷ bs) = "1" ++ showBits bs
showBits (false ∷ bs) = "0" ++ showBits bs

--  Make indexing total by returning an all-zero secret for out-of-range
--  indices rather than failing.
nthD : {A : Set} → A → ℕ → List A → A
nthD d _       []       = d
nthD d zero    (x ∷ _)  = x
nthD d (suc i) (_ ∷ xs) = nthD d i xs

sameBits : {n : ℕ} → Vec Bool n → Vec Bool n → Bool
sameBits xs ys with ≡-dec _≟_ xs ys
... | yes _ = true
... | no  _ = false

------------------------------------------------------------------------
--  Select the built-in gadget with idxApp and the planted target with
--  idxSec, allowing informative answers as described above. dipQA⁻-recovers
--  gives match=1 for every width and pair of indices; print it to check
--  the execution against the theorem.

dipMinusReport : (n idxApp idxSec : ℕ) → String
dipMinusReport n idxApp idxSec =
  "n=" ++ show n
  ++ "\tqueries=" ++ show (2 ^ n ∸ 1)
  ++ "\tkapp=" ++ showBits kapp
  ++ "\tksec=" ++ showBits ksec
  ++ "\trecovered=" ++ showBits got
  ++ "\tnonconst=" ++ (if informative then "1" else "0")
  ++ "\tmatch=" ++ (if sameBits got ksec then "1" else "0")
  where
    kapp : Vec Bool n
    kapp = nthD (zeros n) idxApp (allVecs n)

    ksec : Vec Bool n
    ksec = nthD (zeros n) idxSec (allVecs n)

    host : Vec Bool n → Bool
    host _ = false

    --  Provide the lock's applied gadget through the oracle while keeping its
    --  planted key unknown to the adversary.
    oracle : Vec Bool n → Bool
    oracle = actGen host (pointGadget kapp) pointGadget ksec

    --  With the false host, any true answer on the probes shows the gadgets
    --  did not cancel and the queries carried information.
    informative : Bool
    informative = foldr′ _∨_ false (map oracle (probesMinus n))

    got : Vec Bool n
    got = ask (dipQA⁻ host (pointGadget kapp)) oracle
