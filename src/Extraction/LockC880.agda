------------------------------------------------------------------------
--  Verified flat emission for a second real ISCAS-85 host, c880
--  `Extraction.LockC432` applied `lockHost-locked` to c432's 132-gate cone.
--  Here the same generic theorem is applied to the largest output cone of
--  ISCAS-85 `c880`: `Locking.CompileC880.c880nl`, a 45-input, 119-gate
--  `Netlist`. Together with c17 and c432, this third industrial host
--  demonstrates host-parametricity beyond an individual benchmark.
--  SCALE NOTE: types are inferred for the same reason as in `LockC432`.
--  An explicit instantiated type makes Agda normalize the emitted operation
--  list: 119 gadget cones and two O(n²) popcount comparators at n=45. That
--  term is slightly larger than c432's and can exhaust a 16 GB machine.
--  Type inference instead leaves `lockHostBlock c880nl …` unreduced, enabling
--  elaboration. The resulting type is precisely `lockHost-locked` at c880:
--  (x key ksec : Vec Bool 45) (h : ℕ) →
--  get (runNet (toList x ++ toList key) ops) out ≡ locked h ksec key (importConeF c880nl) x
--  For correct-key restoration, the generic `lockHost-restores`, proved
--  once for an abstract host, gives the same lazy, low-memory application.
--  The module uses no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockC880 where

open import Locking.CompileC880 using (c880nl)
open import Extraction.LockHost using (lockHost-locked; lockHost-restores)

--  Apply verified emission to the actual 119-gate c880 cone. With the
--  inferred type explained in the SCALE NOTE, every x, key, ksec, h satisfies
--  that `lockHostBlock c880nl …` denotes `locked h ksec key (importConeF c880nl) x`.
--  The host's 45 inputs and 119 gates compute the cone before the lock wraps it.
c880flat-locked = lockHost-locked c880nl

--  Correct-key evaluation of the emitted netlist restores c880's cone.
--  The generic lift yields the lazy inferred type `… ≡ importConeF c880nl x`;
--  see the SCALE NOTE.
c880flat-restores = lockHost-restores c880nl
