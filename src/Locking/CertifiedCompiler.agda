------------------------------------------------------------------------
--  Compile a specification into a certified emitted lock (2b).
--  Locking.Synthesis gives CertifiedScheme a Circuit n 1 and proofs of
--  soundness, exact OCR, and a resistance floor. The delivered artifact is
--  the flattened gate-level netlist, so carry those certificates through
--  Extraction.Bench.emit. Compose emit-sound, eval (emit c) ≡ ⟦ c ⟧, with
--  scheme soundness to obtain
--  denotes : eval (emit netlist) x ≡ locked h ksec kapp f x ∷ [].
--  CompiledLock attaches a required proof object directly to the emission.
--  Its record intentionally ends at the netlist. Flat shipping text uses
--  certified Extraction.Render.renderNet.
--  compileSFLL combines data circuit through certified emission
--  in one call, repackaging the verified components without primitives or
--  postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Locking.CertifiedCompiler where

open import Data.Nat using (ℕ; _+_; _≤_)
open import Data.Bool using (Bool; true)
open import Data.Vec using (Vec; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; trans)

open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import SFLL.HD using (locked)
open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (binom)
open import Security.OCR using (OCR)
open import Attack.AppSAT using (ApproxKey)
open import Locking.Synthesis using (CertifiedScheme; synthSFLL)
open import Extraction.Bench using (Expr; eval; emit; emit-sound)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Pair the emitted locked artifact with its certificate.

record CompiledLock (h : ℕ) (ksec kapp : Vec Bool n)
                    (f : Vec Bool n → Bool) : Set where
  field
    --  Store the flattened single-output gate-level netlist.
    expr     : Vec (Expr n) 1
    --  Prove that this emission denotes the SFLL-HD locked function.
    denotes  : (x : Vec Bool n) → eval expr x ≡ locked h ksec kapp f x ∷ []
    --  Record and attain the exact certified output corruption rate.
    ocrValue : ℕ
    meetsOCR : OCR h ksec kapp ≡ ocrValue
    --  Require any ε-approximate key to tolerate at least ocrValue.
    resist   : {ε : ℕ} → ApproxKey h ksec kapp f ε → ocrValue ≤ ε

------------------------------------------------------------------------
--  Emit a CertifiedScheme while preserving its accompanying proofs.

compile : {h : ℕ} {ksec kapp : Vec Bool n} {f : Vec Bool n → Bool} →
          CertifiedScheme h ksec kapp f → CompiledLock h ksec kapp f
compile cs = record
  { expr     = emit nl
  ; denotes  = λ x → trans (emit-sound nl x) (CertifiedScheme.sound cs x)
  ; ocrValue = CertifiedScheme.ocrValue cs
  ; meetsOCR = CertifiedScheme.meetsOCR cs
  ; resist   = CertifiedScheme.resist cs
  }
  where nl = CertifiedScheme.netlist cs

------------------------------------------------------------------------
--  Compile a data circuit Cf denoting f into a certified emitted SFLL-HD
--  netlist, providing the specification-to-certified-silicon pipeline in one call.

compileSFLL :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp : Vec Bool n) → parity (HD ksec kapp) ≡ true →
  CompiledLock h ksec kapp f
compileSFLL Cf f cf-ok h ksec kapp odd =
  compile (synthSFLL Cf f cf-ok h ksec kapp odd)

------------------------------------------------------------------------
--  Expose the main guarantees directly from the compiled artifact.

--  Establish the locked-function denotation by construction.
compileSFLL-denotes :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp : Vec Bool n) (odd : parity (HD ksec kapp) ≡ true)
  (x : Vec Bool n) →
  eval (CompiledLock.expr (compileSFLL Cf f cf-ok h ksec kapp odd)) x
  ≡ locked h ksec kapp f x ∷ []
compileSFLL-denotes Cf f cf-ok h ksec kapp odd =
  CompiledLock.denotes (compileSFLL Cf f cf-ok h ksec kapp odd)

--  Give the emitted artifact's exact certified rate 2·C(n,h).
compileSFLL-OCR :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp : Vec Bool n) (odd : parity (HD ksec kapp) ≡ true) →
  OCR h ksec kapp ≡ binom n h + binom n h
compileSFLL-OCR Cf f cf-ok h ksec kapp odd =
  CompiledLock.meetsOCR (compileSFLL Cf f cf-ok h ksec kapp odd)
