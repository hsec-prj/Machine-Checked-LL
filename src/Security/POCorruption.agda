------------------------------------------------------------------------
--  Relate protected-block corruption to primary-output disagreement.
--  Security.OCR counts disagreement at the protected block. For each
--  input x, a supplied host x : Bool → Bool propagates its signal s;
--  host x false xor host x true is observability ∂PO/∂s.
--  If two keys yield s0 x and s1 x, then
--  PO-disagree(x) ≡ block-disagree(x) ∧ observability(x).
--  The primary output changes exactly when the block changes and the
--  host depends on it at that input. Counting gives OCR-PO-≤-OCR, since
--  the host only masks, and OCR-PO-id-≡-OCR, equality when the signal
--  itself is the primary output. For a supplied Boolean host slice,
--  only corrupted inputs that are observable contribute to ocrPO.
--  No additional primitive or postulate is required.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.POCorruption where

open import Data.Nat using (ℕ; suc; _+_; _≤_; z≤n; s≤s)
open import Data.Nat.Properties using (+-mono-≤; ≤-trans; ≤-reflexive)
open import Data.Bool using (Bool; true; false; _∧_; _xor_; if_then_else_)
open import Data.Bool.Properties using (xor-same; xor-comm; ∧-identityʳ)
open import Data.Vec using (Vec)
open import Data.List using (List; []; _∷_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; trans; sym)

open import Util.Counting using (countT; countT-mono; allVecs; countT-cong)
open import SFLL.HD using (prot)
open import Security.OCR using (OCR)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Local counting helpers follow Util.Counting's recursion.

private
  ∧-true-l : (a b : Bool) → (a ∧ b) ≡ true → a ≡ true
  ∧-true-l true  b _ = refl
  ∧-true-l false b ()

------------------------------------------------------------------------
--  Prove the pointwise identity as a Boolean tautology on the host slice.

--  Two signal values produce different primary outputs precisely when
--  they differ and the host distinguishes them, via host false xor host true.
host-xor-char : (host : Bool → Bool) (a b : Bool) →
                (host a xor host b) ≡ (a xor b) ∧ (host false xor host true)
host-xor-char host false false = xor-same (host false)
host-xor-char host false true  = refl
host-xor-char host true  false = xor-comm (host true) (host false)
host-xor-char host true  true  = xor-same (host true)

------------------------------------------------------------------------
--  Define block disagreement, output disagreement, and observability predicates.

--  At x, block disagreement means the keys drive different protected bits.
bDisagree : (s0 s1 : Vec Bool n → Bool) → Vec Bool n → Bool
bDisagree s0 s1 x = s0 x xor s1 x

--  Define ∂PO/∂s for the host slice at input x.
obs : (host : Vec Bool n → Bool → Bool) → Vec Bool n → Bool
obs host x = host x false xor host x true

--  Define primary-output disagreement at x.
poDisagree : (host : Vec Bool n → Bool → Bool) (s0 s1 : Vec Bool n → Bool) →
             Vec Bool n → Bool
poDisagree host s0 s1 x = host x (s0 x) xor host x (s1 x)

--  Factor output disagreement into the two pointwise conditions.
poDisagree-char : (host : Vec Bool n → Bool → Bool) (s0 s1 : Vec Bool n → Bool)
                  (x : Vec Bool n) →
                  poDisagree host s0 s1 x ≡ bDisagree s0 s1 x ∧ obs host x
poDisagree-char host s0 s1 x = host-xor-char (host x) (s0 x) (s1 x)

------------------------------------------------------------------------
--  Count the predicate-satisfying inputs.

--  Count corrupted protected bits, matching Security.OCR for SFLL keys.
ocrBlock : (s0 s1 : Vec Bool n → Bool) → ℕ
ocrBlock {n} s0 s1 = countT (bDisagree s0 s1) (allVecs n)

--  Count primary-output corruptions after propagation through the host.
ocrPO : (host : Vec Bool n → Bool → Bool) (s0 s1 : Vec Bool n → Bool) → ℕ
ocrPO {n} host s0 s1 = countT (poDisagree host s0 s1) (allVecs n)

------------------------------------------------------------------------
--  Establish the relationships between the counts.

--  Block OCR bounds observed corruption from above. An insensitive host
--  can hide a change, but it cannot create a change absent at the block.
ocrPO-≤-ocrBlock : (host : Vec Bool n → Bool → Bool) (s0 s1 : Vec Bool n → Bool) →
                   ocrPO host s0 s1 ≤ ocrBlock s0 s1
ocrPO-≤-ocrBlock {n} host s0 s1 =
  countT-mono (poDisagree host s0 s1) (bDisagree s0 s1) (allVecs n)
    (λ x e → ∧-true-l (bDisagree s0 s1 x) (obs host x)
                      (trans (sym (poDisagree-char host s0 s1 x)) e))

--  When the signal reaches the output without masking, full observability
--  makes the upper bound an equality.
ocrPO-≡-ocrBlock-full :
  (host : Vec Bool n → Bool → Bool) (s0 s1 : Vec Bool n → Bool) →
  (∀ x → obs host x ≡ true) → ocrPO host s0 s1 ≡ ocrBlock s0 s1
ocrPO-≡-ocrBlock-full {n} host s0 s1 fullObs =
  countT-cong
    (λ x → trans (poDisagree-char host s0 s1 x)
                 (trans (cong (bDisagree s0 s1 x ∧_) (fullObs x))
                        (∧-identityʳ (bDisagree s0 s1 x))))
    (allVecs n)

------------------------------------------------------------------------
--  Instantiate the predicates for SFLL, identifying block disagreement with OCR.

--  For SFLL keys, corrupt is the disagreement indicator and OCR its count.
ocrBlock-SFLL : (h : ℕ) (ksec kapp : Vec Bool n) →
                ocrBlock (prot h ksec) (prot h kapp) ≡ OCR h ksec kapp
ocrBlock-SFLL h ksec kapp = refl

--  Use the identity host when the locked-block output is itself the primary output.
idHost : Vec Bool n → Bool → Bool
idHost _ s = s

idHost-obs : (x : Vec Bool n) → obs idHost x ≡ true
idHost-obs x = refl

--  In the single-output OCR model, the protected signal directly reaches
--  the output, so primary-output and block corruption coincide exactly.
--  The difference between these two mathematical counts is zero in this case.
OCR-PO-id-≡-OCR : (h : ℕ) (ksec kapp : Vec Bool n) →
                  ocrPO idHost (prot h ksec) (prot h kapp) ≡ OCR h ksec kapp
OCR-PO-id-≡-OCR h ksec kapp =
  trans (ocrPO-≡-ocrBlock-full idHost (prot h ksec) (prot h kapp) idHost-obs)
        (ocrBlock-SFLL h ksec kapp)

--  For a general host, exact block OCR upper-bounds what the attacker
--  observes because host observability can only reduce the count.
OCR-PO-≤-OCR : (host : Vec Bool n → Bool → Bool)
               (h : ℕ) (ksec kapp : Vec Bool n) →
               ocrPO host (prot h ksec) (prot h kapp) ≤ OCR h ksec kapp
OCR-PO-≤-OCR host h ksec kapp =
  ≤-trans (ocrPO-≤-ocrBlock host (prot h ksec) (prot h kapp))
          (≤-reflexive (ocrBlock-SFLL h ksec kapp))
