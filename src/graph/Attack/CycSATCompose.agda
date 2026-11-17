------------------------------------------------------------------------
--  Compose both CycSAT stages when oscillation elimination leaves multiple
--  keys (graph track). CycSATAttack alone recovers the feedback-insertion
--  lock because model→correct-T permits stability only at its correct key.
--  General CycSAT follows elimination with ordinary SAT/DIP recovery on
--  survivors. Model that composition with key b ∷ kc: b controls a feedback
--  wire oscillating exactly at true, and kc controls a combinational point
--  lock corrupting settled output at kc. Stage 1 uses decSATModel on b,
--  removing the 2^m keys true ∷ _ while retaining all false ∷ kc. Stage 2
--  folds input DIPs using survives2, rederiving PointDIPAttack locally;
--  x=kc eliminates each wrong stable tail but alone cannot constrain b.
--  killed-by-stage1 and killed-by-stage2 describe these complementary
--  effects. stage1-needed shows that the residual secret survives stage 2;
--  stage2-needed shows that stage 1 accepts false for every suffix.
--  cycSATCompose-recovers leaves exactly false ∷ ksec. At residual width
--  zero, stage 1 already leaves this singleton.
--  Stage 2 reads the settled combinational output, well-defined for stage-1
--  survivors; host cancellation leaves the point indicator as in the
--  acyclic attack. Reuse CycSATAttack.decSATModel, Graph.Util.allVecsK and
--  ∈-allVecsK, and CyclicMulti.allFalse without postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATCompose where

open import Data.Nat using (ℕ; suc)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_; if_then_else_)
open import Data.Bool.Properties using (∧-zeroʳ)
open import Data.Vec using (Vec; []; _∷_)
open import Data.List using (List; []; _∷_)
open import Data.Product using (_×_; _,_)
open import Data.Empty using (⊥; ⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst; _≢_)
open import Relation.Nullary using (¬_)
open import Relation.Nullary.Decidable using (⌊_⌋)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)

open import Graph.Core using (Gate)
open import Graph.Acyclic using (ANetlist)
open import Locking.CyclicMulti using (allFalse)
open import Attack.CycSATAttack using (decSATModel)
open import Graph.Util using (allVecsK; ∈-allVecsK)

private
  variable
    W m : ℕ

------------------------------------------------------------------------
--  Define Boolean/vector equality locally as the point indicator.

xor-self : (a : Bool) → a xor a ≡ false
xor-self true  = refl
xor-self false = refl

eqB : Bool → Bool → Bool
eqB true  c = c
eqB false c = not c

eqB-refl : (a : Bool) → eqB a a ≡ true
eqB-refl true  = refl
eqB-refl false = refl

eqB-complete : (a b : Bool) → eqB a b ≡ true → a ≡ b
eqB-complete true  true  _  = refl
eqB-complete false false _  = refl
eqB-complete true  false ()
eqB-complete false true  ()

eqVec : Vec Bool m → Vec Bool m → Bool
eqVec []       []       = true
eqVec (a ∷ as) (b ∷ bs) = eqB a b ∧ eqVec as bs

eqVec-refl : (v : Vec Bool m) → eqVec v v ≡ true
eqVec-refl []       = refl
eqVec-refl (a ∷ as) rewrite eqB-refl a | eqVec-refl as = refl

eqVec-sound : (a b : Vec Bool m) → a ≡ b → eqVec a b ≡ true
eqVec-sound a b p = subst (λ z → eqVec a z ≡ true) p (eqVec-refl a)

∧true→ : (x y : Bool) → x ∧ y ≡ true → (x ≡ true) × (y ≡ true)
∧true→ true  y eq = refl , eq
∧true→ false y ()

eqVec-complete : (a b : Vec Bool m) → eqVec a b ≡ true → a ≡ b
eqVec-complete []       []       _  = refl
eqVec-complete (a ∷ as) (b ∷ bs) eq =
  let (h , t) = ∧true→ (eqB a b) (eqVec as bs) eq
  in cong₂ _∷_ (eqB-complete a b h) (eqVec-complete as bs t)

false≢true : false ≡ true → ⊥
false≢true ()

eqVec-false→≢ : {a b : Vec Bool m} → eqVec a b ≡ false → a ≢ b
eqVec-false→≢ {a = a} {b} ef p = false≢true (trans (sym ef) (eqVec-sound a b p))

------------------------------------------------------------------------
--  Stage 2 folds input queries over the settled point lock. A tail kc is
--  consistent at x exactly when its point indicator agrees with the secret's,
--  following PointDIPAttack within this library.

consistC : (ksec x kc : Vec Bool m) → Bool
consistC ksec x kc = not (eqVec kc x xor eqVec ksec x)

consistC-self : (ksec x : Vec Bool m) → consistC ksec x ksec ≡ true
consistC-self ksec x = cong not (xor-self (eqVec ksec x))

consistC-kill : (ksec kc : Vec Bool m) → kc ≢ ksec → consistC ksec kc kc ≡ false
consistC-kill ksec kc kc≢ =
  cong not (cong₂ _xor_ (eqVec-refl kc)
                        (eqVecFalse))
  where
    eqVecFalse : eqVec ksec kc ≡ false
    eqVecFalse with eqVec ksec kc in e
    ... | false = refl
    ... | true  = ⊥-elim (kc≢ (sym (eqVec-complete ksec kc e)))

andMapC : (Vec Bool m → Bool) → List (Vec Bool m) → Bool
andMapC f []       = true
andMapC f (x ∷ xs) = f x ∧ andMapC f xs

andMapC-true : (f : Vec Bool m → Bool) (xs : List (Vec Bool m)) →
               (∀ x → f x ≡ true) → andMapC f xs ≡ true
andMapC-true f []       h = refl
andMapC-true f (x ∷ xs) h rewrite h x = andMapC-true f xs h

andMapC-false : (f : Vec Bool m → Bool) (xs : List (Vec Bool m)) (w : Vec Bool m) →
                w ∈ xs → f w ≡ false → andMapC f xs ≡ false
andMapC-false f (x ∷ xs) w (here refl) fw rewrite fw = refl
andMapC-false f (x ∷ xs) w (there mem) fw =
  trans (cong (f x ∧_) (andMapC-false f xs w mem fw)) (∧-zeroʳ (f x))

survives2 : (ksec : Vec Bool m) (inputs : List (Vec Bool m)) (kc : Vec Bool m) → Bool
survives2 ksec inputs kc = andMapC (λ x → consistC ksec x kc) inputs

survives2-self : (ksec : Vec Bool m) → survives2 ksec (allVecsK m) ksec ≡ true
survives2-self ksec = andMapC-true _ (allVecsK _) (consistC-self ksec)

survives2-kill : (ksec kc : Vec Bool m) → kc ≢ ksec →
                 survives2 ksec (allVecsK m) kc ≡ false
survives2-kill ksec kc kc≢ =
  andMapC-false _ (allVecsK _) kc (∈-allVecsK kc) (consistC-kill ksec kc kc≢)

survives2-complete : (ksec kc : Vec Bool m) →
                     survives2 ksec (allVecsK m) kc ≡ true → kc ≡ ksec
survives2-complete ksec kc s2 with eqVec kc ksec in e
... | true  = eqVec-complete kc ksec e
... | false = ⊥-elim (false≢true (trans (sym (survives2-kill ksec kc (eqVec-false→≢ e))) s2))

------------------------------------------------------------------------
--  Stage 1 eliminates oscillating head bits using the single-wire CycSAT
--  decision: false is stable and true oscillates.

stable1 : (out : Gate W) (base : ANetlist W) → Bool → Bool
stable1 out base b = ⌊ decSATModel out base b ⌋

stable1-false : (out : Gate W) (base : ANetlist W) → stable1 out base false ≡ true
stable1-false out base = refl

stable1-true→false : (out : Gate W) (base : ANetlist W) (b : Bool) →
                     stable1 out base b ≡ true → b ≡ false
stable1-true→false out base false _  = refl
stable1-true→false out base true  ()

------------------------------------------------------------------------
--  A key b ∷ kc survives the composition exactly when b is stable and kc
--  satisfies input-DIP consistency.

survivesBoth : (out : Gate W) (base : ANetlist W) (ksec : Vec Bool m)
               (inputs : List (Vec Bool m)) → Vec Bool (suc m) → Bool
survivesBoth out base ksec inputs (b ∷ kc) =
  stable1 out base b ∧ survives2 ksec inputs kc

------------------------------------------------------------------------
--  Show the stages remove complementary classes of candidates.

--  Stage 1 removes oscillating keys, including true ∷ ksec retained by stage 2.
killed-by-stage1 : (out : Gate W) (base : ANetlist W) (ksec : Vec Bool m) →
                   survivesBoth out base ksec (allVecsK m) (true ∷ ksec) ≡ false
killed-by-stage1 out base ksec = refl

--  Stage 2 removes wrong stable tails among the false ∷ kc retained by stage 1.
killed-by-stage2 : (out : Gate W) (base : ANetlist W) (ksec kc : Vec Bool m) →
                   kc ≢ ksec →
                   survivesBoth out base ksec (allVecsK m) (false ∷ kc) ≡ false
killed-by-stage2 out base ksec kc kc≢ =
  trans (cong (stable1 out base false ∧_) (survives2-kill ksec kc kc≢))
        (∧-zeroʳ (stable1 out base false))

--  Stage 1 accepts false independently of kc; stage 2 retains ksec
--  independently of the head test. These lemmas state survival, not
--  non-singleton cardinalities; at m = 0 stage 1 leaves one full key.
stage2-needed : (out : Gate W) (base : ANetlist W) (kc : Vec Bool m) →
                stable1 out base false ≡ true
stage2-needed out base kc = refl

stage1-needed : (ksec : Vec Bool m) → survives2 ksec (allVecsK m) ksec ≡ true
stage1-needed ksec = survives2-self ksec

------------------------------------------------------------------------
--  Scan keys, retain those passing both stages, and return their unique survivor.

scanB : (Vec Bool (suc m) → Bool) → List (Vec Bool (suc m)) → Vec Bool (suc m)
scanB {m = m} p []       = allFalse (suc m)
scanB         p (x ∷ xs) = if p x then x else scanB p xs

scanB-char : (p : Vec Bool (suc m) → Bool) (x* : Vec Bool (suc m))
             (xs : List (Vec Bool (suc m))) →
             (∀ y → p y ≡ true → y ≡ x*) → p x* ≡ true → x* ∈ xs →
             scanB p xs ≡ x*
scanB-char p x* (x ∷ xs) uniq px* (here refl) rewrite px* = refl
scanB-char p x* (x ∷ xs) uniq px* (there mem) with p x in e
... | true  = uniq x e
... | false = scanB-char p x* xs uniq px* mem

cycSATCompose : (out : Gate W) (base : ANetlist W) (ksec : Vec Bool m) →
                Vec Bool (suc m)
cycSATCompose {m = m} out base ksec =
  scanB (survivesBoth out base ksec (allVecsK m)) (allVecsK (suc m))

--  Prove that elimination followed by input-DIP pruning leaves precisely
--  false ∷ ksec.
cycSATCompose-recovers : (out : Gate W) (base : ANetlist W) (ksec : Vec Bool m) →
                         cycSATCompose out base ksec ≡ false ∷ ksec
cycSATCompose-recovers {m = m} out base ksec =
  scanB-char P (false ∷ ksec) (allVecsK (suc m)) uniqueness satisfies
             (∈-allVecsK (false ∷ ksec))
  where
    P : Vec Bool (suc m) → Bool
    P = survivesBoth out base ksec (allVecsK m)

    satisfies : P (false ∷ ksec) ≡ true
    satisfies = cong₂ _∧_ (stable1-false out base) (survives2-self ksec)

    uniqueness : ∀ y → P y ≡ true → y ≡ false ∷ ksec
    uniqueness (b ∷ kc) eq =
      let (s1 , s2) = ∧true→ (stable1 out base b) (survives2 ksec (allVecsK m) kc) eq
      in cong₂ _∷_ (stable1-true→false out base b s1) (survives2-complete ksec kc s2)
