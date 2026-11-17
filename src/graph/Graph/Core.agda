------------------------------------------------------------------------
--  A feedback-capable circuit language for the graph track
--  The main Circuit n m embedding in ../src/Circuit/Core.agda builds
--  acyclic DAGs with Seq, Par, and Swap and denotes total functions
--  Vec Bool n → Vec Bool m. It cannot route a key-controlled mux back
--  to an earlier wire, which kept cyclic locking as future work; the
--  semantic Locking.Cyclic model captures only its one-wire shadow.
--  Here each node i : Fin W has a Gate allowed to read any wire,
--  including itself, making feedback explicit. The semantics is a
--  global one-step update Vec Bool W → Vec Bool W rather than one
--  ordinary circuit-denotation function. Acyclic netlists have a unique
--  fixed point, while cyclic netlists need not, as Graph.Stable develops.
--  step makes one structural pass, not a fixed-point iteration, and is
--  therefore total and --safe. Stability is studied through fixed-point
--  properties. No postulates are used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Graph.Core where

open import Data.Nat using (ℕ)
open import Data.Fin using (Fin)
open import Data.Bool using (Bool; not; _∧_; _∨_)
open import Data.Vec using (Vec; lookup; tabulate)

private
  variable
    W : ℕ

------------------------------------------------------------------------
--  Gate expressions range over W wires. A wire i leaf reads node i's
--  current value; other constructors are ordinary combinational gates.
--  Finite expression trees make evalGate structurally terminating.

data Gate (W : ℕ) : Set where
  wire  : Fin W → Gate W
  cst   : Bool → Gate W
  inv   : Gate W → Gate W
  and2  : Gate W → Gate W → Gate W
  or2   : Gate W → Gate W → Gate W
  mux   : Gate W → Gate W → Gate W → Gate W   --  mux s a b selects a for false s and b for true s

--  Interpret a gate using the current wire valuation.
evalGate : Vec Bool W → Gate W → Bool
evalGate v (wire i)    = lookup v i
evalGate v (cst b)     = b
evalGate v (inv g)     = not (evalGate v g)
evalGate v (and2 g h)  = evalGate v g ∧ evalGate v h
evalGate v (or2 g h)   = evalGate v g ∨ evalGate v h
evalGate v (mux s a b) =
  (evalGate v a ∧ not (evalGate v s)) ∨ (evalGate v b ∧ evalGate v s)

------------------------------------------------------------------------
--  Assign each of W nodes a gate on W wires. Self-references are allowed,
--  extending the acyclic Circuit language with explicit feedback.

Netlist : ℕ → Set
Netlist W = Fin W → Gate W

--  Interpret any netlist, cyclic or otherwise, by recomputing all node
--  values from the current valuation in one global pass.
step : Netlist W → Vec Bool W → Vec Bool W
step nl v = tabulate (λ i → evalGate v (nl i))
