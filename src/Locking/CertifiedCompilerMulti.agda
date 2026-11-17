------------------------------------------------------------------------
--  Extend certified locking compilation to multiple outputs, addressing (ii).
--  compileSFLL certifies a single-output host. Given CF : Circuit n k,
--  possibly a full benchmark from importMulti, its denotation proof, a
--  protected index j, radius hF, and an odd-distance key pair, compileSFLLMulti
--  emits all outputs and proves lockedVec semantics. Output j is SFLL-HD
--  locked; the other k−1 outputs pass through. Width-generic emission,
--  emit : Circuit n m → Vec (Expr n) m, carries emit-sound composed with
--  locked-multi-correct to every output. Exact OCR and approximate
--  resistance concern only cone λ y → lookup (F y) j. Other outputs have
--  zero corruption, so block OCR equals this cone's OCR. The original
--  single-protected-output construction leaves simultaneous locking and
--  joint cross-output analysis for further work. As in the single-output
--  compiler, records contain emitted netlists without rendered text. The
--  construction repackages verified components without new primitives or
--  postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.CertifiedCompilerMulti where

open import Data.Nat using (ℕ; suc; _+_; _≤_)
open import Data.Fin using (Fin; toℕ)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; trans)

open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (binom)
open import Security.OCR using (OCR; OCR-odd)
open import Attack.AppSAT using (ApproxKey; SFLL-approx-needs)
open import Extraction.Bench using (Expr; eval; emit; emit-sound)
open import SFLL.EfficientLockMulti using (lockedVec; locked-multi; locked-multi-correct; locked-multi-set)
open import Security.MultiOCR using (lockedSet; locked-multi-set-denotes)

private
  variable
    n k : ℕ

------------------------------------------------------------------------
--  Pair a multi-output emission with its certificate, using radius h = toℕ hF
--  and protected output j.

record CompiledLockMulti (j : Fin k) (h : ℕ) (ksec kapp : Vec Bool n)
                         (F : Vec Bool n → Vec Bool k) : Set where
  field
    --  Store the flattened gate-level netlist with all k outputs.
    expr     : Vec (Expr n) k
    --  Certify that the emitted netlist denotes the locked output vector.
    denotes  : (x : Vec Bool n) → eval expr x ≡ lockedVec j h ksec kapp F x
    --  Attain the protected output's certified corruption rate exactly.
    ocrValue : ℕ
    meetsOCR : OCR h ksec kapp ≡ ocrValue
    --  Require an ε-approximate key for the protected cone to tolerate ocrValue.
    resist   : {ε : ℕ} →
               ApproxKey h ksec kapp (λ y → lookup (F y) j) ε → ocrValue ≤ ε

------------------------------------------------------------------------
--  Compile CF denoting F into a certified SFLL-HD emission for the full
--  multi-output design in a single call.

compileSFLLMulti :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (j : Fin k) (hF : Fin (suc n)) (ksec kapp : Vec Bool n) →
  parity (HD ksec kapp) ≡ true →
  CompiledLockMulti j (toℕ hF) ksec kapp F
compileSFLLMulti {n} CF F cf-ok j hF ksec kapp odd = record
  { expr     = emit C
  ; denotes  = λ x → trans (emit-sound C x)
                           (locked-multi-correct CF F cf-ok j hF ksec kapp x)
  ; ocrValue = binom n (toℕ hF) + binom n (toℕ hF)
  ; meetsOCR = OCR-odd (toℕ hF) ksec kapp odd
  ; resist   = SFLL-approx-needs (toℕ hF) ksec kapp (λ y → lookup (F y) j) odd
  }
  where C = locked-multi CF j hF ksec kapp

------------------------------------------------------------------------
--  Expose correctness of the emitted locked vector for every one of its
--  k outputs.

compileSFLLMulti-denotes :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (j : Fin k) (hF : Fin (suc n)) (ksec kapp : Vec Bool n)
  (odd : parity (HD ksec kapp) ≡ true) (x : Vec Bool n) →
  eval (CompiledLockMulti.expr (compileSFLLMulti CF F cf-ok j hF ksec kapp odd)) x
  ≡ lockedVec j (toℕ hF) ksec kapp F x
compileSFLLMulti-denotes CF F cf-ok j hF ksec kapp odd =
  CompiledLockMulti.denotes (compileSFLLMulti CF F cf-ok j hF ksec kapp odd)

------------------------------------------------------------------------
--  Compile a selected set P of protected outputs simultaneously. The
--  emission denotes lockedSet from Security.MultiOCR, extending protection
--  from one designated output to any chosen set.

record CompiledLockMultiSet (P : Fin k → Bool) (h : ℕ) (ksec kapp : Vec Bool n)
                            (F : Vec Bool n → Vec Bool k) : Set where
  field
    expr     : Vec (Expr n) k
    --  Certify lockedSet semantics for every selected output in the emission.
    denotes  : (x : Vec Bool n) → eval expr x ≡ lockedSet P h ksec kapp F x
    --  Record certified single-cone OCR, equal to the joint rate for nonempty P.
    ocrValue : ℕ
    meetsOCR : OCR h ksec kapp ≡ ocrValue

compileSFLLMultiSet :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (P : Fin k → Bool) (hF : Fin (suc n)) (ksec kapp : Vec Bool n) →
  parity (HD ksec kapp) ≡ true →
  CompiledLockMultiSet P (toℕ hF) ksec kapp F
compileSFLLMultiSet {n} CF F cf-ok P hF ksec kapp odd = record
  { expr     = emit C
  ; denotes  = λ x → trans (emit-sound C x)
                           (locked-multi-set-denotes CF F cf-ok P hF ksec kapp x)
  ; ocrValue = binom n (toℕ hF) + binom n (toℕ hF)
  ; meetsOCR = OCR-odd (toℕ hF) ksec kapp odd
  }
  where C = locked-multi-set CF P hF ksec kapp
