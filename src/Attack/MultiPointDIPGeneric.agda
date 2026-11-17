------------------------------------------------------------------------
--  Generalise multi-output recovery to arbitrary key types and instantiate
--  genuinely distinct output keys (D8-II frontier 3, option c). Although
--  MultiPointDIP.multiDIP-recovers names a single Vec Bool n key, its proof
--  folds over inputs and uses keys only through the oracle and Distinguishing.
--  Expose that generality in multiDIPK-recovers: any distinguishing
--  om : K → input → Vec Bool m admits recovery in 2ⁿ queries for arbitrary K.
--  Take K = Vec (Vec Bool n) m for one key per output. Using a vector rather
--  than a function lets Vec-≢→∃ locate a differing coordinate without
--  functional extensionality. om-setK ksecs x reads the separate point
--  indicators; at a differing output prot0-false gives cancellation, proving
--  om-setK-distinguishing and om-setK-recovers in 2ⁿ queries regardless of m.
--  Preserve the distinction between axes: recovery cost is output-count
--  independent, while corruption varies with the per-output keys and obeys
--  Security.MultiOCR.mocr-setK-bound ≤ Σᵢ OCRᵢ. Reuse eqVec, andMap,
--  ∈-allVecs, prot0-self, and prot0-false; Vec-≢→∃ and this instance are
--  the new ingredients. No postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.MultiPointDIPGeneric where

open import Data.Nat using (ℕ; _^_)
open import Data.Bool using (Bool; true; false)
open import Data.Vec using (Vec; []; _∷_; lookup; map)
open import Data.Vec.Properties using (lookup-map)
open import Data.Fin using (Fin; zero; suc)
open import Data.List using (List; length)
open import Data.Product using (_×_; _,_; ∃)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Empty using (⊥; ⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HD using (prot)
open import Security.AntiSat using (prot0-false)
open import Attack.PointDIPAttack
  using (prot0-self; andMap; andMap-true; andMap-false; ∈-allVecs)
open import Util.BoolVec using (eqVec-complete)
open import Util.BoolVec using (eqVec; eqVec-refl; eqVec-sound; ≢→eqVec-false)
open import Util.Counting using (allVecs; length-allVecs)


private
  variable
    n m : ℕ
    K : Set

------------------------------------------------------------------------
--  Abstract key type K in the MultiPointDIP proof, which never inspects key
--  structure.

consistVK : (om : K → Vec Bool n → Vec Bool m) (ksec : K) (x : Vec Bool n) (k : K) → Bool
consistVK om ksec x k = eqVec (om k x) (om ksec x)

survivesVK : (om : K → Vec Bool n → Vec Bool m) (ksec : K)
             (qs : List (Vec Bool n)) (k : K) → Bool
survivesVK om ksec qs k = andMap (λ x → consistVK om ksec x k) qs

DistinguishingK : (om : K → Vec Bool n → Vec Bool m) (ksec : K) → Set
DistinguishingK {K = K} om ksec = (k : K) → k ≢ ksec → ∃ λ x → om k x ≢ om ksec x

multiDIPK-sec : (om : K → Vec Bool n → Vec Bool m) (ksec : K) →
                survivesVK om ksec (allVecs n) ksec ≡ true
multiDIPK-sec om ksec =
  andMap-true (λ x → consistVK om ksec x ksec) (allVecs _) (λ x → eqVec-refl (om ksec x))

multiDIPK-kill : (om : K → Vec Bool n → Vec Bool m) (ksec : K) →
                 DistinguishingK om ksec → (k : K) → k ≢ ksec →
                 survivesVK om ksec (allVecs n) k ≡ false
multiDIPK-kill om ksec dist k k≢ with dist k k≢
... | (x , neq) =
  andMap-false (λ y → consistVK om ksec y k) (allVecs _) x (∈-allVecs x)
               (≢→eqVec-false (om k x) (om ksec x) neq)

--  Recover keys of any distinguishing oracle with 2ⁿ queries.
multiDIPK-recovers : (om : K → Vec Bool n → Vec Bool m) (ksec : K) →
                     DistinguishingK om ksec → (k : K) →
                     (k ≡ ksec → survivesVK om ksec (allVecs n) k ≡ true)
                     × (k ≢ ksec → survivesVK om ksec (allVecs n) k ≡ false)
multiDIPK-recovers om ksec dist k = rec , multiDIPK-kill om ksec dist k
  where
    rec : k ≡ ksec → survivesVK om ksec (allVecs _) k ≡ true
    rec refl = multiDIPK-sec om ksec

multiDIPK-queries : (w : ℕ) → length (allVecs w) ≡ 2 ^ w
multiDIPK-queries = length-allVecs

------------------------------------------------------------------------
--  Prove structural facts for vector key tuples, without functional extensionality.

false≢true : false ≡ true → ⊥
false≢true ()

decVec : (a b : Vec Bool n) → (a ≡ b) ⊎ (a ≢ b)
decVec a b with eqVec a b in e
... | true  = inj₁ (eqVec-sound a b e)
... | false = inj₂ (λ p → false≢true (trans (sym e) (eqVec-complete a b p)))

--  Locate an output index where a distinct tuple differs from the secret.
Vec-≢→∃ : {a b : Vec (Vec Bool n) m} → a ≢ b → ∃ λ i → lookup a i ≢ lookup b i
Vec-≢→∃ {a = []}     {[]}     ne = ⊥-elim (ne refl)
Vec-≢→∃ {a = a ∷ as} {b ∷ bs} ne with decVec a b
... | inj₂ a≢b  = zero , a≢b
... | inj₁ refl = let (i , p) = Vec-≢→∃ (λ q → ne (cong (a ∷_) q)) in suc i , p

------------------------------------------------------------------------
--  Instantiate K as a tuple of m separate output keys.

Keys : ℕ → ℕ → Set
Keys n m = Vec (Vec Bool n) m

--  Use each output's own key in its radius-zero point indicator.
om-setK : Keys n m → Vec Bool n → Vec Bool m
om-setK kss x = map (λ k → prot 0 k x) kss

--  At an index i where tuples differ, querying the secret's i-th key makes
--  the corresponding point output cancel.
om-setK-distinguishing : (ksecs : Keys n m) → DistinguishingK om-setK ksecs
om-setK-distinguishing ksecs kss kss≢ with Vec-≢→∃ kss≢
... | (i , ki≢) = lookup ksecs i , vneq
  where
    lhs : lookup (om-setK kss (lookup ksecs i)) i ≡ false
    lhs = trans (lookup-map i (λ k → prot 0 k (lookup ksecs i)) kss)
                (prot0-false (lookup ksecs i) (lookup kss i) (λ p → ki≢ (sym p)))
    rhs : lookup (om-setK ksecs (lookup ksecs i)) i ≡ true
    rhs = trans (lookup-map i (λ k → prot 0 k (lookup ksecs i)) ksecs)
                (prot0-self (lookup ksecs i))
    vneq : om-setK kss (lookup ksecs i) ≢ om-setK ksecs (lookup ksecs i)
    vneq eq = false≢true (trans (sym lhs) (trans (cong (λ v → lookup v i) eq) rhs))

--  The distinct-key lock leaves only the secret tuple after 2ⁿ queries,
--  independently of its number m of outputs.
om-setK-recovers : (ksecs kss : Keys n m) →
  (kss ≡ ksecs → survivesVK om-setK ksecs (allVecs n) kss ≡ true)
  × (kss ≢ ksecs → survivesVK om-setK ksecs (allVecs n) kss ≡ false)
om-setK-recovers ksecs = multiDIPK-recovers om-setK ksecs (om-setK-distinguishing ksecs)
