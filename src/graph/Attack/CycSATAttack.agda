------------------------------------------------------------------------
--  Verify recovery by static oscillation elimination (graph track). The
--  CycSAT name identifies the reused obstruction, not an implementation
--  of the solver-based attack: this procedure exhaustively scans keys and
--  decides stability statically rather than solving a no-structural-path
--  condition. Attack.CycSAT gives the defender's characterisation, stability
--  exactly at the correct key. Turn it into recovery by scanning key space,
--  unlike PointDIPAttack's input-space consistency fold. decSATModelT keeps
--  precisely stable candidates without oscillation simulation. CyclicTopo's
--  lock-wrong-no-stable-T excludes HasTrue for any topology, and
--  lock-correct-T supplies the all-false model for the acyclic base-reading
--  layer. allFalse-or-HasTrue therefore decides SATModelT. scanDec traverses
--  Graph.Util.allVecsK; wrong keys fail, the correct key survives, and
--  model→correct-T makes it unique. cycSATAttack-recovers and
--  cycSATAttack-queries establish recovery with 2ᵏ queries. For this
--  feedback-insertion lock, elimination alone suffices. Locks with multiple
--  non-oscillating survivors need subsequent PointDIPAttack-style pruning,
--  outside this module. Reuse the existing model/obstruction lemmas without
--  postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATAttack where

open import Data.Nat using (ℕ; _^_)
open import Data.Bool using (Bool; true; false)
open import Data.Vec using (Vec)
open import Data.List using (List; []; _∷_; length)
open import Data.Product using (_,_)
open import Data.Sum using (inj₁; inj₂)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; subst)
open import Relation.Nullary using (Dec; yes; no; ¬_)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)

open import Graph.Core using (Gate)
open import Graph.Acyclic using (ANetlist; asolve)
open import Locking.CyclicMulti using (allFalse; fbOpen)
open import Locking.CyclicTopo
  using (baseLayer; SATModelT; lock-correct-T; lock-wrong-no-stable-T;
         model→correct-T; allFalse-or-HasTrue)
open import Graph.Util using (allVecsK; ∈-allVecsK; length-allVecsK)
open import Attack.CycSAT using (SATModel; good-model; cycSAT-obstruction)

private
  variable
    W k : ℕ

------------------------------------------------------------------------
--  Reconstruct the correct model using lock-correct-T without exporting
--  CyclicTopo's private baseLayer-correct. Base outputs themselves fix the
--  base-reading layer at the settled base, so the obligation is refl.

correctModel : (outs : Vec (Gate W) k) (base : ANetlist W) →
               SATModelT (allFalse k) (baseLayer outs) base
correctModel outs base =
    (fbOpen outs (asolve base) , asolve base)
  , lock-correct-T (baseLayer outs) base (fbOpen outs (asolve base)) refl

------------------------------------------------------------------------
--  Decide stability statically: a model exists exactly for allFalse, with
--  one lemma proving each case and no simulation required.

decSATModelT : (outs : Vec (Gate W) k) (base : ANetlist W) (ks : Vec Bool k) →
               Dec (SATModelT ks (baseLayer outs) base)
decSATModelT outs base ks with allFalse-or-HasTrue ks
... | inj₁ e  = yes (subst (λ z → SATModelT z (baseLayer outs) base)
                           (sym e) (correctModel outs base))
... | inj₂ ht = no (lock-wrong-no-stable-T ks (baseLayer outs) base ht)

------------------------------------------------------------------------
--  Scan keys for the first stable model. Use allFalse as a total empty-list
--  fallback, unreachable when scanning allVecsK.

scanDec : (outs : Vec (Gate W) k) (base : ANetlist W) →
          List (Vec Bool k) → Vec Bool k
scanDec outs base []       = allFalse _
scanDec outs base (x ∷ xs) with decSATModelT outs base x
... | yes _ = x
... | no  _ = scanDec outs base xs

--  If the sole stable key x* occurs in the list, the scan returns it
--  regardless of ordering or duplicates.
scanDec-char :
  (outs : Vec (Gate W) k) (base : ANetlist W)
  (x* : Vec Bool k) (xs : List (Vec Bool k)) →
  (∀ y → SATModelT y (baseLayer outs) base → y ≡ x*) →
  SATModelT x* (baseLayer outs) base →
  x* ∈ xs →
  scanDec outs base xs ≡ x*
scanDec-char outs base x* (x ∷ xs) uniq mdl (here refl) with decSATModelT outs base x*
... | yes _  = refl
... | no  ¬m = ⊥-elim (¬m mdl)
scanDec-char outs base x* (x ∷ xs) uniq mdl (there mem) with decSATModelT outs base x
... | yes m  = uniq x m
... | no  _  = scanDec-char outs base x* xs uniq mdl mem

------------------------------------------------------------------------
--  Define the verified elimination attack and its recovery and query guarantees.

cycSATAttack : (outs : Vec (Gate W) k) (base : ANetlist W) → Vec Bool k
cycSATAttack {k = k} outs base = scanDec outs base (allVecsK k)

--  Prove recovery of allFalse: decSATModelT uses lock-wrong-no-stable-T to
--  reject wrong keys, correctModel preserves the right one, and
--  model→correct-T ensures uniqueness.
cycSATAttack-recovers :
  (outs : Vec (Gate W) k) (base : ANetlist W) →
  cycSATAttack outs base ≡ allFalse k
cycSATAttack-recovers {k = k} outs base =
  scanDec-char outs base (allFalse k) (allVecsK k)
    (λ y m → model→correct-T y (baseLayer outs) base m)
    (correctModel outs base)
    (∈-allVecsK (allFalse k))

--  Count inspection of all 2ᵏ keys.
cycSATAttack-queries : (k : ℕ) → length (allVecsK k) ≡ 2 ^ k
cycSATAttack-queries = length-allVecsK

------------------------------------------------------------------------
--  Check the original one-wire Bool-key lock with good-model and
--  cycSAT-obstruction. Its two-key scan reduces definitionally to false.

decSATModel : (out : Gate W) (base : ANetlist W) (b : Bool) → Dec (SATModel b out base)
decSATModel out base false = yes (good-model out base)
decSATModel out base true  = no  (cycSAT-obstruction out base)

scanBool : (out : Gate W) (base : ANetlist W) → List Bool → Bool
scanBool out base []       = false
scanBool out base (b ∷ bs) with decSATModel out base b
... | yes _ = b
... | no  _ = scanBool out base bs

cycSATAttack₁ : (out : Gate W) (base : ANetlist W) → Bool
cycSATAttack₁ out base = scanBool out base (false ∷ true ∷ [])

cycSATAttack₁-recovers : (out : Gate W) (base : ANetlist W) →
                         cycSATAttack₁ out base ≡ false
cycSATAttack₁-recovers out base = refl
