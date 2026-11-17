------------------------------------------------------------------------
--  Threshold-free circuits and the fidelity of static area accounting
--  `Circuit.GateCount.gateCount` assigns one cell to each primitive,
--  including `Thr t`. Boolean gates and muxes each become one expression
--  IR node under `Extraction.Bench.emit`, but a threshold gate does not:
--  the IR has no counting node, so `Extraction.Bench.atLeast` expands it
--  to a nested-mux at-least-t-of-n tree whose size grows with fan-in.
--  One symbolic cell can therefore become many emitted cells.
--  Equality between gateCount and emitted area needs a premise. `ThrFree c`
--  names that premise: no `Thr` occurs anywhere in c. The decision procedure
--  `thrFree?` checks it on concrete circuits. `Locking.ThrFreeLock` proves
--  it along the verified locking compiler's emission path and demonstrates
--  the underestimate on a concrete threshold gate.
--  The predicate recurses into `⊤`, `⊥`, and `_×_` rather than using an
--  inductive family. Only the composition cases carry evidence, so concrete
--  proofs become tuples of `tt` without extra constructor bookkeeping.
--  There are no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Circuit.ThrFree where

open import Data.Empty using (⊥)
open import Data.Product using (_×_; _,_)
open import Data.Unit using (⊤; tt)
open import Relation.Nullary.Decidable using (Dec; yes; no; _×-dec_)

open import Circuit.Core

------------------------------------------------------------------------
--  Define threshold-freedom.

--  `ThrFree c` holds precisely when c contains no threshold primitive.
--  Every other primitive maps to one IR node, so for such circuits the
--  symbolic gateCount agrees with the count produced by emission.
ThrFree : ∀ {n m} → Circuit n m → Set
ThrFree Id        = ⊤
ThrFree Not1      = ⊤
ThrFree And2      = ⊤
ThrFree Or2       = ⊤
ThrFree Xor2      = ⊤
ThrFree Mux21     = ⊤
ThrFree (Seq c d) = ThrFree c × ThrFree d
ThrFree (Par c d) = ThrFree c × ThrFree d
ThrFree Swap      = ⊤
ThrFree Dup       = ⊤
ThrFree (Plug _)  = ⊤
ThrFree (Const _) = ⊤
ThrFree (Thr _)   = ⊥

------------------------------------------------------------------------
--  Decide the predicate by structural recursion.
--  Threshold-freedom is a finite conjunction over the syntax, hence it is
--  decidable. A concrete circuit can be checked automatically instead of
--  requiring a manually constructed proof.

thrFree? : ∀ {n m} (c : Circuit n m) → Dec (ThrFree c)
thrFree? Id        = yes tt
thrFree? Not1      = yes tt
thrFree? And2      = yes tt
thrFree? Or2       = yes tt
thrFree? Xor2      = yes tt
thrFree? Mux21     = yes tt
thrFree? (Seq c d) = thrFree? c ×-dec thrFree? d
thrFree? (Par c d) = thrFree? c ×-dec thrFree? d
thrFree? Swap      = yes tt
thrFree? Dup       = yes tt
thrFree? (Plug _)  = yes tt
thrFree? (Const _) = yes tt
thrFree? (Thr _)   = no (λ ())
