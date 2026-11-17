------------------------------------------------------------------------
--  A common OCR account for SFLL-flex and arbitrary protected sets
--  SFLL-HD chooses a Hamming sphere; SFLL-flex allows any specified pattern
--  set. Both follow the same principle: for protected predicates
--  `p, q : Vec Bool n → Bool`, OCR counts their symmetric difference.
--  Inclusion–exclusion gives OCR(p,q) + 2·|p ∧ q| = |p| + |q|,
--  directly by `Util.Counting.countT-and-xor`. Taking `p = prot h k`
--  recovers SFLL-HD, `prot 0` gives SARLock, and finite-set membership
--  `protList S` supplies the flex case. Thus the exact OCR argument applies
--  beyond spheres; spheres additionally provide the Pascal formula
--  `|prot h k| = C(n,h)`.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.Flex where

open import Data.Nat using (ℕ; _+_; _*_)
open import Data.Bool using (Bool; false; _∧_; _∨_; _xor_)
open import Data.Vec using (Vec)
open import Data.List using (List; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import SFLL.HD using (prot)
open import Util.Counting using (countT; allVecs; binom; countT-and-xor)
open import Security.OCR using (OCR; sphere-count)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Corruption counts for unrestricted protected predicates

--  Define the symmetric-difference count, intersection count, and set size.
OCR-gen : (p q : Vec Bool n → Bool) → ℕ
OCR-gen {n} p q = countT (λ x → p x xor q x) (allVecs n)

inter-gen : (p q : Vec Bool n → Bool) → ℕ
inter-gen {n} p q = countT (λ x → p x ∧ q x) (allVecs n)

card : (p : Vec Bool n → Bool) → ℕ
card {n} p = countT p (allVecs n)

--  Any pair of protected predicates satisfies inclusion–exclusion.
OCR-gen-incl-excl : (p q : Vec Bool n → Bool) →
                    OCR-gen p q + 2 * inter-gen p q ≡ card p + card q
OCR-gen-incl-excl {n} p q = countT-and-xor p q (allVecs n)

------------------------------------------------------------------------
--  Instantiate the general account with SFLL-HD Hamming spheres

--  Applying `OCR-gen` to the sphere predicate `prot h` gives the
--  sphere-based OCR defined in `Security.OCR`.
OCR-is-gen : (h : ℕ) (k k' : Vec Bool n) →
             OCR h k k' ≡ OCR-gen (prot h k) (prot h k')
OCR-is-gen h k k' = refl

--  The sphere case additionally has Pascal's closed-form cardinality.
card-sphere : (h : ℕ) (k : Vec Bool n) → card (prot h k) ≡ binom n h
card-sphere h k = sphere-count h k

------------------------------------------------------------------------
--  Flex protection through membership in a selected finite pattern set

protList : List (Vec Bool n) → Vec Bool n → Bool
protList []      x = false
protList (s ∷ S) x = prot 0 s x ∨ protList S x
