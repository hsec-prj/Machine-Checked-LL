------------------------------------------------------------------------
--  Connect generic certified locking to SAT/query resistance. Existing
--  off-diagonal bounds in SATComplexity and Tradeoff had not been joined
--  to GenericLock's arbitrary ProtGadget-based locked-fun-gen construction.
--  Define actGen f gS G k x = locked-fun-gen f gS (G k) x
--  = (f x xor pred gS x) xor pred (G k) x. Only the applied-key
--  predicate depends on k. PointConc requires it false off k, giving
--  off-diagonal oracle agreement and allowing the existing pigeonhole
--  bounds to apply. gen-SAT-lb leaves at least two consistent keys after
--  q<2ⁿ−1 secret-avoiding DIPs; gen-ExactResist excludes total recovery
--  with 2+q ≤ 2ⁿ. Both the point gadget, covering SARLock/Anti-SAT, and
--  a genuine flex singleton instantiate the bridge. point-ocr-≤2
--  places low corruption and exponential resistance on the same verified
--  locked object. Retain the one-direction scope of Tradeoff: point
--  corruption implies exponential exact recovery cost; no converse is
--  claimed, with FALL-broken high-corruption SFLL-HD as the contrasting
--  endpoint. No primitives or postulates are added.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.GenericSAT where

open import Data.Nat using (ℕ; suc; _+_; _^_; _≤_; _<_)
open import Data.Bool using (Bool; true; false; _xor_; _∨_)
open import Data.Bool.Properties using (xor-identityʳ; ∨-identityʳ)
open import Data.Fin using (Fin; toℕ)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.List using (_∷_; [])
open import Data.Product using (_×_; _,_; ∃)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HD using (prot)
open import SFLL.HammingDistance using (HD; parity)
open import Security.AntiSat using (prot0-false)
open import Security.ModelCount using (modelCount; modelCount-corrupt-odd; modelCount-corrupt-far)
open import Util.Counting using (countT; allVecs; countT-cong; binom)
open import Attack.Oracle using (QAdversary)
open import Attack.SATAttack using (consistentOn)
open import Attack.SATComplexity using (offdiag-SAT-lb)
open import Attack.AppSAT using (xor-mix)
open import Attack.Adaptive using (Adaptive; RecoversA; adaptive-query-lb-off-diag)
open import Attack.Tradeoff using (ExactResist; offdiag→ExactResist; guess0)
open import Locking.GenericLock
  using (ProtGadget; locked-fun-gen; pointGadget; flexGadget; sfllGadget; ocrGen-of; point-ocr-≤2)
open ProtGadget

private
  variable
    n q : ℕ

------------------------------------------------------------------------
--  Define the generic activated family and its key-independent reference.

--  Form the base by disabling the applied-key predicate.
baseGen : (f : Vec Bool n → Bool) (gS : ProtGadget n) → Vec Bool n → Bool
baseGen f gS x = f x xor pred gS x

--  Index the generic locked oracle by applied keys through gadget family G.
actGen : (f : Vec Bool n → Bool) (gS : ProtGadget n)
         (G : Vec Bool n → ProtGadget n) →
         Vec Bool n → Vec Bool n → Bool
actGen f gS G k x = locked-fun-gen f gS (G k) x

------------------------------------------------------------------------
--  Express point concentration as vanishing of the applied predicate
--  away from its key, the gadget-level minimal-corruption structure.

PointConc : (Vec Bool n → ProtGadget n) → Set
PointConc {n} G = (k x : Vec Bool n) → x ≢ k → pred (G k) x ≡ false

------------------------------------------------------------------------
--  Use concentration to reduce the oracle to its key-free base off x=k.

gen-offdiag :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (k x : Vec Bool n) → x ≢ k →
  baseGen f gS x ≡ actGen f gS G k x
gen-offdiag f gS G pc k x x≢k =
  sym (trans (cong (λ b → baseGen f gS x xor b) (pc k x x≢k))
             (xor-identityʳ (baseGen f gS x)))

--  Conclude that distinct applied keys agree outside their two key inputs.
gen-agree :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (k₁ k₂ x : Vec Bool n) → x ≢ k₁ → x ≢ k₂ →
  actGen f gS G k₁ x ≡ actGen f gS G k₂ x
gen-agree f gS G pc k₁ k₂ x x≢k₁ x≢k₂ =
  trans (sym (gen-offdiag f gS G pc k₁ x x≢k₁))
        (gen-offdiag f gS G pc k₂ x x≢k₂)

------------------------------------------------------------------------
--  After q secret-avoiding DIPs with 2+q ≤ 2ⁿ, retain two distinct
--  consistent keys and leave the generic key undetermined.

gen-SAT-lb :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (ksec : Vec Bool n) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOn (actGen f gS G) ksec xs k₁
    × consistentOn (actGen f gS G) ksec xs k₂
gen-SAT-lb f gS G pc ksec xs avoid bound =
  offdiag-SAT-lb (actGen f gS G) (baseGen f gS)
    (λ k x x≢k → gen-offdiag f gS G pc k x x≢k)
    ksec xs avoid bound

--  Exclude total exact recovery when the budget leaves an unprobed key pair
--  for the generic locked oracle.

gen-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → ExactResist (actGen f gS G)
gen-ExactResist f gS G pc =
  offdiag→ExactResist (actGen f gS G) (gen-agree f gS G pc)

--  Extend resistance to adaptive probes chosen from earlier answers.
--  gen-offdiag feeds adaptive-query-lb-off-diag directly, excluding budgets
--  below 2ⁿ−1 for actGen as the SARLock-specific lift did for actSAR.
gen-adaptive-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) →
  2 + q ≤ 2 ^ n → ¬ RecoversA A (actGen f gS G)
gen-adaptive-ExactResist f gS G pc A bound =
  adaptive-query-lb-off-diag A (actGen f gS G) (baseGen f gS)
    (λ k x x≢k → gen-offdiag f gS G pc k x x≢k) bound

------------------------------------------------------------------------
--  Instantiate the point gadget with prot0-false for concentration and
--  point-ocr-≤2 for corruption, combining low OCR and SAT resistance
--  on one verified construction.

point-PointConc : PointConc {n} pointGadget
point-PointConc k x x≢k = prot0-false x k x≢k

point-SAT-lb :
  (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (ksec : Vec Bool n) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOn (actGen f gS pointGadget) ksec xs k₁
    × consistentOn (actGen f gS pointGadget) ksec xs k₂
point-SAT-lb f gS ksec xs avoid bound =
  gen-SAT-lb f gS pointGadget point-PointConc ksec xs avoid bound

point-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  ExactResist (actGen f gS pointGadget)
point-ExactResist f gS = gen-ExactResist f gS pointGadget point-PointConc

--  Record both trade-off aspects for the point lock: corruption ≤2 and
--  the resistance result above.
point-corruption-≤2 : (k k' : Vec Bool n) →
                      ocrGen-of (pointGadget k) (pointGadget k') ≤ 2
point-corruption-≤2 = point-ocr-≤2

------------------------------------------------------------------------
--  Instantiate flex at singleton {k}, whose membership is prot 0 k x OR
--  false and remains point-concentrated, demonstrating scheme generality.

flexSingleton : Vec Bool n → ProtGadget n
flexSingleton k = flexGadget (k ∷ [])

flex-PointConc : PointConc {n} flexSingleton
flex-PointConc k x x≢k = cong (λ b → b ∨ false) (prot0-false x k x≢k)

flex-SAT-lb :
  (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (ksec : Vec Bool n) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOn (actGen f gS flexSingleton) ksec xs k₁
    × consistentOn (actGen f gS flexSingleton) ksec xs k₂
flex-SAT-lb f gS ksec xs avoid bound =
  gen-SAT-lb f gS flexSingleton flex-PointConc ksec xs avoid bound

flex-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  ExactResist (actGen f gS flexSingleton)
flex-ExactResist f gS = gen-ExactResist f gS flexSingleton flex-PointConc

------------------------------------------------------------------------
--  Lift AppSAT's approximate-recovery interpretation to locked-fun-gen.
--  xor-mix cancels f, equating disagreement with ocrGen-of, the symmetric
--  difference of its two predicates. A low uniform corruption bound thus
--  makes all guesses cheap approximate keys despite exact resistance.

--  Count generic locked-function disagreements with its host f, which is
--  restored by the secret-key circuit.
disagreeCountGen : (f : Vec Bool n → Bool) (gS gA : ProtGadget n) → ℕ
disagreeCountGen {n} f gS gA =
  countT (λ x → locked-fun-gen f gS gA x xor f x) (allVecs n)

--  Identify disagreement with host-independent ocrGen-of by cancelling f.
disagreeCountGen≡ocrGen :
  (f : Vec Bool n → Bool) (gS gA : ProtGadget n) →
  disagreeCountGen f gS gA ≡ ocrGen-of gS gA
disagreeCountGen≡ocrGen {n} f gS gA =
  countT-cong (λ x → xor-mix (f x) (pred gS x) (pred gA x)) (allVecs n)

--  Define gA as ε-approximate for the generic lock with secret gadget gS.
ApproxKeyGen : (f : Vec Bool n → Bool) (gS gA : ProtGadget n) (ε : ℕ) → Set
ApproxKeyGen f gS gA ε = disagreeCountGen f gS gA ≤ ε

--  Transfer any gadget-pair corruption bound to approximate-key tolerance.
approxGen-of-bound :
  (f : Vec Bool n → Bool) (gS gA : ProtGadget n) {c : ℕ} →
  ocrGen-of gS gA ≤ c → ApproxKeyGen f gS gA c
approxGen-of-bound f gS gA bound =
  subst (_≤ _) (sym (disagreeCountGen≡ocrGen f gS gA)) bound

------------------------------------------------------------------------
--  Bundle generic exact resistance with free approximate recovery at
--  corruption bound c on the verified locked-fun-gen construction.

record GenNoFreeLunch (f : Vec Bool n → Bool) (gS : ProtGadget n)
                      (G : Vec Bool n → ProtGadget n) (c : ℕ) : Set where
  field
    --  Require exponential query scale for exact applied-key recovery.
    exact  : ExactResist (actGen f gS G)
    --  Make every applied-key guess g a c-approximate key.
    approx : (g : Vec Bool n) → ApproxKeyGen f gS (G g) c
open GenNoFreeLunch

--  Build the bundle from concentration for exact resistance and a uniform
--  corruption bound for free approximation, without claiming a biconditional.
mkGenNoFreeLunch :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G →
  {c : ℕ} (cb : (g : Vec Bool n) → ocrGen-of gS (G g) ≤ c) →
  GenNoFreeLunch f gS G c
mkGenNoFreeLunch f gS G pc cb = record
  { exact  = gen-ExactResist f gS G pc
  ; approx = λ g → approxGen-of-bound f gS (G g) (cb g)
  }

------------------------------------------------------------------------
--  Instantiate the generic no-free-lunch result at bound c=2.

--  Give the point/SARLock/Anti-SAT instance exact resistance and free approximation.
point-GenNoFreeLunch :
  (f : Vec Bool n → Bool) (s : Vec Bool n) →
  GenNoFreeLunch f (pointGadget s) pointGadget 2
point-GenNoFreeLunch f s =
  mkGenNoFreeLunch f (pointGadget s) pointGadget point-PointConc (point-ocr-≤2 s)

--  Any zero-query guess is 2-approximate for each secret, contrasting
--  with exponential exact recovery.
point-appsat-free :
  (f : Vec Bool n → Bool) (s : Vec Bool n)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) 0) →
  ApproxKeyGen f (pointGadget s) (pointGadget (guess0 A)) 2
point-appsat-free f s A = approx (point-GenNoFreeLunch f s) (guess0 A)

--  Transfer both properties to flex singletons: their membership predicate
--  prot 0 k x OR false agrees pointwise with the point predicate.
flex-ocr-≤2 : (s g : Vec Bool n) →
              ocrGen-of (flexSingleton s) (flexSingleton g) ≤ 2
flex-ocr-≤2 {n} s g =
  subst (_≤ 2)
        (sym (countT-cong
               (λ x → cong₂ _xor_ (∨-identityʳ (prot 0 s x)) (∨-identityʳ (prot 0 g x)))
               (allVecs n)))
        (point-ocr-≤2 s g)

flex-GenNoFreeLunch :
  (f : Vec Bool n → Bool) (s : Vec Bool n) →
  GenNoFreeLunch f (flexSingleton s) flexSingleton 2
flex-GenNoFreeLunch f s =
  mkGenNoFreeLunch f (flexSingleton s) flexSingleton flex-PointConc (flex-ocr-≤2 s)

------------------------------------------------------------------------
--  Express generic corruption as #SAT. As ModelCount does for SFLL,
--  corruptGen is the Boolean symmetric-difference instance and ocrGen-of
--  its model count, available in closed form where counting can time out.
--  This same count underlies exact-search resistance and approximate
--  disagreement through disagreeCountGen.

--  Define corruptGen as the generic corruption SAT predicate.
corruptGen : (gS gA : ProtGadget n) → Vec Bool n → Bool
corruptGen gS gA x = pred gS x xor pred gA x

--  Identify ocrGen-of definitionally with corruptGen's #SAT model count.
ocrGen-is-modelCount : (gS gA : ProtGadget n) →
                       ocrGen-of gS gA ≡ modelCount (corruptGen gS gA)
ocrGen-is-modelCount gS gA = refl

--  Use host cancellation to identify approximate disagreement with that
--  same model count.
disagreeGen-is-modelCount :
  (f : Vec Bool n → Bool) (gS gA : ProtGadget n) →
  disagreeCountGen f gS gA ≡ modelCount (corruptGen gS gA)
disagreeGen-is-modelCount f gS gA = disagreeCountGen≡ocrGen f gS gA

--  For SFLL at odd or far key distance, recover exact generic #SAT value
--  2·C(n,h) without a solver, since its corruptGen reduces to corrupt.
gen-modelCount-sfll-odd :
  (hF : Fin (suc n)) (ksec kapp : Vec Bool n) → parity (HD ksec kapp) ≡ true →
  modelCount (corruptGen (sfllGadget hF ksec) (sfllGadget hF kapp))
    ≡ binom n (toℕ hF) + binom n (toℕ hF)
gen-modelCount-sfll-odd hF ksec kapp odd =
  modelCount-corrupt-odd (toℕ hF) ksec kapp odd

gen-modelCount-sfll-far :
  (hF : Fin (suc n)) (ksec kapp : Vec Bool n) → toℕ hF + toℕ hF < HD ksec kapp →
  modelCount (corruptGen (sfllGadget hF ksec) (sfllGadget hF kapp))
    ≡ binom n (toℕ hF) + binom n (toℕ hF)
gen-modelCount-sfll-far hF ksec kapp far =
  modelCount-corrupt-far (toℕ hF) ksec kapp far
