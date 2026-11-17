------------------------------------------------------------------------
-- Constant-free expression emission, lifted to the actual host compiler.
-- This is a syntactic property: constant functions may still be computed.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}
module Extraction.HostNoConst where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; true; false; _∧_)
open import Data.Fin using (Fin; zero)
open import Data.Product using (proj₁; proj₂)
open import Data.Vec using (lookup)
open import Data.List.Relation.Unary.All using () renaming ([] to []ᴬ; _∷_ to _∷ᴬ_)
open import Data.List.Relation.Unary.All.Properties using (++⁺)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Extraction.Bench using (Expr; var; con; gnot; gand; gor; gxor; gmux; emit)
open import Extraction.Netlist using (Builder; ret; _»=_; fresh; oAnd; oOr; oXor; mkNot; mkMux)
open import Extraction.HostNet using (flatE; gadgetOps)
open import Extraction.HostNetlist using (netlistWires; allInputs)
open import Extraction.LockedNetMerged using (NoConst; mkMux-noConst)
open import Locking.NetlistToCircuit using (Netlist; []; _∷_; Gate)
open Gate

cleanExpr : ∀ {n} → Expr n → Bool
cleanExpr (var _) = true
cleanExpr (con _) = false
cleanExpr (gnot e) = cleanExpr e
cleanExpr (gand a b) = cleanExpr a ∧ cleanExpr b
cleanExpr (gor a b) = cleanExpr a ∧ cleanExpr b
cleanExpr (gxor a b) = cleanExpr a ∧ cleanExpr b
cleanExpr (gmux s a b) = cleanExpr s ∧ (cleanExpr a ∧ cleanExpr b)

and-left : ∀ a b → a ∧ b ≡ true → a ≡ true
and-left true b p = refl
and-left false b ()

and-right : ∀ a b → a ∧ b ≡ true → b ≡ true
and-right true b p = p
and-right false b ()

CleanBuilder : ∀ {A} → Builder A → Set
CleanBuilder m = ∀ i → NoConst (proj₂ (proj₂ (m i)))

bind-clean : ∀ {A B} (m : Builder A) (f : A → Builder B) →
  CleanBuilder m → (∀ a → CleanBuilder (f a)) → CleanBuilder (m »= f)
bind-clean m f cm cf i = ++⁺ (cm i) (cf (proj₁ (m i)) (proj₁ (proj₂ (m i))))

flatE-noConst : ∀ {n} (e : Expr n) (ρ : Fin n → ℕ) →
  cleanExpr e ≡ true → CleanBuilder (flatE e ρ)
flatE-noConst (var x) ρ p i = []ᴬ
flatE-noConst (con x) ρ ()
flatE-noConst (gnot e) ρ p =
  bind-clean (flatE e ρ) mkNot (flatE-noConst e ρ p) (λ w i → refl ∷ᴬ []ᴬ)
flatE-noConst (gand a b) ρ p =
  bind-clean (flatE a ρ) (λ wa → flatE b ρ »= λ wb → fresh (oAnd wa wb))
    (flatE-noConst a ρ (and-left (cleanExpr a) (cleanExpr b) p))
    (λ wa → bind-clean (flatE b ρ) (λ wb → fresh (oAnd wa wb))
      (flatE-noConst b ρ (and-right (cleanExpr a) (cleanExpr b) p))
      (λ wb i → refl ∷ᴬ []ᴬ))
flatE-noConst (gor a b) ρ p =
  bind-clean (flatE a ρ) (λ wa → flatE b ρ »= λ wb → fresh (oOr wa wb))
    (flatE-noConst a ρ (and-left (cleanExpr a) (cleanExpr b) p))
    (λ wa → bind-clean (flatE b ρ) (λ wb → fresh (oOr wa wb))
      (flatE-noConst b ρ (and-right (cleanExpr a) (cleanExpr b) p))
      (λ wb i → refl ∷ᴬ []ᴬ))
flatE-noConst (gxor a b) ρ p =
  bind-clean (flatE a ρ) (λ wa → flatE b ρ »= λ wb → fresh (oXor wa wb))
    (flatE-noConst a ρ (and-left (cleanExpr a) (cleanExpr b) p))
    (λ wa → bind-clean (flatE b ρ) (λ wb → fresh (oXor wa wb))
      (flatE-noConst b ρ (and-right (cleanExpr a) (cleanExpr b) p))
      (λ wb i → refl ∷ᴬ []ᴬ))
flatE-noConst (gmux s a b) ρ p =
  bind-clean (flatE s ρ) (λ ws → flatE a ρ »= λ wa → flatE b ρ »= λ wb → mkMux ws wa wb)
    (flatE-noConst s ρ (and-left (cleanExpr s) (cleanExpr a ∧ cleanExpr b) p))
    (λ ws → bind-clean (flatE a ρ) (λ wa → flatE b ρ »= λ wb → mkMux ws wa wb)
      (flatE-noConst a ρ (and-left (cleanExpr a) (cleanExpr b) ab))
      (λ wa → bind-clean (flatE b ρ) (λ wb → mkMux ws wa wb)
        (flatE-noConst b ρ (and-right (cleanExpr a) (cleanExpr b) ab))
        (λ wb → mkMux-noConst ws wa wb)))
  where ab = and-right (cleanExpr s) (cleanExpr a ∧ cleanExpr b) p

cleanHost : ∀ {n G} → Netlist n G → Bool
cleanHost [] = true
cleanHost (gt ∷ nl) = cleanExpr (lookup (emit (g gt)) zero) ∧ cleanHost nl

netlistWires-noConst : ∀ {n G} (nl : Netlist n G) →
  cleanHost nl ≡ true → CleanBuilder (netlistWires nl)
netlistWires-noConst {n} [] p i = []ᴬ
netlistWires-noConst (gt ∷ nl) p =
  bind-clean (netlistWires nl)
    (λ ws → gadgetOps (g gt) (lookup ws (a gt)) (lookup ws (b gt)) »= λ w → ret (w Data.Vec.∷ ws))
    (netlistWires-noConst nl (and-right ce (cleanHost nl) p))
    (λ ws → bind-clean (gadgetOps (g gt) (lookup ws (a gt)) (lookup ws (b gt)))
      (λ w → ret (w Data.Vec.∷ ws))
      (flatE-noConst (lookup (emit (g gt)) zero) _ (and-left ce (cleanHost nl) p))
      (λ w i → []ᴬ))
  where ce = cleanExpr (lookup (emit (g gt)) zero)
