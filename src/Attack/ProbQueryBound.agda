------------------------------------------------------------------------
--  Count exact recovery under a uniform distribution on keys.
--  SARLockQueryBound.SARLock-query-lb and Adaptive.SARLock-adaptive-query-lb
--  exclude exact recovery when 2+q ≤ 2ⁿ because distinct keys remain
--  indistinguishable. Strengthen this to a count and uniform-key probability:
--  Pr[k ← uniform: adversary outputs k] ≤ (q+1)/2ⁿ, with favourable
--  weight ≤ q+1 and total 2ⁿ. This result uses deterministic adversaries;
--  randomness is only in the uniform choice of key. It supplies no theorem
--  for arbitrary key distributions or adversary coins. recovered-count-≤
--  uses the following observation: for an
--  off-diagonal family, reference base omits the applied-key flip and agrees
--  with act k away from k. Every unprobed key thus receives base answers
--  and yields the same guess g. Recovery can cover at most q probed keys
--  plus g. This count uses count-eq and probedV-count-≤ from SARLockQueryBound
--  without pigeonhole reasoning. Fixed-probe ask and adaptive run against
--  base reduce to that same core. SARLock-prob-query-lb and
--  SARLock-adaptive-prob-query-lb each instantiate a generic lemma, without
--  new primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.ProbQueryBound where

open import Data.Nat using (ℕ; zero; suc; _+_; _^_; _≤_; _<_; s≤s; z≤n)
open import Data.Nat.Properties using (≤-trans; ≤-<-trans; ≤-reflexive; +-mono-≤; +-comm)
open import Data.Bool using (Bool; true; false; not; _∧_; if_then_else_)
import Data.Fin as Fin
open Fin using (Fin)
open import Data.Vec using (Vec; []; _∷_; lookup; map)
open import Data.List using (List; []; _∷_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst; _≢_)

open import Util.BoolVec using (eqVec; eqVec-false→≢)
open import Util.Counting using (countT; countT-mono; allVecs; length-allVecs)
open import Attack.QueryLowerBound using (map-lookup-cong)
open import Security.Dist
  using (Dist; total; prob; uniform; total-uniform; prob-uniform)
open import Attack.Oracle using (QAdversary; ask)
open import Attack.Adaptive
  using (Adaptive; run; runProbes; Avoids; avoids→agree; avoids-lookup;
         run-agree; baseSAR; baseSAR-off)
open import Attack.SARLockResist using (actSAR)
open import Attack.SARLockQueryBound using (count-eq; probedV; probedV-count-≤; probedV-false-lookup; count-split-eq; countT-∧-≤ʳ; ∧-true; not-true→false)

private
  variable
    n q : ℕ
    Y : Set

------------------------------------------------------------------------
--  Given q probes ps and a guess function constant at g on unprobed keys,
--  count at most q+1 correct guesses eqVec (guess k) k: at most q queried
--  keys plus the single key g.

recovered-count-≤ :
  (ps : Vec (Vec Bool n) q) (guess : Vec Bool n → Vec Bool n) (g : Vec Bool n) →
  ((k : Vec Bool n) → probedV ps k ≡ false → guess k ≡ g) →
  countT (λ k → eqVec (guess k) k) (allVecs n) ≤ suc q
recovered-count-≤ {n = n} {q = q} ps guess g hyp =
  ≤-trans (≤-reflexive (count-split-eq R P (allVecs n)))
          (≤-trans (+-mono-≤ A≤q B≤1) (≤-reflexive (+-comm q 1)))
  where
    R = λ k → eqVec (guess k) k
    P = λ k → probedV ps k

    --  Recovered probed keys are bounded by the probe count, hence by q.
    A≤q : countT (λ k → R k ∧ P k) (allVecs n) ≤ q
    A≤q = ≤-trans (countT-∧-≤ʳ R P (allVecs n)) (probedV-count-≤ ps)

    --  A recovered unprobed key satisfies eqVec g k ≡ true, so at most the
    --  single key g contributes.
    imp : (k : Vec Bool n) → (R k ∧ not (P k)) ≡ true → eqVec g k ≡ true
    imp k eq =
      trans (cong (λ z → eqVec z k)
                  (sym (hyp k (not-true→false (P k)
                                (proj₂ (∧-true (R k) (not (P k)) eq))))))
            (proj₁ (∧-true (R k) (not (P k)) eq))

    B≤1 : countT (λ k → R k ∧ not (P k)) (allVecs n) ≤ 1
    B≤1 = ≤-trans (countT-mono (λ k → R k ∧ not (P k)) (λ k → eqVec g k)
                               (allVecs n) imp)
                  (≤-reflexive (count-eq g))

------------------------------------------------------------------------
--  Give the uniform-key distribution total weight 2ⁿ.

unifKeys : (n : ℕ) → Dist (Vec Bool n)
unifKeys n = uniform (allVecs n)

total-unifKeys : (n : ℕ) → total (unifKeys n) ≡ 2 ^ n
total-unifKeys n = trans (total-uniform (allVecs n)) (length-allVecs n)

------------------------------------------------------------------------
--  For fixed probes, establish constancy of the guess off the probe set.

--  An unqueried key produces base answers on all probes, so its decoder
--  result is the same as the result against base.
ask-const-off :
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (A : QAdversary (Vec Bool n) Y (Vec Bool n) q) (k : Vec Bool n) →
  probedV (QAdversary.probes A) k ≡ false →
  ask A (act k) ≡ ask A base
ask-const-off act base off A k h =
  cong (QAdversary.decode A)
    (map-lookup-cong (act k) base (QAdversary.probes A)
      (λ i → sym (off k (lookup (QAdversary.probes A) i)
                    (eqVec-false→≢ (lookup (QAdversary.probes A) i) k
                       (probedV-false-lookup (QAdversary.probes A) k h i)))))

------------------------------------------------------------------------
--  Derive the non-adaptive probabilistic bound generically, then for SARLock.

prob-query-lb-off-diag :
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (A : QAdversary (Vec Bool n) Y (Vec Bool n) q) →
  (prob (λ k → eqVec (ask A (act k)) k) (unifKeys n) ≤ suc q)
  × (total (unifKeys n) ≡ 2 ^ n)
prob-query-lb-off-diag {n = n} act base off A =
  ≤-trans (≤-reflexive (prob-uniform R (allVecs n)))
          (recovered-count-≤ (QAdversary.probes A)
                             (λ k → ask A (act k)) (ask A base)
                             (ask-const-off act base off A))
  , total-unifKeys n
  where R = λ k → eqVec (ask A (act k)) k

--  For a uniform SARLock key, a non-adaptive q-query adversary has favourable
--  recovery weight at most q+1 out of total 2ⁿ.
SARLock-prob-query-lb :
  (s : Vec Bool n) (f : Vec Bool n → Bool)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  (prob (λ k → eqVec (ask A (actSAR s f k)) k) (unifKeys n) ≤ suc q)
  × (total (unifKeys n) ≡ 2 ^ n)
SARLock-prob-query-lb s f A =
  prob-query-lb-off-diag (actSAR s f) (baseSAR s f) (baseSAR-off s f) A

------------------------------------------------------------------------
--  In the adaptive case, runProbes A base selects a determined q-probe path.
--  For a key outside that path, run-agree equates its activated execution
--  with the base execution, again fixing the off-probe guess.

run-const-off :
  (A : Adaptive (Vec Bool n) Y (Vec Bool n) q)
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (k : Vec Bool n) →
  probedV (runProbes A base) k ≡ false →
  run A (act k) ≡ run A base
run-const-off A act base off k h =
  sym (run-agree A (avoids→agree A base (act k) k (off k) av))
  where
    av : Avoids A base k
    av = avoids-lookup A base k
           (λ i → eqVec-false→≢ (lookup (runProbes A base) i) k
                    (probedV-false-lookup (runProbes A base) k h i))

adaptive-prob-query-lb-off-diag :
  (A : Adaptive (Vec Bool n) Y (Vec Bool n) q)
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (prob (λ k → eqVec (run A (act k)) k) (unifKeys n) ≤ suc q)
  × (total (unifKeys n) ≡ 2 ^ n)
adaptive-prob-query-lb-off-diag {n = n} A act base off =
  ≤-trans (≤-reflexive (prob-uniform R (allVecs n)))
          (recovered-count-≤ (runProbes A base)
                             (λ k → run A (act k)) (run A base)
                             (run-const-off A act base off))
  , total-unifKeys n
  where R = λ k → eqVec (run A (act k)) k

--  Instantiate the same (q+1)/2ⁿ bound for adaptive SARLock adversaries,
--  complementing SARLock-adaptive-query-lb probabilistically.
SARLock-adaptive-prob-query-lb :
  (s : Vec Bool n) (f : Vec Bool n → Bool)
  (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) →
  (prob (λ k → eqVec (run A (actSAR s f k)) k) (unifKeys n) ≤ suc q)
  × (total (unifKeys n) ≡ 2 ^ n)
SARLock-adaptive-prob-query-lb s f A =
  adaptive-prob-query-lb-off-diag A (actSAR s f) (baseSAR s f) (baseSAR-off s f)

------------------------------------------------------------------------
--  Under 2+q ≤ 2ⁿ, the recovery weight bound q+1 is strictly below
--  the total 2ⁿ, so exact recovery under a uniform key is not certain.
--  This probability statement remains within the Boolean-oracle model.

--  Transport 2+q ≤ 2ⁿ, definitionally suc q < 2ⁿ, to the total-weight bound.
suc-q-<-total : (n q : ℕ) → 2 + q ≤ 2 ^ n → suc q < total (unifKeys n)
suc-q-<-total n q 2+q≤2ⁿ = subst (suc q <_) (sym (total-unifKeys n)) 2+q≤2ⁿ

--  Prove the generic non-adaptive recovery weight is strictly below total weight.
prob-recovery-<-total-off-diag :
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (A : QAdversary (Vec Bool n) Y (Vec Bool n) q) → 2 + q ≤ 2 ^ n →
  prob (λ k → eqVec (ask A (act k)) k) (unifKeys n) < total (unifKeys n)
prob-recovery-<-total-off-diag {n = n} {q = q} act base off A 2+q≤2ⁿ =
  ≤-<-trans (proj₁ (prob-query-lb-off-diag act base off A))
            (suc-q-<-total n q 2+q≤2ⁿ)

--  Obtain a non-vacuous bound for non-adaptive SARLock recovery.
SARLock-recovery-<-total :
  (s : Vec Bool n) (f : Vec Bool n → Bool)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) → 2 + q ≤ 2 ^ n →
  prob (λ k → eqVec (ask A (actSAR s f k)) k) (unifKeys n) < total (unifKeys n)
SARLock-recovery-<-total {n = n} {q = q} s f A 2+q≤2ⁿ =
  ≤-<-trans (proj₁ (SARLock-prob-query-lb s f A)) (suc-q-<-total n q 2+q≤2ⁿ)

--  Retain the strict bound for adaptive key-oblivious Boolean adversaries.
--  It does not cover SAT probes selected from a secret-bearing netlist.
SARLock-adaptive-recovery-<-total :
  (s : Vec Bool n) (f : Vec Bool n → Bool)
  (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) → 2 + q ≤ 2 ^ n →
  prob (λ k → eqVec (run A (actSAR s f k)) k) (unifKeys n) < total (unifKeys n)
SARLock-adaptive-recovery-<-total {n = n} {q = q} s f A 2+q≤2ⁿ =
  ≤-<-trans (proj₁ (SARLock-adaptive-prob-query-lb s f A)) (suc-q-<-total n q 2+q≤2ⁿ)
