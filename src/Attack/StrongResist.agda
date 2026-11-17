------------------------------------------------------------------------
--  Count the secrets a bounded-query adversary must decode incorrectly.
--  Recovers A act requires ask A (act k) ≡ k for every k. Its negation,
--  used by ExactResist, gen-ExactResist, and gen-adaptive-ExactResist,
--  only asserts some missed key, treating recovery of 2ⁿ−1 keys and
--  none alike. Quantify failure and derive the old property as a corollary.
--  ProbQueryBound.recovered-count-≤ already bounds success by q+1 for
--  off-diagonal reference-oracle families, covering ask and adaptive run: q
--  probed keys plus one fixed off-probe guess. Complement that count to
--  obtain strong-resist-off-diag and its subtractive form with at least
--  2ⁿ−q−1 failures. gen-strong-ExactResist lifts it to GenericSAT's scheme
--  families, while strong→ExactResist and gen-ExactResist-via-strong derive
--  the old resistance rather than asserting it separately. This is a
--  worst-case count over keys, not probability or advantage. The uniform-key
--  reading already belongs to ProbQueryBound's prob-query-lb-off-diag and
--  prob-recovery-<-total-off-diag and is not strengthened here. Incorrect
--  keys may still approximate well, as in GenNoFreeLunch. Scope includes
--  only the typed QAdversary and Adaptive classes. Reuse the counting
--  engine without new primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.StrongResist where

open import Data.Nat using (ℕ; suc; _+_; _∸_; _^_; _≤_)
open import Data.Nat.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; +-identityʳ; m≤n+o⇒m∸n≤o; n≮n)
open import Data.Bool using (Bool; true; false; not)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; subst; _≢_)
open import Relation.Nullary using (¬_)

open import Util.BoolVec using (eqVec; eqVec-refl)
open import Util.Counting using (countT; allVecs; length-allVecs; countT-≡0)
open import Attack.Oracle using (QAdversary; ask; Recovers)
open import Attack.Adaptive using (Adaptive; run; runProbes; RecoversA)
open import Attack.SARLockQueryBound using (probedV; count-total)
open import Attack.ProbQueryBound
  using (recovered-count-≤; ask-const-off; run-const-off)
open import Attack.Tradeoff using (ExactResist)
open import Attack.GenericSAT
  using (actGen; baseGen; PointConc; gen-offdiag;
         point-PointConc; flexSingleton; flex-PointConc)
open import Locking.GenericLock using (ProtGadget; pointGadget)

private
  variable
    n q : ℕ
    Y : Set

------------------------------------------------------------------------
--  Count incorrectly decoded secrets among the 2ⁿ possible keys.

--  Let guess map each secret to the adversary's decoded key.
failsAt : (guess : Vec Bool n → Vec Bool n) → Vec Bool n → Bool
failsAt guess k = not (eqVec (guess k) k)

failCount : (Vec Bool n → Vec Bool n) → ℕ
failCount {n} guess = countT (failsAt guess) (allVecs n)

------------------------------------------------------------------------
--  Complement recovered-count-≤ using count-total and length-allVecs.
--  Success plus failure partitions 2ⁿ keys, giving 2ⁿ ≤ (q+1)+failures.
--  Keep this primary form subtraction-free and derive the ∸ form below.

fail-count-≥ :
  (ps : Vec (Vec Bool n) q) (guess : Vec Bool n → Vec Bool n) (g : Vec Bool n) →
  ((k : Vec Bool n) → probedV ps k ≡ false → guess k ≡ g) →
  2 ^ n ≤ suc q + failCount guess
fail-count-≥ {n = n} ps guess g hyp =
  ≤-trans (≤-reflexive (sym partition))
          (+-mono-≤ (recovered-count-≤ ps guess g hyp) ≤-refl)
  where
    partition : countT (λ k → eqVec (guess k) k) (allVecs n) + failCount guess
                ≡ 2 ^ n
    partition = trans (count-total (λ k → eqVec (guess k) k) (allVecs n))
                      (length-allVecs n)

------------------------------------------------------------------------
--  State non-adaptive and adaptive bounds for arbitrary off-diagonal
--  reference families; gen-offdiag supplies the required off premise
--  for generic locking.

strong-resist-off-diag :
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (A : QAdversary (Vec Bool n) Y (Vec Bool n) q) →
  2 ^ n ≤ suc q + failCount (λ k → ask A (act k))
strong-resist-off-diag act base off A =
  fail-count-≥ (QAdversary.probes A) (λ k → ask A (act k)) (ask A base)
               (ask-const-off act base off A)

--  Express the count literally as at least 2ⁿ−q−1 incorrectly decoded keys.
strong-resist-off-diag-∸ :
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  (A : QAdversary (Vec Bool n) Y (Vec Bool n) q) →
  2 ^ n ∸ suc q ≤ failCount (λ k → ask A (act k))
strong-resist-off-diag-∸ {n = n} {q = q} act base off A =
  m≤n+o⇒m∸n≤o (2 ^ n) (suc q) (strong-resist-off-diag act base off A)

--  Apply the same counting bound to the q-point reference path of an
--  adaptive decision tree.
strong-adaptive-resist-off-diag :
  (A : Adaptive (Vec Bool n) Y (Vec Bool n) q)
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  2 ^ n ≤ suc q + failCount (λ k → run A (act k))
strong-adaptive-resist-off-diag A act base off =
  fail-count-≥ (runProbes A base) (λ k → run A (act k)) (run A base)
               (run-const-off A act base off)

strong-adaptive-resist-off-diag-∸ :
  (A : Adaptive (Vec Bool n) Y (Vec Bool n) q)
  (act : Vec Bool n → Vec Bool n → Y) (base : Vec Bool n → Y) →
  (∀ k x → x ≢ k → base x ≡ act k x) →
  2 ^ n ∸ suc q ≤ failCount (λ k → run A (act k))
strong-adaptive-resist-off-diag-∸ {n = n} {q = q} A act base off =
  m≤n+o⇒m∸n≤o (2 ^ n) (suc q) (strong-adaptive-resist-off-diag A act base off)

------------------------------------------------------------------------
--  Derive ExactResist: Recovers would force zero failures and hence
--  2ⁿ ≤ q+1, contradicting 2+q ≤ 2ⁿ. The earlier resistance property
--  therefore follows from the quantitative theorem.

eqVec-≡ : (a b : Vec Bool n) → a ≡ b → eqVec a b ≡ true
eqVec-≡ a .a refl = eqVec-refl a

recovers→failCount≡0 :
  (act : Vec Bool n → Vec Bool n → Bool)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  Recovers A act → failCount (λ k → ask A (act k)) ≡ 0
recovers→failCount≡0 {n = n} act A rec =
  countT-≡0 (failsAt (λ k → ask A (act k)))
            (λ k → cong not (eqVec-≡ (ask A (act k)) k (rec k)))
            (allVecs n)

count→¬Recovers :
  (act : Vec Bool n → Vec Bool n → Bool)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ≤ suc q + failCount (λ k → ask A (act k)) →
  2 + q ≤ 2 ^ n → ¬ Recovers A act
count→¬Recovers {n = n} {q = q} act A cnt bound rec =
  n≮n (suc q) (≤-trans bound collapse)
  where
    collapse : 2 ^ n ≤ suc q
    collapse = subst (2 ^ n ≤_)
                     (trans (cong (suc q +_) (recovers→failCount≡0 act A rec))
                            (+-identityʳ (suc q)))
                     cnt

strong→ExactResist :
  (act : Vec Bool n → Vec Bool n → Bool) →
  (∀ {r} (A : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
     2 ^ n ≤ suc r + failCount (λ k → ask A (act k))) →
  ExactResist act
strong→ExactResist act cnt A bound = count→¬Recovers act A (cnt A) bound

--  Derive the corresponding adaptive implication.
recoversA→failCount≡0 :
  (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q)
  (act : Vec Bool n → Vec Bool n → Bool) →
  RecoversA A act → failCount (λ k → run A (act k)) ≡ 0
recoversA→failCount≡0 {n = n} A act rec =
  countT-≡0 (failsAt (λ k → run A (act k)))
            (λ k → cong not (eqVec-≡ (run A (act k)) k (rec k)))
            (allVecs n)

countA→¬RecoversA :
  (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q)
  (act : Vec Bool n → Vec Bool n → Bool) →
  2 ^ n ≤ suc q + failCount (λ k → run A (act k)) →
  2 + q ≤ 2 ^ n → ¬ RecoversA A act
countA→¬RecoversA {n = n} {q = q} A act cnt bound rec =
  n≮n (suc q) (≤-trans bound collapse)
  where
    collapse : 2 ^ n ≤ suc q
    collapse = subst (2 ^ n ≤_)
                     (trans (cong (suc q +_) (recoversA→failCount≡0 A act rec))
                            (+-identityʳ (suc q)))
                     cnt

------------------------------------------------------------------------
--  Instantiate with GenericLock's baseGen and gen-offdiag to transport
--  the count to the full point-concentrated family under the same
--  premises as gen-ExactResist and gen-adaptive-ExactResist.

gen-strong-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ≤ suc q + failCount (λ k → ask A (actGen f gS G k))
gen-strong-ExactResist f gS G pc A =
  strong-resist-off-diag (actGen f gS G) (baseGen f gS) (gen-offdiag f gS G pc) A

gen-strong-ExactResist-∸ :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ∸ suc q ≤ failCount (λ k → ask A (actGen f gS G k))
gen-strong-ExactResist-∸ {n = n} {q = q} f gS G pc A =
  m≤n+o⇒m∸n≤o (2 ^ n) (suc q) (gen-strong-ExactResist f gS G pc A)

gen-strong-adaptive-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ≤ suc q + failCount (λ k → run A (actGen f gS G k))
gen-strong-adaptive-ExactResist f gS G pc A =
  strong-adaptive-resist-off-diag A (actGen f gS G) (baseGen f gS)
                                  (gen-offdiag f gS G pc)

gen-strong-adaptive-ExactResist-∸ :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ∸ suc q ≤ failCount (λ k → run A (actGen f gS G k))
gen-strong-adaptive-ExactResist-∸ {n = n} {q = q} f gS G pc A =
  m≤n+o⇒m∸n≤o (2 ^ n) (suc q) (gen-strong-adaptive-ExactResist f gS G pc A)

--  Recover GenericSAT.gen-ExactResist's proposition and type as a
--  corollary of the stronger count.
gen-ExactResist-via-strong :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G → ExactResist (actGen f gS G)
gen-ExactResist-via-strong f gS G pc =
  strong→ExactResist (actGen f gS G) (gen-strong-ExactResist f gS G pc)

------------------------------------------------------------------------
--  Exercise the bound on both GenericSAT gadget instances, point
--  (SARLock/Anti-SAT) and genuine flex singletons.

point-strong-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ∸ suc q ≤ failCount (λ k → ask A (actGen f gS pointGadget k))
point-strong-ExactResist f gS A =
  gen-strong-ExactResist-∸ f gS pointGadget point-PointConc A

point-strong-adaptive-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (A : Adaptive (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ∸ suc q ≤ failCount (λ k → run A (actGen f gS pointGadget k))
point-strong-adaptive-ExactResist f gS A =
  gen-strong-adaptive-ExactResist-∸ f gS pointGadget point-PointConc A

flex-strong-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (A : QAdversary (Vec Bool n) Bool (Vec Bool n) q) →
  2 ^ n ∸ suc q ≤ failCount (λ k → ask A (actGen f gS flexSingleton k))
flex-strong-ExactResist f gS A =
  gen-strong-ExactResist-∸ f gS flexSingleton flex-PointConc A
