------------------------------------------------------------------------
--  Static circuit-area accounting (S2)
--  `gateCount c` totals the primitive logic-gate instances, or standard
--  cells, in `c`. It depends only on the syntax of the `Circuit.Core` deep
--  embedding and is evaluated symbolically once, without simulation.
--  This supplies the proven-overhead comparison with measured area that
--  the TCAD/TIFS carve-out (``) places beside synthesis results.
--  The following conventions determine the later closed-form expressions:
--  * `Id`, `Swap`, `Dup`, and `Plug` cost 0: they provide wiring, not cells.
--  * `Const` costs 0: tie-high/tie-low sources are conventionally free or
--  folded away by constant propagation.
--  * `Not1`, `And2`, `Or2`, `Xor2`, `Mux21`, and `Thr` each cost 1.
--  * Sequential and parallel compositions add the costs of their parts.
--  `SFLL.GateCount` applies this common measure to obtain a closed-form
--  gate overhead for the SFLL-HD locked netlist.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Circuit.GateCount where

open import Data.Nat using (ℕ; zero; suc; _+_)
open import Circuit.Core

------------------------------------------------------------------------
--  Definition of the gate-count measure

gateCount : ∀ {n m} → Circuit n m → ℕ
gateCount Id        = 0
gateCount Not1      = 1
gateCount And2      = 1
gateCount Or2       = 1
gateCount Xor2      = 1
gateCount Mux21     = 1
gateCount (Seq c d) = gateCount c + gateCount d
gateCount (Par c d) = gateCount c + gateCount d
gateCount Swap      = 0
gateCount Dup       = 0
gateCount (Plug _)  = 0
gateCount (Const _) = 0
gateCount (Thr _)   = 1
