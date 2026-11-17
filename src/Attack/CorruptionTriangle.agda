------------------------------------------------------------------------
--  Join corruption, resistance, and recovery in a checked triangle
--  (D8 frontier 2). GenericSAT's gen-ExactResist/gen-SAT-lb provide
--  exponential resistance for point corruption, and PointDIPAttack's
--  recovery/count results give a 2ⁿ-query attack. Tight formalises their
--  previous prose Θ relationship; CorruptionTriangle combines it with
--  ocrGen-of ≤2. bridge-consist identifies consistency over actGen in
--  the lower-bound model with consist over prot 0 in the upper-bound
--  attack. Scope is one direction from low point corruption to these
--  bounds, with FALL-broken high-corruption spheres as the contrasting
--  endpoint rather than a converse. Tight is the bracket
--  2ⁿ−1 ≤ cost ≤ 2ⁿ, retaining one-query slack: the lower bound excludes
--  q≤2ⁿ−2 and the upper asks every input. Its secret-avoiding Vec probes
--  and exhaustive List queries remain different data structures; the
--  bridge equates their consistency notions only. Reuse gen-ExactResist,
--  gen-SAT-lb, point-PointConc, point-ocr-≤2, dipAttack-recovers,
--  dipAttack-queries, and survives-ksec. Only XOR cancellation in the
--  bridge is new. The module sits above unchanged GenNoFreeLunch,
--  GenericSAT, and PointDIPAttack, without reversing dependencies or
--  adding postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CorruptionTriangle where

open import Data.Nat using (ℕ; suc; zero; _+_; _≤_; _<_; _^_; s≤s; z≤n)
open import Data.Nat.Properties
  using (+-comm; ≤-refl; ≤-trans; +-mono-≤; m≤n+m; m≤m+n; +-identityʳ)
open import Data.Bool using (Bool; true; false; not; _xor_)
open import Data.Vec using (Vec; lookup)
open import Data.List using (List; length)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.Fin using (Fin)
open import Data.Product using (_×_; _,_; ∃; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; trans; sym; subst; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HD using (prot)
open import SFLL.HammingDistance using (HD; parity; xor-self)
open import Util.Counting using (allVecs; binom)
open import Security.OCR using (OCR)
open import Security.CorruptionCalculus using (calc-OCR-odd)
open import Locking.GenericLock using (ProtGadget; pointGadget; ocrGen-of; point-ocr-≤2)
open import Attack.GenericSAT
  using (actGen; baseGen; PointConc; gen-SAT-lb; gen-ExactResist; point-PointConc)
open import Attack.Tradeoff using (ExactResist)
open import Attack.SATAttack using (consistentOn)
open import Attack.PointDIPAttack
  using (consist; survives; survives-ksec; dipAttack-recovers; dipAttack-queries;
         andMap-true→∈; andMap-∈→true)
open import Attack.Oracle using (Recovers; QAdversary)
open import Attack.FunctionalAnalysis using (distNode)
open import Attack.VerifiedFALL using (fallPolyQA; fallPolyQA-recovers)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Supply XOR cancellation helpers, the only new reasoning.

not-true→false : (b : Bool) → not b ≡ true → b ≡ false
not-true→false false _ = refl
not-true→false true  ()

xor-false→≡ : (a b : Bool) → a xor b ≡ false → a ≡ b
xor-false→≡ true  true  _ = refl
xor-false→≡ true  false ()
xor-false→≡ false true  ()
xor-false→≡ false false _ = refl

------------------------------------------------------------------------
--  Bridge point-indicator consist to agreement of the locked actGen
--  oracles at each x, aligning upper- and lower-bound consistency.

bridge-consist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec x k : Vec Bool n) →
  consist ksec x k ≡ true →
  actGen f gS pointGadget k x ≡ actGen f gS pointGadget ksec x
bridge-consist f gS ksec x k ceq =
  cong (λ b → baseGen f gS x xor b) prot-eq
  where
    prot-eq : prot 0 k x ≡ prot 0 ksec x
    prot-eq = xor-false→≡ (prot 0 k x) (prot 0 ksec x)
                (not-true→false (prot 0 k x xor prot 0 ksec x) ceq)

------------------------------------------------------------------------
--  Prove the converse to establish computability from oracle answers.
--  Although consist mentions ksec, left XOR cancellation shows agreement
--  of candidate and secret oracles forces equality of their point
--  indicators. survives-oracle-iff then identifies the fold with matching
--  the candidate netlist's output against the activated chip at every
--  query. The attacker possesses the former and queries the latter;
--  ksec names the oracle, not additional secret data. This extensional
--  predicate identity leaves survives as a query-list fold and does
--  not convert it into QAdversary.

--  Prove left XOR cancellation by four cases, as for xor-false→≡,
--  avoiding unnecessary group algebra.
xor-cancelˡ : (b p q : Bool) → b xor p ≡ b xor q → p ≡ q
xor-cancelˡ false p     q     eq = eq
xor-cancelˡ true  true  true  _  = refl
xor-cancelˡ true  true  false ()
xor-cancelˡ true  false true  ()
xor-cancelˡ true  false false _  = refl

≡→xor-false : (a b : Bool) → a ≡ b → a xor b ≡ false
≡→xor-false a .a refl = xor-self a

false→not-true : (b : Bool) → b ≡ false → not b ≡ true
false→not-true b eq = cong not eq

bridge-consist-conv :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec x k : Vec Bool n) →
  actGen f gS pointGadget k x ≡ actGen f gS pointGadget ksec x →
  consist ksec x k ≡ true
bridge-consist-conv f gS ksec x k eq =
  false→not-true (prot 0 k x xor prot 0 ksec x)
    (≡→xor-false (prot 0 k x) (prot 0 ksec x)
      (xor-cancelˡ (baseGen f gS x) (prot 0 k x) (prot 0 ksec x) eq))

--  Combine both directions to equate consist with oracle agreement
--  at each input.
bridge-consist-iff :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec x k : Vec Bool n) →
  (consist ksec x k ≡ true →
     actGen f gS pointGadget k x ≡ actGen f gS pointGadget ksec x)
  × (actGen f gS pointGadget k x ≡ actGen f gS pointGadget ksec x →
     consist ksec x k ≡ true)
bridge-consist-iff f gS ksec x k =
  bridge-consist f gS ksec x k , bridge-consist-conv f gS ksec x k

------------------------------------------------------------------------
--  Lift agreement to the queried-input list and its survivor predicate.

--  Express the observable test: candidate netlist and activated chip
--  match on every queried input.
OracleAgreeOn : (f : Vec Bool n → Bool) (gS : ProtGadget n)
                (ksec k : Vec Bool n) (qs : List (Vec Bool n)) → Set
OracleAgreeOn {n} f gS ksec k qs =
  (x : Vec Bool n) → x ∈ qs →
  actGen f gS pointGadget k x ≡ actGen f gS pointGadget ksec x

survives→oracle-agree :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec k : Vec Bool n)
  (qs : List (Vec Bool n)) →
  survives ksec qs k ≡ true → OracleAgreeOn f gS ksec k qs
survives→oracle-agree f gS ksec k qs sv x mem =
  bridge-consist f gS ksec x k
    (andMap-true→∈ (λ y → consist ksec y k) qs sv x mem)

oracle-agree→survives :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec k : Vec Bool n)
  (qs : List (Vec Bool n)) →
  OracleAgreeOn f gS ksec k qs → survives ksec qs k ≡ true
oracle-agree→survives f gS ksec k qs ag =
  andMap-∈→true (λ y → consist ksec y k) qs
    (λ x mem → bridge-consist-conv f gS ksec x k (ag x mem))

--  Conclude that PointDIPAttack's survives pruning is implementable
--  from oracle observations without knowing the secret.
survives-oracle-iff :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec k : Vec Bool n)
  (qs : List (Vec Bool n)) →
  (survives ksec qs k ≡ true → OracleAgreeOn f gS ksec k qs)
  × (OracleAgreeOn f gS ksec k qs → survives ksec qs k ≡ true)
survives-oracle-iff f gS ksec k qs =
  survives→oracle-agree f gS ksec k qs , oracle-agree→survives f gS ksec k qs

------------------------------------------------------------------------
--  Package the point family's checked Θ bracket. lo carries resistance
--  and hi fields the already-proved attack, so this object alone validates
--  the Everything.agda complexity prose without needing the bridge.

record Tight (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec : Vec Bool n) : Set where
  field
    --  Lower bound: exclude q≤2ⁿ−2, leaving an unprobed key pair.
    lo         : ExactResist (actGen f gS pointGadget)
    --  Upper bound: the pruning attack identifies only the secret.
    hi-correct : (k : Vec Bool n) →
                 (k ≡ ksec → survives ksec (allVecs n) k ≡ true)
                 × (k ≢ ksec → survives ksec (allVecs n) k ≡ false)
    --  Count its queries as 2ⁿ.
    hi-cost    : length (allVecs n) ≡ 2 ^ n

point-Tight : (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec : Vec Bool n) →
              Tight f gS ksec
point-Tight {n = n} f gS ksec = record
  { lo         = gen-ExactResist f gS pointGadget point-PointConc
  ; hi-correct = dipAttack-recovers ksec
  ; hi-cost    = dipAttack-queries n
  }

------------------------------------------------------------------------
--  Place corruption bound c, chosen as two for points, above matching
--  resistance and recovery bounds; bridge certifies their common
--  consistency model.

record CorruptionTriangle
    (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec : Vec Bool n) (c : ℕ) : Set where
  field
    --  First aspect: bound secret-versus-candidate corruption by c.
    corruption-≤ : (k : Vec Bool n) → ocrGen-of (pointGadget ksec) (pointGadget k) ≤ c
    --  Second aspect: record exact resistance and its explicit ≥2ⁿ−1 bound.
    resist       : ExactResist (actGen f gS pointGadget)
    resist-sat   : ∀ {q} (xs : Vec (Vec Bool n) q) →
                   ((i : Fin q) → lookup xs i ≢ ksec) → 2 + q ≤ 2 ^ n →
                   ∃ λ k₁ → ∃ λ k₂ →
                     (k₁ ≢ k₂)
                     × consistentOn (actGen f gS pointGadget) ksec xs k₁
                     × consistentOn (actGen f gS pointGadget) ksec xs k₂
    --  Third aspect: exhaustive input pruning leaves exactly the secret.
    recover-only : (k : Vec Bool n) → k ≢ ksec → survives ksec (allVecs n) k ≡ false
    recover-sec  : survives ksec (allVecs n) ksec ≡ true
    recover-cost : length (allVecs n) ≡ 2 ^ n
    --  Connect the resistance and recovery aspects by the same consistency notion.
    bridge       : (x k : Vec Bool n) → consist ksec x k ≡ true →
                   actGen f gS pointGadget k x ≡ actGen f gS pointGadget ksec x

point-Triangle : (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec : Vec Bool n) →
                 CorruptionTriangle f gS ksec 2
point-Triangle {n = n} f gS ksec = record
  { corruption-≤ = point-ocr-≤2 ksec
  ; resist       = gen-ExactResist f gS pointGadget point-PointConc
  ; resist-sat   = λ xs avoid bound →
                     gen-SAT-lb f gS pointGadget point-PointConc ksec xs avoid bound
  ; recover-only = λ k k≢ → proj₂ (dipAttack-recovers ksec k) k≢
  ; recover-sec  = survives-ksec ksec
  ; recover-cost = dipAttack-queries n
  ; bridge       = λ x k → bridge-consist f gS ksec x k
  }

------------------------------------------------------------------------
--  Keep arithmetic/binomial facts local, mirroring FrontierCoverage
--  without importing its Circuit dependency.

binom-pos : (w h : ℕ) → h ≤ w → 1 ≤ binom w h
binom-pos w       zero    _         = ≤-refl
binom-pos (suc w) (suc h) (s≤s h≤w) =
  ≤-trans (binom-pos w h h≤w) (m≤n+m (binom w h) (binom w (suc h)))

spectrum-high : (h : ℕ) → h ≤ n → 2 ≤ binom n h + binom n h
spectrum-high {n = n} h h≤n = +-mono-≤ (binom-pos n h h≤n) (binom-pos n h h≤n)

binom-1 : (w : ℕ) → binom w 1 ≡ w
binom-1 zero    = refl
binom-1 (suc w) = trans (cong (_+ 1) (binom-1 w)) (+-comm w 1)

--  At radius one and n≥2, show sphere corruption 2·C(n,1)=2n strictly
--  exceeds the point bound two.
sphere-exceeds-point : 2 ≤ n → 2 < binom n 1 + binom n 1
sphere-exceeds-point {n = n} 2≤n rewrite binom-1 n =
  ≤-trans (s≤s (s≤s (s≤s z≤n))) (+-mono-≤ 2≤n 2≤n)

1≤2^n : (w : ℕ) → 1 ≤ 2 ^ w
1≤2^n zero    = ≤-refl
1≤2^n (suc w) = ≤-trans (1≤2^n w) (m≤m+n (2 ^ w) _)

suc≤2^n : (w : ℕ) → suc w ≤ 2 ^ w
suc≤2^n zero    = ≤-refl
suc≤2^n (suc w) =
  subst (suc (suc w) ≤_) (cong (2 ^ w +_) (sym (+-identityʳ (2 ^ w))))
        (+-mono-≤ (1≤2^n w) (suc≤2^n w))

------------------------------------------------------------------------
--  Add the high-corruption sphere endpoint with exact 2·C(n,h)
--  corruption and a typed n+1-query FALL adversary on the more revealing
--  natural-valued distNode. recover-ok is a positive recovery witness,
--  not ¬ExactResist, whose type expects Boolean oracles. The endpoints
--  use different observations and do not define one curve or a
--  biconditional between corruption and resistance.

record SphereCorner (h : ℕ) (ksec kapp : Vec Bool n) : Set where
  field
    --  Record exact odd-distance sphere corruption 2·C(n,h).
    --  …
    corruption-high : parity (HD ksec kapp) ≡ true → OCR h ksec kapp ≡ binom n h + binom n h
    --  Bound it below by two non-strictly, since h=0 attains two;
    --  sphere-exceeds-point provides the strict instance.
    corruption-≥pt  : h ≤ n → 2 ≤ binom n h + binom n h
    --  Supply a typed suc n-budget adversary over distNode.
    --  …
    recover-budget  : (x : Vec Bool n) → QAdversary (Vec Bool n) ℕ (Vec Bool n) (suc n)
    --  Certify its positive key recovery with n+1 queries.
    recover-ok      : (x : Vec Bool n) → Recovers (recover-budget x) distNode

sphere-Corner : (h : ℕ) (ksec kapp : Vec Bool n) → SphereCorner h ksec kapp
sphere-Corner h ksec kapp = record
  { corruption-high = calc-OCR-odd h ksec kapp
  ; corruption-≥pt  = spectrum-high h
  ; recover-budget  = fallPolyQA
  ; recover-ok      = fallPolyQA-recovers
  }

------------------------------------------------------------------------
--  Combine two endpoints indexed by corruption: points have OCR≤2 and
--  Θ(2ⁿ) recovery on Boolean actGen; spheres have OCR=2·C(n,h) and
--  n+1 recovery on natural distNode. cost-gap proves n+1≤2ⁿ. This is
--  a one-directional comparison across two oracle types, not one curve
--  or a biconditional.

record TriangleTradeoff (f : Vec Bool n → Bool) (gS : ProtGadget n)
       (ksec kapp : Vec Bool n) (h : ℕ) : Set where
  field
    point  : CorruptionTriangle f gS ksec 2
    sphere : SphereCorner h ksec kapp

  --  Compare polynomial sphere recovery n+1 with exponential point
  --  recovery 2ⁿ.
  cost-gap : suc n ≤ 2 ^ n
  cost-gap = suc≤2^n n

mk-Tradeoff : (f : Vec Bool n → Bool) (gS : ProtGadget n)
              (ksec kapp : Vec Bool n) (h : ℕ) → TriangleTradeoff f gS ksec kapp h
mk-Tradeoff f gS ksec kapp h = record
  { point  = point-Triangle f gS ksec
  ; sphere = sphere-Corner h ksec kapp
  }

------------------------------------------------------------------------
--  At n=4, check the visible one-query bracket 15≤cost≤16 and
--  point corruption ≤2.

_ : 2 ^ 4 ≡ 16
_ = refl

--  At n=4,h=1, sphere corruption is eight, above two, while
--  recovery uses five queries, at most sixteen.
_ : 2 < binom 4 1 + binom 4 1
_ = sphere-exceeds-point {n = 4} (s≤s (s≤s z≤n))
