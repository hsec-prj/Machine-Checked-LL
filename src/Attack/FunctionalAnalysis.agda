------------------------------------------------------------------------
--  Discharge FALL's KeyGatesAtHW1 premise through functional analysis.
--  Attack.FALL proves a recovery round assuming KeyGatesAtHW1 k o =
--  ∀ i → o i ≡ lookup k i, an oracle already exposing key bits. That
--  premise represented FALL step 1, analysis of the locked netlist. Here
--  model recovery of its internal Hamming-distance node and prove that
--  node yields every key bit for all h,n. Sphere membership alone is
--  insufficient: KeyLeakChannel.SFLL-HD-h1-not-full-leak equates 00 and 11
--  at h=1,n=2. Use the stronger distNode k = λ x → HD x k before
--  thresholding. distNode-netlist, from SFLL.Netlist.xorK-weight, proves
--  distNode k x ≡ weight (⟦ xorK k ⟧ x). The modelling step is therefore
--  accessing a node the netlist is proved to contain, rather than adding
--  an axiom about its meaning. recoverOracle scans allVecs, setting bit i
--  when some zero-distance input has that bit set. HD0→≡ identifies k as
--  the unique zero-distance input, so the scan recovers k independently of
--  h and avoids sphere collisions. FA-recovers-oracle establishes
--  KeyGatesAtHW1 k (recoverOracle (distNode k)); FALL-recovers-key-full
--  then applies the existing recovery round without assuming that premise.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.FunctionalAnalysis where

open import Data.Nat using (ℕ; zero; suc; _≡ᵇ_; _≤_)
open import Data.Bool using (Bool; true; false; not; _∧_; T)
open import Data.Unit using (tt)
open import Data.Fin using (Fin)
open import Data.Vec using (Vec; lookup)
open import Data.List using (List; []; _∷_)
open import Data.Nat.Properties using (≡ᵇ⇒≡)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import Util.Counting using (countT; countT-≡0; allVecs; allVecs-count-pos)
open import SFLL.HammingDistance using (HD; HD-refl; HD0→≡)
open import SFLL.Netlist using (weight; xorK; xorK-weight)
open import Circuit.Semantics using (⟦_⟧)
open import Attack.Oracle using (ask)
open import Attack.FALL using (KeyGatesAtHW1; fall; FALL-recovers-key)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Specify the distance node obtained by functional analysis.

--  Use the comparator's pre-threshold popcount, equal to input/key
--  Hamming distance.
distNode : Vec Bool n → Vec Bool n → ℕ
distNode k x = HD x k

--  Ground the node in the verified xorK layer: xorK-weight proves it is
--  exactly the popcount of that layer's output.
distNode-netlist : (k x : Vec Bool n) → distNode k x ≡ weight (⟦ xorK k ⟧ x)
distNode-netlist k x = sym (xorK-weight k x)

------------------------------------------------------------------------
--  Provide supporting counting facts.

--  A positive count fails the Boolean equality test against zero.
nz : (c : ℕ) → 1 ≤ c → (c ≡ᵇ 0) ≡ false
nz zero    ()
nz (suc _) _  = refl

------------------------------------------------------------------------
--  Recover bit i by testing whether any zero-distance input has bit i set.

recoverOracle : (Vec Bool n → ℕ) → Fin n → Bool
recoverOracle {n} dist i =
  not (countT (λ x → (dist x ≡ᵇ 0) ∧ lookup x i) (allVecs n) ≡ᵇ 0)

--  Prove FALL step 1: the recovered oracle returns each key bit for every
--  radius and width.
FA-recovers-oracle : (k : Vec Bool n) → KeyGatesAtHW1 k (recoverOracle (distNode k))
FA-recovers-oracle {n} k i with lookup k i in lk
... | true  = cong not (nz _ (allVecs-count-pos P k Pk))
  where
    P : Vec Bool n → Bool
    P x = (HD x k ≡ᵇ 0) ∧ lookup x i
    --  The key lies in its own radius-zero sphere, HD k k=0, and has bit i true.
    Pk : P k ≡ true
    Pk = cong₂ _∧_ (cong (_≡ᵇ 0) (HD-refl k)) lk
... | false = cong not (cong (_≡ᵇ 0) (countT-≡0 P Pfalse (allVecs n)))
  where
    P : Vec Bool n → Bool
    P x = (HD x k ≡ᵇ 0) ∧ lookup x i
    --  No witness exists when key bit i is false: HD0→≡ makes k the sole
    --  zero-distance input.
    Pfalse : (x : Vec Bool n) → P x ≡ false
    Pfalse x with HD x k ≡ᵇ 0 in e
    ... | false = refl
    ... | true  =
      trans (cong (λ v → lookup v i)
                  (HD0→≡ x k (≡ᵇ⇒≡ (HD x k) 0 (subst T (sym e) tt))))
            lk

------------------------------------------------------------------------
--  Obtain complete FALL recovery without a structural hypothesis.

--  Compose FA-recovers-oracle with Attack.FALL.fall's budget-n round to
--  reconstruct the key exactly, supplying KeyGatesAtHW1 by proof.
FALL-recovers-key-full : (k : Vec Bool n) →
                         ask (fall {n}) (recoverOracle (distNode k)) ≡ k
FALL-recovers-key-full k =
  FALL-recovers-key k (recoverOracle (distNode k)) (FA-recovers-oracle k)
