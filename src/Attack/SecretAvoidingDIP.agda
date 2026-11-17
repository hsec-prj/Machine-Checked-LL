------------------------------------------------------------------------
--  Name the lower bound by its explicit secret-avoidance premise.
--  For a point-concentrated family, q distinguishing inputs that avoid
--  ksec leave two distinct consistent keys whenever 2+q ≤ 2ⁿ.
--  gen-secret-avoiding-DIP-lb aliases gen-SAT-lb with exactly that type.
--  A netlist-guided SAT attacker may inspect a secret-bearing artifact
--  and select ksec itself; this theorem does not establish its cost.
--  The separate uniform query bounds use key-oblivious adversaries and
--  also do not grant a delivered secret-bearing netlist.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.SecretAvoidingDIP where

open import Data.Bool using (Bool)
open import Data.Fin using (Fin)
open import Data.Nat using (ℕ; _+_; _^_; _≤_)
open import Data.Product using (∃; _×_)
open import Data.Vec using (Vec; lookup)
open import Relation.Binary.PropositionalEquality using (_≢_; _≡_; refl)

open import Locking.GenericLock using (ProtGadget)
open import Attack.SATAttack using (consistentOn)
open import Attack.GenericSAT using (actGen; PointConc; gen-SAT-lb)

private
  variable
    n q : ℕ

------------------------------------------------------------------------
--  Section 1: expose the bound under a name reflecting its premise.

--  After q distinguishing inputs that avoid ksec, two distinct candidates
--  survive. Present the full gen-SAT-lb type here so the manuscript can display
--  the entire statement under the accurate name.
gen-secret-avoiding-DIP-lb :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (ksec : Vec Bool n) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOn (actGen f gS G) ksec xs k₁
    × consistentOn (actGen f gS G) ksec xs k₂
gen-secret-avoiding-DIP-lb = gen-SAT-lb

--  Check that both names refer to the identical proof. This verifies that
--  the change is solely a renaming and contributes no second result.
same-theorem :
  {f : Vec Bool n → Bool} {gS : ProtGadget n} {G : Vec Bool n → ProtGadget n} →
  gen-secret-avoiding-DIP-lb {n} {q} f gS G ≡ gen-SAT-lb f gS G
same-theorem = refl
