------------------------------------------------------------------------
--  Verified flat emission for the ISCAS-85 c1355 host (A2)
--  As in `LockC432` and `LockC880`, the generic results `lockHost-locked`
--  and `lockHost-restores` are instantiated here, this time with c1355's
--  largest output cone: `Locking.CompileC1355.c1355nl`, a `Netlist` with
--  41 inputs and 100 gates. Inferred types leave the emitted operation list
--  unreduced and avoid excessive normalization during elaboration; see the
--  SCALE NOTE in LockC432. Restoration uses the generic lift. No postulates
--  are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockC1355 where

open import Locking.CompileC1355 using (c1355nl)
open import Extraction.LockHost using (lockHost-locked; lockHost-restores)

--  Instantiate the generic verified-emission result at c1355's actual
--  100-gate cone, allowing Agda to infer the type.
c1355flat-locked = lockHost-locked c1355nl

--  The emitted c1355 netlist recovers the host cone at the correct key;
--  the generic lift supplies the corollary with an inferred type.
c1355flat-restores = lockHost-restores c1355nl
