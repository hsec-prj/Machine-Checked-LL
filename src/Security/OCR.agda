------------------------------------------------------------------------
--  Define output corruption and establish its lower-bound
--  building blocks. Wrong-key SFLL-HD differs from the
--  host exactly where the protected predicates disagree;
--  OCR counts these inputs among 2ⁿ patterns. sphere-count
--  gives binom n h protected inputs for every key and
--  radius. Two disjoint spheres then give 2·C(n,h)
--  for a one-bit-wrong key, the key case underlying
--  the lower-bound discussion, with disjointness and
--  union established below. OCR-lower-bound-h0 closes
--  radius zero: the secret's singleton pattern is
--  corrupted under every distinct applied key, giving at least one input.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.OCR where

open import Data.Nat using (ℕ; zero; suc; _≡ᵇ_; _+_; _*_; _≤_; _<_)
open import Data.Nat.Properties
  using (+-comm; ≡ᵇ⇒≡; ≤-trans; ≤-reflexive; ≤-<-trans; <-irrefl; +-identityʳ)
open import Data.Bool using (Bool; true; false; T; _∧_; _xor_)
open import Data.Bool.Properties using (∧-comm; ∧-idem; xor-same)
open import Data.Unit using (tt)
open import Data.Vec using (Vec; []; _∷_; replicate; take; drop)
open import Data.Empty using (⊥; ⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; _≢_; sym; cong; cong₂; trans; subst)

open import SFLL.HammingDistance
  using (HD; HD-refl; HD-sym; HD-triangle; HD0→≡; parity; HD-xor-parity)
open import SFLL.HD using (prot)
open import Util.Counting
  using (countT; allVecs; allVecs-count-pos; binom; countT-false; split-count;
         countT-xor-disjoint; countT-xor-≤; countT-prod; countT-and-xor; countT-≡0;
         countT-cong)

private
  variable
    n m : ℕ

--  Express wrong-key disagreement as the input predicate
--  prot ksec x xor prot kapp x.
corrupt : ℕ → (ksec kapp : Vec Bool n) → Vec Bool n → Bool
corrupt h ksec kapp x = prot h ksec x xor prot h kapp x

--  Count corrupted inputs over all 2ⁿ patterns.
OCR : ℕ → (ksec kapp : Vec Bool n) → ℕ
OCR {n = n} h ksec kapp = countT (corrupt h ksec kapp) (allVecs n)

------------------------------------------------------------------------
--  Establish protected-set cardinality C(n,h) for general h.

--  Count the radius-h sphere with countT (prot h k).
--  Splitting allVecs by the leading bit yields Pascal's
--  rule: agreement with the leading key bit keeps h,
--  while disagreement decrements the remaining radius.
sphere-count : (h : ℕ) (k : Vec Bool n) →
               countT (prot h k) (allVecs n) ≡ binom n h
sphere-count zero    []              = refl
sphere-count (suc h) []              = refl
sphere-count {n = suc m} zero    (false ∷ k) =
  trans (split-count (prot zero (false ∷ k)))
        (cong₂ _+_ (sphere-count zero k) (countT-false (allVecs m)))
sphere-count {n = suc m} (suc h) (false ∷ k) =
  trans (split-count (prot (suc h) (false ∷ k)))
        (cong₂ _+_ (sphere-count (suc h) k) (sphere-count h k))
sphere-count {n = suc m} zero    (true ∷ k) =
  trans (split-count (prot zero (true ∷ k)))
        (cong₂ _+_ (countT-false (allVecs m)) (sphere-count zero k))
sphere-count {n = suc m} (suc h) (true ∷ k) =
  trans (split-count (prot (suc h) (true ∷ k)))
        (trans (cong₂ _+_ (sphere-count h k) (sphere-count (suc h) k))
               (+-comm (binom m h) (binom m (suc h))))

------------------------------------------------------------------------
--  Establish the radius-zero lower bound.

≢0→≡ᵇ0 : (m : ℕ) → m ≢ 0 → (m ≡ᵇ 0) ≡ false
≢0→≡ᵇ0 zero    ne = ⊥-elim (ne refl)
≢0→≡ᵇ0 (suc m) ne = refl

--  At h = 0, HD k k = 0 makes k its own protected pattern.
prot0-refl : (k : Vec Bool n) → prot 0 k k ≡ true
prot0-refl k = subst (λ m → (m ≡ᵇ 0) ≡ true) (sym (HD-refl k)) refl

--  A distinct radius-zero key does not protect the secret's pattern.
prot0-≢ : (ksec kapp : Vec Bool n) → ksec ≢ kapp → prot 0 kapp ksec ≡ false
prot0-≢ ksec kapp ne = ≢0→≡ᵇ0 (HD ksec kapp) (λ e → ne (HD0→≡ ksec kapp e))

--  Deduce corruption of the secret input under every distinct applied key.
corrupt0-ksec : (ksec kapp : Vec Bool n) → ksec ≢ kapp →
                corrupt 0 ksec kapp ksec ≡ true
corrupt0-ksec ksec kapp ne =
  cong₂ _xor_ (prot0-refl ksec) (prot0-≢ ksec kapp ne)

--  For h = 0, show every wrong key corrupts at least one input.
OCR-lower-bound-h0 : (ksec kapp : Vec Bool n) → ksec ≢ kapp →
                     1 ≤ OCR 0 ksec kapp
OCR-lower-bound-h0 ksec kapp ne =
  allVecs-count-pos (corrupt 0 ksec kapp) ksec (corrupt0-ksec ksec kapp ne)

------------------------------------------------------------------------
--  Obtain exact general-radius OCR = 2·C(n,h) for one-bit-different keys.

--  Rule out simultaneous equality of a and suc a to h,
--  making their conjunction false and the relevant spheres disjoint.
≡ᵇ-suc-false : (a h : ℕ) → ((a ≡ᵇ h) ∧ (suc a ≡ᵇ h)) ≡ false
≡ᵇ-suc-false zero    zero    = refl
≡ᵇ-suc-false zero    (suc h) = refl
≡ᵇ-suc-false (suc a) zero    = refl
≡ᵇ-suc-false (suc a) (suc h) = ≡ᵇ-suc-false a h

--  For keys differing only in their first bit, distances
--  to any input differ by one, so no input lies on both radius-h spheres.
prot-disjoint-fst : (h : ℕ) (r : Vec Bool m) (x : Vec Bool (suc m)) →
                    (prot h (false ∷ r) x ∧ prot h (true ∷ r) x) ≡ false
prot-disjoint-fst h r (false ∷ x) = ≡ᵇ-suc-false (HD x r) h
prot-disjoint-fst h r (true  ∷ x) =
  trans (∧-comm (suc (HD x r) ≡ᵇ h) (HD x r ≡ᵇ h)) (≡ᵇ-suc-false (HD x r) h)

--  Count two disjoint C(n,h) spheres to obtain 2·C(n,h)
--  for the one-bit-wrong case. This is the security-critical
--  case discussed as hardest to rule out, yet already
--  corrupting a binomial number of outputs.
OCR-onebit : (h : ℕ) (r : Vec Bool m) →
             OCR h (false ∷ r) (true ∷ r) ≡ binom (suc m) h + binom (suc m) h
OCR-onebit h r =
  trans (countT-xor-disjoint (prot h (false ∷ r)) (prot h (true ∷ r))
                             (prot-disjoint-fst h r) (allVecs (suc _)))
        (cong₂ _+_ (sphere-count h (false ∷ r)) (sphere-count h (true ∷ r)))

------------------------------------------------------------------------
--  Generalise the first-bit result to arbitrary odd-distance
--  keys. HD-xor-parity forces opposite distance parities
--  for every input, hence unequal distances and disjoint
--  spheres. Their OCR is 2·C(n,h). A one-bit difference
--  at any position specialises HD to one, whose parity is true.

--  Exclude two unequal distances both matching one target.
and-≡ᵇ-false : (a b h : ℕ) → a ≢ b → ((a ≡ᵇ h) ∧ (b ≡ᵇ h)) ≡ false
and-≡ᵇ-false a b h ne with a ≡ᵇ h in eqa | b ≡ᵇ h in eqb
... | false | _     = refl
... | true  | false = refl
... | true  | true  =
  ⊥-elim (ne (trans (≡ᵇ⇒≡ a h (subst T (sym eqa) tt))
                    (sym (≡ᵇ⇒≡ b h (subst T (sym eqb) tt)))))

--  Infer unequal bits from a true XOR.
xor-true-≢ : (a b : Bool) → (a xor b) ≡ true → a ≢ b
xor-true-≢ false false ()
xor-true-≢ false true  _ = λ ()
xor-true-≢ true  false _ = λ ()
xor-true-≢ true  true  ()

--  Prove protected-set disjointness for odd-distance keys.
prot-disjoint-odd : (h : ℕ) {k k' : Vec Bool n} → parity (HD k k') ≡ true →
                    (x : Vec Bool n) → (prot h k x ∧ prot h k' x) ≡ false
prot-disjoint-odd h {k} {k'} odd x =
  and-≡ᵇ-false (HD x k) (HD x k') h
    (λ eq → xor-true-≢ (parity (HD x k)) (parity (HD x k'))
                       (trans (HD-xor-parity x k k') odd)
                       (cong parity eq))

--  Conclude exact OCR 2·C(n,h) at every odd key distance.
OCR-odd : (h : ℕ) (k k' : Vec Bool n) → parity (HD k k') ≡ true →
          OCR h k k' ≡ binom n h + binom n h
OCR-odd h k k' odd =
  trans (countT-xor-disjoint (prot h k) (prot h k') (prot-disjoint-odd h odd) (allVecs _))
        (cong₂ _+_ (sphere-count h k) (sphere-count h k'))

--  Specialise to a one-bit difference in any coordinate.
OCR-onebit-any : (h : ℕ) (k k' : Vec Bool n) → HD k k' ≡ 1 →
                 OCR h k k' ≡ binom n h + binom n h
OCR-onebit-any h k k' d1 = OCR-odd h k k' (cong parity d1)

------------------------------------------------------------------------
--  For general distance d, express OCR as the spheres'
--  symmetric difference: 2·C(n,h) minus twice their
--  intersection. The even-distance intersection has
--  Vandermonde form C(n−d,h−d/2)·C(d,d/2); odd d
--  uses the disjoint zero-intersection case OCR-odd.

--  Bound symmetric difference by the union to obtain
--  OCR ≤ 2·C(n,h) for every key. Overlap reduces the
--  count strictly in the intersecting even-distance cases.
OCR-upper : (h : ℕ) (k k' : Vec Bool n) → OCR h k k' ≤ binom n h + binom n h
OCR-upper h k k' =
  ≤-trans (countT-xor-≤ (prot h k) (prot h k') (allVecs _))
          (≤-reflexive (cong₂ _+_ (sphere-count h k) (sphere-count h k')))

--  Prove the contiguous-region Vandermonde kernel. Weight
--  a on p wires and b on d independent wires contributes
--  C(p,a)·C(d,b), using countT-prod and sphere-count
--  on all-false keys. This supplies the intersection's
--  C(n−d,·)·C(d,·) factor. Completing the closed even
--  formula also requires permutation/XOR-shift normalisation
--  and solving a+b=h, a+(d−b)=h to force b=d/2.
vandermonde-kernel : (p d a b : ℕ) →
  countT (λ x → prot a (replicate p false) (take p x)
              ∧ prot b (replicate d false) (drop p x))
         (allVecs (p + d))
  ≡ binom p a * binom d b
vandermonde-kernel p d a b =
  trans (countT-prod p (prot a (replicate p false)) (prot b (replicate d false)))
        (cong₂ _*_ (sphere-count a (replicate p false)) (sphere-count b (replicate d false)))

------------------------------------------------------------------------
--  Reduce the full distance-dependent OCR formula to
--  one intersection count using inclusion–exclusion:
--  OCR h k k' + 2·|S_h(k) ∩ S_h(k')| = 2·C(n,h).
--  This holds before coordinate normalisation. Odd
--  distance gives zero intersection; the remaining
--  even-distance arithmetic evaluates the Vandermonde product.

--  Count the intersection S_h(k) ∩ S_h(k').
inter : ℕ → (k k' : Vec Bool n) → ℕ
inter {n = n} h k k' = countT (λ x → prot h k x ∧ prot h k' x) (allVecs n)

--  Prove inclusion–exclusion for every key pair.
OCR-incl-excl : (h : ℕ) (k k' : Vec Bool n) →
                OCR h k k' + 2 * inter h k k' ≡ binom n h + binom n h
OCR-incl-excl h k k' =
  trans (countT-and-xor (prot h k) (prot h k') (allVecs _))
        (cong₂ _+_ (sphere-count h k) (sphere-count h k'))

--  Use empty odd-distance intersection to reduce
--  OCR-incl-excl to OCR = 2·C(n,h), agreeing with OCR-odd.
inter-odd : (h : ℕ) {k k' : Vec Bool n} → parity (HD k k') ≡ true →
            inter h k k' ≡ 0
inter-odd h {k} {k'} odd =
  countT-≡0 (λ x → prot h k x ∧ prot h k' x) (prot-disjoint-odd h odd) (allVecs _)

--  At matching keys, distance zero gives no corruption
--  and the complete sphere as intersection.
OCR-same : (h : ℕ) (k : Vec Bool n) → OCR h k k ≡ 0
OCR-same h k = countT-≡0 (corrupt h k k) (λ x → xor-same (prot h k x)) (allVecs _)

inter-same : (h : ℕ) (k : Vec Bool n) → inter h k k ≡ binom n h
inter-same h k =
  trans (countT-cong (λ x → ∧-idem (prot h k x)) (allVecs _)) (sphere-count h k)

------------------------------------------------------------------------
--  Complete the far-distance case: beyond 2h the
--  triangle inequality makes spheres disjoint, giving
--  2·C(n,h). EvenOCRGeneral's C(n−2e,h−e)·C(2e,e)
--  formula assumes e ≤ h; e > h instead uses this
--  empty-intersection result. Together with OCR-odd
--  and OCR-even, it supplies exact OCR at every distance.

--  Make (a ≡ᵇ h) ∧ (b ≡ᵇ h) false whenever
--  a and b cannot both equal h.
and-≡ᵇ-both-false : (a b h : ℕ) → (a ≡ h → b ≡ h → ⊥) →
                    ((a ≡ᵇ h) ∧ (b ≡ᵇ h)) ≡ false
and-≡ᵇ-both-false a b h ¬both with a ≡ᵇ h in eqa | b ≡ᵇ h in eqb
... | false | _     = refl
... | true  | false = refl
... | true  | true  =
  ⊥-elim (¬both (≡ᵇ⇒≡ a h (subst T (sym eqa) tt))
                (≡ᵇ⇒≡ b h (subst T (sym eqb) tt)))

--  An input at distance h from both keys would imply
--  HD k k' ≤ HD k x + HD x k' = h+h,
--  contradicting h+h < HD k k'.
prot-far : (h : ℕ) {k k' : Vec Bool n} → h + h < HD k k' →
           (x : Vec Bool n) → (prot h k x ∧ prot h k' x) ≡ false
prot-far h {k} {k'} lt x =
  and-≡ᵇ-both-false (HD x k) (HD x k') h
    (λ e1 e2 → <-irrefl refl
                 (≤-<-trans
                    (≤-trans (HD-triangle k x k')
                             (≤-reflexive (cong₂ _+_ (trans (HD-sym k x) e1) e2)))
                    lt))

--  Deduce an empty intersection for keys farther apart than 2h.
inter-far : (h : ℕ) (k k' : Vec Bool n) → h + h < HD k k' → inter h k k' ≡ 0
inter-far h k k' lt =
  countT-≡0 (λ x → prot h k x ∧ prot h k' x) (prot-far h {k} {k'} lt) (allVecs _)

--  Obtain exact disjoint OCR 2·C(n,h) whenever distance exceeds 2h.
OCR-far : (h : ℕ) (k k' : Vec Bool n) → h + h < HD k k' →
          OCR h k k' ≡ binom n h + binom n h
OCR-far h k k' lt =
  trans (sym (trans (cong (λ z → OCR h k k' + 2 * z) (inter-far h k k' lt))
                    (+-identityʳ (OCR h k k'))))
        (OCR-incl-excl h k k')
