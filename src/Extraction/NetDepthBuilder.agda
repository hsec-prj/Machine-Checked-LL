------------------------------------------------------------------------
--  Relating builder allocation to wire positions
--  Every builder advances its fresh identifier by precisely its emitted
--  gate count. The tight comparator-depth proof needs to identify that
--  allocated wire with its position in the environment folded by `runLevels`.
--  Builders composed from `ret`, `fresh`, `»=`, `mapMB`, and `foldlMB`
--  satisfy `id₂ = id₁ + (gates emitted)`. Hence a new gate occupies the
--  environment position designated by the current fresh identifier.
--  Checked with `--safe --without-K`, using zero postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthBuilder where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_)
open import Data.Nat.Properties using (+-comm; +-assoc; +-identityʳ; m≤m+n)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.List.Properties using (length-++)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; sym; trans; subst)

open import Extraction.Netlist using (Builder; ret; fresh; _»=_; mapMB; foldlMB; Op; mkMux; mkNot; mkAnd; oNot; oAnd; oOr)

------------------------------------------------------------------------
--  The allocation invariant: final fresh-id = initial fresh-id + emitted gate count.

CntLaw : {A : Set} → Builder A → Set
CntLaw m = (i : ℕ) → proj₁ (proj₂ (m i)) ≡ i + length (proj₂ (proj₂ (m i)))

------------------------------------------------------------------------
--  The builder constructors maintain the invariant.

ret-cnt : {A : Set} (a : A) → CntLaw (ret a)
ret-cnt a i = sym (+-identityʳ i)

fresh-cnt : (op : Op) → CntLaw (fresh op)
fresh-cnt op i = +-comm 1 i

»=-cnt : {A B : Set} (m : Builder A) (f : A → Builder B) →
           CntLaw m → ((a : A) → CntLaw (f a)) → CntLaw (m »= f)
»=-cnt m f im if i with m i | im i
... | a , i₁ , o₁ | eq1 with f a i₁ | if a i₁
... | b , i₂ , o₂ | eq2 =
  trans eq2 (trans (cong (_+ length o₂) eq1)
                   (trans (+-assoc i (length o₁) (length o₂))
                          (cong (i +_) (sym (length-++ o₁)))))

------------------------------------------------------------------------
--  The iterator constructors maintain the invariant as well.

mapMB-cnt-general : {B : Set} (f : ℕ × ℕ → Builder B) →
              ((p : ℕ × ℕ) → CntLaw (f p)) → (xs : List (ℕ × ℕ)) → CntLaw (mapMB f xs)
mapMB-cnt-general {B = B} f hf []       = ret-cnt {A = List B} []
mapMB-cnt-general {B = B} f hf (x ∷ xs) = »=-cnt (f x) cont (hf x) contLen
  where
    cont : B → Builder (List B)
    cont y = _»=_ {A = List B} {B = List B} (mapMB f xs) (λ ys → ret (y ∷ ys))
    contLen : (y : B) → CntLaw (cont y)
    contLen y = »=-cnt (mapMB f xs) (λ ys → ret (y ∷ ys))
                         (mapMB-cnt-general f hf xs) (λ ys → ret-cnt (y ∷ ys))

foldlMB-cnt-general : (f : List ℕ → ℕ → Builder (List ℕ)) →
                ((acc : List ℕ) (x : ℕ) → CntLaw (f acc x)) →
                (acc : List ℕ) (xs : List ℕ) → CntLaw (foldlMB f acc xs)
foldlMB-cnt-general f hf acc []       = ret-cnt acc
foldlMB-cnt-general f hf acc (x ∷ xs) = »=-cnt (f acc x) cont (hf acc x) contLen
  where
    cont : List ℕ → Builder (List ℕ)
    cont acc′ = foldlMB f acc′ xs
    contLen : (acc′ : List ℕ) → CntLaw (cont acc′)
    contLen acc′ = foldlMB-cnt-general f hf acc′ xs

mkMux-cnt : (s a b : ℕ) → CntLaw (mkMux s a b)
mkMux-cnt s a b =
  »=-cnt (mkNot s)
         (λ ns → mkAnd a ns »= (λ t1 → mkAnd b s »= (λ t2 → fresh (oOr t1 t2))))
         (fresh-cnt (oNot s))
         (λ ns → »=-cnt (mkAnd a ns)
                        (λ t1 → mkAnd b s »= (λ t2 → fresh (oOr t1 t2)))
                        (fresh-cnt (oAnd a ns))
                        (λ t1 → »=-cnt (mkAnd b s) (λ t2 → fresh (oOr t1 t2))
                                       (fresh-cnt (oAnd b s))
                                       (λ t2 → fresh-cnt (oOr t1 t2))))

cnt-mono : {Value : Set} (builder : Builder Value) → CntLaw builder →
           (start : ℕ) → start ≤ proj₁ (proj₂ (builder start))
cnt-mono builder allocation start =
  subst (start ≤_) (sym (allocation start))
        (m≤m+n start (length (proj₂ (proj₂ (builder start)))))
