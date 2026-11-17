------------------------------------------------------------------------
--  Develop an algebra for composing locking corruption.
--  Compose treats a particular two-SFLL cascade; abstract
--  a scheme here to its corruption predicate relative
--  to the locked function. Sequential _⊚_ on one bus
--  uses symmetric difference, as compose-disagree does.
--  Up to pointwise _≈_, Scheme n with idScheme is
--  an elementary abelian 2-group: associativity, commutativity,
--  unit, congruence, and ⊚-self make each element
--  self-inverse. Check the library structures through
--  ⊚-isCommutativeMonoid/⊚-isAbelianGroup and their bundles.
--  Stacked OCR obeys inclusion–exclusion, subadditivity,
--  and disjoint additivity via ocr-⊚-incl-excl/≤/disjoint.
--  Independent-bus _⊗_ requires corruption on both halves
--  and multiplies OCR by countT-prod, the multiplicative
--  homomorphism law ocr-⊗. stack-is-cascade connects
--  abstract SFLL stacking to concrete ocr², while
--  stack-SARLock-≤4 keeps two radius-zero layers within
--  four corrupted inputs at every width. Locking.Functor
--  connects the categorical track to this algebra.
--  Use pointwise equality because function-field equality
--  would require unavailable --safe funext; ocr-cong
--  respects that relation. Add no primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.SchemeAlgebra where

open import Data.Nat using (ℕ; _+_; _*_; _≤_)
open import Data.Nat.Properties using (≤-trans; +-mono-≤)
open import Data.Bool using (Bool; true; false; _xor_; _∧_)
open import Data.Bool.Properties
  using (xor-assoc; xor-comm; xor-identityˡ; xor-identityʳ; xor-same)
open import Data.Product using (_,_)
import Data.Vec as Vec
open Vec using (Vec)
open import Function.Base using (id)
open import Level using (0ℓ)
open import Algebra.Structures
  using (IsMagma; IsSemigroup; IsMonoid; IsCommutativeMonoid; IsGroup; IsAbelianGroup)
open import Algebra.Bundles using (CommutativeMonoid; AbelianGroup)
open import Relation.Binary.Bundles using (Setoid)
open import Relation.Binary.Structures using (IsEquivalence)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong₂; sym; trans)

open import Security.OCR using (corrupt; OCR)
open import Security.SARLock using (OCR-SARLock-≤2)
open import Security.Compose using (ocr²; ocr²≡)
open import Util.Counting
  using (countT; allVecs; countT-cong; countT-false; countT-prod;
         countT-xor-≤; countT-and-xor; countT-xor-disjoint)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Represent a scheme by disagreement with the function it locks.

record Scheme (n : ℕ) : Set where
  constructor mkScheme
  field corruption : Vec Bool n → Bool

open Scheme public

--  Count a scheme's corrupted inputs as its OCR.
ocr : Scheme n → ℕ
ocr {n} s = countT (corruption s) (allVecs n)

--  Compare schemes through pointwise corruption equality, avoiding funext.
_≈_ : Scheme n → Scheme n → Set
s ≈ t = (x : Vec Bool _) → corruption s x ≡ corruption t x

--  Preserve OCR under _≈_.
ocr-cong : {s t : Scheme n} → s ≈ t → ocr s ≡ ocr t
ocr-cong {s = s} {t} eq = countT-cong eq (allVecs _)

------------------------------------------------------------------------
--  Define the scheme-composition operations.

--  Use zero corruption as the identity for _⊚_.
idScheme : Scheme n
idScheme = mkScheme (λ _ → false)

--  Stack locks on one bus by symmetric difference of
--  corruption, matching Compose.compose-disagree.
infixr 5 _⊚_
_⊚_ : Scheme n → Scheme n → Scheme n
s ⊚ t = mkScheme (λ x → corruption s x xor corruption t x)

--  Tensor independent concatenated buses, corrupting
--  exactly when both halves corrupt their respective inputs.
infixr 6 _⊗_
_⊗_ : {p d : ℕ} → Scheme p → Scheme d → Scheme (p + d)
_⊗_ {p} s t =
  mkScheme (λ x → corruption s (Vec.take p x) ∧ corruption t (Vec.drop p x))

------------------------------------------------------------------------
--  Establish the commutative-monoid laws for Scheme,
--  _⊚_, and idScheme modulo _≈_.

⊚-idˡ : (s : Scheme n) → (idScheme ⊚ s) ≈ s
⊚-idˡ s x = xor-identityˡ (corruption s x)

⊚-idʳ : (s : Scheme n) → (s ⊚ idScheme) ≈ s
⊚-idʳ s x = xor-identityʳ (corruption s x)

⊚-comm : (s t : Scheme n) → (s ⊚ t) ≈ (t ⊚ s)
⊚-comm s t x = xor-comm (corruption s x) (corruption t x)

⊚-assoc : (s t u : Scheme n) → ((s ⊚ t) ⊚ u) ≈ (s ⊚ (t ⊚ u))
⊚-assoc s t u x = xor-assoc (corruption s x) (corruption t x) (corruption u x)

⊚-cong : {s s' t t' : Scheme n} → s ≈ s' → t ≈ t' → (s ⊚ t) ≈ (s' ⊚ t')
⊚-cong es et x = cong₂ _xor_ (es x) (et x)

------------------------------------------------------------------------
--  Strengthen the monoid to an elementary abelian 2-group.
--  Stacking any scheme with itself cancels by xor-same;
--  its inverse map is identity and every order divides
--  two. Package the stronger structure in the library's
--  ⊚-isAbelianGroup/schemeAbelianGroup definitions. These
--  are laws of corruption sets under symmetric difference,
--  with no implication about attack resistance.

⊚-self : (s : Scheme n) → (s ⊚ s) ≈ idScheme
⊚-self s x = xor-same (corruption s x)

--  Use equivalence of _≈_ to give fixed-width schemes a setoid.
≈-isEquivalence : IsEquivalence (_≈_ {n})
≈-isEquivalence = record
  { refl  = λ _ → refl
  ; sym   = λ e x → sym (e x)
  ; trans = λ e₁ e₂ x → trans (e₁ x) (e₂ x)
  }

schemeSetoid : (n : ℕ) → Setoid 0ℓ 0ℓ
schemeSetoid n = record
  { Carrier       = Scheme n
  ; _≈_           = _≈_
  ; isEquivalence = ≈-isEquivalence
  }

⊚-isMagma : IsMagma (_≈_ {n}) _⊚_
⊚-isMagma = record { isEquivalence = ≈-isEquivalence ; ∙-cong = ⊚-cong }

⊚-isSemigroup : IsSemigroup (_≈_ {n}) _⊚_
⊚-isSemigroup = record { isMagma = ⊚-isMagma ; assoc = ⊚-assoc }

⊚-isMonoid : IsMonoid (_≈_ {n}) _⊚_ idScheme
⊚-isMonoid = record { isSemigroup = ⊚-isSemigroup ; identity = ⊚-idˡ , ⊚-idʳ }

⊚-isCommutativeMonoid : IsCommutativeMonoid (_≈_ {n}) _⊚_ idScheme
⊚-isCommutativeMonoid = record { isMonoid = ⊚-isMonoid ; comm = ⊚-comm }

--  Choose identity as the inverse operation, expressing ⊚-self.
⊚-isGroup : IsGroup (_≈_ {n}) _⊚_ idScheme id
⊚-isGroup = record
  { isMonoid = ⊚-isMonoid
  ; inverse  = ⊚-self , ⊚-self
  ; ⁻¹-cong  = λ e → e
  }

⊚-isAbelianGroup : IsAbelianGroup (_≈_ {n}) _⊚_ idScheme id
⊚-isAbelianGroup = record { isGroup = ⊚-isGroup ; comm = ⊚-comm }

schemeCommutativeMonoid : (n : ℕ) → CommutativeMonoid 0ℓ 0ℓ
schemeCommutativeMonoid n = record
  { Carrier             = Scheme n
  ; _≈_                 = _≈_
  ; _∙_                 = _⊚_
  ; ε                   = idScheme
  ; isCommutativeMonoid = ⊚-isCommutativeMonoid
  }

schemeAbelianGroup : (n : ℕ) → AbelianGroup 0ℓ 0ℓ
schemeAbelianGroup n = record
  { Carrier        = Scheme n
  ; _≈_            = _≈_
  ; _∙_            = _⊚_
  ; ε              = idScheme
  ; _⁻¹            = id
  ; isAbelianGroup = ⊚-isAbelianGroup
  }

------------------------------------------------------------------------
--  Lift Compose's OCR laws to abstract stacking.

ocr-idScheme : ocr (idScheme {n}) ≡ 0
ocr-idScheme {n} = countT-false (allVecs n)

--  Bound stacked corruption by the sum of its component rates.
ocr-⊚-≤ : (s t : Scheme n) → ocr (s ⊚ t) ≤ ocr s + ocr t
ocr-⊚-≤ {n} s t = countT-xor-≤ (corruption s) (corruption t) (allVecs n)

--  Equate composite OCR plus twice the overlap with the sum.
ocr-⊚-incl-excl :
  (s t : Scheme n) →
  ocr (s ⊚ t) + 2 * countT (λ x → corruption s x ∧ corruption t x) (allVecs n)
  ≡ ocr s + ocr t
ocr-⊚-incl-excl {n} s t = countT-and-xor (corruption s) (corruption t) (allVecs n)

--  Obtain additive OCR for layers with disjoint corrupted inputs.
ocr-⊚-disjoint :
  (s t : Scheme n) →
  (∀ x → (corruption s x ∧ corruption t x) ≡ false) →
  ocr (s ⊚ t) ≡ ocr s + ocr t
ocr-⊚-disjoint {n} s t dis =
  countT-xor-disjoint (corruption s) (corruption t) dis (allVecs n)

------------------------------------------------------------------------
--  Prove tensor OCR multiplies, the homomorphism law into (ℕ,*).

ocr-⊗ : {p d : ℕ} (s : Scheme p) (t : Scheme d) → ocr (s ⊗ t) ≡ ocr s * ocr t
ocr-⊗ {p} s t = countT-prod p (corruption s) (corruption t)

------------------------------------------------------------------------
--  Connect the algebra to SFLL catalogue schemes and cascades.

sfllScheme : (h : ℕ) (ksec kapp : Vec Bool n) → Scheme n
sfllScheme h ksec kapp = mkScheme (corrupt h ksec kapp)

--  Identify an SFLL scheme's abstract OCR with catalogue OCR.
ocr-sfll : (h : ℕ) (ksec kapp : Vec Bool n) →
           ocr (sfllScheme h ksec kapp) ≡ OCR h ksec kapp
ocr-sfll h ksec kapp = refl

--  Recover Compose's two-layer cascade OCR by _⊚_
--  for every locked function f.
stack-is-cascade :
  (h₁ h₂ : ℕ) (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) (f : Vec Bool n → Bool) →
  ocr (sfllScheme h₁ ks₁ kap₁ ⊚ sfllScheme h₂ ks₂ kap₂)
  ≡ ocr² h₁ h₂ ks₁ kap₁ ks₂ kap₂ f
stack-is-cascade h₁ h₂ ks₁ kap₁ ks₂ kap₂ f =
  sym (ocr²≡ h₁ h₂ ks₁ kap₁ ks₂ kap₂ f)

------------------------------------------------------------------------
--  Keep two stacked radius-zero SARLock schemes within
--  four corrupted inputs for every n, preserving the low-corruption regime.

sarScheme : (ksec kapp : Vec Bool n) → Scheme n
sarScheme = sfllScheme 0

stack-SARLock-≤4 : (ks₁ kap₁ ks₂ kap₂ : Vec Bool n) →
                   ocr (sarScheme ks₁ kap₁ ⊚ sarScheme ks₂ kap₂) ≤ 4
stack-SARLock-≤4 ks₁ kap₁ ks₂ kap₂ =
  ≤-trans (ocr-⊚-≤ (sarScheme ks₁ kap₁) (sarScheme ks₂ kap₂))
          (+-mono-≤ (OCR-SARLock-≤2 ks₁ kap₁) (OCR-SARLock-≤2 ks₂ kap₂))

------------------------------------------------------------------------
--  Check identity has zero OCR and tensor multiplies
--  rates. fullScheme corrupts all 2ⁿ inputs, giving
--  2ⁿ·2ⁿ for its tensor square.

fullScheme : Scheme n
fullScheme = mkScheme (λ _ → true)

_ : ocr (idScheme {3}) ≡ 0
_ = refl

_ : ocr (fullScheme {2}) ≡ 4
_ = refl

_ : ocr (fullScheme {1} ⊗ fullScheme {1}) ≡ ocr (fullScheme {1}) * ocr (fullScheme {1})
_ = ocr-⊗ (fullScheme {1}) (fullScheme {1})
