------------------------------------------------------------------------
--  Bind the secret-side gadget to the applied-key family. actGen f gS G
--  otherwise leaves gS independent of G. Setting gS = G ksec gives
--  bound-right-key for every family without further hypotheses.
--  Attack.VacuousCertificate shows why strengthened resistance alone
--  does not ensure an opening key; empty-not-bound identifies its
--  empty-set gadget as outside the bound point family.
--  Authorised keys restore the host function and need not be syntactically
--  unique. At n=h+h, SFLL.Complement proves that the secret's complement
--  also restores the host. AuthorizedKey names this functional class.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.LockCorrectness where

open import Data.Bool using (Bool; true; false)
open import Data.List using ([])
open import Data.Nat using (ℕ)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans)
open import Relation.Nullary using (¬_)

open import Locking.GenericLock
  using (ProtGadget; pointGadget; flexGadget; locked-fun-gen;
         locked-fun-gen-recover)
open ProtGadget using (pred)
open import Attack.GenericSAT using (actGen)
open import Attack.PointDIPAttack using (prot0-self)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Section 1: bind the secret to its family in the correctness statement.

--  Set the secret-side gadget to G ksec. This single difference from
--  NonVacuousResist makes the right-key law expressible.
record LockCorrectness
         (f : Vec Bool n → Bool) (G : Vec Bool n → ProtGadget n)
         (ksec : Vec Bool n) : Set where
  field
    right-key : (x : Vec Bool n) → actGen f (G ksec) G ksec x ≡ f x
open LockCorrectness public

--  When both gadget slots agree, locked-fun-gen-recover reduces the lock
--  to its host. No property of G is needed and no scheme owes another proof.
bound-right-key :
  (f : Vec Bool n → Bool) (G : Vec Bool n → ProtGadget n) (ksec : Vec Bool n) →
  LockCorrectness f G ksec
bound-right-key f G ksec =
  record { right-key = locked-fun-gen-recover f (G ksec) }

------------------------------------------------------------------------
--  Section 2: identify the counterexample's unbound secret gadget.

--  At every width and every ksec, flexGadget [] is false while pointGadget
--  ksec holds at ksec. Thus the gadget used by VacuousCertificate cannot
--  equal G ksec for any key, explaining its escape from right-key correctness.
empty-not-bound :
  (ksec : Vec Bool n) →
  ¬ ((x : Vec Bool n) → pred (flexGadget []) x ≡ pred (pointGadget ksec) x)
empty-not-bound ksec agree with trans (agree ksec) (prot0-self ksec)
... | ()

------------------------------------------------------------------------
--  Section 3: define authorised keys without demanding uniqueness.

--  Authorisation means restoring the host. ksec-authorized includes the
--  secret; at n=h+h its complement also qualifies by SFLL.Complement.
--  Functional authorisation and exact syntactic key recovery are distinct.
AuthorizedKey :
  (f : Vec Bool n → Bool) (G : Vec Bool n → ProtGadget n)
  (ksec k : Vec Bool n) → Set
AuthorizedKey {n} f G ksec k =
  (x : Vec Bool n) → actGen f (G ksec) G k x ≡ f x

ksec-authorized :
  (f : Vec Bool n → Bool) (G : Vec Bool n → ProtGadget n) (ksec : Vec Bool n) →
  AuthorizedKey f G ksec ksec
ksec-authorized f G ksec = right-key (bound-right-key f G ksec)
