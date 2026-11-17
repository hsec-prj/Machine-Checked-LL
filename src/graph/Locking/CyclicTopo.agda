------------------------------------------------------------------------
--  Allow arbitrary feedback topology in cyclic locking (graph track, item 2c).
--  `Locking.Cyclic` adds a single key-controlled wire, and CyclicMulti adds
--  `k` loops that read only the base. Here feedback wires may also read one
--  another. Their open-loop behaviour is represented by
--  layer : Vec Bool k → Vec Bool W → Vec Bool k,
--  taking feedback and base values. Each key mux chooses the layer's value
--  at its coordinate or closes that coordinate through `b ↦ ¬b`.
--  For `HasTrue ks`, `lock-wrong-no-stable-T` rules out stability for every
--  layer: the offending wire inverts itself regardless of the layer's
--  dependencies. Hence the CycSAT obstruction is independent of topology,
--  and `model→correct-T` permits a combinational model only at the correct,
--  all-false key. This security property survives arbitrary feedback wiring.
--  At `allFalse`, `updateFBt-allFalse` reduces the update to the open layer.
--  Well-definedness therefore requires precisely a (unique) fixed point of
--  the open interconnect over the settled base, as captured by
--  `lock-correct-T` and `lock-correct-unique-T`; this holds if and only if the
--  open topology is acyclic. CyclicMulti is recovered by `baseLayer`, which
--  ignores feedback values and is trivially acyclic. The base comes from
--  `Graph.Acyclic`; muxes, `allFalse`, `HasTrue`, and `fbOpen` come from
--  `Locking.{Cyclic,CyclicMulti}`. No primitives or postulates are added.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.CyclicTopo where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Bool using (Bool; true; false; not)
open import Data.Vec using (Vec; []; _∷_; head; tail)
open import Data.Product using (Σ; _×_; _,_; proj₁; proj₂)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; _≢_)
open import Relation.Nullary using (¬_)

open import Graph.Core using (Gate; evalGate)
open import Graph.Acyclic
  using (ANetlist; astep; asolve; asolve-stable; astable-unique)
open import Locking.Cyclic using (mux; mux-false; mux-true; not-no-fixpoint)
open import Locking.CyclicMulti using (allFalse; fbOpen; HasTrue; here; there)

private
  variable
    W k : ℕ

------------------------------------------------------------------------
--  Represent an arbitrary open-loop topology by the next values of all `k`
--  feedback wires, computed from the entire feedback-and-base valuation.

FBLayer : ℕ → ℕ → Set
FBLayer k W = Vec Bool k → Vec Bool W → Vec Bool k

--  Apply key selection coordinate by coordinate: choose the open-layer value
--  `o` or close the wire through its negation `¬b`.
gateFB : Vec Bool k → Vec Bool k → Vec Bool k → Vec Bool k
gateFB []       []       []       = []
gateFB (s ∷ ks) (o ∷ os) (b ∷ bs) = mux s o (not b) ∷ gateFB ks os bs

updateFBt : Vec Bool k → FBLayer k W → Vec Bool W → Vec Bool k → Vec Bool k
updateFBt ks layer vs fbs = gateFB ks (layer fbs vs) fbs

lstepT : Vec Bool k → FBLayer k W → ANetlist W →
         Vec Bool k × Vec Bool W → Vec Bool k × Vec Bool W
lstepT ks layer base (fbs , vs) = updateFBt ks layer vs fbs , astep base vs

LStableT : Vec Bool k → FBLayer k W → ANetlist W →
           Vec Bool k × Vec Bool W → Set
LStableT ks layer base p = lstepT ks layer base p ≡ p

------------------------------------------------------------------------
--  At a wrong key, a true bit forces its wire to follow `b ↦ ¬b`, excluding
--  fixed points of the gated update independently of the layer.

gateFB-no-fix : (ks os fbs : Vec Bool k) → HasTrue ks → gateFB ks os fbs ≢ fbs
gateFB-no-fix (true ∷ ks) (o ∷ os) (b ∷ bs) here eq =
  not-no-fixpoint b (trans (sym (mux-true o (not b))) (cong head eq))
gateFB-no-fix (s ∷ ks) (o ∷ os) (b ∷ bs) (there ht) eq =
  gateFB-no-fix ks os bs ht (cong tail eq)

--  Wrong keys therefore admit no stable valuation under any feedback topology.
lock-wrong-no-stable-T :
  (ks : Vec Bool k) (layer : FBLayer k W) (base : ANetlist W) → HasTrue ks →
  ¬ Σ (Vec Bool k × Vec Bool W) (LStableT ks layer base)
lock-wrong-no-stable-T ks layer base ht ((fbs , vs) , eq) =
  gateFB-no-fix ks (layer fbs vs) fbs ht (cong proj₁ eq)

------------------------------------------------------------------------
--  The general CycSAT obstruction allows a combinational model, that is a
--  stable valuation, only at the correct all-false key, for every topology.

SATModelT : {k W : ℕ} → Vec Bool k → FBLayer k W → ANetlist W → Set
SATModelT {k} {W} ks layer base = Σ (Vec Bool k × Vec Bool W) (LStableT ks layer base)

allFalse-or-HasTrue : (ks : Vec Bool k) → (ks ≡ allFalse k) ⊎ HasTrue ks
allFalse-or-HasTrue []           = inj₁ refl
allFalse-or-HasTrue (true  ∷ ks) = inj₂ here
allFalse-or-HasTrue (false ∷ ks) with allFalse-or-HasTrue ks
... | inj₁ e  = inj₁ (cong (false ∷_) e)
... | inj₂ ht = inj₂ (there ht)

model→correct-T :
  (ks : Vec Bool k) (layer : FBLayer k W) (base : ANetlist W) →
  SATModelT ks layer base → ks ≡ allFalse k
model→correct-T ks layer base sat with allFalse-or-HasTrue ks
... | inj₁ e  = e
... | inj₂ ht = ⊥-elim (lock-wrong-no-stable-T ks layer base ht sat)

------------------------------------------------------------------------
--  The correct all-false key opens every loop and leaves just the open-layer
--  update. Its fixed point determines well-definedness of the interconnect.

gateFB-allFalse : (os fbs : Vec Bool k) → gateFB (allFalse k) os fbs ≡ os
gateFB-allFalse []       []       = refl
gateFB-allFalse (o ∷ os) (b ∷ bs) =
  cong₂ _∷_ (mux-false o (not b)) (gateFB-allFalse os bs)

updateFBt-allFalse : (layer : FBLayer k W) (vs : Vec Bool W) (fbs : Vec Bool k) →
                     updateFBt (allFalse k) layer vs fbs ≡ layer fbs vs
updateFBt-allFalse layer vs fbs = gateFB-allFalse (layer fbs vs) fbs

--  Lift an open-layer fixed point `fb*` at the settled base to a stable
--  valuation of the complete lock.
lock-correct-T :
  (layer : FBLayer k W) (base : ANetlist W) (fb* : Vec Bool k) →
  layer fb* (asolve base) ≡ fb* →
  LStableT (allFalse k) layer base (fb* , asolve base)
lock-correct-T layer base fb* fix =
  cong₂ _,_ (trans (updateFBt-allFalse layer (asolve base) fb*) fix)
            (asolve-stable base)

--  A unique open-layer fixed point at the settled base yields a unique stable
--  lock valuation; `astable-unique` fixes the base component.
lock-correct-unique-T :
  (layer : FBLayer k W) (base : ANetlist W) (fb* : Vec Bool k) →
  ((fbs : Vec Bool k) → layer fbs (asolve base) ≡ fbs → fbs ≡ fb*) →
  (p : Vec Bool k × Vec Bool W) → LStableT (allFalse k) layer base p →
  p ≡ (fb* , asolve base)
lock-correct-unique-T layer base fb* uniq (fbs , vs) eq = cong₂ _,_ fbsEq vsEq
  where
    vsEq : vs ≡ asolve base
    vsEq = astable-unique base vs (cong proj₂ eq)
    openfix : layer fbs (asolve base) ≡ fbs
    openfix = trans (cong (layer fbs) (sym vsEq))
                    (trans (sym (updateFBt-allFalse layer vs fbs)) (cong proj₁ eq))
    fbsEq : fbs ≡ fb*
    fbsEq = uniq fbs openfix

------------------------------------------------------------------------
--  Recover `Locking.CyclicMulti` by making the layer depend only on the base.
--  Such a layer ignores feedback, is trivially acyclic, and has one fixed point.

baseLayer : Vec (Gate W) k → FBLayer k W
baseLayer outs fbs vs = fbOpen outs vs

private
  --  At the settled base, `fbOpen …` is the base-reading layer's sole fixed
  --  point. Substituting it into the general correct-key results recovers
  --  CyclicMulti.
  baseLayer-fix : (outs : Vec (Gate W) k) (base : ANetlist W) →
    baseLayer outs (fbOpen outs (asolve base)) (asolve base)
      ≡ fbOpen outs (asolve base)
  baseLayer-fix outs base = refl

  baseLayer-unique : (outs : Vec (Gate W) k) (base : ANetlist W)
                     (fbs : Vec Bool k) →
    baseLayer outs fbs (asolve base) ≡ fbs → fbs ≡ fbOpen outs (asolve base)
  baseLayer-unique outs base fbs eq = sym eq

  --  Obtain CyclicMulti's correct-key stability from the general lemma.
  baseLayer-correct : (outs : Vec (Gate W) k) (base : ANetlist W) →
    LStableT (allFalse k) (baseLayer outs) base
      (fbOpen outs (asolve base) , asolve base)
  baseLayer-correct outs base =
    lock-correct-T (baseLayer outs) base (fbOpen outs (asolve base))
                   (baseLayer-fix outs base)
