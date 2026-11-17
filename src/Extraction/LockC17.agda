------------------------------------------------------------------------
--  Verified flat emission for the actual c17 host
--  `Extraction.LockHost.lockHost-locked` establishes locking for every
--  imported host in the composed flat netlist. The instance here uses the
--  ISCAS-85 c17 cone `Locking.CompileC17Multi.c17nl2`, whose bus position 0
--  is output N23. Within Agda, without a synthesizer, the shared-wire result
--  of `lockHostBlock` is certified to implement this cone's SFLL-HD lock
--  and to recover the original cone exactly with the correct key. This is
--  the correct-by-construction counterpart of external `splice_sfll.py`:
--  the host gates compute `f x` instead of taking it from an input wire.
--  No postulates are required.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockC17 where

open import Data.Bool using (Bool)
open import Data.Fin using (toℕ)
open import Data.List using (_++_; length)
open import Data.Product using (_,_)
open import Data.Vec using (Vec; toList)
open import Relation.Binary.PropositionalEquality using (_≡_)

open import SFLL.HD using (locked)
open import Locking.NetlistToCircuit using (importConeF)
open import Locking.CompileC17Multi using (c17nl2; ksec; hF)
open import Extraction.Netlist using (get; runNet)
open import Extraction.LockHost using (lockHostBlock; lockHost-locked; lockHost-restores)

--  Interpret c17's actual cone at primary output N23 (bus position 0) as a host function.
c17coneF : Vec Bool 5 → Bool
c17coneF = importConeF c17nl2

--  The flat netlist implements the c17 lock by construction. On the bus
--  [x(0..4) | key(5..9)], c17's own NAND gates compute N23, and the surrounding
--  lock block applies `locked (HD radius 2) ksec key`.
c17flat-locked : (x key : Vec Bool 5) →
  let (out , _ , ops) = lockHostBlock c17nl2 (toList ksec) (toℕ hF)
                          (length (toList x ++ toList key))
  in get (runNet (toList x ++ toList key) ops) out
       ≡ locked (toℕ hF) ksec key c17coneF x
c17flat-locked x key = lockHost-locked c17nl2 x key ksec (toℕ hF)

--  Supplying the correct key, ksec, restores the actual c17 cone in the emitted netlist.
c17flat-restores : (x : Vec Bool 5) →
  let (out , _ , ops) = lockHostBlock c17nl2 (toList ksec) (toℕ hF)
                          (length (toList x ++ toList ksec))
  in get (runNet (toList x ++ toList ksec) ops) out ≡ c17coneF x
c17flat-restores x = lockHost-restores c17nl2 x ksec (toℕ hF)
