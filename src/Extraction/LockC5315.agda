------------------------------------------------------------------------
--  Verified flat emission for the ISCAS-85 c5315 host (A2)
--  As in `LockC432` and `LockC880`, the generic results `lockHost-locked`
--  and `lockHost-restores` are instantiated here, this time with c5315's
--  largest output cone: `Locking.CompileC5315.c5315nl`, a `Netlist` with
--  67 inputs and 187 gates. Inferred types leave the emitted operation list
--  unreduced and avoid excessive normalization during elaboration; see the
--  SCALE NOTE in LockC432. Restoration uses the generic lift. No postulates
--  are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockC5315 where

open import Locking.CompileC5315 using (c5315nl)
open import Extraction.LockHost using (lockHost-locked; lockHost-restores)

--  Instantiate the generic verified-emission result at c5315's actual
--  187-gate cone, allowing Agda to infer the type.
c5315flat-locked = lockHost-locked c5315nl

--  The emitted c5315 netlist recovers the host cone at the correct key;
--  the generic lift supplies the corollary with an inferred type.
c5315flat-restores = lockHost-restores c5315nl
