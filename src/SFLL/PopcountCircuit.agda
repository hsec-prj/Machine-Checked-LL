------------------------------------------------------------------------
--  Close D1-B through path b: a verified thermometer circuit in the DSL
--  SFLL.Popcount proves correctness of the pure distribution `distF`.
--  This module realizes it as a `Circuit` with the exact specification
--  distC-spec : ⟦ distC N ⟧ v ≡ distF v.
--  `Extraction.Bench.emit-sound` therefore gives `distF` as the emitted
--  netlist's denotation; `SFLL.Popcount.distF-spec` identifies that function
--  with the exact weight indicator.
--  --
--  This supplies a fully verified efficient .bench route. Projecting
--  slot `k` gives the single-output comparator `popcountEqC N k`:
--  popcountEqC-spec : ⟦ popcountEqC N k ⟧ v ≡ (weight v ≡ᵇ toℕ k) ∷ [].
--  With one shift layer per input bit and no branching, `distC` is
--  polynomial and emits without exactlyH's expansion. No postulates are used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.PopcountCircuit where

open import Data.Nat using (ℕ; zero; suc; _≡ᵇ_)
open import Data.Bool using (Bool; true; false; _∧_)
open import Data.Fin using (Fin; zero; suc; toℕ)
open import Data.Vec using (Vec; []; _∷_; _++_; lookup; tabulate)
open import Data.Vec.Properties using (tabulate∘lookup; tabulate-cong)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; trans)

open import Circuit.Core
open import Circuit.Semantics using (⟦_⟧)
open import SFLL.Netlist using (weight)
open import SFLL.Popcount using (bmux; shift; distF; distF-spec)

private
  variable
    m N : ℕ

------------------------------------------------------------------------
--  Specify `Plug` against an explicit target bus using an index function.

plugSpec : {n p : ℕ} (v : Vec Bool n) (f : Fin p → Fin n) (t : Vec Bool p) →
           (∀ i → lookup v (f i) ≡ lookup t i) → ⟦ Plug f ⟧ v ≡ t
plugSpec v f t pf = trans (tabulate-cong pf) (tabulate∘lookup t)

------------------------------------------------------------------------
--  Implement the shift identity ⟦ shiftFC m ⟧ (b ∷ prev ∷ d) ≡ shift b prev d.

--  The base case is shift b prev [] = bmux b false prev = prev ∧ b.
swap2 : Fin 2 → Fin 2
swap2 zero       = suc zero
swap2 (suc zero) = zero

--  Route the step input (b ∷ prev ∷ x ∷ xs) to (b ∷ x ∷ prev) ++ (b ∷ x ∷ xs).
fIdx : Fin (suc (suc (suc (suc (suc m))))) → Fin (suc (suc (suc m)))
fIdx zero                                     = zero
fIdx (suc zero)                               = suc (suc zero)
fIdx (suc (suc zero))                         = suc zero
fIdx (suc (suc (suc zero)))                   = zero
fIdx (suc (suc (suc (suc zero))))             = suc (suc zero)
fIdx (suc (suc (suc (suc (suc i)))))          = suc (suc (suc i))

shiftFC : (m : ℕ) → Circuit (suc (suc m)) (suc m)
shiftFC zero    = Seq (Plug swap2) And2
shiftFC (suc m) = Seq (Plug fIdx) (Par {n₁ = 3} Mux21 (shiftFC m))

shiftFC-spec : (m : ℕ) (b prev : Bool) (d : Vec Bool m) →
               ⟦ shiftFC m ⟧ (b ∷ prev ∷ d) ≡ shift b prev d
shiftFC-spec zero    b prev []       = refl
shiftFC-spec (suc m) b prev (x ∷ xs) =
  trans (cong ⟦ Par {n₁ = 3} Mux21 (shiftFC m) ⟧ plug-eq)
        (cong (bmux b x prev ∷_) (shiftFC-spec m b x xs))
  where
    plug-eq : ⟦ Plug fIdx ⟧ (b ∷ prev ∷ x ∷ xs)
              ≡ (b ∷ x ∷ prev ∷ []) ++ (b ∷ x ∷ xs)
    plug-eq = plugSpec (b ∷ prev ∷ x ∷ xs) fIdx _ ok
      where
        ok : (i : Fin (suc (suc (suc (suc (suc m)))))) →
             lookup (b ∷ prev ∷ x ∷ xs) (fIdx i)
             ≡ lookup ((b ∷ x ∷ prev ∷ []) ++ (b ∷ x ∷ xs)) i
        ok zero                            = refl
        ok (suc zero)                      = refl
        ok (suc (suc zero))                = refl
        ok (suc (suc (suc zero)))          = refl
        ok (suc (suc (suc (suc zero))))    = refl
        ok (suc (suc (suc (suc (suc i))))) = refl

------------------------------------------------------------------------
--  Realize the distribution as a circuit: ⟦ distC N ⟧ v ≡ distF v.

distC : (N : ℕ) → Circuit N (suc N)
distC zero    = Const true
distC (suc N) =
  Seq (Seq (Par {n₁ = 1} Id (distC N))
           (Par {n₁ = 1} Id (Par {n₁ = 0} (Const false) Id)))
      (shiftFC (suc N))

distC-spec : (N : ℕ) (v : Vec Bool N) → ⟦ distC N ⟧ v ≡ distF v
distC-spec zero    []         = refl
distC-spec (suc N) (b ∷ rest) =
  trans (cong ⟦ shiftFC (suc N) ⟧
              (cong (λ z → b ∷ false ∷ z) (distC-spec N rest)))
        (shiftFC-spec (suc N) b false (distF rest))

------------------------------------------------------------------------
--  Project a single comparison result: ⟦ popcountEqC N k ⟧ v ≡ [weight v = toℕ k].

popcountEqC : (N : ℕ) (k : Fin (suc N)) → Circuit N 1
popcountEqC N k = Seq (distC N) (Plug (λ _ → k))

popcountEqC-spec : (N : ℕ) (k : Fin (suc N)) (v : Vec Bool N) →
                   ⟦ popcountEqC N k ⟧ v ≡ (weight v ≡ᵇ toℕ k) ∷ []
popcountEqC-spec N k v =
  trans (cong (λ d → lookup d k ∷ []) (distC-spec N v))
        (cong (_∷ []) (distF-spec v k))
