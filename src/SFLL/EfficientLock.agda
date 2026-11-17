------------------------------------------------------------------------
--  Construct an efficient verified locked circuit (item 2, section 8-iv).
--  SFLL.Netlist's `locked-circuit` uses the verified `exactlyH` comparator,
--  whose mux tree grows exponentially with cube width. Although correct, it
--  is unsuitable for synthesis; measured artifacts have instead used an
--  external splice with an efficient popcount comparator, creating the
--  substitution trust link of section 8-iv. This module performs that
--  replacement within Agda, retaining the lock construction and using the
--  polynomial, synthesizable `popcountEqC` from SFLL.PopcountCircuit. Both
--  `exactlyH-spec` and `popcountEqC-spec` describe `weight v ≡ᵇ threshold`, so
--  the `locked-circuit-correct` argument applies with the new comparator:
--  locked-circuit-eff-correct :
--  ⟦ locked-circuit-eff Cf hF ksec kapp ⟧ x ≡ locked (toℕ hF) ksec kapp f x ∷ []
--  A real host imported through Locking.NetlistToCircuit can thus produce
--  a lock that is both verified and synthesizable, allowing the verified
--  netlist itself to serve as the measured artifact. No postulates are used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.EfficientLock where

open import Data.Nat using (ℕ; suc; _≡ᵇ_)
open import Data.Fin using (Fin; toℕ)
open import Data.Bool using (Bool)
open import Data.Vec using (Vec; []; _∷_; _++_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; trans; cong; cong₂)

open import Circuit.Core using (Circuit; Seq; Par)
open import Circuit.Semantics using (⟦_⟧)
open import Circuit.Util.Vec using (take-++; drop-++)
open import SFLL.HD using (prot; locked)
open import SFLL.PopcountCircuit using (popcountEqC; popcountEqC-spec)
open import SFLL.Netlist using
  (xorK; xorK-weight; tripleAll; tripleAll-spec; xor3; xor3-spec)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Implement the protection test by XORing the key and applying the polynomial
--  popcount comparator. It meets prot-circuit's specification and permits synthesis.

prot-circuit-eff : (hF : Fin (suc n)) (k : Vec Bool n) → Circuit n 1
prot-circuit-eff {n} hF k = Seq (xorK k) (popcountEqC n hF)

prot-circuit-eff-correct : (hF : Fin (suc n)) (k x : Vec Bool n) →
  ⟦ prot-circuit-eff hF k ⟧ x ≡ prot (toℕ hF) k x ∷ []
prot-circuit-eff-correct {n} hF k x =
  trans (popcountEqC-spec n hF (⟦ xorK k ⟧ x))
        (cong (λ w → (w ≡ᵇ toℕ hF) ∷ []) (xorK-weight k x))

------------------------------------------------------------------------
--  Retain SFLL.Netlist.locked-circuit's assembly, substituting prot-circuit-eff
--  for each of its two protection tests.

locked-circuit-eff :
  (Cf : Circuit n 1) (hF : Fin (suc n)) (ksec kapp : Vec Bool n) → Circuit n 1
locked-circuit-eff {n} Cf hF ksec kapp =
  Seq (tripleAll n)
      (Seq (Par {n₁ = n} Cf
              (Par {n₁ = n} (prot-circuit-eff hF ksec) (prot-circuit-eff hF kapp)))
           xor3)

--  Prove that the efficient circuit denotes the locked function, reusing the
--  exponential-comparator argument with only the comparator replaced.
locked-circuit-eff-correct :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (hF : Fin (suc n)) (ksec kapp x : Vec Bool n) →
  ⟦ locked-circuit-eff Cf hF ksec kapp ⟧ x ≡ locked (toℕ hF) ksec kapp f x ∷ []
locked-circuit-eff-correct {n} Cf f cf-ok hF ksec kapp x =
  trans (cong (λ w → ⟦ xor3 ⟧ (⟦ mid ⟧ w)) (tripleAll-spec n x))
        (trans (cong ⟦ xor3 ⟧ stepM)
               (xor3-spec (f x) (prot (toℕ hF) ksec x) (prot (toℕ hF) kapp x)))
  where
    mid = Par {n₁ = n} Cf
            (Par {n₁ = n} (prot-circuit-eff hF ksec) (prot-circuit-eff hF kapp))
    stepM : ⟦ mid ⟧ (x ++ (x ++ x))
              ≡ f x ∷ prot (toℕ hF) ksec x ∷ prot (toℕ hF) kapp x ∷ []
    stepM = cong₂ _++_
      (trans (cong ⟦ Cf ⟧ (take-++ x (x ++ x))) (cf-ok x))
      (trans (cong ⟦ Par {n₁ = n} (prot-circuit-eff hF ksec)
                          (prot-circuit-eff hF kapp) ⟧
                   (drop-++ x (x ++ x)))
             (cong₂ _++_
               (trans (cong ⟦ prot-circuit-eff hF ksec ⟧ (take-++ x x))
                      (prot-circuit-eff-correct hF ksec x))
               (trans (cong ⟦ prot-circuit-eff hF kapp ⟧ (drop-++ x x))
                      (prot-circuit-eff-correct hF kapp x))))
