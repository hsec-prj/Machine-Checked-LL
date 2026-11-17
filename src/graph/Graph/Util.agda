------------------------------------------------------------------------
--  Enumerating keys within the graph library
--  `logic-locking-graph` is a separate library without a dependency on
--  `../src`, so it cannot use `Util.Counting.allVecs` directly. The verified
--  oscillation-elimination attack in `Attack.CycSATAttack` scans the full key
--  space and therefore needs a local enumeration of all `k`-bit vectors.
--  This translates `Util.Counting`'s `allVecs`, `∈-allVecs`, and
--  `length-allVecs` to Boolean vectors; the corresponding membership proof
--  there is in `src/Attack/PointDIPAttack.agda`. The same import convention
--  keeps List constructors unqualified and `Data.Vec as Vec` qualified,
--  confining the `[]`/`_∷_` naming clash to this file. No postulate is used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Graph.Util where

open import Data.Nat using (ℕ; zero; suc; _+_; _^_)
open import Data.Nat.Properties using (+-identityʳ)
open import Data.Bool using (Bool; true; false)
open import Data.List using (List; []; _∷_; _++_; map; length)
open import Data.List.Properties using (length-++; length-map)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here)
open import Data.List.Membership.Propositional.Properties using (∈-++⁺ˡ; ∈-++⁺ʳ; ∈-map⁺)
import Data.Vec as Vec
open Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; trans; sym)

private
  variable
    k : ℕ

------------------------------------------------------------------------
--  Listing the entire key-vector space

--  For width `k`, `allVecsK k` enumerates the 2ᵏ possible keys.
allVecsK : (k : ℕ) → List (Vec Bool k)
allVecsK zero    = Vec.[] ∷ []
allVecsK (suc k) = map (Vec._∷_ false) (allVecsK k) ++ map (Vec._∷_ true) (allVecsK k)

--  Every key occurs in the list, ensuring that the correct key can be reached.
∈-allVecsK : (v : Vec Bool k) → v ∈ allVecsK k
∈-allVecsK {zero}  Vec.[]          = here refl
∈-allVecsK {suc k} (false Vec.∷ v) = ∈-++⁺ˡ   (∈-map⁺ (Vec._∷_ false) (∈-allVecsK v))
∈-allVecsK {suc k} (true  Vec.∷ v) = ∈-++⁺ʳ _ (∈-map⁺ (Vec._∷_ true)  (∈-allVecsK v))

--  The enumeration contains 2ᵏ entries, giving the attack's query count.
length-allVecsK : (k : ℕ) → length (allVecsK k) ≡ 2 ^ k
length-allVecsK zero    = refl
length-allVecsK (suc k) =
  trans (length-++ (map (Vec._∷_ false) (allVecsK k)) {map (Vec._∷_ true) (allVecsK k)})
        (trans (cong₂ _+_ (length-map (Vec._∷_ false) (allVecsK k))
                          (length-map (Vec._∷_ true)  (allVecsK k)))
               (trans (cong₂ _+_ (length-allVecsK k) (length-allVecsK k))
                      (cong (2 ^ k +_) (sym (+-identityʳ (2 ^ k))))))
