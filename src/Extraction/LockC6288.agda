------------------------------------------------------------------------
--  Verified flat emission for the ISCAS-85 c6288 host (A2)
--  As in `LockC432` and `LockC880`, the generic results `lockHost-locked`
--  and `lockHost-restores` are instantiated here, this time with c6288's
--  largest output cone: `Locking.CompileC6288.c6288nl`, a `Netlist` with
--  32 inputs and 633 gates. Inferred types leave the emitted operation list
--  unreduced and avoid excessive normalization during elaboration; see the
--  SCALE NOTE in LockC432. Restoration uses the generic lift. No postulates
--  are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockC6288 where

open import Locking.CompileC6288 using (c6288nl)
open import Extraction.LockHost using (lockHost-locked; lockHost-restores)

--  Instantiate the generic verified-emission result at c6288's actual
--  633-gate cone, allowing Agda to infer the type.
c6288flat-locked = lockHost-locked c6288nl

--  The emitted c6288 netlist recovers the host cone at the correct key;
--  the generic lift supplies the corollary with an inferred type.
c6288flat-restores = lockHost-restores c6288nl
