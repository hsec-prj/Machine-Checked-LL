------------------------------------------------------------------------
--  Generalise both CycSAT stages on the graph track.
--  CycSATCompose combines one feedback head bit
--  with a point-lock tail. Extend stage one to
--  arbitrary feedback topology: decSATModelT decides
--  oscillation for k mutually reading outs over
--  any CyclicTopo base, and model→correct-T makes
--  allFalse k the unique stable key. Extend stage
--  two to any residual s2 with s2 ksec = true
--  and every surviving t equal to ksec, including
--  SARLock, sphere, or flex instances satisfying
--  that premise. Split Vec Bool (k+m) into feedback
--  and residual portions using the prepend convention.
--  composeP combines their predicates by conjunction,
--  and composeGen-recovers returns hsec ++ ksec.
--  With oscillation as stage one,
--  cycSATComposeGen-recovers returns allFalse k ++ ksec
--  after scanning 2^(k+m) candidates. The original
--  construction is k = 1 with s2 = survives2.
--  Generalise scanB to scanV and use self-contained
--  splitV, allVecsK, CyclicTopo obstruction lemmas,
--  and CycSATCompose residual helpers. No postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATComposeGen where

open import Data.Nat using (ℕ; zero; suc; _+_; _^_)
open import Data.Bool using (Bool; true; false; _∧_; if_then_else_)
open import Data.Vec using (Vec; []; _∷_; _++_)
open import Data.List using (List; []; _∷_; length)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)
open import Relation.Nullary using (yes; no)
open import Relation.Nullary.Decidable using (⌊_⌋)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)

open import Graph.Core using (Gate)
open import Graph.Acyclic using (ANetlist)
open import Locking.CyclicMulti using (allFalse)
open import Locking.CyclicTopo using (baseLayer; SATModelT; model→correct-T)
open import Attack.CycSATAttack using (decSATModelT; correctModel)
open import Graph.Util using (allVecsK; ∈-allVecsK; length-allVecsK)
open import Attack.CycSATCompose
  using (∧true→; false≢true; survives2; survives2-self; survives2-complete)

private
  variable
    W k m : ℕ

------------------------------------------------------------------------
--  Generalise width-suc-m scanB to scanV at any
--  width n. Return the first key satisfying p,
--  with an all-false empty-list fallback unused
--  when the full enumeration contains its survivor.

scanV : (Vec Bool m → Bool) → List (Vec Bool m) → Vec Bool m
scanV {m = m} p []       = allFalse m
scanV         p (x ∷ xs) = if p x then x else scanV p xs

scanV-char : (p : Vec Bool m → Bool) (x* : Vec Bool m) (xs : List (Vec Bool m)) →
             (∀ y → p y ≡ true → y ≡ x*) → p x* ≡ true → x* ∈ xs →
             scanV p xs ≡ x*
scanV-char p x* (x ∷ xs) uniq px* (here refl) rewrite px* = refl
scanV-char p x* (x ∷ xs) uniq px* (there mem) with p x in e
... | true  = uniq x e
... | false = scanV-char p x* xs uniq px* mem

------------------------------------------------------------------------
--  Split Vec Bool (k+m) into k feedback and m
--  residual bits. Explicit projections reduce without
--  with-abstraction, keeping both algebraic proofs direct.

splitV : (k : ℕ) → Vec Bool (k + m) → Vec Bool k × Vec Bool m
splitV zero    v       = [] , v
splitV (suc k) (x ∷ v) = (x ∷ proj₁ (splitV k v)) , proj₂ (splitV k v)

--  Prove splitting is a left inverse of concatenation.
splitV-++ : (h : Vec Bool k) (t : Vec Bool m) → splitV k (h ++ t) ≡ (h , t)
splitV-++ []      t = refl
splitV-++ (x ∷ h) t = cong (λ p → (x ∷ proj₁ p) , proj₂ p) (splitV-++ h t)

--  Recover the original bus by concatenating the split halves.
splitV-join : (v : Vec Bool (k + m)) →
              proj₁ (splitV k v) ++ proj₂ (splitV k v) ≡ v
splitV-join {k = zero}  v       = refl
splitV-join {k = suc k} (x ∷ v) = cong (x ∷_) (splitV-join {k = k} v)

------------------------------------------------------------------------
--  Require the feedback half to pass stage one
--  and the residual half to pass stage two.

composeP : (Vec Bool k → Bool) → (Vec Bool m → Bool) → Vec Bool (k + m) → Bool
composeP {k = k} s1 s2 v = s1 (proj₁ (splitV k v)) ∧ s2 (proj₂ (splitV k v))

------------------------------------------------------------------------
--  From unique survivors hsec and ksec of s1
--  and s2, prove the combined predicate has unique
--  survivor hsec ++ ksec. Oscillation and residual
--  recovery fix complementary halves; neither suffices alone.

composeGen-recovers :
  (s1 : Vec Bool k → Bool) (s2 : Vec Bool m → Bool)
  (hsec : Vec Bool k) (ksec : Vec Bool m) →
  s1 hsec ≡ true → (∀ h → s1 h ≡ true → h ≡ hsec) →
  s2 ksec ≡ true → (∀ t → s2 t ≡ true → t ≡ ksec) →
  scanV (composeP s1 s2) (allVecsK (k + m)) ≡ hsec ++ ksec
composeGen-recovers {k = k} {m = m} s1 s2 hsec ksec s1self s1uniq s2self s2uniq =
  scanV-char P (hsec ++ ksec) (allVecsK (k + m)) uniq sat (∈-allVecsK _)
  where
    P : Vec Bool (k + m) → Bool
    P = composeP s1 s2

    sat : P (hsec ++ ksec) ≡ true
    sat rewrite splitV-++ hsec ksec = cong₂ _∧_ s1self s2self

    uniq : ∀ y → P y ≡ true → y ≡ hsec ++ ksec
    uniq y eq =
      let (p , q) = ∧true→ (s1 (proj₁ (splitV k y))) (s2 (proj₂ (splitV k y))) eq
      in trans (sym (splitV-join {k = k} y))
               (cong₂ _++_ (s1uniq _ p) (s2uniq _ q))

------------------------------------------------------------------------
--  Instantiate stage one with arbitrary-topology
--  oscillation elimination, uniquely surviving at allFalse k.

stageOsc : (outs : Vec (Gate W) k) (base : ANetlist W) → Vec Bool k → Bool
stageOsc outs base hs = ⌊ decSATModelT outs base hs ⌋

--  Use correctModel to admit a stable model for the correct key.
stageOsc-self : (outs : Vec (Gate W) k) (base : ANetlist W) →
                stageOsc outs base (allFalse k) ≡ true
stageOsc-self outs base with decSATModelT outs base (allFalse _)
... | yes _  = refl
... | no ¬m = ⊥-elim (¬m (correctModel outs base))

--  Use model→correct-T to force every admitted model's key to allFalse.
stageOsc-uniq : (outs : Vec (Gate W) k) (base : ANetlist W) →
                ∀ hs → stageOsc outs base hs ≡ true → hs ≡ allFalse k
stageOsc-uniq outs base hs eq with decSATModelT outs base hs
... | yes m = model→correct-T hs (baseLayer outs) base m
... | no  _ = ⊥-elim (false≢true eq)

------------------------------------------------------------------------
--  Scan the entire 2^(k+m) key bus for candidates
--  passing arbitrary-topology oscillation elimination
--  and residual s2, returning allFalse k ++ ksec.

cycSATComposeGen :
  (outs : Vec (Gate W) k) (base : ANetlist W)
  (s2 : Vec Bool m → Bool) → Vec Bool (k + m)
cycSATComposeGen {k = k} {m = m} outs base s2 =
  scanV (composeP (stageOsc outs base) s2) (allVecsK (k + m))

cycSATComposeGen-recovers :
  (outs : Vec (Gate W) k) (base : ANetlist W)
  (s2 : Vec Bool m → Bool) (ksec : Vec Bool m) →
  s2 ksec ≡ true → (∀ t → s2 t ≡ true → t ≡ ksec) →
  cycSATComposeGen outs base s2 ≡ allFalse k ++ ksec
cycSATComposeGen-recovers outs base s2 ksec s2self s2uniq =
  composeGen-recovers (stageOsc outs base) s2 (allFalse _) ksec
    (stageOsc-self outs base) (stageOsc-uniq outs base) s2self s2uniq

--  Count full-bus inspection as 2^(k+m).
cycSATComposeGen-queries : (k m : ℕ) → length (allVecsK (k + m)) ≡ 2 ^ (k + m)
cycSATComposeGen-queries k m = length-allVecsK (k + m)

------------------------------------------------------------------------
--  Use survives2 as the point residual for arbitrary
--  feedback topology. Restricting further to k = 1
--  recovers CycSATCompose's original concrete lock
--  as the single-feedback-wire point instance.

cycSATComposeGen-point :
  (outs : Vec (Gate W) k) (base : ANetlist W) (ksec : Vec Bool m) →
  cycSATComposeGen outs base (survives2 ksec (allVecsK m)) ≡ allFalse k ++ ksec
cycSATComposeGen-point outs base ksec =
  cycSATComposeGen-recovers outs base (survives2 ksec (allVecsK _)) ksec
    (survives2-self ksec) (survives2-complete ksec)
