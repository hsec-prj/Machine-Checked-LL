------------------------------------------------------------------------
--  Derive failed recovery from indistinguishability. Attack.FALL used the
--  budget-indexed QAdversary from Attack.Oracle to show sufficiency: n
--  queries recover the SFLL key via FALL-recovers-key. Here the same type
--  expresses impossibility. A non-adaptive q-query adversary receives only
--  answers to q fixed probes. If distinct keys' activated oracles agree on
--  those probes, its guess is identical for both and cannot recover both
--  secrets. The argument is scheme-independent and uses only ask's access
--  through probes. Attack.SARLockResist instantiates it with single-point
--  wrong-key corruption to obtain resistance, complementing FALL recovery.
--  The central map-lookup-cong lemma supplies the converse of the
--  map-cong/map-lookup-allFin reasoning used in Attack.FALL.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.QueryLowerBound where

open import Data.Fin using (Fin; zero; suc)
open import Data.Vec using (Vec; []; _∷_; map; lookup)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; _≢_)
open import Relation.Nullary using (¬_)

open import Attack.Oracle using (QAdversary; ask; Recovers)

------------------------------------------------------------------------
--  Pointwise agreement on the vector's elements suffices for equal map
--  results. Agreement is needed only on probes, not on the whole domain,
--  providing the converse direction of map-cong.

map-lookup-cong : ∀ {a b} {A : Set a} {B : Set b} {q}
                  (f g : A → B) (xs : Vec A q) →
                  (∀ i → f (lookup xs i) ≡ g (lookup xs i)) →
                  map f xs ≡ map g xs
map-lookup-cong f g []       h = refl
map-lookup-cong f g (x ∷ xs) h =
  cong₂ _∷_ (h zero) (map-lookup-cong f g xs (λ i → h (suc i)))

------------------------------------------------------------------------
--  The result of ask is determined solely by answers to its probes.

ask-cong : ∀ {X Y K q} (A : QAdversary X Y K q) {O₁ O₂ : X → Y} →
           map O₁ (QAdversary.probes A) ≡ map O₂ (QAdversary.probes A) →
           ask A O₁ ≡ ask A O₂
ask-cong A eq = cong (QAdversary.decode A) eq

------------------------------------------------------------------------
--  Distinct keys indistinguishable on the chosen probes prevent recovery
--  by any adversary using those probes.

indistinguishable→¬Recovers :
  ∀ {X Y K q} (A : QAdversary X Y K q) (act : K → X → Y) {k₁ k₂ : K} →
    k₁ ≢ k₂ →
    (∀ i → act k₁ (lookup (QAdversary.probes A) i)
         ≡ act k₂ (lookup (QAdversary.probes A) i)) →
    ¬ Recovers A act
indistinguishable→¬Recovers A act {k₁} {k₂} ne agree rec =
  ne (trans (sym (rec k₁)) (trans askeq (rec k₂)))
  where
    askeq : ask A (act k₁) ≡ ask A (act k₂)
    askeq = ask-cong A (map-lookup-cong (act k₁) (act k₂) (QAdversary.probes A) agree)

------------------------------------------------------------------------
--  Generic structural point-function resistance: suppose distinct keys agree
--  away from their own two points, so each is distinguished only at its
--  key-located point. An unprobed pair then defeats recovery. SARLock-resist
--  in Attack.SARLockResist instantiates act = actSAR s f and discharges agree
--  with actSAR-agree. SFLL-HD lies at the opposite extreme, distinguishing
--  keys across whole spheres; the premise fails, explaining the FALL attack.

resist-off-diag :
  ∀ {Y q} {K : Set} (act : K → K → Y)
    (agree : (k₁ k₂ x : K) → x ≢ k₁ → x ≢ k₂ → act k₁ x ≡ act k₂ x)
    (A : QAdversary K Y K q) {k₁ k₂ : K} → k₁ ≢ k₂ →
    (∀ i → lookup (QAdversary.probes A) i ≢ k₁) →
    (∀ i → lookup (QAdversary.probes A) i ≢ k₂) →
    ¬ Recovers A act
resist-off-diag act agree A {k₁} {k₂} ne p₁ p₂ =
  indistinguishable→¬Recovers A act ne
    (λ i → agree k₁ k₂ (lookup (QAdversary.probes A) i) (p₁ i) (p₂ i))
