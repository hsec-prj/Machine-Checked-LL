------------------------------------------------------------------------
--  Generalise certified locking compilation across schemes (M3).
--  Locking.CertifiedCompiler.compileSFLL certifies emitted SFLL-HD netlists.
--  Its generic counterpart accepts a host and any pair of ProtGadget values
--  from Locking.GenericLock. The emitted netlist carries a machine-checked
--  proof of the generic locked function and the predicates' OCR-gen
--  corruption value. Supplying the corresponding gadgets instantiates
--  SFLL-HD, SARLock, or SFLL-flex; the generic calculus yields their exact
--  corruption, including compile-gen-sfll-OCR-odd = 2·C(n,h) and the
--  compile-gen-point-≤2 bound ≤ 2. As with CompiledLock, the record ends at
--  the emitted netlist and contains no rendered text.
--  This repackages locked-circuit-gen-correct composed
--  with emit-sound, without adding primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.GenericCompiler where

open import Data.Nat using (ℕ; suc; _+_; _≤_)
open import Data.Fin using (Fin; toℕ)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans)

open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import Extraction.Bench using (Expr; eval; emit; emit-sound)
open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (binom)
open import Security.CorruptionCalculus using (calc-OCR-odd)
open import Locking.GenericLock
  using (ProtGadget; locked-circuit-gen; locked-circuit-gen-correct;
         locked-fun-gen; ocrGen-of; sfllGadget; pointGadget; point-ocr-≤2)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Package the generic emitted lock with its correctness certificate.

record CompiledGenLock (gS gA : ProtGadget n) (f : Vec Bool n → Bool) : Set where
  field
    expr     : Vec (Expr n) 1
    --  Certify that the emitted netlist denotes the generic locked function.
    denotes  : (x : Vec Bool n) → eval expr x ≡ locked-fun-gen f gS gA x ∷ []
    --  Identify corruption with the two predicates' symmetric-difference count.
    ocrValue : ℕ
    meetsOCR : ocrGen-of gS gA ≡ ocrValue

------------------------------------------------------------------------
--  Compile a host circuit and two protection gadgets into a certified netlist.

compile-gen :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (gS gA : ProtGadget n) → CompiledGenLock gS gA f
compile-gen Cf f cf-ok gS gA = record
  { expr     = emit C
  ; denotes  = λ x → trans (emit-sound C x) (locked-circuit-gen-correct Cf f cf-ok gS gA x)
  ; ocrValue = ocrGen-of gS gA
  ; meetsOCR = refl
  }
  where C = locked-circuit-gen Cf gS gA

------------------------------------------------------------------------
--  Principal consequences.

--  By construction, the emitted artifact implements the locked function.
compile-gen-denotes :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (gS gA : ProtGadget n) (x : Vec Bool n) →
  eval (CompiledGenLock.expr (compile-gen Cf f cf-ok gS gA)) x
  ≡ locked-fun-gen f gS gA x ∷ []
compile-gen-denotes Cf f cf-ok gS gA =
  CompiledGenLock.denotes (compile-gen Cf f cf-ok gS gA)

--  For odd-distance SFLL-HD, certify the exact corruption value 2·C(n,h).
compile-gen-sfll-OCR-odd :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (hF : Fin (suc n)) (ksec kapp : Vec Bool n) → parity (HD ksec kapp) ≡ true →
  CompiledGenLock.ocrValue (compile-gen Cf f cf-ok (sfllGadget hF ksec) (sfllGadget hF kapp))
  ≡ binom n (toℕ hF) + binom n (toℕ hF)
compile-gen-sfll-OCR-odd Cf f cf-ok hF ksec kapp odd =
  calc-OCR-odd (toℕ hF) ksec kapp odd

--  For SARLock/point locks, certify corruption at most 2 in the point regime.
compile-gen-point-≤2 :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (k k' : Vec Bool n) →
  CompiledGenLock.ocrValue (compile-gen Cf f cf-ok (pointGadget k) (pointGadget k')) ≤ 2
compile-gen-point-≤2 Cf f cf-ok k k' = point-ocr-≤2 k k'
