------------------------------------------------------------------------
--  Decode structure directly from the shipped characters.
--  Attack.ObservationSeparation.decodeConst-correct extracts the secret from
--  an emitted operation list. The artifact reader instead receives .bench
--  characters, whose conversion to operations belongs to the parser.
--  renderNet-roundtrip recovers the emitter's operation list from its
--  certified character list. Composing it with decodeConst-correct proves
--  text-level decoding for this printer/parser pair. It does not cover
--  other tools' output or synthesis-transformed files. Whole-host decoding
--  is separately stated in Extraction.HostDisclosure with a constant-free
--  host-prefix premise.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.DecodeText where

open import Data.Bool using (Bool)
open import Data.Char using (Char)
open import Data.List using (List; length)
open import Data.Maybe using (Maybe; just; map)
open import Data.Nat using (ℕ)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Vec using (Vec; toList)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; trans)

open import Extraction.BenchISCAS using (renderNetL; parseNet; renderNet-roundtrip)
open import Extraction.Netlist using (Op)
open import Extraction.LockedNet using (lockedBlock)
open import Attack.ObservationSeparation using (decodeConst; decodeConst-recovers)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Section 1: begin decoding with the file contents.

--  Parse the text and extract its first `m` constant payloads. A parse failure
--  returns `nothing` without recovery; our printer's output always parses.
decodeConstText : ℕ → List Char → Maybe (List Bool)
decodeConstText m cs = map (λ r → decodeConst m (proj₁ (proj₂ r))) (parseNet cs)

--  For this emitter's printed text, decoding the file equals decoding its list.
decodeConst-text :
  (m n' : ℕ) (ops : List Op) (outId : ℕ) →
  decodeConstText m (renderNetL n' ops outId) ≡ just (decodeConst m ops)
decodeConst-text m n' ops outId
  rewrite renderNet-roundtrip n' ops outId = refl

------------------------------------------------------------------------
--  Section 2: show that the locked block's characters encode the secret.

--  State structural separation at the file interface available to the reader.
--  The statement involves no oracle queries.
decodeConst-bench :
  {n : ℕ} (xs keys : List ℕ) (s : Vec Bool n) (h fWire start outId : ℕ) →
  decodeConstText n
    (renderNetL (length xs)
                (proj₂ (proj₂ (lockedBlock xs keys (toList s) h fWire start)))
                outId)
  ≡ just (toList s)
decodeConst-bench {n} xs keys s h fWire start outId =
  trans (decodeConst-text n (length xs)
          (proj₂ (proj₂ (lockedBlock xs keys (toList s) h fWire start))) outId)
        (cong just (decodeConst-recovers xs keys s h fWire start))
