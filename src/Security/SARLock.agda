------------------------------------------------------------------------
--  SARLock as radius-zero protection in the OCR framework
--  SARLock's mask triggers on x = k, while SFLL-HD uses distance h.
--  At h=0 these semantic protection predicates coincide: prot 0 k
--  selects exactly {k}. Thus the general SFLL results give SARLock a
--  constant OCR ≤ 2 at every n. This quantifies the contrast in the
--  attack-resistance analysis: the tiny constant corruption supports
--  SAT-attack resistance yet makes approximation easy, whereas SFLL-HD
--  at radius h has growing 2inom{n}{h} corruption in Security.OCR.
--  Reusing the SFLL theorems unchanged gives a machine-checked account
--  of the related-work connection between low corruption and resistance,
--  and shows that the framework also includes this second named scheme.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.SARLock where

open import Data.Nat using (ℕ; zero; suc; _+_; _≡ᵇ_; _≤_)
open import Data.Bool using (Bool; true; false)
open import Data.Vec using (Vec; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)

open import SFLL.HD using (prot; locked; SFLL_correct)
open import SFLL.HammingDistance using (HD; HD-refl; HD0→≡; parity)
open import Security.OCR using (OCR; OCR-upper; OCR-odd)
open import Util.Counting using (binom)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Exact matching is SARLock's radius-zero protected sphere.

--  Instantiate the SFLL protected predicate and locked output at radius zero.
sarProt : Vec Bool n → Vec Bool n → Bool
sarProt k x = prot 0 k x

sarLocked : (ksec kapp : Vec Bool n) (f : Vec Bool n → Bool) →
            Vec Bool n → Bool
sarLocked ksec kapp f = locked 0 ksec kapp f

--  A natural number passing ≡ᵇ 0 must be zero.
≡ᵇ0→0 : (m : ℕ) → (m ≡ᵇ 0) ≡ true → m ≡ 0
≡ᵇ0→0 zero    _ = refl
≡ᵇ0→0 (suc m) ()

--  The key belongs to its singleton protected set {k}; the predicate
--  therefore tests exact key equality.
sarProt-self : (k : Vec Bool n) → sarProt k k ≡ true
sarProt-self k = cong (_≡ᵇ 0) (HD-refl k)

sarProt-exact : (k x : Vec Bool n) → sarProt k x ≡ true → x ≡ k
sarProt-exact k x p = HD0→≡ x k (≡ᵇ0→0 (HD x k) p)

------------------------------------------------------------------------
--  Inherit correct-key restoration from SFLL with h=0.

SARLock-correct : (k : Vec Bool n) (f : Vec Bool n → Bool) (x : Vec Bool n) →
                  sarLocked k k f x ≡ f x
SARLock-correct k f x = SFLL_correct 0 k f x

------------------------------------------------------------------------
--  Inherit a constant corruption bound from SFLL: binom n 0 + binom n 0
--  reduces to 2.

--  At every width n, any wrong key corrupts at most two inputs.
OCR-SARLock-≤2 : (ksec kapp : Vec Bool n) → OCR 0 ksec kapp ≤ 2
OCR-SARLock-≤2 ksec kapp = OCR-upper 0 ksec kapp

--  An odd-distance wrong key corrupts exactly two inputs.
OCR-SARLock-odd : (k k' : Vec Bool n) → parity (HD k k') ≡ true →
                  OCR 0 k k' ≡ 2
OCR-SARLock-odd k k' = OCR-odd 0 k k'

------------------------------------------------------------------------
--  Quantify the contrast: SARLock has constant corruption 2, whereas
--  SFLL-HD corruption grows with radius. At n=4, SARLock ≤ 2 while
--  SFLL-HD² gives 2·C(4,2) = 12.

_ : binom 4 0 + binom 4 0 ≡ 2
_ = refl

_ : binom 4 2 + binom 4 2 ≡ 12
_ = refl
