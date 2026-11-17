------------------------------------------------------------------------
--  Prove a round trip for parsing LUT-netlist input (D6, option 1, phase 2).
--  Extraction.BenchRoundTrip concerns the compiler's emitted flat .bench
--  output. This module supplies the input counterpart, with renderFlat and
--  parseFlat for host text consisting of header `n G` and G lines `a b code`.
--  Each line records two fan-ins and a two-input LUT truth-table code. The
--  roundtrip theorem, parseFlat (renderFlat n gs) ≡ just (n, gs), proves
--  that printing retains the gate structure. decodeCode delegates codes to
--  Extraction.LUTGadget.lutCircuit for verified gadget semantics. Thus
--  gen_netlist_data.py need only emit (a,b,code) triples: Agda recovers both
--  structure through this round trip and semantics through phase 1. The
--  number machinery is reused from BenchRoundTrip, without postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LUTNetParse where

open import Data.Nat using (ℕ; suc; _<?_)
open import Data.Fin using (Fin; fromℕ<)
open import Data.Char using (Char)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Nullary using (yes; no)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Data.Digit using (toDigits)

open import Circuit.Core using (Circuit)
open import Extraction.LUTGadget using (lutCircuit)
open import Extraction.BenchRoundTrip using (natToDigits; readNat; span-rt; match; _>>=_)

------------------------------------------------------------------------
--  Section 1: represent a flat gate by three naturals, its two fan-ins and code.

FGate : Set
FGate = ℕ × ℕ × ℕ

--  Render in continuation style, prepending "a b code\n" to tail `t`.
rFGate : FGate → List Char → List Char
rFGate (a , b , c) t =
  natToDigits a ++ ' ' ∷ natToDigits b ++ ' ' ∷ natToDigits c ++ '\n' ∷ t

parseFGate : List Char → Maybe (FGate × List Char)
parseFGate cs =
  let (a , r1) = readNat cs in
  match (' ' ∷ []) r1 >>= λ r2 →
  let (b , r3) = readNat r2 in
  match (' ' ∷ []) r3 >>= λ r4 →
  let (c , r5) = readNat r4 in
  match ('\n' ∷ []) r5 >>= λ r6 →
  just ((a , b , c) , r6)

parseFGate-rt : (g : FGate) (t : List Char) → parseFGate (rFGate g t) ≡ just (g , t)
parseFGate-rt (a , b , c) t
  rewrite span-rt (proj₁ (toDigits 10 a)) ' ' (natToDigits b ++ ' ' ∷ natToDigits c ++ '\n' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 b)) ' ' (natToDigits c ++ '\n' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 c)) '\n' t refl
        | proj₂ (toDigits 10 a) | proj₂ (toDigits 10 b) | proj₂ (toDigits 10 c) = refl

------------------------------------------------------------------------
--  Section 2: process gate lines by structural recursion on the count `g`.

rFGates : List FGate → List Char → List Char
rFGates []       t = t
rFGates (g ∷ gs) t = rFGate g (rFGates gs t)

parseFGates : ℕ → List Char → Maybe (List FGate × List Char)
parseFGates 0       cs = just ([] , cs)
parseFGates (suc k) cs =
  parseFGate cs >>= λ p →
  parseFGates k (proj₂ p) >>= λ q →
  just (proj₁ p ∷ proj₁ q , proj₂ q)

parseFGates-rt : (gs : List FGate) (t : List Char) →
                 parseFGates (length gs) (rFGates gs t) ≡ just (gs , t)
parseFGates-rt []       t = refl
parseFGates-rt (g ∷ gs) t
  rewrite parseFGate-rt g (rFGates gs t)
        | parseFGates-rt gs t = refl

------------------------------------------------------------------------
--  Section 3: render the full netlist with header "n G\n".

rHeader : ℕ → ℕ → List Char → List Char
rHeader n g t = natToDigits n ++ ' ' ∷ natToDigits g ++ '\n' ∷ t

parseHeader : List Char → Maybe ((ℕ × ℕ) × List Char)
parseHeader cs =
  let (n , r1) = readNat cs in
  match (' ' ∷ []) r1 >>= λ r2 →
  let (g , r3) = readNat r2 in
  match ('\n' ∷ []) r3 >>= λ r4 →
  just ((n , g) , r4)

parseHeader-rt : (n g : ℕ) (t : List Char) → parseHeader (rHeader n g t) ≡ just ((n , g) , t)
parseHeader-rt n g t
  rewrite span-rt (proj₁ (toDigits 10 n)) ' ' (natToDigits g ++ '\n' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 g)) '\n' t refl
        | proj₂ (toDigits 10 n) | proj₂ (toDigits 10 g) = refl

renderFlat : ℕ → List FGate → List Char
renderFlat n gs = rHeader n (length gs) (rFGates gs [])

parseFlat : List Char → Maybe (ℕ × List FGate)
parseFlat cs =
  parseHeader cs >>= λ h →
  parseFGates (proj₂ (proj₁ h)) (proj₂ h) >>= λ p →
  just (proj₁ (proj₁ h) , proj₁ p)

--  The input round trip recovers the original input count and gate list
--  from the printed netlist, corresponding to BenchRoundTrip's output theorem.
roundtrip : (n : ℕ) (gs : List FGate) → parseFlat (renderFlat n gs) ≡ just (n , gs)
roundtrip n gs
  rewrite parseHeader-rt n (length gs) (rFGates gs [])
        | parseFGates-rt gs [] = refl

------------------------------------------------------------------------
--  Section 4: decode parsed codes into verified gadgets. Values 0..13 select
--  Extraction.LUTGadget's 14 non-constant functions, validated by
--  lutCircuit-correct; reject any code outside that range.

decodeCode : ℕ → Maybe (Circuit 2 1)
decodeCode c with c <? 14
... | yes p = just (lutCircuit (fromℕ< p))
... | no  _ = nothing
