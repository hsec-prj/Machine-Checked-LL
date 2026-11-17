------------------------------------------------------------------------
--  Expose two limits of locking specifications on shared instances.
--  WeakSpecCounterexample bundles the weak condition and its lower bound
--  with a family whose applied key never affects the output.
--  CertifiedButUnopenable inhabits the stronger NonVacuousResist record
--  even though no applied key restores the host. That record has a free
--  secret-side gadget: it imposes neither gS=G ksec nor a right-key law,
--  and its corruption field compares two applied gadgets. An empty-set
--  secret gadget yields the certificate while every applied point key
--  breaks the host at its own point. Locking.LockCorrectness separately
--  states the family binding and right-key law.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.VacuousCertificate where

open import Data.Bool using (Bool; true; false; not; _xor_)
open import Data.Bool.Properties using (xor-identityʳ)
open import Data.List using (List; [])
open import Data.Nat using (ℕ)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong)
open import Relation.Nullary using (¬_)

open import Locking.GenericLock
  using (ProtGadget; pointGadget; flexGadget)
open ProtGadget using (pred)
open import Attack.GenericSAT using (actGen; baseGen; PointConc)
open import Attack.Tradeoff using (ExactResist)
open import Attack.NonDegenerate
  using (NonVacuousResist; mkNonVacuousResist; point-PointConcND;
         nullFamily; null-PointConc; null-ExactResist; null-lock-vacuous)
open import Attack.PointDIPAttack using (prot0-self)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Section 1, S1: certify a key-independent family under the weak condition.

--  Combine everything the weak specification promises with the same
--  family's ineffectiveness. Reading the three fields together makes the
--  counterexample rather than three unrelated observations.
record WeakSpecCounterexample
         (f : Vec Bool n → Bool) (gS : ProtGadget n)
         (G : Vec Bool n → ProtGadget n) : Set where
  field
    --  Establish the weak premise.
    weak-ok         : PointConc G
    --  Establish its derived exact-recovery lower bound.
    lower-bound-ok  : ExactResist (actGen f gS G)
    --  Nevertheless the applied key has no output influence: every pair of keys
    --  produces the same function on all inputs.
    key-insensitive : (k₁ k₂ : Vec Bool n) (x : Vec Bool n) →
                      actGen f gS G k₁ x ≡ actGen f gS G k₂ x
open WeakSpecCounterexample public

null-WeakSpecCounterexample :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  WeakSpecCounterexample f gS nullFamily
null-WeakSpecCounterexample f gS = record
  { weak-ok         = null-PointConc
  ; lower-bound-ok  = null-ExactResist f gS
  ; key-insensitive = λ k₁ k₂ x →
      trans (null-lock-vacuous f gS k₁ x) (sym (null-lock-vacuous f gS k₂ x))
  }

------------------------------------------------------------------------
--  Section 2, S2: inhabit the stronger certificate with a lock that never opens.

--  Negate restoration for every applied key, directly denying the right-key
--  law absent from NonVacuousResist.
NoCorrectKey : (f : Vec Bool n → Bool) (gS : ProtGadget n)
               (G : Vec Bool n → ProtGadget n) → Set
NoCorrectKey {n} f gS G =
  (k : Vec Bool n) → ¬ ((x : Vec Bool n) → actGen f gS G k x ≡ f x)

--  With the empty-set gadget, the lock reduces to f x xor prot 0 k x;
--  at x=k this is not (f k), the Boolean fact supporting the witness.
flip-at-self : (b : Bool) → (b xor false) xor true ≡ not b
flip-at-self false = refl
flip-at-self true  = refl

not-≢ : (b : Bool) → ¬ (not b ≡ b)
not-≢ false ()
not-≢ true  ()

--  Use each applied key as its own witness. pred (flexGadget []) reduces
--  to false, while prot0-self gives prot 0 k k=true, making locked output
--  the host's negation at k.
point-over-empty-no-correct :
  (f : Vec Bool n → Bool) → NoCorrectKey f (flexGadget []) pointGadget
point-over-empty-no-correct f k opens =
  not-≢ (f k)
    (trans (sym (trans (cong ((f k xor false) xor_) (prot0-self k))
                       (flip-at-self (f k))))
           (opens k))

--  Bundle S2's certificate and failure at identical f, gS, and G.
record CertifiedButUnopenable
         (f : Vec Bool n → Bool) (gS : ProtGadget n)
         (G : Vec Bool n → ProtGadget n) : Set where
  field
    certified  : NonVacuousResist f gS G
    unopenable : NoCorrectKey f gS G
open CertifiedButUnopenable public

--  Instantiate pointGadget, one of the manuscript's two stronger-specification
--  families, over a secret-side gadget that permits no opening key.
point-over-empty :
  (f : Vec Bool n → Bool) →
  CertifiedButUnopenable f (flexGadget []) pointGadget
point-over-empty f = record
  { certified  = mkNonVacuousResist f (flexGadget []) pointGadget point-PointConcND
  ; unopenable = point-over-empty-no-correct f
  }

------------------------------------------------------------------------
--  Section 3: delimit the conclusion. NonVacuousResist excludes S1's
--  key-independent family but does not entail an opening key. This is a
--  non-implication about the record, not a claim about deployed SFLL-HD.
--  Locking.LockCorrectness supplies the separate secret/family binding.
