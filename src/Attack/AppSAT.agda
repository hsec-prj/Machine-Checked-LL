------------------------------------------------------------------------
--  Formalise approximate key recovery and AppSAT (formalisation 2).
--  SARLockQueryBound, Adaptive, and ProbQueryBound address exact secrets.
--  AppSAT [Shamsi et al. 2017] instead accepts keys whose locked functions
--  agree with the de-obfuscated host except on a small fraction of inputs.
--  The same OCR governing the meta-analysis has the opposite interpretation
--  here: rare wrong-key errors hinder exact recovery but make a wrong key
--  already approximately correct. disagreeCount≡OCR proves that using kapp
--  with secret ksec yields exactly OCR h ksec kapp host disagreements; f
--  cancels, making the count host-independent. ApproxKey requires at most
--  ε disagreeing inputs. SARLock-approx-any shows every radius-zero key is
--  2-approximate for every secret and host. SARLock-appsat-free therefore
--  uses a constant zero-query guess for approximate recovery, contrasting
--  with the exponential exact bound of SARLock-query-lb. Odd-distance
--  SFLL-HD instead has exactly 2·C(n,h) disagreements, so SFLL-approx-needs
--  requires 2·C(n,h) ≤ ε. The tolerated error follows its radius-dependent
--  larger corruption. Reuse the OCR catalogue without new primitives or
--  postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.AppSAT where

open import Data.Nat using (ℕ; _+_; _≤_)
open import Data.Bool using (Bool; true; false; _xor_)
open import Data.Vec using (Vec)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; subst)

open import SFLL.HD using (prot; locked)
open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (countT; allVecs; countT-cong; binom)
open import Security.OCR using (OCR; OCR-odd)
open import Security.SARLock using (OCR-SARLock-≤2)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Connect actual locked-output disagreement to the abstract corruption count.

--  Cancel the host using ((a ⊕ b) ⊕ c) ⊕ a = b ⊕ c, with a=f x and
--  b,c the protected predicates.
xor-mix : (a b c : Bool) → ((a xor b) xor c) xor a ≡ b xor c
xor-mix true  true  true  = refl
xor-mix true  true  false = refl
xor-mix true  false true  = refl
xor-mix true  false false = refl
xor-mix false true  true  = refl
xor-mix false true  false = refl
xor-mix false false true  = refl
xor-mix false false false = refl

--  Count disagreements with de-obfuscated f when kapp is applied to an
--  SFLL circuit with secret ksec.
disagreeCount : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) → ℕ
disagreeCount {n = n} h ksec kapp f =
  countT (λ x → locked h ksec kapp f x xor f x) (allVecs n)

--  Identify that count with OCR h ksec kapp, independently of host f.
disagreeCount≡OCR : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
                    disagreeCount h ksec kapp f ≡ OCR h ksec kapp
disagreeCount≡OCR {n = n} h ksec kapp f =
  countT-cong (λ x → xor-mix (f x) (prot h ksec x) (prot h kapp x)) (allVecs n)

------------------------------------------------------------------------
--  Define approximate keys through ε-functional circuit equivalence.

--  Accept kapp as ε-approximate for secret ksec and host f when it corrupts
--  at most ε inputs.
ApproxKey : (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) (ε : ℕ) → Set
ApproxKey h ksec kapp f ε = disagreeCount h ksec kapp f ≤ ε

------------------------------------------------------------------------
--  For radius-zero SARLock, every candidate key is 2-approximate.

SARLock-approx-any : (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
                     ApproxKey 0 ksec kapp f 2
SARLock-approx-any ksec kapp f =
  subst (_≤ 2) (sym (disagreeCount≡OCR 0 ksec kapp f)) (OCR-SARLock-≤2 ksec kapp)

--  A fixed guess g with no queries gives 2-approximate recovery for every
--  SARLock secret and host, making approximation free despite exponential
--  exact-recovery cost.
SARLock-appsat-free :
  (g : Vec Bool n) (f : Vec Bool n → Bool) (ksec : Vec Bool n) →
  ApproxKey 0 ksec g f 2
SARLock-appsat-free g f ksec = SARLock-approx-any ksec g f

------------------------------------------------------------------------
--  At odd key distance, an ε-approximate radius-h SFLL-HD key requires
--  2·C(n,h) ≤ ε, giving the radius-dependent tolerance bound.

SFLL-approx-needs :
  (h : ℕ) (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
  parity (HD ksec kapp) ≡ true →
  {ε : ℕ} → ApproxKey h ksec kapp f ε → binom n h + binom n h ≤ ε
SFLL-approx-needs h ksec kapp f odd approx =
  subst (_≤ _)
        (trans (disagreeCount≡OCR h ksec kapp f) (OCR-odd h ksec kapp odd))
        approx
