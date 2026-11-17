------------------------------------------------------------------------
-- Whole-host constant-channel recovery, conditional on constant-free host
-- operations. This covers our rendered characters, not transformed files.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}
module Extraction.HostDisclosure where

open import Data.Bool using (Bool; true; false)
open import Data.List using (List; []; _∷_; _++_; length; take)
open import Data.Nat using (ℕ; suc)
open import Data.Fin using (zero)
open import Data.Product using (proj₁; proj₂)
open import Data.Vec using (Vec; toList; lookup)
open import Data.Vec.Properties using (length-toList)
open import Data.Maybe using (just)
open import Relation.Binary.PropositionalEquality using (_≡_; trans; cong; sym)
open import Locking.NetlistToCircuit using (Netlist)
open import Extraction.Netlist using (upFrom)
open import Extraction.HostNetlist using (netlistWires)
open import Extraction.LockHost using (lockHostBlock)
open import Extraction.LockedNet using (lockedBlock)
open import Extraction.LockedNetMerged using
  (NoConst; constVals; constVals-++; noConst⇒constVals; lockedBlock-constVals)
open import Attack.ObservationSeparation using (decodeConst; take-prefix)
open import Extraction.DecodeText using (decodeConstText; decodeConst-text)
open import Extraction.BenchISCAS using (renderNetL)

private
  variable
    n G : ℕ

host-constVals :
  (nl : Netlist n (suc G)) (s : Vec Bool n) (h start : ℕ) →
  NoConst (proj₂ (proj₂ (netlistWires nl start))) →
  constVals (proj₂ (proj₂ (lockHostBlock nl (toList s) h start)))
  ≡ toList s ++ (true ∷ false ∷ true ∷ false ∷ [])
host-constVals {n} nl s h start nc =
  trans (constVals-++ hostOps lockOps)
    (trans (cong (_++ constVals lockOps) (noConst⇒constVals nc))
      (lockedBlock-constVals (upFrom 0 n) (upFrom n n) (toList s) h feed next))
  where
    hostOps = proj₂ (proj₂ (netlistWires nl start))
    next = proj₁ (proj₂ (netlistWires nl start))
    feed = lookup (proj₁ (netlistWires nl start)) zero
    lockOps = proj₂ (proj₂ (lockedBlock (upFrom 0 n) (upFrom n n) (toList s) h feed next))

decodeConst-host :
  (nl : Netlist n (suc G)) (s : Vec Bool n) (h start : ℕ) →
  NoConst (proj₂ (proj₂ (netlistWires nl start))) →
  decodeConst n (proj₂ (proj₂ (lockHostBlock nl (toList s) h start))) ≡ toList s
decodeConst-host {n} nl s h start nc =
  trans (cong (take n) (host-constVals nl s h start nc))
    (trans (cong (λ m → take m (toList s ++ (true ∷ false ∷ true ∷ false ∷ [])))
                 (sym (length-toList s)))
           (take-prefix (toList s) (true ∷ false ∷ true ∷ false ∷ [])))

decodeConst-host-text :
  (nl : Netlist n (suc G)) (s : Vec Bool n) (h start inputs : ℕ) →
  NoConst (proj₂ (proj₂ (netlistWires nl start))) →
  decodeConstText n
    (renderNetL inputs (proj₂ (proj₂ (lockHostBlock nl (toList s) h start)))
                       (proj₁ (lockHostBlock nl (toList s) h start)))
  ≡ just (toList s)
decodeConst-host-text {n} nl s h start inputs nc =
  trans (decodeConst-text n inputs
           (proj₂ (proj₂ (lockHostBlock nl (toList s) h start)))
           (proj₁ (lockHostBlock nl (toList s) h start)))
        (cong just (decodeConst-host nl s h start nc))
