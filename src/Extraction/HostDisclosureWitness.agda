------------------------------------------------------------------------
-- The actual imported host literals satisfy cleanHost, without assuming
-- that the Python importer used lutCircuit. Each refl is kernel checked.
-- Recovery is for the exact renderNetL output, before external processing.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}
module Extraction.HostDisclosureWitness where
open import Data.Nat using (ℕ; suc)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec; toList)
open import Data.Product using (proj₁; proj₂)
open import Data.Maybe using (just)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Extraction.HostNoConst using (cleanHost; netlistWires-noConst; CleanBuilder)
open import Extraction.HostNetlist using (netlistWires)
open import Extraction.HostDisclosure using (decodeConst-host-text)
open import Extraction.DecodeText using (decodeConstText)
open import Extraction.BenchISCAS using (renderNetL)
open import Extraction.LockHost using (lockHostBlock)
open import Locking.NetlistToCircuit using (Netlist)
open import Locking.CompileC1355 using (c1355nl)
open import Locking.CompileC17Multi using (c17nl2)
open import Locking.CompileC432 using (c432nl)
open import Locking.CompileC5315 using (c5315nl)
open import Locking.CompileC6288 using (c6288nl)
open import Locking.CompileC7552 using (c7552nl)
open import Locking.CompileC880 using (c880nl)
open import Locking.CompileISCAS using (c17nl)

-- Keep the host abstract while composing proofs. Concrete aliases below
-- infer this type without normalising large emitted operation lists.
clean-host-decode : ∀ {n G} (nl : Netlist n (suc G)) → cleanHost nl ≡ true →
  (s : Vec Bool n) (h start inputs : ℕ) →
  decodeConstText n
    (renderNetL inputs (proj₂ (proj₂ (lockHostBlock nl (toList s) h start)))
                      (proj₁ (lockHostBlock nl (toList s) h start)))
  ≡ just (toList s)
clean-host-decode nl p s h start inputs =
  decodeConst-host-text nl s h start inputs (netlistWires-noConst nl p start)

c1355nl-clean : cleanHost c1355nl ≡ true
c1355nl-clean = refl

c1355nl-noConst = netlistWires-noConst c1355nl c1355nl-clean

c1355nl-decode = clean-host-decode c1355nl c1355nl-clean

c17nl2-clean : cleanHost c17nl2 ≡ true
c17nl2-clean = refl

c17nl2-noConst = netlistWires-noConst c17nl2 c17nl2-clean

c17nl2-decode = clean-host-decode c17nl2 c17nl2-clean

c432nl-clean : cleanHost c432nl ≡ true
c432nl-clean = refl

c432nl-noConst = netlistWires-noConst c432nl c432nl-clean

c432nl-decode = clean-host-decode c432nl c432nl-clean

c5315nl-clean : cleanHost c5315nl ≡ true
c5315nl-clean = refl

c5315nl-noConst = netlistWires-noConst c5315nl c5315nl-clean

c5315nl-decode = clean-host-decode c5315nl c5315nl-clean

c6288nl-clean : cleanHost c6288nl ≡ true
c6288nl-clean = refl

c6288nl-noConst = netlistWires-noConst c6288nl c6288nl-clean

c6288nl-decode = clean-host-decode c6288nl c6288nl-clean

c7552nl-clean : cleanHost c7552nl ≡ true
c7552nl-clean = refl

c7552nl-noConst = netlistWires-noConst c7552nl c7552nl-clean

c7552nl-decode = clean-host-decode c7552nl c7552nl-clean

c880nl-clean : cleanHost c880nl ≡ true
c880nl-clean = refl

c880nl-noConst = netlistWires-noConst c880nl c880nl-clean

c880nl-decode = clean-host-decode c880nl c880nl-clean

c17nl-clean : cleanHost c17nl ≡ true
c17nl-clean = refl

c17nl-noConst = netlistWires-noConst c17nl c17nl-clean

c17nl-decode = clean-host-decode c17nl c17nl-clean
