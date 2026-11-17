------------------------------------------------------------------------
--  Verified flat emission for the ISCAS-85 c7552 host (A2)
--  As in `LockC432` and `LockC880`, the generic results `lockHost-locked`
--  and `lockHost-restores` are instantiated here, this time with c7552's
--  largest output cone: `Locking.CompileC7552.c7552nl`, a `Netlist` with
--  194 inputs and 523 gates. Inferred types leave the emitted operation list
--  unreduced and avoid excessive normalization during elaboration; see the
--  SCALE NOTE in LockC432. Restoration uses the generic lift. No postulates
--  are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockC7552 where

open import Locking.CompileC7552 using (c7552nl)
open import Extraction.LockHost using (lockHost-locked; lockHost-restores)

--  Instantiate the generic verified-emission result at c7552's actual
--  523-gate cone, allowing Agda to infer the type.
c7552flat-locked = lockHost-locked c7552nl

--  The emitted c7552 netlist recovers the host cone at the correct key;
--  the generic lift supplies the corollary with an inferred type.
c7552flat-restores = lockHost-restores c7552nl
