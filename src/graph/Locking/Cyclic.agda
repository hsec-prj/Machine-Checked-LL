------------------------------------------------------------------------
--  Insert feedback controlled by a key bit (graph track, G3).
--  G2 (`Graph.Acyclic`) gives an acyclic base its unique stable valuation,
--  `asolve base`. Here the one-node `selfLoop` from `Graph.Stable` extends to
--  an arbitrary acyclic base by adding a feedback wire. A mux controlled by
--  `k` chooses either the base output `evalGate (base wires) out`, opening
--  the loop, or the feedback wire's own inverted value, closing it.
--  With the correct key `false`, `lock-correct-stable` and
--  `lock-correct-unique` establish the sole stable valuation
--  `evalGate (asolve base) out ∷ asolve base`: the new wire holds the output
--  and the remaining wires solve the base, preserving its function. With
--  the wrong key `true`, the new wire follows `b ↦ ¬b`. Since this map has no
--  fixed point, `lock-wrong-no-stable` excludes a stable valuation for every
--  base, destroying well-definedness. The base uses G2's existing `astep`,
--  `asolve`, and uniqueness proof. Combining the wire through a meta-level
--  `mux` keeps the representation intrinsic without Fin-index manipulation.
--  The development introduces no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.Cyclic where

open import Data.Nat using (ℕ; suc)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_)
open import Data.Vec using (Vec; []; _∷_; head; tail)
open import Data.Product using (Σ; _,_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; _≢_)
open import Relation.Nullary using (¬_)

open import Graph.Core using (Gate; evalGate)
open import Graph.Acyclic using (ANetlist; astep; asolve; asolve-stable; astable-unique)

private
  variable
    W : ℕ

------------------------------------------------------------------------
--  Define the meta-level 2:1 mux and establish selector behaviour by cases.

mux : Bool → Bool → Bool → Bool
mux s a b = (a ∧ not s) ∨ (b ∧ s)

mux-false : (a b : Bool) → mux false a b ≡ a
mux-false true  true  = refl
mux-false true  false = refl
mux-false false true  = refl
mux-false false false = refl

mux-true : (a b : Bool) → mux true a b ≡ b
mux-true true  true  = refl
mux-true true  false = refl
mux-true false true  = refl
mux-true false false = refl

not-no-fixpoint : (b : Bool) → not b ≢ b
not-no-fixpoint true  ()
not-no-fixpoint false ()

------------------------------------------------------------------------
--  Place a key-controlled feedback wire before the acyclic `base`. It reads
--  `out` from the base and its own negated value, giving the complete valuation
--  `(feedback wire) ∷ (base wires)`.

lstep : Bool → Gate W → ANetlist W → Vec Bool (suc W) → Vec Bool (suc W)
lstep k out base (b ∷ vs) = mux k (evalGate vs out) (not b) ∷ astep base vs

LStable : Bool → Gate W → ANetlist W → Vec Bool (suc W) → Set
LStable k out base v = lstep k out base v ≡ v

------------------------------------------------------------------------
--  Setting the key to `false` opens the loop. Its sole stable valuation puts
--  the base output on the new wire and `asolve base` on the original wires.

lock-correct-stable : (out : Gate W) (base : ANetlist W) →
                      LStable false out base
                        (evalGate (asolve base) out ∷ asolve base)
lock-correct-stable out base =
  cong₂ _∷_
    (mux-false (evalGate (asolve base) out) (not (evalGate (asolve base) out)))
    (asolve-stable base)

lock-correct-unique : (out : Gate W) (base : ANetlist W)
                      (v : Vec Bool (suc W)) →
                      LStable false out base v →
                      v ≡ (evalGate (asolve base) out ∷ asolve base)
lock-correct-unique out base (b ∷ vs) eq = cong₂ _∷_ headEq tailEq
  where
    voutb : evalGate vs out ≡ b
    voutb = trans (sym (mux-false (evalGate vs out) (not b))) (cong head eq)
    tailEq : vs ≡ asolve base
    tailEq = astable-unique base vs (cong tail eq)
    headEq : b ≡ evalGate (asolve base) out
    headEq = trans (sym voutb) (cong (λ w → evalGate w out) tailEq)

------------------------------------------------------------------------
--  Setting the key to `true` forces the new wire to follow `b ↦ ¬b`. The
--  absence of a fixed point rules out stability for the entire lock, for any base.

lock-wrong-no-stable : (out : Gate W) (base : ANetlist W) →
                       ¬ Σ (Vec Bool (suc W)) (LStable true out base)
lock-wrong-no-stable out base (b ∷ vs , eq) =
  not-no-fixpoint b
    (trans (sym (mux-true (evalGate vs out) (not b))) (cong head eq))
