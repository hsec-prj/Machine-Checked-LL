------------------------------------------------------------------------
--  Develop GF(2) algebra and characterise confused keys by kernels and cosets.
--  Over Bool, define vector addition, inner products, and matrix application,
--  proving apply-⊕ directly. For the linear leakage oracle k ↦ apply M k,
--  ker-char states apply M k ≡ apply M k′ iff apply M (k ⊕ⱽ k′) ≡ 0.
--  The completeness direction linColl→ker explains every collision by a
--  kernel element. The full confusion set is the affine coset k ⊕ⱽ ker M,
--  with dimension n − rank M and closure expressed by conf-closed. This
--  describes more structure than an existential colliding pair. The
--  co-evolution module Coevo.LinearKernel uses such a pair in the generic
--  no-recovery argument; this file contains only oracle-independent
--  mathematics. It is --safe --without-K with no postulates. Define zeroⱽ
--  recursively to avoid changes to Data.Vec.replicate across stdlib versions.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.LinearKernel where

open import Data.Bool using (Bool; true; false; _xor_; _∧_)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Vec using (Vec; []; _∷_; map; zipWith; head; tail)
open import Function.Bundles using (_⇔_; mk⇔)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

private
  variable
    n m : ℕ

------------------------------------------------------------------------
--  Define the basic GF(2) linear-algebra operations.

--  Add vectors coordinatewise by XOR.
_⊕ⱽ_ : Vec Bool n → Vec Bool n → Vec Bool n
_⊕ⱽ_ = zipWith _xor_

--  Compute the GF(2) inner product recursively, avoiding foldr API variation.
dot : Vec Bool n → Vec Bool n → Bool
dot []       []       = false
dot (a ∷ as) (b ∷ bs) = (a ∧ b) xor dot as bs

--  Apply a matrix by collecting its m row-dot-key products.
apply : Vec (Vec Bool n) m → Vec Bool n → Vec Bool m
apply M k = map (λ row → dot row k) M

--  Use a local recursive zero vector to avoid Data.Vec.replicate API drift.
zeroⱽ : (n : ℕ) → Vec Bool n
zeroⱽ zero    = []
zeroⱽ (suc n) = false ∷ zeroⱽ n

------------------------------------------------------------------------
--  Prove the required Boolean GF(2) identities by exhaustive cases.

--  Distribute conjunction over XOR on the left.
∧-xor-distribˡ : (r a b : Bool) → r ∧ (a xor b) ≡ (r ∧ a) xor (r ∧ b)
∧-xor-distribˡ false a b = refl
∧-xor-distribˡ true  a b = refl

--  Rearrange four XOR terms.
xor-middle : (A B C D : Bool) → (A xor B) xor (C xor D) ≡ (A xor C) xor (B xor D)
xor-middle false false false false = refl
xor-middle false false false true  = refl
xor-middle false false true  false = refl
xor-middle false false true  true  = refl
xor-middle false true  false false = refl
xor-middle false true  false true  = refl
xor-middle false true  true  false = refl
xor-middle false true  true  true  = refl
xor-middle true  false false false = refl
xor-middle true  false false true  = refl
xor-middle true  false true  false = refl
xor-middle true  false true  true  = refl
xor-middle true  true  false false = refl
xor-middle true  true  false true  = refl
xor-middle true  true  true  false = refl
xor-middle true  true  true  true  = refl

xor-self-b : (a : Bool) → a xor a ≡ false
xor-self-b false = refl
xor-self-b true  = refl

xor-identityʳ-b : (a : Bool) → a xor false ≡ a
xor-identityʳ-b false = refl
xor-identityʳ-b true  = refl

xor-zero→eq-b : (a b : Bool) → a xor b ≡ false → a ≡ b
xor-zero→eq-b false false _ = refl
xor-zero→eq-b true  true  _ = refl
xor-zero→eq-b false true ()
xor-zero→eq-b true  false ()

xor-cancelˡ-b : (k v : Bool) → k xor v ≡ k → v ≡ false
xor-cancelˡ-b false v     hyp = hyp
xor-cancelˡ-b true  false _   = refl
xor-cancelˡ-b true  true  ()

------------------------------------------------------------------------
--  Lift the Boolean identities to vectors by structural induction.

vec-xor-self : (v : Vec Bool n) → v ⊕ⱽ v ≡ zeroⱽ n
vec-xor-self []       = refl
vec-xor-self (x ∷ xs) = cong₂ _∷_ (xor-self-b x) (vec-xor-self xs)

vec-xor-identityʳ : (v : Vec Bool n) → v ⊕ⱽ zeroⱽ n ≡ v
vec-xor-identityʳ []       = refl
vec-xor-identityʳ (x ∷ xs) = cong₂ _∷_ (xor-identityʳ-b x) (vec-xor-identityʳ xs)

vec-xor-zero→eq : (u v : Vec Bool n) → u ⊕ⱽ v ≡ zeroⱽ n → u ≡ v
vec-xor-zero→eq []       []       _   = refl
vec-xor-zero→eq (x ∷ xs) (y ∷ ys) hyp =
  cong₂ _∷_ (xor-zero→eq-b x y (cong head hyp)) (vec-xor-zero→eq xs ys (cong tail hyp))

vec-add-cancel : (k v : Vec Bool n) → k ⊕ⱽ v ≡ k → v ≡ zeroⱽ n
vec-add-cancel []       []       _   = refl
vec-add-cancel (x ∷ xs) (y ∷ ys) hyp =
  cong₂ _∷_ (xor-cancelˡ-b x y (cong head hyp)) (vec-add-cancel xs ys (cong tail hyp))

------------------------------------------------------------------------
--  Establish the central linearity property.

--  Prove inner-product bilinearity in its second argument.
dot-⊕ : (r a b : Vec Bool n) → dot r (a ⊕ⱽ b) ≡ dot r a xor dot r b
dot-⊕ []       []       []       = refl
dot-⊕ (r ∷ rs) (a ∷ as) (b ∷ bs) =
  trans (cong₂ _xor_ (∧-xor-distribˡ r a b) (dot-⊕ rs as bs))
        (xor-middle (r ∧ a) (r ∧ b) (dot rs as) (dot rs bs))

--  Show matrix application preserves addition:
--  apply M (a ⊕ⱽ b) ≡ apply M a ⊕ⱽ apply M b.
apply-⊕ : (M : Vec (Vec Bool n) m) (a b : Vec Bool n) →
          apply M (a ⊕ⱽ b) ≡ apply M a ⊕ⱽ apply M b
apply-⊕ []           a b = refl
apply-⊕ (row ∷ rows) a b = cong₂ _∷_ (dot-⊕ row a b) (apply-⊕ rows a b)

------------------------------------------------------------------------
--  Give the exact kernel/coset account of collisions.

--  Define kernel membership and observational collision.
inKer : Vec (Vec Bool n) m → Vec Bool n → Set
inKer {m = m} M v = apply M v ≡ zeroⱽ m

linColl : Vec (Vec Bool n) m → Vec Bool n → Vec Bool n → Set
linColl M k k′ = apply M k ≡ apply M k′

--  Prove completeness: each confused pair has a kernel difference.
linColl→ker : (M : Vec (Vec Bool n) m) (k k′ : Vec Bool n) →
              apply M k ≡ apply M k′ → inKer M (k ⊕ⱽ k′)
linColl→ker M k k′ hyp =
  trans (apply-⊕ M k k′)
        (trans (cong (apply M k ⊕ⱽ_) (sym hyp)) (vec-xor-self (apply M k)))

--  Prove soundness: a kernel difference produces a confused pair.
ker→linColl : (M : Vec (Vec Bool n) m) (k k′ : Vec Bool n) →
              inKer M (k ⊕ⱽ k′) → apply M k ≡ apply M k′
ker→linColl M k k′ hyp =
  vec-xor-zero→eq (apply M k) (apply M k′) (trans (sym (apply-⊕ M k k′)) hyp)

--  Combine the directions: confusion is equivalent to kernel membership
--  of the key difference.
ker-char : (M : Vec (Vec Bool n) m) (k k′ : Vec Bool n) →
           (apply M k ≡ apply M k′) ⇔ inKer M (k ⊕ⱽ k′)
ker-char M k k′ = mk⇔ (linColl→ker M k k′) (ker→linColl M k k′)

--  Establish coset closure: any two members of Conf M k = k ⊕ⱽ ker M
--  differ by a kernel element. ker M is a subspace and Conf M k its coset,
--  with dimension n − rank M.
conf-closed : (M : Vec (Vec Bool n) m) {k k′ k″ : Vec Bool n} →
              linColl M k k′ → linColl M k k″ → inKer M (k′ ⊕ⱽ k″)
conf-closed M p q = linColl→ker M _ _ (trans (sym p) q)
