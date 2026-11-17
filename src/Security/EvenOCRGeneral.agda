------------------------------------------------------------------------
--  Complete even-distance OCR by relabelling general keys.
--  EvenOCR counts intersection in contiguous agreement/disagreement
--  form. For arbitrary distance 2·e, preserve inter under
--  XOR shift to (0,k⊕k') and coordinate sorting of the
--  remaining key. Both transformations preserve enumeration
--  counts. Sorting requires two-target g h₁ h₂ v, counting
--  wt x = h₁ and HD x v = h₂, because a single-target
--  equality cannot pass a fixed coordinate. Its recurrence
--  supports adjacent swaps that move true disagreement bits
--  to the end. Use --safe --without-K and no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.EvenOCRGeneral where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _∸_; _≡ᵇ_; _≤_; z≤n; s≤s)
open import Data.Nat.Properties
  using (+-comm; +-assoc; +-identityʳ; +-suc; m+n∸n≡m; m∸n+n≡m; +-∸-assoc;
         ≡-irrelevant; m≤n⇒m≤1+n)
open import Data.Bool using (Bool; true; false; _∧_; _xor_; not; if_then_else_)
open import Data.Bool.Properties using (∧-zeroʳ; ∧-comm; xor-identityʳ)
open import Data.Vec using (Vec; []; _∷_; _++_; replicate)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst)
open import Relation.Binary.PropositionalEquality.Properties using (subst-subst)

open import SFLL.HammingDistance using (HD; b2n; xor-self)
open import Util.Counting
  using (countT; allVecs; split-count; countT-cong; countT-false; binom; mid4)
open import Security.OCR using (inter; OCR; OCR-incl-excl)
open import Security.EvenOCR using (inter-normal-even)

private
  variable
    n m : ℕ

------------------------------------------------------------------------
--  Count true bits as weight and equate it with HD to the zero vector.

wt : Vec Bool n → ℕ
wt []       = 0
wt (x ∷ xs) = b2n x + wt xs

------------------------------------------------------------------------
--  Define g h₁ h₂ v as the number of x with weight h₁
--  and HD x v = h₂. At v = 0 it counts the intersection
--  of spheres with radii h₁ and h₂.

g : ℕ → ℕ → Vec Bool n → ℕ
g {n} h₁ h₂ v = countT (λ x → (wt x ≡ᵇ h₁) ∧ (HD x v ≡ᵇ h₂)) (allVecs n)

--  Split the leading input and key bits. Both resulting
--  counts retain tail key v', shifting targets according
--  to agreement with the leading key bit b.
g-split : (h₁ h₂ : ℕ) (b : Bool) (v' : Vec Bool m) →
          g h₁ h₂ (b ∷ v')
          ≡ countT (λ x → (wt x ≡ᵇ h₁) ∧ ((b2n b + HD x v') ≡ᵇ h₂)) (allVecs m)
          + countT (λ x → (suc (wt x) ≡ᵇ h₁) ∧ ((b2n (not b) + HD x v') ≡ᵇ h₂)) (allVecs m)
g-split h₁ h₂ b v' =
  split-count (λ x → (wt x ≡ᵇ h₁) ∧ (HD x (b ∷ v') ≡ᵇ h₂))

------------------------------------------------------------------------
--  Swap the first two key coordinates without changing
--  the count. Two leading-bit splits give four terms;
--  false/true and true/false exchange places, preserving
--  the sum by the middle-four identity.

--  Expand both leading input bits in one step.
double-split : (P : Vec Bool (suc (suc m)) → Bool) →
  countT P (allVecs (suc (suc m)))
  ≡ (countT (λ x → P (false ∷ false ∷ x)) (allVecs m)
     + countT (λ x → P (false ∷ true ∷ x)) (allVecs m))
  + (countT (λ x → P (true ∷ false ∷ x)) (allVecs m)
     + countT (λ x → P (true ∷ true ∷ x)) (allVecs m))
double-split P =
  trans (split-count P)
        (cong₂ _+_ (split-count (λ x → P (false ∷ x)))
                   (split-count (λ x → P (true ∷ x))))

g-swap-head : (h₁ h₂ : ℕ) (r : Vec Bool m) →
              g h₁ h₂ (false ∷ true ∷ r) ≡ g h₁ h₂ (true ∷ false ∷ r)
g-swap-head {m = m} h₁ h₂ r =
  trans (double-split (λ x → (wt x ≡ᵇ h₁) ∧ (HD x (false ∷ true ∷ r) ≡ᵇ h₂)))
  (trans (mid4 A B C D)
         (sym (double-split (λ x → (wt x ≡ᵇ h₁) ∧ (HD x (true ∷ false ∷ r) ≡ᵇ h₂)))))
  where
    A = countT (λ x → (wt x ≡ᵇ h₁) ∧ (suc (HD x r) ≡ᵇ h₂)) (allVecs m)
    B = countT (λ x → (suc (wt x) ≡ᵇ h₁) ∧ (HD x r ≡ᵇ h₂)) (allVecs m)
    C = countT (λ x → (suc (wt x) ≡ᵇ h₁) ∧ (suc (suc (HD x r)) ≡ᵇ h₂)) (allVecs m)
    D = countT (λ x → (suc (suc (wt x)) ≡ᵇ h₁) ∧ (suc (HD x r) ≡ᵇ h₂)) (allVecs m)

------------------------------------------------------------------------
--  Lift equality for tail keys w,w' through fixed prefix
--  bit b. Quantification over every pair of targets
--  enables this step, unlike a single-target count.

--  Preserve count equality when shifting the HD target
--  by s, stepping it down until the zero-equality boundary.
lift-count : (W : ℕ → Bool) (s h₂ : ℕ) (w w' : Vec Bool m) →
             (∀ j → countT (λ x → W (wt x) ∧ (HD x w ≡ᵇ j)) (allVecs m)
                  ≡ countT (λ x → W (wt x) ∧ (HD x w' ≡ᵇ j)) (allVecs m)) →
             countT (λ x → W (wt x) ∧ ((s + HD x w) ≡ᵇ h₂)) (allVecs m)
           ≡ countT (λ x → W (wt x) ∧ ((s + HD x w') ≡ᵇ h₂)) (allVecs m)
lift-count W zero    h₂       w w' hyp = hyp h₂
lift-count W (suc s) zero     w w' hyp = refl
lift-count W (suc s) (suc h₂) w w' hyp = lift-count W s h₂ w w' hyp

g-lift : (b : Bool) (h₁ h₂ : ℕ) (w w' : Vec Bool m) →
         (∀ j₁ j₂ → g j₁ j₂ w ≡ g j₁ j₂ w') →
         g h₁ h₂ (b ∷ w) ≡ g h₁ h₂ (b ∷ w')
g-lift {m = m} b h₁ h₂ w w' gh =
  trans (g-split h₁ h₂ b w)
  (trans (cong₂ _+_ c0 c1)
         (sym (g-split h₁ h₂ b w')))
  where
    c0 : countT (λ x → (wt x ≡ᵇ h₁) ∧ ((b2n b + HD x w) ≡ᵇ h₂)) (allVecs m)
       ≡ countT (λ x → (wt x ≡ᵇ h₁) ∧ ((b2n b + HD x w') ≡ᵇ h₂)) (allVecs m)
    c0 = lift-count (λ z → z ≡ᵇ h₁) (b2n b) h₂ w w' (λ j → gh h₁ j)
    --  Read the successor-weight conjunct as g (h₁∸1),
    --  with an empty case when h₁ = 0.
    c1hyp : (h : ℕ) → ∀ j → countT (λ x → (suc (wt x) ≡ᵇ h) ∧ (HD x w ≡ᵇ j)) (allVecs m)
                          ≡ countT (λ x → (suc (wt x) ≡ᵇ h) ∧ (HD x w' ≡ᵇ j)) (allVecs m)
    c1hyp zero    j = refl
    c1hyp (suc h) j = gh h j
    c1 : countT (λ x → (suc (wt x) ≡ᵇ h₁) ∧ ((b2n (not b) + HD x w) ≡ᵇ h₂)) (allVecs m)
       ≡ countT (λ x → (suc (wt x) ≡ᵇ h₁) ∧ ((b2n (not b) + HD x w') ≡ᵇ h₂)) (allVecs m)
    c1 = lift-count (λ z → suc z ≡ᵇ h₁) (b2n (not b)) h₂ w w' (c1hyp h₁)

------------------------------------------------------------------------
--  Sort by bubbling true coordinates to the end. g-swap
--  handles adjacent transpositions, g-rotate moves past
--  a block, and g-lift composes them under fixed coordinates.

--  Swap arbitrary first and second key bits.
g-swap : (a b : Bool) (r : Vec Bool m) (h₁ h₂ : ℕ) →
         g h₁ h₂ (a ∷ b ∷ r) ≡ g h₁ h₂ (b ∷ a ∷ r)
g-swap false false r h₁ h₂ = refl
g-swap false true  r h₁ h₂ = g-swap-head h₁ h₂ r
g-swap true  false r h₁ h₂ = sym (g-swap-head h₁ h₂ r)
g-swap true  true  r h₁ h₂ = refl

--  Append a with snoc at definitional length suc n,
--  keeping tail lengths aligned for g-lift.
snoc : Vec Bool n → Bool → Vec Bool (suc n)
snoc []       a = a ∷ []
snoc (x ∷ xs) a = x ∷ snoc xs a

--  Rotate a leading bit to the end of the vector.
g-rotate : (a : Bool) (w : Vec Bool m) (h₁ h₂ : ℕ) →
           g h₁ h₂ (a ∷ w) ≡ g h₁ h₂ (snoc w a)
g-rotate a []        h₁ h₂ = refl
g-rotate a (b ∷ w'') h₁ h₂ =
  trans (g-swap a b w'' h₁ h₂)
        (g-lift b h₁ h₂ (a ∷ w'') (snoc w'' a) (λ j₁ j₂ → g-rotate a w'' j₁ j₂))

--  Build the false-then-true normal form by retaining
--  a leading false or rotating a leading true to the back.
sortV : Vec Bool n → Vec Bool n
sortV []          = []
sortV (false ∷ v) = false ∷ sortV v
sortV (true  ∷ v) = snoc (sortV v) true

--  Preserve the two-target count when sorting the key.
g-sort : (v : Vec Bool n) (h₁ h₂ : ℕ) → g h₁ h₂ v ≡ g h₁ h₂ (sortV v)
g-sort []           h₁ h₂ = refl
g-sort (false ∷ v') h₁ h₂ =
  g-lift false h₁ h₂ v' (sortV v') (λ j₁ j₂ → g-sort v' j₁ j₂)
g-sort (true ∷ v')  h₁ h₂ =
  trans (g-lift true h₁ h₂ v' (sortV v') (λ j₁ j₂ → g-sort v' j₁ j₂))
        (g-rotate true (sortV v') h₁ h₂)

------------------------------------------------------------------------
--  Relate g to inter and evaluate contiguous normal forms.

--  Identify HD from the all-false key with weight.
HD-zeros : (x : Vec Bool n) → HD x (replicate n false) ≡ wt x
HD-zeros []       = refl
HD-zeros (x ∷ xs) = cong₂ _+_ (cong b2n (xor-identityʳ x)) (HD-zeros xs)

--  Interpret g h h as intersection against an all-false secret.
g-is-inter : (h : ℕ) (v : Vec Bool n) → g h h v ≡ inter h (replicate n false) v
g-is-inter {n = n} h v =
  countT-cong (λ x → cong (λ z → (z ≡ᵇ h) ∧ (HD x v ≡ᵇ h)) (sym (HD-zeros x)))
              (allVecs n)

--  Distribute replicate across concatenation.
repl-++ : (p q : ℕ) (b : Bool) →
          replicate (p + q) b ≡ replicate p b ++ replicate q b
repl-++ zero    q b = refl
repl-++ (suc p) q b = cong (b ∷_) (repl-++ p q b)

--  Evaluate contiguous intersection with EvenOCR's even-distance
--  Vandermonde result.
g-even-contig : (p e h : ℕ) → e ≤ h →
  g h h (replicate p false ++ replicate (2 * e) true)
  ≡ binom p (h ∸ e) * binom (2 * e) e
g-even-contig p e h e≤h =
  trans (g-is-inter h (replicate p false ++ replicate (2 * e) true))
  (trans (cong (λ z → inter h z (replicate p false ++ replicate (2 * e) true))
               (repl-++ p (2 * e) false))
         (inter-normal-even p e h e≤h))

------------------------------------------------------------------------
--  Preserve the count under a common XOR shift of inputs
--  and keys, allowing the secret key to become zero.

xorVec : Vec Bool n → Vec Bool n → Vec Bool n
xorVec []       []       = []
xorVec (s ∷ ss) (x ∷ xs) = (s xor x) ∷ xorVec ss xs

--  Cancel the shared shift s at each coordinate.
xor-shuffle : (s x k : Bool) → (s xor x) xor (s xor k) ≡ x xor k
xor-shuffle false x     k     = refl
xor-shuffle true  false false = refl
xor-shuffle true  false true  = refl
xor-shuffle true  true  false = refl
xor-shuffle true  true  true  = refl

--  Keep HD unchanged when XOR-shifting both arguments by s.
HD-xorVec : (s x k : Vec Bool n) → HD (xorVec s x) (xorVec s k) ≡ HD x k
HD-xorVec []       []       []       = refl
HD-xorVec (s ∷ ss) (x ∷ xs) (k ∷ ks) =
  cong₂ _+_ (cong b2n (xor-shuffle s x k)) (HD-xorVec ss xs ks)

--  XOR a key with itself to obtain the all-false vector.
xorVec-self : (k : Vec Bool n) → xorVec k k ≡ replicate n false
xorVec-self []       = refl
xorVec-self (k ∷ ks) = cong₂ _∷_ (xor-self k) (xorVec-self ks)

--  Preserve allVecs counts under input relabelling x ↦ s ⊕ x.
countT-xorVec : (s : Vec Bool n) (P : Vec Bool n → Bool) →
                countT (λ x → P (xorVec s x)) (allVecs n) ≡ countT P (allVecs n)
countT-xorVec []            P = refl
countT-xorVec (false ∷ ss) P =
  trans (split-count (λ x → P (xorVec (false ∷ ss) x)))
  (trans (cong₂ _+_ (countT-xorVec ss (λ y → P (false ∷ y)))
                    (countT-xorVec ss (λ y → P (true ∷ y))))
         (sym (split-count P)))
countT-xorVec (true ∷ ss) P =
  trans (split-count (λ x → P (xorVec (true ∷ ss) x)))
  (trans (cong₂ _+_ (countT-xorVec ss (λ y → P (true ∷ y)))
                    (countT-xorVec ss (λ y → P (false ∷ y))))
  (trans (+-comm (countT (λ y → P (true ∷ y)) (allVecs _))
                 (countT (λ y → P (false ∷ y)) (allVecs _)))
         (sym (split-count P))))

--  Apply the shift that sends the secret key to zero.
inter-xorshift : (h : ℕ) (k k' : Vec Bool n) →
                 inter h k k' ≡ inter h (replicate n false) (xorVec k k')
inter-xorshift {n = n} h k k' =
  trans (countT-cong
           (λ x → cong₂ (λ a b → (a ≡ᵇ h) ∧ (b ≡ᵇ h))
                        (sym (HD-xorVec k x k)) (sym (HD-xorVec k x k')))
           (allVecs n))
  (trans (countT-xorVec k (λ y → (HD y (xorVec k k) ≡ᵇ h) ∧ (HD y (xorVec k k') ≡ᵇ h)))
         (cong (λ z → inter h z (xorVec k k')) (xorVec-self k)))

------------------------------------------------------------------------
--  Assemble the general even-distance intersection/OCR theorem
--  from inter-xorshift and g-sort, closing the connection
--  to inter-normal-even. The remaining new step is
--  sortV-normal, identifying the actual sorted vector
--  with the contiguous form. Transport dependent lengths
--  with subst (Vec Bool); Nat's UIP via ≡-irrelevant
--  identifies the different length proofs.

--  Bound weight by vector length and identify XOR weight with HD.
wt≤len : (v : Vec Bool n) → wt v ≤ n
wt≤len []           = z≤n
wt≤len (false ∷ v') = m≤n⇒m≤1+n (wt≤len v')
wt≤len (true  ∷ v') = s≤s (wt≤len v')

wt-xorVec : (k k' : Vec Bool n) → wt (xorVec k k') ≡ HD k k'
wt-xorVec []        []         = refl
wt-xorVec (k ∷ ks) (k' ∷ ks') = cong (b2n (k xor k') +_) (wt-xorVec ks ks')

--  Handle length casts, proof irrelevance, and reflexive casts.
cast : {p q : ℕ} → p ≡ q → Vec Bool p → Vec Bool q
cast = subst (Vec Bool)

cast-irrel : {p q : ℕ} (e₁ e₂ : p ≡ q) (xs : Vec Bool p) → cast e₁ xs ≡ cast e₂ xs
cast-irrel e₁ e₂ xs = cong (λ r → cast r xs) (≡-irrelevant e₁ e₂)

cast-refl : {p : ℕ} (e : p ≡ p) (xs : Vec Bool p) → cast e xs ≡ xs
cast-refl e xs = cast-irrel e refl xs

--  Reconcile casts of false-prefixed normal forms whose
--  prefix lengths are propositionally equal but do not reduce identically.
cast-len : {a a' b N : ℕ} (le : a ≡ a') (B : Vec Bool b)
           (e₁ : a + b ≡ N) (e₂ : a' + b ≡ N) →
           cast e₁ (replicate a false ++ B) ≡ cast e₂ (replicate a' false ++ B)
cast-len refl B e₁ e₂ = cast-irrel e₁ e₂ _

--  Identify every length-zero vector with the empty vector.
vec0 : (xs : Vec Bool 0) → xs ≡ []
vec0 [] = refl

--  Commute subst with cons and snoc by matching its equality proof.
cast-∷ : {p q : ℕ} (e : p ≡ q) (x : Bool) (xs : Vec Bool p) →
         x ∷ cast e xs ≡ cast (cong suc e) (x ∷ xs)
cast-∷ refl x xs = refl

cast-snoc : {p q : ℕ} (e : p ≡ q) (a : Bool) (xs : Vec Bool p) →
            snoc (cast e xs) a ≡ cast (cong suc e) (snoc xs a)
cast-snoc refl a xs = refl

--  Extend true^q to true^(suc q) by snoc true.
snoc-repl-true : (q : ℕ) → snoc (replicate q true) true ≡ replicate (suc q) true
snoc-repl-true zero    = refl
snoc-repl-true (suc q) = cong (true ∷_) (snoc-repl-true q)

--  Append true to extend the final true block of false^p true^q.
snoc-NF : (p q : ℕ) →
  snoc (replicate p false ++ replicate q true) true
  ≡ cast (+-suc p q) (replicate p false ++ replicate (suc q) true)
snoc-NF zero    q = trans (snoc-repl-true q) (sym (cast-refl (+-suc zero q) _))
snoc-NF (suc p) q =
  trans (cong (false ∷_) (snoc-NF p q))
  (trans (cast-∷ (+-suc p q) false (replicate p false ++ replicate (suc q) true))
         (cast-irrel (cong suc (+-suc p q)) (+-suc (suc p) q) _))

--  Identify sortV's output exactly with contiguous normal form.
sortV-normal : (v : Vec Bool n) →
  sortV v ≡ cast (m∸n+n≡m (wt≤len v))
                 (replicate (n ∸ wt v) false ++ replicate (wt v) true)
sortV-normal []                       = sym (vec0 _)
sortV-normal {n = suc n'} (false ∷ v') =
  trans (cong (false ∷_) (sortV-normal v'))
  (trans (cast-∷ (m∸n+n≡m (wt≤len v')) false _)
         (cast-len (sym (+-∸-assoc 1 (wt≤len v'))) (replicate (wt v') true)
                   (cong suc (m∸n+n≡m (wt≤len v'))) (m∸n+n≡m (wt≤len (false ∷ v')))))
sortV-normal {n = suc n'} (true ∷ v') =
  trans (cong (λ w → snoc w true) (sortV-normal v'))
  (trans (cast-snoc (m∸n+n≡m (wt≤len v')) true _)
  (trans (cong (cast (cong suc (m∸n+n≡m (wt≤len v')))) (snoc-NF (n' ∸ wt v') (wt v')))
  (trans (subst-subst (+-suc (n' ∸ wt v') (wt v')))
         (cast-irrel (trans (+-suc (n' ∸ wt v') (wt v')) (cong suc (m∸n+n≡m (wt≤len v'))))
                     (m∸n+n≡m (wt≤len (true ∷ v'))) _))))

--  Evaluate g on sortV v by removing the irrelevant
--  length cast and rewriting its weight as 2·e.
g-sortV-even : (v : Vec Bool n) (h e : ℕ) → wt v ≡ 2 * e → e ≤ h →
  g h h (sortV v) ≡ binom (n ∸ 2 * e) (h ∸ e) * binom (2 * e) e
g-sortV-even {n} v h e wv e≤h =
  trans (cong (g h h) (sortV-normal v))
  (trans (g-cast (m∸n+n≡m (wt≤len v)) _)
         (subst (λ w → g h h (replicate (n ∸ w) false ++ replicate w true)
                       ≡ binom (n ∸ 2 * e) (h ∸ e) * binom (2 * e) e)
                (sym wv)
                (g-even-contig (n ∸ 2 * e) e h e≤h)))
  where
    --  Ignore the length cast in g, whose allVecs count returns plain ℕ.
    g-cast : {p q : ℕ} (e₁ : p ≡ q) (xs : Vec Bool p) →
             g h h (cast e₁ xs) ≡ g h h xs
    g-cast refl xs = refl

--  ============================================================================
--  State exact even-distance intersection/OCR for arbitrary key pairs.

inter-even : (h e : ℕ) (k k' : Vec Bool n) → HD k k' ≡ 2 * e → e ≤ h →
  inter h k k' ≡ binom (n ∸ 2 * e) (h ∸ e) * binom (2 * e) e
inter-even {n} h e k k' hd e≤h =
  trans (inter-xorshift h k k')
  (trans (sym (g-is-inter h (xorVec k k')))
  (trans (g-sort (xorVec k k') h h)
         (g-sortV-even (xorVec k k') h e
                       (trans (wt-xorVec k k') hd) e≤h)))

OCR-even : (h e : ℕ) (k k' : Vec Bool n) → HD k k' ≡ 2 * e → e ≤ h →
  OCR h k k' + 2 * (binom (n ∸ 2 * e) (h ∸ e) * binom (2 * e) e)
  ≡ binom n h + binom n h
OCR-even h e k k' hd e≤h =
  trans (cong (λ z → OCR h k k' + 2 * z) (sym (inter-even h e k k' hd e≤h)))
        (OCR-incl-excl h k k')
