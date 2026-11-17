------------------------------------------------------------------------
--  Supply host slices for per-host observability measurements (M3).
--  Attack.FALLObservability establishes key recovery from the emitted
--  distance node under observability and failure of bit recovery under
--  masking. Here --safe Boolean host functions and verified counting
--  cores allow Main obs to execute compiled verified functions.
--  For m : Vec Bool n → Bool,
--  maskHost m x s = m x ∧ s passes the protected signal exactly where m x
--  holds; maskHost-obs proves obs (maskHost m) x ≡ m x. Consequently
--  obsCount m counts inputs satisfying m, and fallCount m counts references
--  where m holds both at x and at every flipAt i x, enabling whole-key FALL.
--  For the identity mask mId = const true, obsCount-mId-full gives
--  obsCount mId ≡ 2^n, the full-visibility endpoint corresponding to
--  recoverKeyVis-emitted. Every masking host reduces both counts. The module
--  uses no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.ObsHosts where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _/_; _%_; _^_; _≤?_; _<?_)
open import Data.Bool using (Bool; true; false; if_then_else_; _∧_)
open import Data.Vec using (Vec; allFin; toList)
import Data.Vec as DV
open import Data.List using (List; []; _∷_; map; foldr; length)
open import Relation.Nullary.Decidable using (⌊_⌋)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans; cong)

open import SFLL.HammingDistance using (b2n; parity)
open import SFLL.Netlist using (weight)
open import Security.POCorruption using (obs)
open import Attack.FALLPoly using (flipAt)
open import Util.Counting using (countT; allVecs; length-allVecs)

private variable n : ℕ

------------------------------------------------------------------------
--  Section 1: define masked hosts and prove their observability identity.

--  Pass the protected signal only when m x is true.
maskHost : (Vec Bool n → Bool) → Vec Bool n → Bool → Bool
maskHost m x s = if m x then s else false

--  Prove that the host's observability equals its mask.
maskHost-obs : (m : Vec Bool n → Bool) (x : Vec Bool n) → obs (maskHost m) x ≡ m x
maskHost-obs m x with m x
... | true  = refl
... | false = refl

------------------------------------------------------------------------
--  Section 2: express host slices as --safe Boolean functions.

mId : Vec Bool n → Bool                       --  Always visible under H(x,s)=s
mId _ = true

mParity : Vec Bool n → Bool                   --  Weight-parity mask, exposing roughly half the inputs
mParity x = parity (weight x)

mThresh : Vec Bool n → Bool                   --  Threshold mask for weight ≥ ⌈n/2⌉
mThresh {n} x = ⌊ (suc n / 2) ≤? weight x ⌋

--  Encode integers least-significant-bit first: bit i = (x>>i)&1.
vecToℕ : Vec Bool n → ℕ
vecToℕ DV.[]       = 0
vecToℕ (b DV.∷ bs) = b2n b + 2 * vecToℕ bs

mDensity : ℕ → Vec Bool n → Bool             --  Knuth-hash mask with a pseudo-random percentage density
mDensity dens x = ⌊ ((vecToℕ x * 2654435761 + 12345) % 100) <? dens ⌋

------------------------------------------------------------------------
--  Section 3: define verified counting functions for compiled Main obs execution.

allFlipsVis : (Vec Bool n → Bool) → Vec Bool n → Bool
allFlipsVis {n} m x = foldr _∧_ true (map (λ i → m (flipAt i x)) (toList (allFin n)))

fallVis : (Vec Bool n → Bool) → Vec Bool n → Bool
fallVis m x = m x ∧ allFlipsVis m x

obsCount fallCount : (Vec Bool n → Bool) → ℕ
obsCount  {n} m = countT m (allVecs n)
fallCount {n} m = countT (fallVis m) (allVecs n)

------------------------------------------------------------------------
--  Section 4: prove complete observability of the identity host.

countT-mId : (xs : List (Vec Bool n)) → countT mId xs ≡ length xs
countT-mId []       = refl
countT-mId (x ∷ xs) = cong suc (countT-mId xs)

--  Prove obsCount mId ≡ 2^n, giving full visibility and the endpoint
--  used by recoverKeyVis-emitted.
obsCount-mId-full : obsCount {n} mId ≡ 2 ^ n
obsCount-mId-full {n} = trans (countT-mId (allVecs n)) (length-allVecs n)
