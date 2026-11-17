------------------------------------------------------------------------
--  Generalise certified locking (M1 feasibility). EfficientLock's
--  SFLL-HD construction fans inputs three ways, runs the host
--  and two protected tests in parallel, then XORs the results.
--  That structure does not require a Hamming-popcount test.
--  Parameterise it by ProtGadget, a predicate circuit with
--  correctness, to cover arbitrary corruption-based schemes.
--  sfllGadget recovers SFLL-HD; point and membership gadgets
--  give SARLock/Anti-SAT and SFLL-flex instances. Generic
--  corruption is Flex.OCR-gen's symmetric-difference count,
--  handled uniformly by CorruptionCalculus. Correctness and
--  exact corruption therefore share a framework, with only
--  the gadget and cardinality specific to each scheme. No postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.GenericLock where

open import Data.Nat using (ℕ; suc; _≤_)
open import Data.Fin using (Fin; toℕ; zero)
open import Data.Bool using (Bool; _xor_)
open import Data.Bool.Properties using (xor-assoc; xor-same; xor-identityʳ)
open import Data.Vec using (Vec; []; _∷_; _++_)
open import Data.List using (List; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans; cong; cong₂)

open import Circuit.Core using (Circuit; Or2; Seq; Par)
open import Circuit.Semantics using (⟦_⟧)
open import Circuit.Util.Vec using (take-++; drop-++)
open import SFLL.Netlist
  using (tripleAll; tripleAll-spec; xor3; xor3-spec; dupAll; dupAll-spec; cFalse; cFalse-spec)
open import SFLL.EfficientLock using (prot-circuit-eff; prot-circuit-eff-correct; locked-circuit-eff)
open import SFLL.HD using (prot; locked)
open import SFLL.Flex using (OCR-gen; protList)
open import Security.CorruptionCalculus using (calc-point-≤2)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Package a protected predicate with a circuit and correctness proof.

record ProtGadget (n : ℕ) : Set where
  field
    pred    : Vec Bool n → Bool
    gadget  : Circuit n 1
    correct : (x : Vec Bool n) → ⟦ gadget ⟧ x ≡ pred x ∷ []
open ProtGadget

------------------------------------------------------------------------
--  Define the generic locked function and its circuit implementation.

--  Compute (f xor pSec) xor pApp for any two protected predicates.
locked-fun-gen : (f : Vec Bool n → Bool) (gS gA : ProtGadget n) →
                 Vec Bool n → Bool
locked-fun-gen f gS gA x = (f x xor pred gS x) xor pred gA x

--  Instantiate EfficientLock's structural skeleton with arbitrary gadgets.
locked-circuit-gen : (Cf : Circuit n 1) (gS gA : ProtGadget n) → Circuit n 1
locked-circuit-gen {n} Cf gS gA =
  Seq (tripleAll n)
      (Seq (Par {n₁ = n} Cf (Par {n₁ = n} (gadget gS) (gadget gA))) xor3)

--  Reuse the efficient-lock correctness argument, replacing the
--  SFLL comparator theorem with each gadget's correct field.
locked-circuit-gen-correct :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (gS gA : ProtGadget n) (x : Vec Bool n) →
  ⟦ locked-circuit-gen Cf gS gA ⟧ x ≡ locked-fun-gen f gS gA x ∷ []
locked-circuit-gen-correct {n} Cf f cf-ok gS gA x =
  trans (cong (λ w → ⟦ xor3 ⟧ (⟦ mid ⟧ w)) (tripleAll-spec n x))
        (trans (cong ⟦ xor3 ⟧ stepM)
               (xor3-spec (f x) (pred gS x) (pred gA x)))
  where
    mid = Par {n₁ = n} Cf (Par {n₁ = n} (gadget gS) (gadget gA))
    stepM : ⟦ mid ⟧ (x ++ (x ++ x)) ≡ f x ∷ pred gS x ∷ pred gA x ∷ []
    stepM = cong₂ _++_
      (trans (cong ⟦ Cf ⟧ (take-++ x (x ++ x))) (cf-ok x))
      (trans (cong ⟦ Par {n₁ = n} (gadget gS) (gadget gA) ⟧ (drop-++ x (x ++ x)))
             (cong₂ _++_
               (trans (cong ⟦ gadget gS ⟧ (take-++ x x)) (correct gS x))
               (trans (cong ⟦ gadget gA ⟧ (drop-++ x x)) (correct gA x))))

------------------------------------------------------------------------
--  Prove right-key recovery for every covered scheme. Equal
--  gadgets in both slots cancel their XORs by xor-same,
--  yielding locked-fun-gen-recover and locked-circuit-gen-recover.
--  This generalises SFLL.HD.SFLL_correct's SFLL-only law.
--  It establishes intended functional behaviour, not a security property.

locked-fun-gen-recover :
  (f : Vec Bool n → Bool) (g : ProtGadget n) (x : Vec Bool n) →
  locked-fun-gen f g g x ≡ f x
locked-fun-gen-recover f g x =
  trans (xor-assoc (f x) (pred g x) (pred g x))
        (trans (cong (f x xor_) (xor-same (pred g x)))
               (xor-identityʳ (f x)))

--  At circuit level, equal gadgets in both slots denote
--  the host circuit's original function.
locked-circuit-gen-recover :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (g : ProtGadget n) (x : Vec Bool n) →
  ⟦ locked-circuit-gen Cf g g ⟧ x ≡ f x ∷ []
locked-circuit-gen-recover Cf f cf-ok g x =
  trans (locked-circuit-gen-correct Cf f cf-ok g g x)
        (cong (_∷ []) (locked-fun-gen-recover f g x))

--  Measure generic corruption by OCR-gen on the two predicates,
--  with its value supplied by CorruptionCalculus.
ocrGen-of : (gS gA : ProtGadget n) → ℕ
ocrGen-of gS gA = OCR-gen (pred gS) (pred gA)

------------------------------------------------------------------------
--  Instantiate SFLL-HD with the popcount-comparator gadget.

sfllGadget : (hF : Fin (suc n)) (k : Vec Bool n) → ProtGadget n
sfllGadget hF k = record
  { pred    = prot (toℕ hF) k
  ; gadget  = prot-circuit-eff hF k
  ; correct = prot-circuit-eff-correct hF k
  }

--  Identify the efficient SFLL circuit definitionally with
--  the generic construction specialised to sfllGadget.
sfll-is-gen :
  (Cf : Circuit n 1) (hF : Fin (suc n)) (ksec kapp : Vec Bool n) →
  locked-circuit-eff Cf hF ksec kapp
  ≡ locked-circuit-gen Cf (sfllGadget hF ksec) (sfllGadget hF kapp)
sfll-is-gen Cf hF ksec kapp = refl

--  Derive SFLL_correct's right-key proposition by applying
--  locked-fun-gen-recover to sfllGadget, without SFLL-specific reasoning.
sfll-recover :
  (hF : Fin (suc n)) (ksec : Vec Bool n) (f : Vec Bool n → Bool) (x : Vec Bool n) →
  locked (toℕ hF) ksec ksec f x ≡ f x
sfll-recover hF ksec f x = locked-fun-gen-recover f (sfllGadget hF ksec) x

------------------------------------------------------------------------
--  Use the radius-zero popcount comparator as the point
--  gadget protecting {k}, covering SARLock/Anti-SAT. The
--  generic construction applies and its calculus bounds corruption by two.

pointGadget : (k : Vec Bool n) → ProtGadget n
pointGadget k = sfllGadget zero k          --  pred = prot 0 k = {k}

--  Bound point-family corruption by two inputs through the
--  same calculus, contrasting with SFLL-HD's 2C regime.
point-ocr-≤2 : (k k' : Vec Bool n) → ocrGen-of (pointGadget k) (pointGadget k') ≤ 2
point-ocr-≤2 k k' = calc-point-≤2 k k'

------------------------------------------------------------------------
--  Instantiate SFLL-flex with an arbitrary finite protected
--  set, implemented by an OR tree of membership point comparators.

flexCirc : List (Vec Bool n) → Circuit n 1
flexCirc []      = cFalse _
flexCirc (s ∷ S) =
  Seq (dupAll _) (Seq (Par (prot-circuit-eff zero s) (flexCirc S)) Or2)

flexCirc-correct : (S : List (Vec Bool n)) (x : Vec Bool n) →
                   ⟦ flexCirc S ⟧ x ≡ protList S x ∷ []
flexCirc-correct []      x = cFalse-spec _ x
flexCirc-correct (s ∷ S) x =
  trans (cong ⟦ Seq (Par (prot-circuit-eff zero s) (flexCirc S)) Or2 ⟧ (dupAll-spec _ x))
        (cong ⟦ Or2 ⟧ parStep)
  where
    parStep : ⟦ Par (prot-circuit-eff zero s) (flexCirc S) ⟧ (x ++ x)
              ≡ prot 0 s x ∷ protList S x ∷ []
    parStep = cong₂ _++_
      (trans (cong ⟦ prot-circuit-eff zero s ⟧ (take-++ x x))
             (prot-circuit-eff-correct zero s x))
      (trans (cong ⟦ flexCirc S ⟧ (drop-++ x x)) (flexCirc-correct S x))

flexGadget : List (Vec Bool n) → ProtGadget n
flexGadget S = record
  { pred    = protList S
  ; gadget  = flexCirc S
  ; correct = flexCirc-correct S
  }

--  Use locked-circuit-gen for all three families: sfllGadget
--  for SFLL-HD, pointGadget for SARLock/points, and flexGadget
--  for SFLL-flex, each receiving its corruption result from the calculus.
