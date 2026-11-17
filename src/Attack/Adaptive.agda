------------------------------------------------------------------------
--  Extend SARLock's exponential bound to adaptive queries. SARLockQueryBound
--  uses fixed-probe QAdversary values, whereas SAT may choose each next
--  input from previous answers. Model Adaptive as a q-query decision tree
--  and retain the bound 2+q ≤ 2ⁿ. Since probe paths vary with the oracle,
--  use a fixed reference base agreeing with act k away from k. For SARLock
--  it is f ⊕ prot 0 s, omitting the applied-key flip. runProbes against
--  base selects one determined q-point path. Two distinct keys outside
--  that path give the same answers as base wherever inspected, so run-agree
--  makes both activated runs and the reference run return the same guess.
--  --
--  That guess cannot recover both keys, as base-ref-resist proves. The
--  unprobed-pair pigeonhole argument over 2ⁿ inputs supplies them whenever
--  2+q ≤ 2ⁿ. The bound therefore survives adaptivity and expresses SARLock
--  resistance against the stronger model. The proof is scheme-independent
--  under the reference premise, with SARLock as its instance. No primitives
--  or postulates are added and main-track invariants remain intact.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.Adaptive where

open import Data.Nat using (ℕ; zero; suc; _+_; _^_; _≤_)
open import Data.Bool using (Bool; true; false; _xor_)
open import Data.Fin using (Fin; zero; suc)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.Unit using (⊤; tt)
open import Data.Product using (_×_; _,_; ∃; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; sym; trans; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HD using (prot)
open import Security.AntiSat using (prot0-false)
open import Attack.SARLockResist using (actSAR)
open import Attack.SARLockQueryBound using (unprobed-pair)

------------------------------------------------------------------------
--  Define a q-deep query tree: stop returns a guess; query x f asks x
--  and continues with f applied to its answer. As with QAdversary the
--  budget is typed, but continuations may now depend on previous answers.

data Adaptive (X Y K : Set) : ℕ → Set where
  stop  : K → Adaptive X Y K 0
  query : ∀ {q} → X → (Y → Adaptive X Y K q) → Adaptive X Y K (suc q)

--  Execute the adaptive tree against oracle O : X → Y.
run : ∀ {X Y K q} → Adaptive X Y K q → (X → Y) → K
run (stop k)    O = k
run (query x f) O = run (f (O x)) O

--  Define recovery for oracle family act : K → (X → Y).
RecoversA : ∀ {X Y K q} → Adaptive X Y K q → (K → X → Y) → Set
RecoversA A act = ∀ k → run A (act k) ≡ k

------------------------------------------------------------------------
--  Prove equal results when two oracles agree at each point visited
--  against the first. Define agreement recursively along O₁'s run,
--  providing the adaptive analogue of ask-cong.

Agree : ∀ {X Y K q} → Adaptive X Y K q → (X → Y) → (X → Y) → Set
Agree (stop _)    O₁ O₂ = ⊤
Agree (query x f) O₁ O₂ = (O₁ x ≡ O₂ x) × Agree (f (O₁ x)) O₁ O₂

run-agree : ∀ {X Y K q} (A : Adaptive X Y K q) {O₁ O₂ : X → Y} →
            Agree A O₁ O₂ → run A O₁ ≡ run A O₂
run-agree (stop k)    _                = refl
run-agree (query x f) {O₁} {O₂} (ax , rest) =
  trans (run-agree (f (O₁ x)) rest) (cong (λ y → run (f y) O₂) ax)

------------------------------------------------------------------------
--  A run Avoids z when each probe differs from z. Combining avoidance
--  with off-diagonal agreement of base and O₂ yields Agree.

Avoids : ∀ {X Y K q} → Adaptive X Y K q → (X → Y) → X → Set
Avoids (stop _)    O z = ⊤
Avoids (query x f) O z = (x ≢ z) × Avoids (f (O x)) O z

avoids→agree : ∀ {X Y K q} (A : Adaptive X Y K q) (base O₂ : X → Y) (z : X) →
               (∀ x → x ≢ z → base x ≡ O₂ x) →
               Avoids A base z → Agree A base O₂
avoids→agree (stop _)    base O₂ z off av           = tt
avoids→agree (query x f) base O₂ z off (x≢z , rest) =
  off x x≢z , avoids→agree (f (base x)) base O₂ z off rest

------------------------------------------------------------------------
--  Derive structural resistance: two keys avoided by the base run both
--  produce that same run result under their activated oracles, so one
--  guess cannot recover both distinct keys.

base-ref-resist :
  ∀ {Y K q} (A : Adaptive K Y K q) (act : K → K → Y) (base : K → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  {k₁ k₂ : K} → k₁ ≢ k₂ →
  Avoids A base k₁ → Avoids A base k₂ →
  ¬ RecoversA A act
base-ref-resist A act base off {k₁} {k₂} ne av₁ av₂ rec =
  ne (trans (sym e₁) e₂)
  where
    e₁ : run A base ≡ k₁
    e₁ = trans (run-agree A (avoids→agree A base (act k₁) k₁ (off k₁) av₁))
               (rec k₁)
    e₂ : run A base ≡ k₂
    e₂ = trans (run-agree A (avoids→agree A base (act k₂) k₂ (off k₂) av₂))
               (rec k₂)

------------------------------------------------------------------------
--  Extract the fixed-oracle probe sequence and connect pointwise probe
--  inequality with Avoids.

runProbes : ∀ {X Y K q} → Adaptive X Y K q → (X → Y) → Vec X q
runProbes (stop _)    O = []
runProbes (query x f) O = x ∷ runProbes (f (O x)) O

avoids-lookup : ∀ {X Y K q} (A : Adaptive X Y K q) (O : X → Y) (z : X) →
                ((i : Fin q) → lookup (runProbes A O) i ≢ z) → Avoids A O z
avoids-lookup (stop _)    O z h = tt
avoids-lookup (query x f) O z h =
  h zero , avoids-lookup (f (O x)) O z (λ i → h (suc i))

------------------------------------------------------------------------
--  For any diagonal-distinguishing family with a reference oracle,
--  unprobed-pair finds two keys outside the q-probe base path under
--  2+q ≤ 2ⁿ. Apply base-ref-resist for the adaptive lower bound.

adaptive-query-lb-off-diag :
  ∀ {Y : Set} {n q}
    (A : Adaptive (Vec Bool n) Y (Vec Bool n) q)
    (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
    (∀ k x → x ≢ k → base x ≡ act k x) →
    2 + q ≤ 2 ^ n →
    ¬ RecoversA A act
adaptive-query-lb-off-diag A act base off bound =
  base-ref-resist A act base off {k₁} {k₂} ne
    (avoids-lookup A base k₁ p₁)
    (avoids-lookup A base k₂ p₂)
  where
    up = unprobed-pair (runProbes A base) bound
    k₁ = proj₁ up
    k₂ = proj₁ (proj₂ up)
    ne = proj₁ (proj₂ (proj₂ up))
    p₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    p₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))

------------------------------------------------------------------------
--  Instantiate SARLock with the reference omitting its applied-key flip,
--  differing from actSAR s f k only at k.

private
  variable
    n q : ℕ

--  Simplify b xor false to b.
xor-false : (b : Bool) → b xor false ≡ b
xor-false true  = refl
xor-false false = refl

baseSAR : (s : Vec Bool n) (f : Vec Bool n → Bool) → Vec Bool n → Bool
baseSAR s f x = f x xor prot 0 s x

--  Away from k, prot 0 k x=false and XOR with false is identity, making
--  the activated and reference oracles equal.
baseSAR-off : (s : Vec Bool n) (f : Vec Bool n → Bool) (k x : Vec Bool n) →
              x ≢ k → baseSAR s f x ≡ actSAR s f k x
baseSAR-off s f k x x≢k =
  sym (trans (cong (λ b → (f x xor prot 0 s x) xor b) (prot0-false x k x≢k))
             (xor-false (f x xor prot 0 s x)))

--  For SARLock, two distinct keys avoided along the reference path prevent
--  q-query adaptive recovery.
SARLock-adaptive-resist :
  (s : Vec Bool n) (f : Vec Bool n → Bool)
  (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) {k₁ k₂ : Vec Bool n} →
  k₁ ≢ k₂ →
  Avoids A (baseSAR s f) k₁ → Avoids A (baseSAR s f) k₂ →
  ¬ RecoversA A (actSAR s f)
SARLock-adaptive-resist s f A ne av₁ av₂ =
  base-ref-resist A (actSAR s f) (baseSAR s f) (baseSAR-off s f) ne av₁ av₂

--  Quantitatively extend SARLock-query-lb: even adaptive recovery fails
--  at budgets below 2ⁿ−1.
SARLock-adaptive-query-lb :
  (s : Vec Bool n) (f : Vec Bool n → Bool)
  (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) →
  2 + q ≤ 2 ^ n →
  ¬ RecoversA A (actSAR s f)
SARLock-adaptive-query-lb s f A bound =
  adaptive-query-lb-off-diag A (actSAR s f) (baseSAR s f) (baseSAR-off s f) bound
