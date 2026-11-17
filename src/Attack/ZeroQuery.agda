------------------------------------------------------------------------
--  The lower bound requires recovery uniformly over all secrets.
--  For each separately fixed secret s, a constant adversary can issue no
--  probes and return s; fixed-secret-zero-query proves this directly.
--  Recovers instead requires one adversary, fixed before the secret,
--  to recover every possible secret. zero-query-not-uniform applies
--  the generic lower bound at q=0 and n≥1 to exclude that uniform claim.
--  At n=0 there is only one key and the constant adversary is uniform.
--  Per-secret existence and existence of a uniform adversary are different
--  quantifier orders; the former does not contradict the query optimum.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.ZeroQuery where

open import Data.Bool using (Bool)
open import Data.Nat using (ℕ; suc; _≤_; _^_)
open import Data.Product using (Σ; _,_; Σ-syntax)
open import Data.Vec using (Vec; [])
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Relation.Nullary using (¬_)

open import Locking.GenericLock using (ProtGadget)
open import Attack.Oracle using (QAdversary; ask; Recovers)
open import Attack.GenericSAT using (actGen; PointConc; gen-ExactResist)
open import Attack.ExactQuery using (2≤2^)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  §1 Zero-query recovery for a separately fixed secret

--  Use an empty probe vector and a decoder returning `s`. Mapping the oracle
--  over that vector with `ask` yields no answers, so decoding simply returns
--  its fixed value. The equality follows from `refl` without invoking any lock
--  property. Consequently this per-secret result applies independently of the
--  particular locking scheme.
fixed-secret-zero-query :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n)
  (s : Vec Bool n) →
  Σ[ A ∈ QAdversary (Vec Bool n) Bool (Vec Bool n) 0 ]
    (ask A (actGen f gS G s) ≡ s)
fixed-secret-zero-query f gS G s =
  record { probes = [] ; decode = λ _ → s } , refl

------------------------------------------------------------------------
--  §2 Uniform recovery cannot use zero queries

--  Specialise the generic bound to its minimum budget. The requirement
--  `2 + 0 ≤ 2 ^ n` simplifies to `2 ≤ 2 ^ n`, using `1 ≤ n`.
--  This premise is essential: at `n = 0` the sole key makes the constant
--  adversary correct uniformly as well.
zero-query-not-uniform :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → 1 ≤ n →
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) 0) →
  ¬ Recovers A (actGen f gS G)
zero-query-not-uniform {n} f gS G pc 1≤n A =
  gen-ExactResist f gS G pc A (2≤2^ n 1≤n)
