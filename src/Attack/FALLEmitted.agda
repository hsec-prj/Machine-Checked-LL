------------------------------------------------------------------------
--  Locate FALL's distance node in the emitted comparator, partially closing
--  the compiler connection. FunctionalAnalysis proves recovery from
--  distNode k = λ x → HD x k and relates it to weight (⟦ xorK k ⟧ x)
--  through distNode-netlist. That isolated xorK result still abstracted the
--  connection to an emitted lock as sensitisation. The certified compiler's
--  efficient comparator is prot-circuit-eff hF k = Seq (xorK k)
--  (popcountEqC n hF). protEff-factors proves by refl that xorK is its
--  first stage, placing ⟦ xorK k ⟧ x on an actual internal bus. Reading its
--  popcount defines distOracleEmit; FALL-recovers-emitted recovers the key
--  from that emitted-node oracle. The remaining premise is observability
--  of the internal node at the complete lock's primary output, namely FALL
--  input sensitisation. The node's existence in the emitted netlist and
--  recovery from it are now theorems. No postulates are added.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.FALLEmitted where

open import Data.Nat using (ℕ; suc; _≡ᵇ_)
open import Data.Bool using (Bool; not; _∧_)
open import Data.Fin using (Fin; toℕ)
open import Data.Vec using (Vec; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans; cong)

open import Circuit.Core using (Circuit; Seq)
open import Circuit.Semantics using (⟦_⟧)
open import Util.Counting using (countT; allVecs; countT-cong)
open import SFLL.Netlist using (xorK; weight; xorK-weight)
open import SFLL.PopcountCircuit using (popcountEqC)
open import SFLL.EfficientLock using (prot-circuit-eff)
open import Attack.Oracle using (ask)
open import Attack.FALL using (KeyGatesAtHW1; fall; FALL-recovers-key)
open import Attack.FunctionalAnalysis using (distNode; recoverOracle; FA-recovers-oracle)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Identify the distance stage as a subcircuit of the emitted comparator.

--  Before thresholding, the efficient comparator applies xorK; its output
--  weight equals the input's Hamming distance from the key.
distNodeCirc : (k : Vec Bool n) → Circuit n n
distNodeCirc k = xorK k

--  Factor the emitted comparator definitionally into the distance stage
--  and polynomial popcount threshold, establishing a real compiler-output bus.
protEff-factors : (hF : Fin (suc n)) (k : Vec Bool n) →
  prot-circuit-eff hF k ≡ Seq (distNodeCirc k) (popcountEqC n hF)
protEff-factors hF k = refl

--  Obtain FALL's oracle by counting set bits on the emitted bus ⟦ xorK k ⟧ x.
distOracleEmit : (k : Vec Bool n) → Vec Bool n → ℕ
distOracleEmit k x = weight (⟦ distNodeCirc k ⟧ x)

--  Use xorK-weight to identify it with FALL's abstract distance node.
distOracleEmit-≡ : (k x : Vec Bool n) → distOracleEmit k x ≡ distNode k x
distOracleEmit-≡ k x = xorK-weight k x

------------------------------------------------------------------------
--  Transfer FALL recovery to the emitted-node oracle.

--  Pointwise oracle agreement and countT-cong make the recovery scan read
--  the same bit from emitted and abstract nodes, without functional extensionality.
recoverOracle-emit-≡ : (k : Vec Bool n) (i : Fin n) →
  recoverOracle (distOracleEmit k) i ≡ recoverOracle (distNode k) i
recoverOracle-emit-≡ k i =
  cong (λ c → not (c ≡ᵇ 0))
       (countT-cong
         (λ x → cong (λ d → (d ≡ᵇ 0) ∧ lookup x i) (distOracleEmit-≡ k x))
         (allVecs _))

--  Establish FALL step 1 for the emitted-node oracle.
FA-recovers-oracle-emit : (k : Vec Bool n) →
  KeyGatesAtHW1 k (recoverOracle (distOracleEmit k))
FA-recovers-oracle-emit k i = trans (recoverOracle-emit-≡ k i) (FA-recovers-oracle k i)

--  Recover the key by querying weight (⟦ xorK k ⟧ x) on the emitted
--  distance bus, whose xorK stage is definitionally first in prot-circuit-eff
--  by protEff-factors.
FALL-recovers-emitted : (k : Vec Bool n) →
  ask (fall {n}) (recoverOracle (distOracleEmit k)) ≡ k
FALL-recovers-emitted k =
  FALL-recovers-key k (recoverOracle (distOracleEmit k)) (FA-recovers-oracle-emit k)
