------------------------------------------------------------------------
--  An oracle interface with an explicit query bound
--  The non-adaptive adversary chooses `q` inputs in advance and supplies a
--  decoder for the resulting `q` answers. Its type carries the budget `q`,
--  making a polynomial query allowance a typed requirement instead of an
--  informal qualification. `Attack.FALL` uses this interface to express its
--  key-recovery procedure as an adversary with budget `n`.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.Oracle where

open import Data.Nat using (ℕ)
open import Data.Vec using (Vec; map)
open import Relation.Binary.PropositionalEquality using (_≡_)

--  An adversary that reconstructs a member of `K` using `q` queries to an `X → Y` oracle.
record QAdversary (X Y K : Set) (q : ℕ) : Set where
  field
    probes : Vec X q          --  q inputs chosen before any answers are observed
    decode : Vec Y q → K       --  a key reconstructed from the q oracle responses

--  Execute the adversary with the activated oracle.
ask : ∀ {X Y K q} → QAdversary X Y K q → (X → Y) → K
ask A O = QAdversary.decode A (map O (QAdversary.probes A))

--  Key recovery for `act : K → (X → Y)`, which assigns an activated oracle
--  to each secret key.
Recovers : ∀ {X Y K q} → QAdversary X Y K q → (K → X → Y) → Set
Recovers A act = ∀ k → ask A (act k) ≡ k
