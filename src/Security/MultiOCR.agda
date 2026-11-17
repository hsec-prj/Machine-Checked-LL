------------------------------------------------------------------------
--  Count joint corruption of multiple outputs, extending the
--  designated-output lock in EfficientLockMulti. With shared
--  (h,ksec,kapp), every protected output flips on the
--  same δ x = prot ksec x xor prot kapp x = corrupt …
--  input set. For a nonempty protected set, vector
--  disagreement therefore holds exactly on δ and its
--  count is single-cone OCR, independent of which or
--  how many outputs are protected. mocr-set proves
--  mocr (lockedSet P …) F ≡ OCR h ksec kapp,
--  mocr-set-odd yields 2·C(n,h) at odd key distance,
--  and mocr-set-invariant states protected-set independence.
--  lockedVec-is-lockedSet recovers designated-output locking
--  as a singleton instance. Add no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.MultiOCR where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_)
open import Data.Nat.Properties using (≤-refl; ≤-reflexive; ≤-trans; +-mono-≤)
open import Data.List using (List)
open import Data.Fin using (Fin; toℕ; _≟_) renaming (zero to fz; suc to fs)
open import Data.Bool using (Bool; true; false; _xor_; _∧_; _∨_)
open import Data.Bool.Properties
  using (∧-distribʳ-∨; ∧-distribˡ-∨; ∧-zeroʳ; ∨-zeroʳ; xor-assoc; xor-same; xor-identityʳ)
open import Data.Vec using (Vec; lookup; tabulate; updateAt)
open import Data.Vec.Properties
  using (lookup∘tabulate; lookup∘updateAt; lookup∘updateAt′; tabulate∘lookup; tabulate-cong)
open import Relation.Nullary using (does; yes; no)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import Util.Counting using (countT; allVecs; countT-cong; countT-false; countT-xor-disjoint; binom)
open import Attack.SARLockQueryBound using (countT-∨-≤; countT-∧-≤ʳ)
open import Security.OCR using (OCR; corrupt; OCR-odd; OCR-far)
open import SFLL.HammingDistance using (HD; parity)
open import SFLL.HD using (prot)
open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import SFLL.EfficientLockMulti using
  (lockedVec; locked-multi-set; locked-multi-set-correct;
   locked-multi-setK; locked-multi-setK-correct)

private
  variable
    n k : ℕ

------------------------------------------------------------------------
--  Define finite OR on Fin k with the needed supporting laws.

orFin : (k : ℕ) → (Fin k → Bool) → Bool
orFin zero    f = false
orFin (suc k) f = f fz ∨ orFin k (λ i → f (fs i))

orFin-cong : (k : ℕ) {f g : Fin k → Bool} → (∀ i → f i ≡ g i) → orFin k f ≡ orFin k g
orFin-cong zero    _ = refl
orFin-cong (suc k) e = cong₂ _∨_ (e fz) (orFin-cong k (λ i → e (fs i)))

--  Distribute conjunction through finite OR:
--  ⋁ᵢ (f i ∧ c) ≡ (⋁ᵢ f i) ∧ c.
orFin-∧ : (k : ℕ) (f : Fin k → Bool) (c : Bool) →
          orFin k (λ i → f i ∧ c) ≡ orFin k f ∧ c
orFin-∧ zero    f c = refl
orFin-∧ (suc k) f c =
  trans (cong ((f fz ∧ c) ∨_) (orFin-∧ k (λ i → f (fs i)) c))
        (sym (∧-distribʳ-∨ c (f fz) (orFin k (λ i → f (fs i)))))

--  Make the OR true from one true entry.
orFin-true-at : (k : ℕ) (f : Fin k → Bool) (i : Fin k) → f i ≡ true → orFin k f ≡ true
orFin-true-at (suc k) f fz     e = cong (_∨ orFin k (λ i → f (fs i))) e
orFin-true-at (suc k) f (fs i) e =
  trans (cong (f fz ∨_) (orFin-true-at k (λ j → f (fs j)) i e)) (∨-zeroʳ (f fz))

--  Cancel the repeated left XOR input: (a xor m) xor a ≡ m.
xorCancelL : (a m : Bool) → (a xor m) xor a ≡ m
xorCancelL false false = refl
xorCancelL false true  = refl
xorCancelL true  false = refl
xorCancelL true  true  = refl

------------------------------------------------------------------------
--  Define set-locked vectors and joint output corruption.

--  For each P-selected output, XOR the shared corrupt
--  h ksec kapp x perturbation; preserve all other outputs.
lockedSet : (P : Fin k → Bool) (h : ℕ) (ksec kapp : Vec Bool n)
            (F : Vec Bool n → Vec Bool k) → Vec Bool n → Vec Bool k
lockedSet {k} P h ksec kapp F x =
  tabulate (λ i → lookup (F x) i xor (P i ∧ corrupt h ksec kapp x))

--  Detect vector inequality by a differing position.
vdiffF : Vec Bool k → Vec Bool k → Bool
vdiffF {k} u v = orFin k (λ i → lookup u i xor lookup v i)

--  Count inputs on which the output vectors disagree.
mocr : (G H : Vec Bool n → Vec Bool k) → ℕ
mocr {n} G H = countT (λ x → vdiffF (G x) (H x)) (allVecs n)

------------------------------------------------------------------------
--  For nonempty protection, equate vector disagreement
--  pointwise with the common corruption predicate.

vdiff-pointwise :
  (P : Fin k → Bool) (i₀ : Fin k) → P i₀ ≡ true →
  (h : ℕ) (ksec kapp : Vec Bool n) (F : Vec Bool n → Vec Bool k) (x : Vec Bool n) →
  vdiffF (lockedSet P h ksec kapp F x) (F x) ≡ corrupt h ksec kapp x
vdiff-pointwise {k} P i₀ Pi₀ h ksec kapp F x =
  trans (orFin-cong k step1)
        (trans (orFin-∧ k P (corrupt h ksec kapp x))
               (cong (_∧ corrupt h ksec kapp x) (orFin-true-at k P i₀ Pi₀)))
  where
    step1 : (i : Fin k) →
            lookup (lockedSet P h ksec kapp F x) i xor lookup (F x) i
            ≡ P i ∧ corrupt h ksec kapp x
    step1 i =
      trans (cong (_xor lookup (F x) i)
                  (lookup∘tabulate
                    (λ j → lookup (F x) j xor (P j ∧ corrupt h ksec kapp x)) i))
            (xorCancelL (lookup (F x) i) (P i ∧ corrupt h ksec kapp x))

------------------------------------------------------------------------
--  Prove joint corruption equals single-cone OCR for
--  every nonempty protected set, independent of its membership and size.

mocr-set :
  (P : Fin k → Bool) (i₀ : Fin k) → P i₀ ≡ true →
  (h : ℕ) (ksec kapp : Vec Bool n) (F : Vec Bool n → Vec Bool k) →
  mocr (lockedSet P h ksec kapp F) F ≡ OCR h ksec kapp
mocr-set {k} {n} P i₀ Pi₀ h ksec kapp F =
  countT-cong (λ x → vdiff-pointwise P i₀ Pi₀ h ksec kapp F x) (allVecs n)

--  At odd key distance, obtain protected-set-independent 2·C(n,h).
mocr-set-odd :
  (P : Fin k → Bool) (i₀ : Fin k) → P i₀ ≡ true →
  (h : ℕ) (ksec kapp : Vec Bool n) (F : Vec Bool n → Vec Bool k) →
  parity (HD ksec kapp) ≡ true →
  mocr (lockedSet P h ksec kapp F) F ≡ binom n h + binom n h
mocr-set-odd P i₀ Pi₀ h ksec kapp F odd =
  trans (mocr-set P i₀ Pi₀ h ksec kapp F) (OCR-odd h ksec kapp odd)

--  Equate corruption for any two nonempty protected sets.
mocr-set-invariant :
  (P Q : Fin k → Bool) (iP iQ : Fin k) → P iP ≡ true → Q iQ ≡ true →
  (h : ℕ) (ksec kapp : Vec Bool n) (F : Vec Bool n → Vec Bool k) →
  mocr (lockedSet P h ksec kapp F) F ≡ mocr (lockedSet Q h ksec kapp F) F
mocr-set-invariant P Q iP iQ PiP QiQ h ksec kapp F =
  trans (mocr-set P iP PiP h ksec kapp F)
        (sym (mocr-set Q iQ QiQ h ksec kapp F))

------------------------------------------------------------------------
--  Identify lockedVec j with lockedSet (λ i → does (i ≟ j)),
--  embedding designated-output locking as a singleton.

--  Reassociate shared perturbation from (v xor ps) xor pp
--  to v xor (ps xor pp).
private
  g≡xorδ : (v ps pp : Bool) → (v xor ps) xor pp ≡ v xor (ps xor pp)
  g≡xorδ v ps pp = xor-assoc v ps pp

lockedVec-is-lockedSet :
  (j : Fin k) (h : ℕ) (ksec kapp : Vec Bool n)
  (F : Vec Bool n → Vec Bool k) (x : Vec Bool n) →
  lockedVec j h ksec kapp F x ≡ lockedSet (λ i → does (i ≟ j)) h ksec kapp F x
lockedVec-is-lockedSet {k} j h ksec kapp F x =
  trans (sym (tabulate∘lookup (lockedVec j h ksec kapp F x)))
        (tabulate-cong pointwise)
  where
    δ : Bool
    δ = corrupt h ksec kapp x
    pointwise : (i : Fin k) →
      lookup (lockedVec j h ksec kapp F x) i
      ≡ lookup (F x) i xor (does (i ≟ j) ∧ δ)
    pointwise i with i ≟ j
    ... | yes refl =
          trans (lookup∘updateAt j (F x))
                (g≡xorδ (lookup (F x) j) (prot h ksec x) (prot h kapp x))
    ... | no  i≢j =
          trans (lookup∘updateAt′ i j i≢j (F x))
                (sym (xor-identityʳ (lookup (F x) i)))

------------------------------------------------------------------------
--  Connect the actual locked-multi-set circuit to the
--  set-vector specification and its exact single-cone OCR.

--  Show EfficientLockMulti's circuit implements lockedSet.
locked-multi-set-denotes :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (P : Fin k → Bool) (hF : Fin (suc n)) (ksec kapp x : Vec Bool n) →
  ⟦ locked-multi-set CF P hF ksec kapp ⟧ x ≡ lockedSet P (toℕ hF) ksec kapp F x
locked-multi-set-denotes CF F cf-ok P hF ksec kapp x =
  locked-multi-set-correct CF F cf-ok P hF ksec kapp x

--  For every nonempty protected set, prove the certified
--  circuit's output vector differs on exactly OCR inputs.
mocr-locked-multi-set :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (P : Fin k → Bool) (i₀ : Fin k) → P i₀ ≡ true →
  (hF : Fin (suc n)) (ksec kapp : Vec Bool n) →
  mocr (λ x → ⟦ locked-multi-set CF P hF ksec kapp ⟧ x) F ≡ OCR (toℕ hF) ksec kapp
mocr-locked-multi-set {n} CF F cf-ok P i₀ Pi₀ hF ksec kapp =
  trans (countT-cong (λ x → cong (λ u → vdiffF u (F x))
                                 (locked-multi-set-denotes CF F cf-ok P hF ksec kapp x))
                     (allVecs n))
        (mocr-set P i₀ Pi₀ (toℕ hF) ksec kapp F)

------------------------------------------------------------------------
--  Handle separate key cubes per output. Each output
--  then has its own δᵢ set, and joint corruption
--  counts their union. Characterise that union exactly
--  and bound it by Σᵢ OCRᵢ, attaining equality for
--  disjoint sets. Shared keys collapse the union to
--  one set; distinct sets can enlarge it but never exceed the sum.

--  Define finite summation on Fin k and its monotonicity law.
sumFin : (k : ℕ) → (Fin k → ℕ) → ℕ
sumFin zero    g = 0
sumFin (suc k) g = g fz + sumFin k (λ i → g (fs i))

sumFin-mono : (k : ℕ) (g h : Fin k → ℕ) → (∀ i → g i ≤ h i) →
              sumFin k g ≤ sumFin k h
sumFin-mono zero    g h le = ≤-refl
sumFin-mono (suc k) g h le =
  +-mono-≤ (le fz) (sumFin-mono k (λ i → g (fs i)) (λ i → h (fs i)) (λ i → le (fs i)))

--  Bound the count of a finite OR by the sum of individual counts.
countT-orFin-≤-sum :
  (k : ℕ) (q : Fin k → (Vec Bool n → Bool)) (xs : List (Vec Bool n)) →
  countT (λ x → orFin k (λ i → q i x)) xs ≤ sumFin k (λ i → countT (q i) xs)
countT-orFin-≤-sum zero    q xs = ≤-reflexive (countT-false xs)
countT-orFin-≤-sum (suc k) q xs =
  ≤-trans (countT-∨-≤ (q fz) (λ x → orFin k (λ i → q (fs i) x)) xs)
          (+-mono-≤ ≤-refl (countT-orFin-≤-sum k (λ i → q (fs i)) xs))

--  Assign each protected output its own key cube.
lockedSetK : (P : Fin k → Bool) (hs : Fin k → ℕ)
             (ksecs kapps : Fin k → Vec Bool n)
             (F : Vec Bool n → Vec Bool k) → Vec Bool n → Vec Bool k
lockedSetK {k} P hs ksecs kapps F x =
  tabulate (λ i → lookup (F x) i xor (P i ∧ corrupt (hs i) (ksecs i) (kapps i) x))

vdiff-pointwiseK :
  (P : Fin k → Bool) (hs : Fin k → ℕ) (ksecs kapps : Fin k → Vec Bool n)
  (F : Vec Bool n → Vec Bool k) (x : Vec Bool n) →
  vdiffF (lockedSetK P hs ksecs kapps F x) (F x)
  ≡ orFin k (λ i → P i ∧ corrupt (hs i) (ksecs i) (kapps i) x)
vdiff-pointwiseK {k} P hs ksecs kapps F x = orFin-cong k step1
  where
    step1 : (i : Fin k) →
            lookup (lockedSetK P hs ksecs kapps F x) i xor lookup (F x) i
            ≡ P i ∧ corrupt (hs i) (ksecs i) (kapps i) x
    step1 i =
      trans (cong (_xor lookup (F x) i)
                  (lookup∘tabulate
                    (λ j → lookup (F x) j xor (P j ∧ corrupt (hs j) (ksecs j) (kapps j) x)) i))
            (xorCancelL (lookup (F x) i) (P i ∧ corrupt (hs i) (ksecs i) (kapps i) x))

--  Identify joint corruption exactly with the union count of δᵢ sets.
mocr-setK-char :
  (P : Fin k → Bool) (hs : Fin k → ℕ) (ksecs kapps : Fin k → Vec Bool n)
  (F : Vec Bool n → Vec Bool k) →
  mocr (lockedSetK P hs ksecs kapps F) F
  ≡ countT (λ x → orFin k (λ i → P i ∧ corrupt (hs i) (ksecs i) (kapps i) x)) (allVecs n)
mocr-setK-char {k} {n} P hs ksecs kapps F =
  countT-cong (λ x → vdiff-pointwiseK P hs ksecs kapps F x) (allVecs n)

--  Bound joint corruption by summed per-output OCRs;
--  shared-key mocr-set gives the opposite single-set extreme.
mocr-setK-bound :
  (P : Fin k → Bool) (hs : Fin k → ℕ) (ksecs kapps : Fin k → Vec Bool n)
  (F : Vec Bool n → Vec Bool k) →
  mocr (lockedSetK P hs ksecs kapps F) F
  ≤ sumFin k (λ i → OCR (hs i) (ksecs i) (kapps i))
mocr-setK-bound {k} {n} P hs ksecs kapps F =
  ≤-trans (≤-reflexive (mocr-setK-char P hs ksecs kapps F))
          (≤-trans (countT-orFin-≤-sum k
                      (λ i x → P i ∧ corrupt (hs i) (ksecs i) (kapps i) x) (allVecs n))
                   (sumFin-mono k _ _ perI))
  where
    perI : (i : Fin k) →
           countT (λ x → P i ∧ corrupt (hs i) (ksecs i) (kapps i) x) (allVecs n)
           ≤ OCR (hs i) (ksecs i) (kapps i)
    perI i = countT-∧-≤ʳ (λ _ → P i) (corrupt (hs i) (ksecs i) (kapps i)) (allVecs n)

------------------------------------------------------------------------
--  Attain the sum when all δ sets are pairwise disjoint,
--  for example with suitably separated keys and all outputs protected.

private
  --  Replace disjoint OR by XOR to obtain an exact count.
  ∨≡xor : (a b : Bool) → (a ∧ b) ≡ false → (a ∨ b) ≡ (a xor b)
  ∨≡xor false b _ = refl
  ∨≡xor true  false _ = refl
  ∨≡xor true  true  ()

  --  Preserve disjointness from a predicate through the OR
  --  of a family disjoint from it memberwise.
  orFin-⊥ : (p : Vec Bool n → Bool) (k : ℕ) (q : Fin k → (Vec Bool n → Bool)) →
            (∀ i x → (p x ∧ q i x) ≡ false) → (x : Vec Bool n) →
            (p x ∧ orFin k (λ i → q i x)) ≡ false
  orFin-⊥ p zero    q dis x = ∧-zeroʳ (p x)
  orFin-⊥ p (suc k) q dis x =
    trans (∧-distribˡ-∨ (p x) (q fz x) (orFin k (λ i → q (fs i) x)))
          (cong₂ _∨_ (dis fz x) (orFin-⊥ p k (λ i → q (fs i)) (λ i → dis (fs i)) x))

--  Count a pairwise-disjoint finite OR as the sum of its members' counts.
countT-orFin-disjoint :
  (k : ℕ) (q : Fin k → (Vec Bool n → Bool)) →
  (∀ i j → i ≢ j → ∀ x → (q i x ∧ q j x) ≡ false) →
  countT (λ x → orFin k (λ i → q i x)) (allVecs n)
  ≡ sumFin k (λ i → countT (q i) (allVecs n))
countT-orFin-disjoint {n} zero    q pd = countT-false (allVecs n)
countT-orFin-disjoint {n} (suc k) q pd =
  trans (countT-cong (λ x → ∨≡xor (q fz x) (orFin k (λ i → q (fs i) x)) (headDisj x))
                     (allVecs n))
        (trans (countT-xor-disjoint (q fz) (λ x → orFin k (λ i → q (fs i) x)) headDisj (allVecs n))
               (cong (countT (q fz) (allVecs n) +_)
                     (countT-orFin-disjoint k (λ i → q (fs i))
                       (λ i j i≢j → pd (fs i) (fs j) (λ e → i≢j (fs-injective e))))))
  where
    fs-injective : {i j : Fin k} → fs i ≡ fs j → i ≡ j
    fs-injective refl = refl
    headDisj : (x : Vec Bool n) → (q fz x ∧ orFin k (λ i → q (fs i) x)) ≡ false
    headDisj = orFin-⊥ (q fz) k (λ i → q (fs i)) (λ i → pd fz (fs i) (λ ()))

--  For disjoint δ sets and all outputs locked, prove
--  joint corruption equals Σᵢ OCRᵢ.
mocr-setK-disjoint :
  (hs : Fin k → ℕ) (ksecs kapps : Fin k → Vec Bool n)
  (F : Vec Bool n → Vec Bool k) →
  (∀ i j → i ≢ j → ∀ x →
     (corrupt (hs i) (ksecs i) (kapps i) x ∧ corrupt (hs j) (ksecs j) (kapps j) x) ≡ false) →
  mocr (lockedSetK (λ _ → true) hs ksecs kapps F) F
  ≡ sumFin k (λ i → OCR (hs i) (ksecs i) (kapps i))
mocr-setK-disjoint {k} {n} hs ksecs kapps F disj =
  trans (mocr-setK-char (λ _ → true) hs ksecs kapps F)
        (countT-orFin-disjoint k (λ i x → corrupt (hs i) (ksecs i) (kapps i) x) disj)

------------------------------------------------------------------------
--  Link locked-multi-setK to lockedSetK so the union
--  characterisation and subadditive bound concern the
--  actual circuit rather than only its specification.

--  Realise lockedSetK with hs = toℕ ∘ hsf. This
--  is the circuit-correctness lemma, since corrupt
--  definitionally equals prot ksec ⊕ prot kapp.
locked-multi-setK-denotes :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (P : Fin k → Bool) (hsf : Fin k → Fin (suc n))
  (ksecs kapps : Fin k → Vec Bool n) (x : Vec Bool n) →
  ⟦ locked-multi-setK CF P hsf ksecs kapps ⟧ x
  ≡ lockedSetK P (λ i → toℕ (hsf i)) ksecs kapps F x
locked-multi-setK-denotes CF F cf-ok P hsf ksecs kapps x =
  locked-multi-setK-correct CF F cf-ok P hsf ksecs kapps x

--  Bound the verified distinct-key circuit by Σᵢ OCRᵢ
--  corrupted inputs. Together with shared-key
--  mocr-locked-multi-set's single OCR, both regimes
--  now have circuit-to-metric certification.
mocr-locked-multi-setK-bound :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (P : Fin k → Bool) (hsf : Fin k → Fin (suc n)) (ksecs kapps : Fin k → Vec Bool n) →
  mocr (λ x → ⟦ locked-multi-setK CF P hsf ksecs kapps ⟧ x) F
  ≤ sumFin k (λ i → OCR (toℕ (hsf i)) (ksecs i) (kapps i))
mocr-locked-multi-setK-bound {n} {k} CF F cf-ok P hsf ksecs kapps =
  ≤-trans (≤-reflexive
            (countT-cong (λ x → cong (λ u → vdiffF u (F x))
                               (locked-multi-setK-denotes CF F cf-ok P hsf ksecs kapps x))
                         (allVecs n)))
          (mocr-setK-bound P (λ i → toℕ (hsf i)) ksecs kapps F)
