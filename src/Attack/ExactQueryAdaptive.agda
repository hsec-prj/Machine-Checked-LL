------------------------------------------------------------------------
--  Exact uniform recovery for deterministic adaptive Boolean adversaries.
--  Attack.ExactQuery proves the non-adaptive optimum 2ⁿ−1. toAdaptive
--  interprets fixed probes as an adaptive run that ignores earlier answers;
--  run-toAdaptive preserves its output. point-ExactQueryA combines that
--  winner with gen-adaptive-ExactResist's failure at every smaller budget.
--  The public family parameters permit offline candidate evaluation, but
--  the adversary receives no secret-bearing delivered netlist. Recovery
--  must hold for every secret, with the adversary fixed before the secret.
--  Only oracle calls are counted; no decoder time bound is established.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.ExactQueryAdaptive where

open import Data.Bool using (Bool)
open import Data.Nat using (ℕ; suc; _+_; _≤_; _^_; _∸_)
open import Data.Vec using (Vec; []; _∷_; map)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans; sym)
open import Relation.Nullary using (¬_)

open import Locking.GenericLock using (ProtGadget; pointGadget)
open import Attack.Oracle using (QAdversary; ask; Recovers)
open QAdversary using (probes; decode)
open import Attack.Adaptive using (Adaptive; stop; query; run; RecoversA)
open import Attack.GenericSAT
  using (actGen; PointConc; point-PointConc; gen-adaptive-ExactResist)
open import Attack.ExactQuery using (ExactQuery; point-ExactQuery)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Section 1: interpret a fixed probe vector as an adaptive computation.

--  Ask each probe in order, accumulating answers without using them to choose
--  later probes. Thread the decoder through continuations so the leaf receives
--  answers in query order.
go : ∀ {X Y K q} → Vec X q → (Vec Y q → K) → Adaptive X Y K q
go []       d = stop (d [])
go (x ∷ xs) d = query x (λ y → go xs (λ ys → d (y ∷ ys)))

toAdaptive : ∀ {X Y K q} → QAdversary X Y K q → Adaptive X Y K q
toAdaptive A = go (probes A) (decode A)

--  Prove output preservation by induction over probes. At a leaf both terms
--  apply the decoder to an empty answer list; the step applies the induction
--  hypothesis to the extended decoder.
run-go : ∀ {X Y K q} (xs : Vec X q) (d : Vec Y q → K) (O : X → Y) →
         run (go xs d) O ≡ d (map O xs)
run-go []       d O = refl
run-go (x ∷ xs) d O = run-go xs (λ ys → d (O x ∷ ys)) O

run-toAdaptive : ∀ {X Y K q} (A : QAdversary X Y K q) (O : X → Y) →
                 run (toAdaptive A) O ≡ ask A O
run-toAdaptive A O = run-go (probes A) (decode A) O

--  Transfer recovery through the coercion in either direction.
Recovers→A : ∀ {X Y K q} (A : QAdversary X Y K q) (act : K → X → Y) →
             Recovers A act → RecoversA (toAdaptive A) act
Recovers→A A act rec k = trans (run-toAdaptive A (act k)) (rec k)

------------------------------------------------------------------------
--  Section 2: match the adaptive upper and lower bounds.

--  Use ExactQuery's structure and budget with the Adaptive adversary type.
record ExactQueryA (f : Vec Bool n → Bool) (gS : ProtGadget n) : Set where
  field
    opt    : Adaptive (Vec Bool n) Bool (Vec Bool n) (2 ^ n ∸ 1)
    opt-ok : RecoversA opt (actGen f gS pointGadget)
    below  : ∀ {r} (A : Adaptive (Vec Bool n) Bool (Vec Bool n) r) →
             2 + r ≤ 2 ^ n → ¬ RecoversA A (actGen f gS pointGadget)
open ExactQueryA public

--  Instantiate the point family using the coerced non-adaptive optimum for
--  the upper bound and the existing adaptive theorem for the lower bound.
point-ExactQueryA :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) → ExactQueryA f gS
point-ExactQueryA f gS = record
  { opt    = toAdaptive (ExactQuery.opt eq)
  ; opt-ok = Recovers→A (ExactQuery.opt eq) _ (ExactQuery.opt-ok eq)
  ; below  = λ A bound →
               gen-adaptive-ExactResist f gS pointGadget point-PointConc A bound
  }
  where eq = point-ExactQuery f gS
