------------------------------------------------------------------------
--  Characterise the inhabitants of the strengthened specification.
--  Attack.NonDegenerate adds non-degeneracy to point concentration: `conc`
--  makes the applied-key predicate vanish away from its key, while `fires`
--  makes it hold at that key. Both real instances satisfy these conditions,
--  and the degenerate family provably fails them, so the strengthening is
--  non-vacuous. Here we establish more: PointConcND determines the predicate
--  completely as Boolean equality with its key, for every input and key.
--  Its inhabitants are therefore precisely point families up to
--  extensionality. This characterises the point (radius-0) instances used
--  in the paper's 2^n-1 bound: every admitted family agrees pointwise with
--  that construction, so the term is more than a construction's name.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.PointFamilyChar where

open import Data.Bool using (Bool; true; false)
open import Data.Nat using (ℕ)
open import Data.Vec using (Vec)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong)
open import Relation.Nullary using (¬_)

open import Locking.GenericLock using (ProtGadget)
open ProtGadget using (pred)
open import Util.BoolVec using (eqVec; eqVec-refl; eqVec-false→≢; eqVec-sound)
open import Attack.NonDegenerate using (PointConcND; conc; fires)


private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Section 1: establish the characterisation.

--  An admitted family's predicate equals Boolean key equality. Split on the
--  value of eqVec x k, without a vector equality decision procedure: soundness
--  gives x ≡ k in the true case and x ≢ k in the false case.
PointConcND→eqVec :
  (G : Vec Bool n → ProtGadget n) → PointConcND G →
  (k x : Vec Bool n) → pred (G k) x ≡ eqVec x k
PointConcND→eqVec G nd k x with eqVec x k in eq
--  The `with... in eq` abstraction replaces eqVec x k in the goal by the
--  matched value, leaving branch goals of the form ... ≡ true or ... ≡ false.
... | true  = trans (cong (λ z → pred (G k) z) (eqVec-sound x k eq)) (fires nd k)
... | false = conc nd k x (eqVec-false→≢ x k eq)

--  State the immediate converse as well: a family with this equality
--  predicate satisfies the strengthened specification, completing an equivalence.
eqVec→PointConcND :
  (G : Vec Bool n → ProtGadget n) →
  ((k x : Vec Bool n) → pred (G k) x ≡ eqVec x k) → PointConcND G
eqVec→PointConcND G h = record
  { conc  = λ k x x≢k → trans (h k x) (lemma x k x≢k)
  ; fires = λ k → trans (h k k) (eqVec-refl k)
  }
  where
    lemma : (x k : Vec Bool n) → x ≢ k → eqVec x k ≡ false
    lemma x k x≢k with eqVec x k in eq
    ... | true  = ⊥-elim (x≢k (eqVec-sound x k eq))
    ... | false = refl
