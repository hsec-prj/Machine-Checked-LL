------------------------------------------------------------------------
--  A supplied correction table restores the host and has size OCR.
--  corrupt h ksec kapp = prot ksec ⊕ prot kapp is independent of f but
--  depends on the secret and applied keys. bypass-correct cancels those
--  terms from locked output; bypass-cost≡OCR counts the correction inputs.
--  SARLock-bypass-≤2 bounds that table by two entries, and SFLL-bypass-odd
--  gives 2·C(n,h) entries at odd key distance. These equations assume the
--  correction is supplied; they do not discover it from an observation,
--  bound an attack's computation, or certify a general bypass algorithm.
--  Locking.NetlistCatalogue.bypass-circuit-correct separately realises the
--  same supplied-key correction at gate level.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.Bypass where

open import Data.Nat using (ℕ; _+_; _≤_)
open import Data.Bool using (Bool; true; false; _xor_)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import SFLL.HD using (locked; prot)
open import SFLL.HammingDistance using (HD; parity)
open import Security.OCR using (corrupt; OCR; OCR-odd)
open import Security.SARLock using (OCR-SARLock-≤2)
open import Util.Counting using (countT; allVecs; binom)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  XOR the host-independent corrupt correction into the wrong-key locked output.

bypass : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
         Vec Bool n → Bool
bypass h ksec kapp f x = locked h ksec kapp f x xor corrupt h ksec kapp x

------------------------------------------------------------------------
--  Prove that bypass restores f on every input for any applied key, whether
--  correct or wrong.

--  Cancel both protected terms with ((g ⊕ a) ⊕ b) ⊕ (a ⊕ b) ≡ g.
bypass-bit : (g a b : Bool) → ((g xor a) xor b) xor (a xor b) ≡ g
bypass-bit true  true  true  = refl
bypass-bit true  true  false = refl
bypass-bit true  false true  = refl
bypass-bit true  false false = refl
bypass-bit false true  true  = refl
bypass-bit false true  false = refl
bypass-bit false false true  = refl
bypass-bit false false false = refl

bypass-correct : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool)
                 (x : Vec Bool n) → bypass h ksec kapp f x ≡ f x
bypass-correct h ksec kapp f x =
  bypass-bit (f x) (prot h ksec x) (prot h kapp x)

------------------------------------------------------------------------
--  Identify correction-table size exactly with output corruption rate.

--  The correction domain consists precisely of inputs where the lock differs
--  from f, namely the host-independent corrupt predicate.
bypassTable : (h : ℕ) (ksec kapp : Vec Bool n) → Vec Bool n → Bool
bypassTable = corrupt

bypass-cost : (h : ℕ) (ksec kapp : Vec Bool n) → ℕ
bypass-cost {n = n} h ksec kapp = countT (bypassTable h ksec kapp) (allVecs n)

bypass-cost≡OCR : (h : ℕ) (ksec kapp : Vec Bool n) →
                  bypass-cost h ksec kapp ≡ OCR h ksec kapp
bypass-cost≡OCR h ksec kapp = refl

------------------------------------------------------------------------
--  The supplied radius-zero correction table contains at most two entries;
--  its discovery is outside this statement.

SARLock-bypass-≤2 : (ksec kapp : Vec Bool n) → bypass-cost 0 ksec kapp ≤ 2
SARLock-bypass-≤2 ksec kapp = OCR-SARLock-≤2 ksec kapp

--  At odd key distance, SFLL-HD requires 2·C(n,h) correction entries; the
--  bypass cost follows its larger radius-dependent corruption.
SFLL-bypass-odd : (h : ℕ) (ksec kapp : Vec Bool n) →
                  parity (HD ksec kapp) ≡ true →
                  bypass-cost h ksec kapp ≡ binom n h + binom n h
SFLL-bypass-odd h ksec kapp odd = OCR-odd h ksec kapp odd
