------------------------------------------------------------------------
--  Parameterise cyclic locking by an arbitrary secret (graph track).
--  In `Locking.CyclicTopo`, the raw key controls the feedback mux directly:
--  gateFB (s ∷ ks) (o ∷ os) (b ∷ bs) = mux s o (not b) ∷ gateFB ks os bs
--  Thus each loop opens at `false`, fixing the correct key to `allFalse k`
--  and the conclusion of `model→correct-T` to `ks ≡ allFalse k`. We instead
--  decode the key before selecting mux inputs:
--  updateFBk enc ks layer vs fbs = updateFBt (enc ks) layer vs fbs
--  Selectors now receive internal values `enc ks`. The results use two
--  decoder assumptions separately: `enc ksec ≡ allFalse k` opens every loop
--  at the secret, providing existence and functional correctness;
--  `enc ts ≡ allFalse k → ts ≡ ksec` excludes every other fully opening key,
--  providing the oscillation obstruction and model uniqueness. Together they
--  transport the CyclicTopo characterisation to arbitrary feedback topology
--  and universally quantified `ksec`: the combinational model occurs exactly
--  at that secret (`model→correct-K`, `lock-wrong-no-stable-K`,
--  `lock-correct-K`, and `lock-correct-unique-K`).
--  The concrete polarity decoder is `xorEnc ksec ks = zipWith _xor_ ksec ks`,
--  one XOR per key line, acting as an inverter exactly where the secret bit
--  is true: the usual XOR/XNOR construction. `gateFBX` and `gateFBX-xorEnc`
--  realise it locally at each gate by replacing `s` with `p xor s` in the
--  existing recursion, without a global decoder circuit. `xorEnc-self` and
--  `xorEnc-only` prove the assumptions. `xorEnc-allFalseˡ` gives the identity
--  at `allFalse k`, recovering `Locking.CyclicTopo`. This construction only
--  reindexes keys by a bijection sending the secret to the all-false selector
--  vector. The oscillation argument is unchanged: it reuses Cyclic's
--  `not-no-fixpoint`. The secret becomes a parameter instead of a constant.
--  The module uses `Locking.{Cyclic,CyclicMulti,CyclicTopo}` without postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.CyclicKey where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; true; false; not; _xor_)
open import Data.Bool.Properties using (xor-same)
open import Data.Vec using (Vec; []; _∷_; head; tail; zipWith)
open import Data.Product using (_×_; _,_)
open import Data.Sum using (inj₁; inj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; cong; cong₂; subst)
open import Relation.Nullary using (¬_)

open import Graph.Acyclic using (ANetlist; asolve)
open import Locking.Cyclic using (mux)
open import Locking.CyclicMulti using (allFalse)
open import Locking.CyclicTopo
  using (FBLayer; gateFB; updateFBt; lstepT; LStableT; SATModelT;
         allFalse-or-HasTrue; lock-wrong-no-stable-T; model→correct-T;
         lock-correct-T; lock-correct-unique-T)

private
  variable
    W k : ℕ

------------------------------------------------------------------------
--  Section 1: define the decoder and the lock it controls.

--  Decode the key bus into mux selectors through a combinational map.
KeyEnc : ℕ → Set
KeyEnc k = Vec Bool k → Vec Bool k

--  Use decoded key values as selectors in the update, allowing the loop-opening
--  key to be chosen as a parameter rather than fixed by the construction.
updateFBk : KeyEnc k → Vec Bool k → FBLayer k W →
            Vec Bool W → Vec Bool k → Vec Bool k
updateFBk enc ks layer vs fbs = updateFBt (enc ks) layer vs fbs

lstepK : KeyEnc k → Vec Bool k → FBLayer k W → ANetlist W →
         Vec Bool k × Vec Bool W → Vec Bool k × Vec Bool W
lstepK enc ks layer base p = lstepT (enc ks) layer base p

LStableK : KeyEnc k → Vec Bool k → FBLayer k W → ANetlist W →
           Vec Bool k × Vec Bool W → Set
LStableK enc ks layer base p = LStableT (enc ks) layer base p

--  State the keyed lock's precondition for a SAT/CycSAT attack.
SATModelK : KeyEnc k → Vec Bool k → FBLayer k W → ANetlist W → Set
SATModelK enc ks layer base = SATModelT (enc ks) layer base

------------------------------------------------------------------------
--  Section 2: exclude stable valuations at wrong keys for arbitrary topology.
--  D2: only injectivity at `allFalse`, the `only` hypothesis, is required here;
--  the equality `enc ksec ≡ allFalse k` is unnecessary for this obstruction.

lock-wrong-no-stable-K :
  (enc : KeyEnc k) (ksec ks : Vec Bool k)
  (layer : FBLayer k W) (base : ANetlist W) →
  ((ts : Vec Bool k) → enc ts ≡ allFalse k → ts ≡ ksec) →
  ¬ (ks ≡ ksec) →
  ¬ SATModelK enc ks layer base
lock-wrong-no-stable-K enc ksec ks layer base only ks≢ sat
  with allFalse-or-HasTrue (enc ks)
... | inj₁ e  = ks≢ (only ks e)
... | inj₂ ht = lock-wrong-no-stable-T (enc ks) layer base ht sat

--  For the keyed CycSAT obstruction, existence of a combinational model forces
--  the supplied key to equal `ksec`.
model→correct-K :
  (enc : KeyEnc k) (ksec ks : Vec Bool k)
  (layer : FBLayer k W) (base : ANetlist W) →
  ((ts : Vec Bool k) → enc ts ≡ allFalse k → ts ≡ ksec) →
  SATModelK enc ks layer base → ks ≡ ksec
model→correct-K enc ksec ks layer base only sat =
  only ks (model→correct-T (enc ks) layer base sat)

------------------------------------------------------------------------
--  Section 3: at the secret every loop opens, reducing well-definedness to a
--  fixed point of the open interconnect. D2: both results here require only
--  `enc ksec ≡ allFalse k`.

lock-correct-K :
  (enc : KeyEnc k) (ksec : Vec Bool k)
  (layer : FBLayer k W) (base : ANetlist W) (fb* : Vec Bool k) →
  enc ksec ≡ allFalse k →
  layer fb* (asolve base) ≡ fb* →
  LStableK enc ksec layer base (fb* , asolve base)
lock-correct-K enc ksec layer base fb* esec fix =
  subst (λ z → LStableT z layer base (fb* , asolve base)) (sym esec)
        (lock-correct-T layer base fb* fix)

lock-correct-unique-K :
  (enc : KeyEnc k) (ksec : Vec Bool k)
  (layer : FBLayer k W) (base : ANetlist W) (fb* : Vec Bool k) →
  enc ksec ≡ allFalse k →
  ((fbs : Vec Bool k) → layer fbs (asolve base) ≡ fbs → fbs ≡ fb*) →
  (p : Vec Bool k × Vec Bool W) → LStableK enc ksec layer base p →
  p ≡ (fb* , asolve base)
lock-correct-unique-K enc ksec layer base fb* esec uniq p st =
  lock-correct-unique-T layer base fb* uniq p
    (subst (λ z → LStableT z layer base p) esec st)

------------------------------------------------------------------------
--  Section 4: implement polarity decoding with one XOR on each key line.

xorEnc : Vec Bool k → KeyEnc k
xorEnc ksec ks = zipWith _xor_ ksec ks

--  Every loop is opened by the planted key.
xorEnc-self : (ks : Vec Bool k) → xorEnc ks ks ≡ allFalse k
xorEnc-self []       = refl
xorEnc-self (x ∷ xs) = cong₂ _∷_ (xor-same x) (xorEnc-self xs)

xor-false→≡ : (a b : Bool) → a xor b ≡ false → a ≡ b
xor-false→≡ true  true  _  = refl
xor-false→≡ true  false ()
xor-false→≡ false true  ()
xor-false→≡ false false _  = refl

--  All other keys fail to open every loop.
xorEnc-only : (ksec ks : Vec Bool k) → xorEnc ksec ks ≡ allFalse k → ks ≡ ksec
xorEnc-only []       []       eq = refl
xorEnc-only (s ∷ ss) (x ∷ xs) eq =
  cong₂ _∷_ (sym (xor-false→≡ s x (cong head eq)))
            (xorEnc-only ss xs (cong tail eq))

--  All-false polarity makes decoding the identity. Consequently this module
--  specialises to `Locking.CyclicTopo` when `ksec = allFalse k`.
xorEnc-allFalseˡ : (ks : Vec Bool k) → xorEnc (allFalse k) ks ≡ ks
xorEnc-allFalseˡ []       = refl
xorEnc-allFalseˡ (x ∷ xs) = cong (x ∷_) (xorEnc-allFalseˡ xs)

------------------------------------------------------------------------
--  Section 5: realise decoding at individual gates. Follow `gateFB`'s
--  coordinate recursion with `p xor s` in place of the raw bit `s`; `xorEnc`
--  consists of `k` two-input XOR gates and needs no global decoder circuit.

gateFBX : (ps ks os bs : Vec Bool k) → Vec Bool k
gateFBX []       []       []       []       = []
gateFBX (p ∷ ps) (s ∷ ks) (o ∷ os) (b ∷ bs) =
  mux (p xor s) o (not b) ∷ gateFBX ps ks os bs

gateFBX-xorEnc : (ps ks os bs : Vec Bool k) →
                 gateFBX ps ks os bs ≡ gateFB (xorEnc ps ks) os bs
gateFBX-xorEnc []       []       []       []       = refl
gateFBX-xorEnc (p ∷ ps) (s ∷ ks) (o ∷ os) (b ∷ bs) =
  cong (mux (p xor s) o (not b) ∷_) (gateFBX-xorEnc ps ks os bs)

updateFBx : (ps ks : Vec Bool k) (layer : FBLayer k W) →
            Vec Bool W → Vec Bool k → Vec Bool k
updateFBx ps ks layer vs fbs = gateFBX ps ks (layer fbs vs) fbs

--  The locally implemented lock equals the keyed construction using polarity
--  decoding.
updateFBx-updateFBk :
  (ps ks : Vec Bool k) (layer : FBLayer k W) (vs : Vec Bool W) (fbs : Vec Bool k) →
  updateFBx ps ks layer vs fbs ≡ updateFBk (xorEnc ps) ks layer vs fbs
updateFBx-updateFBk ps ks layer vs fbs = gateFBX-xorEnc ps ks (layer fbs vs) fbs

------------------------------------------------------------------------
--  Section 6: instantiate the characterisation for every secret, with a
--  combinational model exactly at that key.

xor-model→correct :
  (ksec ks : Vec Bool k) (layer : FBLayer k W) (base : ANetlist W) →
  SATModelK (xorEnc ksec) ks layer base → ks ≡ ksec
xor-model→correct ksec ks layer base =
  model→correct-K (xorEnc ksec) ksec ks layer base (xorEnc-only ksec)

xor-lock-wrong-no-stable :
  (ksec ks : Vec Bool k) (layer : FBLayer k W) (base : ANetlist W) →
  ¬ (ks ≡ ksec) → ¬ SATModelK (xorEnc ksec) ks layer base
xor-lock-wrong-no-stable ksec ks layer base =
  lock-wrong-no-stable-K (xorEnc ksec) ksec ks layer base (xorEnc-only ksec)

xor-lock-correct :
  (ksec : Vec Bool k) (layer : FBLayer k W) (base : ANetlist W) (fb* : Vec Bool k) →
  layer fb* (asolve base) ≡ fb* →
  LStableK (xorEnc ksec) ksec layer base (fb* , asolve base)
xor-lock-correct ksec layer base fb* =
  lock-correct-K (xorEnc ksec) ksec layer base fb* (xorEnc-self ksec)
