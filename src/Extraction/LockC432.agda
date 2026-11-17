------------------------------------------------------------------------
--  Verified flat emission for the real 132-gate c432 host (M1 B4.3)
--  After `Extraction.LockC17` applied the host-generic `lockHost-locked` to
--  the 4-input c17 cone, this module applies it to the actual ISCAS-85 c432
--  output cone, `Locking.CompileC432.c432nl`, a 36-input, 132-gate `Netlist`.
--  Agda certifies that the shared-wire netlist emitted by `lockHostBlock`
--  denotes the SFLL-HD lock of this cone, extending the guarantee beyond c17.
--  SCALE NOTE: the absence of explicit signatures is deliberate. The generic
--  proof requires only one application per imported host, but writing its
--  instantiated type, `get (runNet env ops) out ≡ locked …`, forces Agda to
--  normalize `ops`. At n=36, the 132 gadget cones and two O(n²) popcount
--  comparators form a term large enough to exhaust memory. An inferred
--  type leaves `lockHostBlock c432nl …` unreduced and permits elaboration.
--  That inferred type is exactly the c432 instance of `lockHost-locked`:
--  (x key ksec : Vec Bool 36) (h : ℕ) →
--  get (runNet (toList x ++ toList key) ops) out ≡ locked h ksec key (importConeF c432nl) x
--  The restoration corollary likewise instantiates `lockHost-restores`,
--  whose proof is generic in the host. This lazy application uses little
--  memory; applying `trans` directly to concrete c432 would force operation-
--  list normalization and exhaust memory instead. No postulates are used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockC432 where

open import Locking.CompileC432 using (c432nl)
open import Extraction.LockHost using (lockHost-locked; lockHost-restores)

--  Specialize verified emission to c432's actual 132-gate cone, with its
--  type inferred as explained in the SCALE NOTE. For every x, key, ksec, h,
--  `lockHostBlock c432nl …` denotes `locked h ksec key (importConeF c432nl) x`.
--  The cone is computed by c432's 36 inputs and 132 gates, then wrapped by the lock.
c432flat-locked = lockHost-locked c432nl

--  With the correct key, the emitted netlist restores the c432 cone.
--  Its lazy inferred type is `… ≡ importConeF c432nl x`, obtained through
--  the generic lift described in the SCALE NOTE.
c432flat-restores = lockHost-restores c432nl
