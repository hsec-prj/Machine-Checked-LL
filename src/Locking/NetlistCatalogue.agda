------------------------------------------------------------------------
--  Realise the locking catalogue at gate level. SFLL.Netlist builds SFLL-HD
--  in the circuit DSL and proves agreement with semantic locked, connecting
--  OCR theorems to a concrete netlist. Extend that connection to the remaining
--  schemes by reusing prot-circuit and locked-circuit plus combine2. The
--  helper duplicates the input bus, executes two single-output circuits,
--  then passes their bits to a two-input gate G. SARLock is radius-zero
--  SFLL: sarLocked-circuit uses locked-circuit … 0 and denotes sarLocked.
--  Anti-SAT combines two radius-zero comparators with AND to realise
--  [x=k1] ∧ ¬[x=k2], proved by antiSat-circuit-correct. The circuit for
--  prot ksec ⊕ prot kapp implements corruption via corrupt-circuit-correct.
--  Finally bypass-circuit-correct proves that locked ⊕ corrupt restores
--  f at gate level. This construction takes both secret and applied
--  gadgets as parameters; it does not discover a secret or correction
--  from an attacker observation. Per-wire schemes in Locking.* and
--  SFLL.Netlist's comparators have their own gate-level representations.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.NetlistCatalogue where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; not; _∧_; _xor_)
open import Data.Vec using (Vec; []; _∷_; _++_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; cong₂; trans)

open import Circuit.Core using (Circuit; Seq; Par; And2; Xor2; Not1)
open import Circuit.Semantics using (⟦_⟧)
open import Circuit.Util.Vec using (take-++; drop-++)
open import SFLL.Netlist
  using (prot-circuit; prot-circuit-correct; locked-circuit; locked-circuit-correct;
         dupAll; dupAll-spec)
open import SFLL.HD using (prot; locked)
open import Security.OCR using (corrupt)
open import Security.SARLock using (sarLocked)
open import Security.AntiSat using (antiSat)
open import Attack.Bypass using (bypass; bypass-correct)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Combine gates by duplicating inputs, running two subcircuits, and applying
--  a two-input gate to their outputs.

combine2 : (G : Circuit 2 1) (C₁ C₂ : Circuit n 1) → Circuit n 1
combine2 {n} G C₁ C₂ = Seq (dupAll n) (Seq (Par {n₁ = n} C₁ C₂) G)

combine2-spec :
  (G : Circuit 2 1) (C₁ C₂ : Circuit n 1) (a b g : Bool) (x : Vec Bool n) →
  ⟦ C₁ ⟧ x ≡ a ∷ [] → ⟦ C₂ ⟧ x ≡ b ∷ [] → ⟦ G ⟧ (a ∷ b ∷ []) ≡ g ∷ [] →
  ⟦ combine2 G C₁ C₂ ⟧ x ≡ g ∷ []
combine2-spec {n} G C₁ C₂ a b g x p₁ p₂ pg =
  trans (cong (λ w → ⟦ G ⟧ (⟦ Par {n₁ = n} C₁ C₂ ⟧ w)) (dupAll-spec n x))
        (trans (cong ⟦ G ⟧ step) pg)
  where
    step : ⟦ Par {n₁ = n} C₁ C₂ ⟧ (x ++ x) ≡ a ∷ b ∷ []
    step = cong₂ _++_ (trans (cong ⟦ C₁ ⟧ (take-++ x x)) p₁)
                      (trans (cong ⟦ C₂ ⟧ (drop-++ x x)) p₂)

--  Negate the output of a single-output subcircuit at circuit level.
notC : Circuit n 1 → Circuit n 1
notC C = Seq C Not1

notC-spec : (C : Circuit n 1) (p : Bool) (x : Vec Bool n) →
            ⟦ C ⟧ x ≡ p ∷ [] → ⟦ notC C ⟧ x ≡ not p ∷ []
notC-spec C p x pc = cong ⟦ Not1 ⟧ pc

------------------------------------------------------------------------
--  Instantiate SARLock as SFLL with radius zero.

sarLocked-circuit : (Cf : Circuit n 1) (ksec kapp : Vec Bool n) → Circuit n 1
sarLocked-circuit Cf ksec kapp = locked-circuit Cf 0 ksec kapp

sarLocked-circuit-correct :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (ksec kapp x : Vec Bool n) →
  ⟦ sarLocked-circuit Cf ksec kapp ⟧ x ≡ sarLocked ksec kapp f x ∷ []
sarLocked-circuit-correct Cf f cf-ok ksec kapp x =
  locked-circuit-correct Cf f cf-ok 0 ksec kapp x

------------------------------------------------------------------------
--  Construct Anti-SAT's [x=k1] ∧ ¬[x=k2] using radius-zero comparators and AND.

antiSat-circuit : (k1 k2 : Vec Bool n) → Circuit n 1
antiSat-circuit k1 k2 =
  combine2 And2 (prot-circuit 0 k1) (notC (prot-circuit 0 k2))

antiSat-circuit-correct : (k1 k2 x : Vec Bool n) →
                          ⟦ antiSat-circuit k1 k2 ⟧ x ≡ antiSat k1 k2 x ∷ []
antiSat-circuit-correct k1 k2 x =
  combine2-spec And2 (prot-circuit 0 k1) (notC (prot-circuit 0 k2))
    (prot 0 k1 x) (not (prot 0 k2 x)) (prot 0 k1 x ∧ not (prot 0 k2 x)) x
    (prot-circuit-correct 0 k1 x)
    (notC-spec (prot-circuit 0 k2) (prot 0 k2 x) x (prot-circuit-correct 0 k2 x))
    refl

------------------------------------------------------------------------
--  Realise the corruption predicate prot ksec ⊕ prot kapp as a circuit.

corrupt-circuit : (h : ℕ) (ksec kapp : Vec Bool n) → Circuit n 1
corrupt-circuit h ksec kapp =
  combine2 Xor2 (prot-circuit h ksec) (prot-circuit h kapp)

corrupt-circuit-correct : (h : ℕ) (ksec kapp x : Vec Bool n) →
                          ⟦ corrupt-circuit h ksec kapp ⟧ x ≡ corrupt h ksec kapp x ∷ []
corrupt-circuit-correct h ksec kapp x =
  combine2-spec Xor2 (prot-circuit h ksec) (prot-circuit h kapp)
    (prot h ksec x) (prot h kapp x) (prot h ksec x xor prot h kapp x) x
    (prot-circuit-correct h ksec x) (prot-circuit-correct h kapp x) refl

------------------------------------------------------------------------
--  Build the bypass locked ⊕ corrupt, eliminating the lock at gate level and
--  recovering the original function f on every input.

bypass-circuit : (Cf : Circuit n 1) (h : ℕ) (ksec kapp : Vec Bool n) → Circuit n 1
bypass-circuit Cf h ksec kapp =
  combine2 Xor2 (locked-circuit Cf h ksec kapp) (corrupt-circuit h ksec kapp)

bypass-circuit-correct :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp x : Vec Bool n) →
  ⟦ bypass-circuit Cf h ksec kapp ⟧ x ≡ f x ∷ []
bypass-circuit-correct Cf f cf-ok h ksec kapp x =
  trans (combine2-spec Xor2 (locked-circuit Cf h ksec kapp) (corrupt-circuit h ksec kapp)
           (locked h ksec kapp f x) (corrupt h ksec kapp x)
           (locked h ksec kapp f x xor corrupt h ksec kapp x) x
           (locked-circuit-correct Cf f cf-ok h ksec kapp x)
           (corrupt-circuit-correct h ksec kapp x) refl)
        (cong (_∷ []) (bypass-correct h ksec kapp f x))
