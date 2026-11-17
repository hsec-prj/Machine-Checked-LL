------------------------------------------------------------------------
--  Express OCR probabilistically. Finite distributions are lists of outcomes
--  with natural-number weights, keeping the development rational-free and
--  --safe. `Pr p d` represents event probability by (favourable weight, total
--  weight). Under uniform inputs, the deterministic OCR count becomes the
--  corruption probability `OCR / 2ⁿ`; for odd-distance wrong keys,
--  Pr-OCR-bound gives `2·C(n,h) / 2ⁿ`. The distributions constructed here,
--  unifInputs, concern inputs, so these quantities are normalised corruption
--  rates. No adversary or asymptotic analysis is present, and no security
--  advantage is defined. The monad's sole use on keys is in
--  Attack.ProbQueryBound.unifKeys, which directly reuses uniform, prob, and
--  total to express a query lower bound as Pr[recover] ≤ (q + 1) / 2ⁿ.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Security.Dist where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _^_)
open import Data.Bool using (Bool; true; if_then_else_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Vec using (Vec)
open import Data.List using (List; []; _∷_; map; length; concatMap)
open import Data.Nat.ListAction using (sum)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; cong₂; trans)

open import SFLL.HammingDistance using (HD; parity)
open import Util.Counting using (countT; allVecs; length-allVecs; binom)
open import Security.OCR using (corrupt; OCR; OCR-odd)

private
  variable
    A B : Set
    n : ℕ

------------------------------------------------------------------------
--  Define a monad for finite distributions represented by weighted outcomes.

Dist : Set → Set
Dist A = List (A × ℕ)

return : A → Dist A
return x = (x , 1) ∷ []

_>>=_ : Dist A → (A → Dist B) → Dist B
d >>= f = concatMap (λ aw → map (λ bw → (proj₁ bw , proj₂ aw * proj₂ bw)) (f (proj₁ aw))) d

--  Sum all weights and the weights satisfying a Boolean event.
total : Dist A → ℕ
total d = sum (map proj₂ d)

prob : (A → Bool) → Dist A → ℕ
prob p d = sum (map (λ aw → if p (proj₁ aw) then proj₂ aw else 0) d)

--  Represent probability by (favourable weight, total weight), avoiding rationals.
Pr : (A → Bool) → Dist A → ℕ × ℕ
Pr p d = prob p d , total d

--  Assign weight 1 to every outcome of a finite support to obtain uniformity.
uniform : List A → Dist A
uniform = map (λ x → (x , 1))

------------------------------------------------------------------------
--  Relate weighted quantities to the deterministic count.

total-uniform : (xs : List A) → total (uniform xs) ≡ length xs
total-uniform []       = refl
total-uniform (x ∷ xs) = cong suc (total-uniform xs)

prob-uniform : (p : A → Bool) (xs : List A) → prob p (uniform xs) ≡ countT p xs
prob-uniform p []       = refl
prob-uniform p (x ∷ xs) = cong ((if p x then 1 else 0) +_) (prob-uniform p xs)

------------------------------------------------------------------------
--  Interpret OCR over the uniform distribution on inputs.

unifInputs : (n : ℕ) → Dist (Vec Bool n)
unifInputs n = uniform (allVecs n)

--  A uniformly sampled input is corrupted with probability OCR / 2ⁿ.
Pr-OCR : (h : ℕ) (k k' : Vec Bool n) →
         Pr (corrupt h k k') (unifInputs n) ≡ (OCR h k k' , 2 ^ n)
Pr-OCR {n = n} h k k' =
  cong₂ _,_ (prob-uniform (corrupt h k k') (allVecs n))
            (trans (total-uniform (allVecs n)) (length-allVecs n))

--  For an odd-distance wrong key, normalising the closed form gives precisely
--  2·C(n,h) / 2ⁿ as the corruption probability.
Pr-OCR-bound : (h : ℕ) (k k' : Vec Bool n) → parity (HD k k') ≡ true →
               Pr (corrupt h k k') (unifInputs n) ≡ (binom n h + binom n h , 2 ^ n)
Pr-OCR-bound {n = n} h k k' odd =
  trans (Pr-OCR h k k') (cong (_, 2 ^ n) (OCR-odd h k k' odd))
