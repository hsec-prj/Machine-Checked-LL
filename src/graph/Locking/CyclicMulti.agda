------------------------------------------------------------------------
--  Extend key-controlled feedback to multiple wires (graph track, G3, item 1a).
--  The single feedback wire of `Locking.Cyclic` becomes `k` independent loops
--  sharing an acyclic base. Represent the valuation as the pair
--  (feedback wires : Vec Bool k) × (base wires : Vec Bool W).
--  Recursing over its first component and using G2's `astep` on its second
--  avoids `Vec` index operations such as `take`, `drop`, and `splitAt`. Each
--  wire `j` has key bit `ks[j]` and output gate `outs[j] : Gate W`. Its gate
--  reads only base wires, so the loops are parallel instances of `selfLoop`,
--  with no dependencies between them. The G3 mux either opens a loop to its
--  base output or closes it through inversion, `b ↦ ¬b`.
--  At `allFalse k`, all loops open. The unique stable valuation is
--  (fbOpen outs (asolve base), asolve base): feedback wires hold their base
--  outputs and the base settles to G2's solution. `lock-correct-stable` and
--  `lock-correct-unique`, combined in `lock-correct-unique-fixpoint`, establish
--  the same functional behaviour as the base. If `HasTrue ks` witnesses even
--  one true key bit, that coordinate follows the fixed-point-free inversion
--  map. Projecting to it in `updateFB-no-fix` excludes stability of the whole
--  system, independently of the base and all other loops, as expressed by
--  `lock-wrong-no-stable`. Thus one incorrect bit suffices for the obstruction,
--  while correct-key uniqueness extends to any loop count. The proof reuses
--  `Graph.Acyclic` for the base and `Locking.Cyclic` for muxes, introducing
--  neither primitives nor postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.CyclicMulti where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Bool using (Bool; true; false; not)
open import Data.Fin using (Fin; zero)
open import Data.Vec using (Vec; []; _∷_; head; tail)
open import Data.Product using (Σ; _×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; _≢_)
open import Relation.Nullary using (¬_)

open import Graph.Core using (Gate; evalGate; wire; cst)
open import Graph.Acyclic
  using (ANetlist; astep; asolve; asolve-stable; astable-unique)
open import Graph.Acyclic using () renaming ([] to a[]; _∷_ to _a∷_)
open import Locking.Cyclic using (mux; mux-false; mux-true; not-no-fixpoint)

private
  variable
    W k : ℕ

------------------------------------------------------------------------
--  Give structural definitions of the all-false key and the open-loop
--  feedback solution, so updates reduce directly. Each open wire holds its
--  corresponding base output.

allFalse : (k : ℕ) → Vec Bool k
allFalse zero    = []
allFalse (suc k) = false ∷ allFalse k

--  An open feedback wire takes the value of its base output.
fbOpen : Vec (Gate W) k → Vec Bool W → Vec Bool k
fbOpen []       vs = []
fbOpen (g ∷ gs) vs = evalGate vs g ∷ fbOpen gs vs

------------------------------------------------------------------------
--  Update all `k` feedback wires synchronously. At coordinate `j`, `ks[j]`
--  selects either `evalGate vs outs[j]` for an open loop or the wire's own
--  negation for a closed loop.

updateFB : Vec Bool k → Vec (Gate W) k → Vec Bool W → Vec Bool k → Vec Bool k
updateFB []       []       vs []       = []
updateFB (s ∷ ks) (g ∷ gs) vs (b ∷ bs) =
  mux s (evalGate vs g) (not b) ∷ updateFB ks gs vs bs

--  Perform one update of the complete pair of feedback and base valuations.
lstepM : Vec Bool k → Vec (Gate W) k → ANetlist W →
         Vec Bool k × Vec Bool W → Vec Bool k × Vec Bool W
lstepM ks outs base (fbs , vs) = updateFB ks outs vs fbs , astep base vs

LStableM : Vec Bool k → Vec (Gate W) k → ANetlist W →
           Vec Bool k × Vec Bool W → Set
LStableM ks outs base p = lstepM ks outs base p ≡ p

------------------------------------------------------------------------
--  With every key bit false, all loops open: feedback values become the base
--  outputs and base values become `asolve base`, yielding stability.

updateFB-allFalse : (outs : Vec (Gate W) k) (vs : Vec Bool W) →
                    updateFB (allFalse k) outs vs (fbOpen outs vs) ≡ fbOpen outs vs
updateFB-allFalse []       vs = refl
updateFB-allFalse (g ∷ gs) vs =
  cong₂ _∷_ (mux-false (evalGate vs g) (not (evalGate vs g)))
            (updateFB-allFalse gs vs)

lock-correct-stable : (outs : Vec (Gate W) k) (base : ANetlist W) →
                      LStableM (allFalse k) outs base
                        (fbOpen outs (asolve base) , asolve base)
lock-correct-stable outs base =
  cong₂ _,_ (updateFB-allFalse outs (asolve base)) (asolve-stable base)

------------------------------------------------------------------------
--  At the correct key, stability forces the base to `asolve base` and each
--  open feedback wire to its base output, proving uniqueness.

updateFB-allFalse-unique : (outs : Vec (Gate W) k) (vs : Vec Bool W)
                           (fbs : Vec Bool k) →
                           updateFB (allFalse k) outs vs fbs ≡ fbs →
                           fbs ≡ fbOpen outs vs
updateFB-allFalse-unique []       vs []       eq = refl
updateFB-allFalse-unique (g ∷ gs) vs (b ∷ bs) eq =
  cong₂ _∷_ headEq (updateFB-allFalse-unique gs vs bs (cong tail eq))
  where
    headEq : b ≡ evalGate vs g
    headEq = trans (sym (cong head eq))
                   (mux-false (evalGate vs g) (not b))

lock-correct-unique : (outs : Vec (Gate W) k) (base : ANetlist W)
                      (p : Vec Bool k × Vec Bool W) →
                      LStableM (allFalse k) outs base p →
                      p ≡ (fbOpen outs (asolve base) , asolve base)
lock-correct-unique outs base (fbs , vs) eq = cong₂ _,_ fbsEq vsEq
  where
    vsEq : vs ≡ asolve base
    vsEq = astable-unique base vs (cong proj₂ eq)
    fbsEq : fbs ≡ fbOpen outs (asolve base)
    fbsEq = trans (updateFB-allFalse-unique outs vs fbs (cong proj₁ eq))
                  (cong (fbOpen outs) vsEq)

--  Combine existence and uniqueness of the stable valuation at the correct key.
lock-correct-unique-fixpoint :
  (outs : Vec (Gate W) k) (base : ANetlist W) →
  Σ (Vec Bool k × Vec Bool W) (λ p →
     LStableM (allFalse k) outs base p ×
     ((q : Vec Bool k × Vec Bool W) → LStableM (allFalse k) outs base q → q ≡ p))
lock-correct-unique-fixpoint outs base =
  (fbOpen outs (asolve base) , asolve base)
  , lock-correct-stable outs base
  , lock-correct-unique outs base

------------------------------------------------------------------------
--  A wrong key contains a true bit. The structural predicate `HasTrue`
--  witnesses such a coordinate, serving as a custom `Any (_≡ true)`.

data HasTrue : Vec Bool k → Set where
  here  : ∀ {k} {ks : Vec Bool k} → HasTrue (true ∷ ks)
  there : ∀ {k b} {ks : Vec Bool k} → HasTrue ks → HasTrue (b ∷ ks)

--  Project onto a true-key coordinate to obtain `b ↦ ¬b`; its lack of a fixed
--  point excludes a fixed point of the feedback update.
updateFB-no-fix : (ks : Vec Bool k) (outs : Vec (Gate W) k) (vs : Vec Bool W)
                  (fbs : Vec Bool k) → HasTrue ks →
                  updateFB ks outs vs fbs ≢ fbs
updateFB-no-fix (true ∷ ks) (g ∷ gs) vs (b ∷ bs) here eq =
  not-no-fixpoint b
    (trans (sym (mux-true (evalGate vs g) (not b))) (cong head eq))
updateFB-no-fix (s ∷ ks) (g ∷ gs) vs (b ∷ bs) (there ht) eq =
  updateFB-no-fix ks gs vs bs ht (cong tail eq)

--  The full lock consequently has no stable valuation, whatever the base
--  and output gates are.
lock-wrong-no-stable :
  (ks : Vec Bool k) (outs : Vec (Gate W) k) (base : ANetlist W) →
  HasTrue ks →
  ¬ Σ (Vec Bool k × Vec Bool W) (LStableM ks outs base)
lock-wrong-no-stable ks outs base ht ((fbs , vs) , eq) =
  updateFB-no-fix ks outs vs fbs ht (cong proj₁ eq)

------------------------------------------------------------------------
--  Check two loops over the single-node base `cst true`, whose solution is
--  `true ∷ []`. Both read `wire zero`. The correct key opens and settles both;
--  flipping just one bit eliminates all stable valuations even though the
--  other loop remains open.

private
  base1 : ANetlist 1
  base1 = cst true a∷ a[]

  outs2 : Vec (Gate 1) 2
  outs2 = wire zero ∷ wire zero ∷ []

  _ : LStableM (false ∷ false ∷ []) outs2 base1
        (fbOpen outs2 (asolve base1) , asolve base1)
  _ = lock-correct-stable outs2 base1

  _ : ¬ Σ (Vec Bool 2 × Vec Bool 1) (LStableM (true ∷ false ∷ []) outs2 base1)
  _ = lock-wrong-no-stable (true ∷ false ∷ []) outs2 base1 here
