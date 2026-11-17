------------------------------------------------------------------------
--  Compute exact intersections at even distance d ≥ 2. For keys in contiguous
--  agreement/disagreement normal form with d = 2·e differing coordinates,
--  the protected spheres intersect in C(p, h∸e) · C(2e, e), a Vandermonde
--  product. Parameterising distance by 2·e avoids division and settles the
--  remaining distance-d OCR case. The construction proceeds from Boolean
--  and natural-number arithmetic to resolution of the coupled constraints.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.EvenOCR where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _∸_; _≡ᵇ_; _≤_)
open import Data.Nat.Properties
  using (+-identityʳ; +-suc; +-comm; suc-injective; +-cancelˡ-≡; ≡ᵇ⇒≡; ≡⇒≡ᵇ;
         m+n∸n≡m; m+[n∸m]≡n)
open import Data.Bool using (Bool; true; false; T; not; _∧_; _xor_)
open import Data.Bool.Properties using (∧-comm)
open import Data.Unit using (tt)
open import Data.Vec using (Vec; []; _∷_; _++_; replicate; take; drop)
open import Data.Vec.Properties using (take++drop≡id)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst)

open import SFLL.HammingDistance using (HD; b2n; HD-++)
open import SFLL.HD using (prot)
open import Util.Counting using (mid4; countT; countT-cong; countT-prod; binom; allVecs)
open import Security.OCR using (OCR; inter; sphere-count; OCR-incl-excl)

------------------------------------------------------------------------
--  Supporting lemmas for Boolean reflection.

--  Characterise a Boolean by the condition under which it equals true.
bool-≡ : (p q : Bool) → (p ≡ true → q ≡ true) → (q ≡ true → p ≡ true) → p ≡ q
bool-≡ true  true  f g = refl
bool-≡ true  false f g with f refl
... | ()
bool-≡ false true  f g with g refl
... | ()
bool-≡ false false f g = refl

∧⁻ˡ : (a b : Bool) → (a ∧ b) ≡ true → a ≡ true
∧⁻ˡ true  b _  = refl
∧⁻ˡ false b ()

∧⁻ʳ : (a b : Bool) → (a ∧ b) ≡ true → b ≡ true
∧⁻ʳ true  b eq = eq
∧⁻ʳ false b ()

∧⁺ : (a b : Bool) → a ≡ true → b ≡ true → (a ∧ b) ≡ true
∧⁺ true  b _ eqb = eqb
∧⁺ false b () _

--  Relate natural-number equality to its Boolean comparison.
T→≡true : (b : Bool) → T b → b ≡ true
T→≡true true  _ = refl
T→≡true false ()

≡ᵇ-true→≡ : (m n : ℕ) → (m ≡ᵇ n) ≡ true → m ≡ n
≡ᵇ-true→≡ m n eq = ≡ᵇ⇒≡ m n (subst T (sym eq) tt)

≡→≡ᵇ-true : (m n : ℕ) → m ≡ n → (m ≡ᵇ n) ≡ true
≡→≡ᵇ-true m n eq = T→≡true (m ≡ᵇ n) (≡⇒≡ᵇ m n eq)

------------------------------------------------------------------------
--  Supporting natural-number arithmetic facts.

2*≡+ : (x : ℕ) → 2 * x ≡ x + x
2*≡+ x = cong (x +_) (+-identityʳ x)

+suc2 : (m : ℕ) → suc m + suc m ≡ suc (suc (m + m))
+suc2 m = cong suc (+-suc m m)

double-injective : (a b : ℕ) → a + a ≡ b + b → a ≡ b
double-injective zero    zero    _  = refl
double-injective zero    (suc b) ()
double-injective (suc a) zero    ()
double-injective (suc a) (suc b) eq =
  cong suc (double-injective a b
    (suc-injective (suc-injective (trans (sym (+suc2 a)) (trans eq (+suc2 b))))))

------------------------------------------------------------------------
--  Resolve the coupled constraints. Under B + B' = 2·e, requiring both
--  Hamming distances to be h fixes the disagreement weight to e:
--  (A + B ≡ h) ∧ (A + B' ≡ h) ⟺ (B ≡ e) ∧ (A + e ≡ h).
--  Use Boolean equality so the predicates can be exchanged beneath countT.

split-eqv : (A B B' e h : ℕ) → B + B' ≡ 2 * e →
            ((A + B ≡ᵇ h) ∧ (A + B' ≡ᵇ h)) ≡ ((B ≡ᵇ e) ∧ (A + e ≡ᵇ h))
split-eqv A B B' e h sum = bool-≡ _ _ fwd bwd
  where
    fwd : ((A + B ≡ᵇ h) ∧ (A + B' ≡ᵇ h)) ≡ true →
          ((B ≡ᵇ e) ∧ (A + e ≡ᵇ h)) ≡ true
    fwd lhs =
      let AB≡h  = ≡ᵇ-true→≡ (A + B)  h (∧⁻ˡ _ _ lhs)
          AB'≡h = ≡ᵇ-true→≡ (A + B') h (∧⁻ʳ _ _ lhs)
          B≡B'  = +-cancelˡ-≡ A B B' (trans AB≡h (sym AB'≡h))
          BB≡ee = trans (cong (B +_) B≡B') (trans sum (2*≡+ e))
          B≡e   = double-injective B e BB≡ee
          Ae≡h  = subst (λ z → A + z ≡ h) B≡e AB≡h
      in ∧⁺ _ _ (≡→≡ᵇ-true B e B≡e) (≡→≡ᵇ-true (A + e) h Ae≡h)
    bwd : ((B ≡ᵇ e) ∧ (A + e ≡ᵇ h)) ≡ true →
          ((A + B ≡ᵇ h) ∧ (A + B' ≡ᵇ h)) ≡ true
    bwd rhs =
      let B≡e   = ≡ᵇ-true→≡ B e (∧⁻ˡ _ _ rhs)
          Ae≡h  = ≡ᵇ-true→≡ (A + e) h (∧⁻ʳ _ _ rhs)
          eB'≡ee = trans (subst (λ z → z + B' ≡ 2 * e) B≡e sum) (2*≡+ e)
          B'≡e  = +-cancelˡ-≡ e B' e eB'≡ee
          AB≡h  = subst (λ z → A + z ≡ h) (sym B≡e) Ae≡h
          AB'≡h = subst (λ z → A + z ≡ h) (sym B'≡e) Ae≡h
      in ∧⁺ _ _ (≡→≡ᵇ-true (A + B) h AB≡h) (≡→≡ᵇ-true (A + B') h AB'≡h)

------------------------------------------------------------------------
--  Prove regional Hamming-distance identities.

--  Each coordinate disagrees with exactly one of the all-false and all-true
--  reference values.
b2n-xor-ft : (x : Bool) → b2n (x xor false) + b2n (x xor true) ≡ 1
b2n-xor-ft false = refl
b2n-xor-ft true  = refl

--  Within the disagreement region, distances to the all-false and all-true
--  vectors sum to that region's width.
HD-false+true : (d : ℕ) (xs : Vec Bool d) →
                HD xs (replicate d false) + HD xs (replicate d true) ≡ d
HD-false+true zero    []       = refl
HD-false+true (suc d) (x ∷ xs) =
  trans (mid4 (b2n (x xor false)) (HD xs (replicate d false))
              (b2n (x xor true))  (HD xs (replicate d true)))
        (cong₂ _+_ (b2n-xor-ft x) (HD-false+true d xs))

--  Split Hamming distance to a concatenated reference using take and drop.
HD-split : (p d : ℕ) (x : Vec Bool (p + d)) (ys : Vec Bool p) (ls : Vec Bool d) →
           HD x (ys ++ ls) ≡ HD (take p x) ys + HD (drop p x) ls
HD-split p d x ys ls =
  trans (cong (λ z → HD z (ys ++ ls)) (sym (take++drop≡id p x)))
        (HD-++ (take p x) ys (drop p x) ls)

--  Shift the comparison target across _≡ᵇ_ under e ≤ h.
shift-≡ᵇ : (w e h : ℕ) → e ≤ h → (w + e ≡ᵇ h) ≡ (w ≡ᵇ h ∸ e)
shift-≡ᵇ w e h e≤h = bool-≡ _ _ fwd bwd
  where
    fwd : (w + e ≡ᵇ h) ≡ true → (w ≡ᵇ h ∸ e) ≡ true
    fwd eq = ≡→≡ᵇ-true w (h ∸ e)
      (trans (sym (m+n∸n≡m w e)) (cong (_∸ e) (≡ᵇ-true→≡ (w + e) h eq)))
    bwd : (w ≡ᵇ h ∸ e) ≡ true → (w + e ≡ᵇ h) ≡ true
    bwd eq = ≡→≡ᵇ-true (w + e) h
      (trans (cong (_+ e) (≡ᵇ-true→≡ w (h ∸ e) eq))
             (trans (+-comm (h ∸ e) e) (m+[n∸m]≡n e≤h)))

------------------------------------------------------------------------
--  Express the contiguous normal-form intersection as a Vandermonde product.
--  Both keys share replicate p false; their remaining regions are
--  replicate (2e) false and replicate (2e) true, giving HD k k' = 2e.

--  For each input, replace the coupled distance predicate by independent
--  conditions on the two regions.
pred-eqv : (p e h : ℕ) (x : Vec Bool (p + 2 * e)) →
  ((HD x (replicate p false ++ replicate (2 * e) false) ≡ᵇ h)
   ∧ (HD x (replicate p false ++ replicate (2 * e) true) ≡ᵇ h))
  ≡ ((HD (take p x) (replicate p false) + e ≡ᵇ h)
     ∧ (HD (drop p x) (replicate (2 * e) false) ≡ᵇ e))
pred-eqv p e h x =
  trans (cong₂ _∧_ (cong (_≡ᵇ h) splitF) (cong (_≡ᵇ h) splitT))
        (trans (split-eqv A B B' e h sumBB')
               (∧-comm (B ≡ᵇ e) (A + e ≡ᵇ h)))
  where
    A  = HD (take p x) (replicate p false)
    B  = HD (drop p x) (replicate (2 * e) false)
    B' = HD (drop p x) (replicate (2 * e) true)
    splitF : HD x (replicate p false ++ replicate (2 * e) false) ≡ A + B
    splitF = HD-split p (2 * e) x (replicate p false) (replicate (2 * e) false)
    splitT : HD x (replicate p false ++ replicate (2 * e) true) ≡ A + B'
    splitT = HD-split p (2 * e) x (replicate p false) (replicate (2 * e) true)
    sumBB' : B + B' ≡ 2 * e
    sumBB' = HD-false+true (2 * e) (drop p x)

--  Establish the exact even-distance intersection in contiguous normal form
--  assuming e ≤ h.
inter-normal-even : (p e h : ℕ) → e ≤ h →
  inter h (replicate p false ++ replicate (2 * e) false)
          (replicate p false ++ replicate (2 * e) true)
  ≡ binom p (h ∸ e) * binom (2 * e) e
inter-normal-even p e h e≤h =
  trans (countT-cong (pred-eqv p e h) (allVecs (p + 2 * e)))
  (trans (countT-prod p
            (λ xp → HD xp (replicate p false) + e ≡ᵇ h)
            (λ xd → HD xd (replicate (2 * e) false) ≡ᵇ e))
         (cong₂ _*_ countP≡ countQ≡))
  where
    countQ≡ : countT (λ xd → HD xd (replicate (2 * e) false) ≡ᵇ e) (allVecs (2 * e))
              ≡ binom (2 * e) e
    countQ≡ = sphere-count e (replicate (2 * e) false)
    countP≡ : countT (λ xp → HD xp (replicate p false) + e ≡ᵇ h) (allVecs p)
              ≡ binom p (h ∸ e)
    countP≡ =
      trans (countT-cong (λ xp → shift-≡ᵇ (HD xp (replicate p false)) e h e≤h) (allVecs p))
            (sphere-count (h ∸ e) (replicate p false))

--  Combine this intersection with inclusion–exclusion for exact even-distance
--  OCR in contiguous normal form. State it additively, avoiding rationals and
--  subtraction: OCR + 2·C(p, h∸e)·C(2e, e) = 2·C(p+2e, h).
OCR-normal-even : (p e h : ℕ) → e ≤ h →
  OCR h (replicate p false ++ replicate (2 * e) false)
        (replicate p false ++ replicate (2 * e) true)
  + 2 * (binom p (h ∸ e) * binom (2 * e) e)
  ≡ binom (p + 2 * e) h + binom (p + 2 * e) h
OCR-normal-even p e h e≤h =
  subst (λ m →
           OCR h (replicate p false ++ replicate (2 * e) false)
                 (replicate p false ++ replicate (2 * e) true)
           + 2 * m ≡ binom (p + 2 * e) h + binom (p + 2 * e) h)
        (inter-normal-even p e h e≤h)
        (OCR-incl-excl h (replicate p false ++ replicate (2 * e) false)
                         (replicate p false ++ replicate (2 * e) true))
