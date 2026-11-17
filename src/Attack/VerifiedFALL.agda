------------------------------------------------------------------------
--  Package verified FALL as an adversary with a query budget in its type.
--  Attack.FALLPoly already supplies a terminating executable polynomial
--  recovery function: fall-poly-recovers-key extracts the whole key from
--  distNode k = λ x → HD x k in n+1 queries. Here a concrete QAdversary
--  records the budget suc n in its type and satisfies Recovers for the
--  distance-node scheme without structural assumptions. In particular it
--  does not require the KeyGatesAtHW1 premise of Attack.FALL.fall. This gives
--  the SFLL family a machine-checked SAT/FALL adversary with a typed query
--  count instead of an external trusted procedure. The reference x and its
--  n single-bit flips are selected independently of oracle answers, so FALL
--  is non-adaptive and fits QAdversary. The probe-vector length encodes
--  suc n = n+1. No postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.VerifiedFALL where

open import Data.Nat using (ℕ; suc; _≡ᵇ_)
open import Data.Bool using (Bool; not; if_then_else_)
open import Data.Fin using (Fin)
open import Data.Vec using (Vec; _∷_; lookup; tabulate; map)
open import Data.Vec.Properties using (lookup-map; lookup∘tabulate; tabulate-cong)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans; cong)

open import Attack.Oracle using (QAdversary; ask; Recovers)
open import Attack.FunctionalAnalysis using (distNode)
open import Attack.FALLPoly using (flipAt; recoverBitPoly; recoverKeyPoly; fall-poly-recovers-key)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Decode n+1 answers, comprising reference distance d0 and flip distances ds,
--  by applying the FALLPoly comparison to each key bit.

decodeFall : (x : Vec Bool n) → Vec ℕ (suc n) → Vec Bool n
decodeFall x (d0 ∷ ds) =
  tabulate (λ i → if (lookup ds i ≡ᵇ suc d0) then lookup x i else not (lookup x i))

------------------------------------------------------------------------
--  Probe reference x and all n values flipAt i x. The probe vector's type
--  records the adversary's suc n budget.

fallPolyQA : (x : Vec Bool n) → QAdversary (Vec Bool n) ℕ (Vec Bool n) (suc n)
fallPolyQA x = record
  { probes = x ∷ tabulate (λ i → flipAt i x)
  ; decode = decodeFall x
  }

------------------------------------------------------------------------
--  For any secret, running this adversary against its distance-node oracle
--  returns that secret, without a structural premise.

fallPolyQA-recovers : (x : Vec Bool n) → Recovers (fallPolyQA x) distNode
fallPolyQA-recovers {n} x k = trans step (fall-poly-recovers-key k x)
  where
    --  The i-th flip answer is distNode k (flipAt i x), making the decoded result
    --  equal to the FALLPoly recovery function.
    lkup : (i : Fin n) →
           lookup (map (distNode k) (tabulate (λ j → flipAt j x))) i
             ≡ distNode k (flipAt i x)
    lkup i = trans (lookup-map i (distNode k) (tabulate (λ j → flipAt j x)))
                   (cong (distNode k) (lookup∘tabulate (λ j → flipAt j x) i))

    step : ask (fallPolyQA x) (distNode k) ≡ recoverKeyPoly (distNode k) x
    step = tabulate-cong
      (λ i → cong (λ d → if (d ≡ᵇ suc (distNode k x))
                          then lookup x i else not (lookup x i)) (lkup i))
