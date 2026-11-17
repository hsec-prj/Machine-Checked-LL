{-# OPTIONS --safe --without-K #-}

module Util.BoolVec where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; true; false; _∧_)
open import Data.Bool.Properties using (∧-conicalˡ; ∧-conicalʳ)
open import Data.Empty using (⊥; ⊥-elim)
import Data.Vec as Vec
open Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; cong₂; sym; trans)

private
  variable
    n : ℕ

  t≢f : true ≡ false → ⊥
  t≢f ()

eqB : Bool → Bool → Bool
eqB true  true  = true
eqB false false = true
eqB true  false = false
eqB false true  = false

eqVec : Vec Bool n → Vec Bool n → Bool
eqVec Vec.[]       Vec.[]       = true
eqVec (x Vec.∷ xs) (y Vec.∷ ys) = eqB x y ∧ eqVec xs ys

eqB-refl : (value : Bool) → eqB value value ≡ true
eqB-refl true = refl
eqB-refl false = refl

eqVec-refl : (values : Vec Bool n) → eqVec values values ≡ true
eqVec-refl Vec.[] = refl
eqVec-refl (value Vec.∷ values) = cong₂ _∧_ (eqB-refl value) (eqVec-refl values)

eqB-sound : (left right : Bool) → eqB left right ≡ true → left ≡ right
eqB-sound true true proof = refl
eqB-sound false false proof = refl
eqB-sound true false ()
eqB-sound false true ()

eqB-complete : (left right : Bool) → left ≡ right → eqB left right ≡ true
eqB-complete left .left refl = eqB-refl left

eqVec-sound : (left right : Vec Bool n) → eqVec left right ≡ true → left ≡ right
eqVec-sound Vec.[] Vec.[] proof = refl
eqVec-sound (left Vec.∷ lefts) (right Vec.∷ rights) proof =
  cong₂ Vec._∷_
    (eqB-sound left right (∧-conicalˡ (eqB left right) (eqVec lefts rights) proof))
    (eqVec-sound lefts rights (∧-conicalʳ (eqB left right) (eqVec lefts rights) proof))

eqVec-complete : (left right : Vec Bool n) → left ≡ right → eqVec left right ≡ true
eqVec-complete left .left refl = eqVec-refl left

eqVec-false→≢ : (left right : Vec Bool n) → eqVec left right ≡ false → left ≢ right
eqVec-false→≢ left .left different refl = t≢f (trans (sym (eqVec-refl left)) different)

≢→eqVec-false : (left right : Vec Bool n) → left ≢ right → eqVec left right ≡ false
≢→eqVec-false left right different with eqVec left right in equal
... | true = ⊥-elim (different (eqVec-sound left right equal))
... | false = refl
