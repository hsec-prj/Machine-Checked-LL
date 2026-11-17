------------------------------------------------------------------------
--  Characterise the information limit of CycSAT
--  composition (graph branch A). composeGen-recovers
--  assumes a unique residual survivor; noninjective
--  observations violate this, leaving a key equivalence
--  class after every input has been queried. For
--  example, the discussed SFLL-HD collision has
--  00 and 11 agreeing on all inputs at radius h ≥ 1.
--  No additional query separates equal observable
--  functions. Generalise the point indicator to
--  obs : key → input → Bool. survivesObs tests
--  agreement with the secret over the full input
--  enumeration. Prove survival iff pointwise observable
--  agreement and recovery-up-to-class: the secret
--  survives and any survivors are indistinguishable.
--  survivesObs-eqVec≡survives2 recovers the singleton
--  point case; collideObs/two-survivors witness a
--  nontrivial fibre analogous to main-track fibre-h1-n2 = 2.
--  Reuse CycSATCompose's Boolean/fold helpers,
--  CycSATComposeGen's splitV/composeP, and allVecsK.
--  Unlike LeakEntropy's counting proof, use
--  ∈-allVecsK and andMapC-true→∈ membership. Add
--  no postulates and leave composeGen-recovers as
--  the unique-key companion result.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATComposeFibre where

open import Data.Nat using (ℕ; _+_)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_)
open import Data.Vec using (Vec; []; _∷_)
open import Data.List using (List; []; _∷_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong₂; subst; _≢_)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)

open import Graph.Util using (allVecsK; ∈-allVecsK)
open import Attack.CycSATCompose
  using (eqB; eqB-refl; eqB-complete; eqVec; ∧true→;
         andMapC; andMapC-true; consistC; survives2)
open import Attack.CycSATComposeGen using (splitV; composeP)

private
  variable
    k m : ℕ

------------------------------------------------------------------------
--  Interpret obs k x as the applied-key circuit's
--  observable bit. eqVec gives point locking; a
--  noninjective obs identifies multiple keys.

Obs : ℕ → Set
Obs m = Vec Bool m → Vec Bool m → Bool

consistObs : Obs m → Vec Bool m → Vec Bool m → Vec Bool m → Bool
consistObs obs ksec x kc = eqB (obs kc x) (obs ksec x)

--  Keep kc when its observations match the secret
--  on every enumerated input.
survivesObs : Obs m → Vec Bool m → List (Vec Bool m) → Vec Bool m → Bool
survivesObs obs ksec inputs kc = andMapC (λ x → consistObs obs ksec x kc) inputs

------------------------------------------------------------------------
--  Supply Boolean equality facts and the dual of andMapC-false.

--  From a true AND fold, derive truth of every member.
andMapC-true→∈ : (f : Vec Bool m → Bool) (xs : List (Vec Bool m)) (w : Vec Bool m) →
                 w ∈ xs → andMapC f xs ≡ true → f w ≡ true
andMapC-true→∈ f (x ∷ xs) w (here refl) eq = proj₁ (∧true→ (f x) (andMapC f xs) eq)
andMapC-true→∈ f (x ∷ xs) w (there mem) eq =
  andMapC-true→∈ f xs w mem (proj₂ (∧true→ (f x) (andMapC f xs) eq))

--  Identify eqB with negated XOR to connect abstract
--  observation agreement to point consistC.
eqB-not-xor : (a b : Bool) → eqB a b ≡ not (a xor b)
eqB-not-xor true  true  = refl
eqB-not-xor true  false = refl
eqB-not-xor false true  = refl
eqB-not-xor false false = refl

eqB-from-≡ : {a b : Bool} → a ≡ b → eqB a b ≡ true
eqB-from-≡ {a} refl = eqB-refl a

andMapC-cong : (f g : Vec Bool m → Bool) (xs : List (Vec Bool m)) →
               (∀ x → f x ≡ g x) → andMapC f xs ≡ andMapC g xs
andMapC-cong f g []       h = refl
andMapC-cong f g (x ∷ xs) h = cong₂ _∧_ (h x) (andMapC-cong f g xs h)

------------------------------------------------------------------------
--  Equate full-enumeration survival with membership
--  in the secret's pointwise observation fibre.

survivesObs→pointwise : (obs : Obs m) (ksec kc : Vec Bool m) →
  survivesObs obs ksec (allVecsK m) kc ≡ true →
  (x : Vec Bool m) → obs kc x ≡ obs ksec x
survivesObs→pointwise obs ksec kc s x =
  eqB-complete (obs kc x) (obs ksec x)
    (andMapC-true→∈ (λ y → consistObs obs ksec y kc) (allVecsK _) x (∈-allVecsK x) s)

pointwise→survivesObs : (obs : Obs m) (ksec kc : Vec Bool m) →
  ((x : Vec Bool m) → obs kc x ≡ obs ksec x) →
  survivesObs obs ksec (allVecsK m) kc ≡ true
pointwise→survivesObs obs ksec kc h =
  andMapC-true (λ x → consistObs obs ksec x kc) (allVecsK _) (λ x → eqB-from-≡ (h x))

------------------------------------------------------------------------
--  Recover up to the equivalence class: retain the
--  secret and prove all survivors indistinguishable.
--  A nontrivial fibre prevents unique-key recovery,
--  exposing the limit excluded by composeGen-recovers' premise.

recovery-up-to-class : (obs : Obs m) (ksec : Vec Bool m) →
  (survivesObs obs ksec (allVecsK m) ksec ≡ true)
  × ((k1 k2 : Vec Bool m) →
       survivesObs obs ksec (allVecsK m) k1 ≡ true →
       survivesObs obs ksec (allVecsK m) k2 ≡ true →
       (x : Vec Bool m) → obs k1 x ≡ obs k2 x)
recovery-up-to-class obs ksec =
    pointwise→survivesObs obs ksec ksec (λ x → refl)
  , λ k1 k2 s1 s2 x → trans (survivesObs→pointwise obs ksec k1 s1 x)
                            (sym (survivesObs→pointwise obs ksec k2 s2 x))

------------------------------------------------------------------------
--  Specialise obs to eqVec, identifying survivesObs
--  with survives2 through eqB's negated XOR. Its
--  singleton fibre recovers composeGen-point.

survivesObs-eqVec≡survives2 : (ksec kc : Vec Bool m) (inputs : List (Vec Bool m)) →
  survivesObs eqVec ksec inputs kc ≡ survives2 ksec inputs kc
survivesObs-eqVec≡survives2 ksec kc inputs =
  andMapC-cong (λ x → consistObs eqVec ksec x kc) (λ x → consistC ksec x kc) inputs
    (λ x → eqB-not-xor (eqVec kc x) (eqVec ksec x))

------------------------------------------------------------------------
--  Compose the limit: a uniquely surviving feedback
--  predicate fixes hsec exactly, while the residual
--  key is fixed only up to its fibre. Characterise
--  when the composed predicate holds rather than returning one key.

composeFibre-char : (s1 : Vec Bool k → Bool) (hsec : Vec Bool k) →
  s1 hsec ≡ true → (∀ h → s1 h ≡ true → h ≡ hsec) →
  (obs : Obs m) (ksec : Vec Bool m) (v : Vec Bool (k + m)) →
  (composeP s1 (survivesObs obs ksec (allVecsK m)) v ≡ true →
     (proj₁ (splitV k v) ≡ hsec)
     × (survivesObs obs ksec (allVecsK m) (proj₂ (splitV k v)) ≡ true))
  × ((proj₁ (splitV k v) ≡ hsec)
       × (survivesObs obs ksec (allVecsK m) (proj₂ (splitV k v)) ≡ true) →
     composeP s1 (survivesObs obs ksec (allVecsK m)) v ≡ true)
composeFibre-char {k = k} {m = m} s1 hsec s1self s1uniq obs ksec v = fwd , bwd
  where
    s2 : Vec Bool m → Bool
    s2 = survivesObs obs ksec (allVecsK m)

    fwd : composeP s1 s2 v ≡ true →
          (proj₁ (splitV k v) ≡ hsec) × (s2 (proj₂ (splitV k v)) ≡ true)
    fwd eq =
      let (p , q) = ∧true→ (s1 (proj₁ (splitV k v))) (s2 (proj₂ (splitV k v))) eq
      in s1uniq (proj₁ (splitV k v)) p , q

    bwd : (proj₁ (splitV k v) ≡ hsec) × (s2 (proj₂ (splitV k v)) ≡ true) →
          composeP s1 s2 v ≡ true
    bwd (ph , qt) =
      cong₂ _∧_ (subst (λ z → s1 z ≡ true) (sym ph) s1self) qt

------------------------------------------------------------------------
--  Exhibit a two-bit residual ignoring its second
--  key bit. Keys 00 and 01 both survive identically,
--  leaving that bit information-theoretically unrecoverable,
--  the graph analogue of fibre-h1-n2 = 2.

collideObs : Obs 2
collideObs (a ∷ _ ∷ []) (x ∷ _ ∷ []) = eqB a x

--  Give Vec-typed secret 00 and colliding key 01, avoiding List ambiguity.
k00 k01 : Vec Bool 2
k00 = false ∷ false ∷ []
k01 = false ∷ true  ∷ []

collide-00-01 : (x : Vec Bool 2) → collideObs k00 x ≡ collideObs k01 x
collide-00-01 (x ∷ _ ∷ []) = refl

two-survivors :
  (survivesObs collideObs k00 (allVecsK 2) k00 ≡ true)
  × (survivesObs collideObs k00 (allVecsK 2) k01 ≡ true)
  × (k00 ≢ k01)
two-survivors =
    pointwise→survivesObs collideObs k00 k00 (λ x → refl)
  , pointwise→survivesObs collideObs k00 k01 (λ x → sym (collide-00-01 x))
  , λ ()
