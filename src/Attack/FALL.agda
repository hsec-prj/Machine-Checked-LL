------------------------------------------------------------------------
--  A formal reduction for FALL key recovery
--  The functional-analysis attack FALL (Sirone--Subramanyan) first analyzes
--  the locked netlist and then reads out the key with a recovery procedure.
--  The formalization covers this second step, the one round required by the
--  milestone; the first step relies on the cited reduction. Its structural
--  premise, `KeyGatesAtHW1`, says that key gates at Hamming-weight-1 positions
--  give an oracle `o : Fin n → Bool` whose answers equal the individual key
--  bits. Given that premise, `FALL-recovers-key` queries every position and
--  reconstructs the exact key. `Attack.Oracle` records its polynomial budget
--  in the type of this `n`-query adversary.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.FALL where

open import Data.Nat using (ℕ)
open import Data.Fin using (Fin)
open import Data.Bool using (Bool)
open import Data.Vec using (Vec; lookup; allFin)
open import Data.Vec.Properties using (map-cong; map-lookup-allFin)
open import Relation.Binary.PropositionalEquality using (_≡_; trans)

open import Attack.Oracle using (QAdversary; ask)

private
  variable
    n : ℕ

--  The cited first stage of FALL supplies this structural premise: at
--  every position, the extracted structural oracle agrees with the key bit.
KeyGatesAtHW1 : Vec Bool n → (Fin n → Bool) → Set
KeyGatesAtHW1 k o = ∀ i → o i ≡ lookup k i

--  Represent FALL recovery with budget `n`: query all bit positions and
--  return the answer vector, using the identity function as the decoder.
fall : QAdversary (Fin n) Bool (Vec Bool n) n
fall = record { probes = allFin _ ; decode = λ ys → ys }

--  For one round, the structural premise suffices for exact FALL key
--  recovery after `n` oracle queries.
FALL-recovers-key : (k : Vec Bool n) (o : Fin n → Bool) →
                    KeyGatesAtHW1 k o → ask (fall {n}) o ≡ k
FALL-recovers-key k o assum =
  trans (map-cong assum (allFin _)) (map-lookup-allFin k)
