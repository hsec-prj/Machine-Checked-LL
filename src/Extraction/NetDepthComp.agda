------------------------------------------------------------------------
--  Assemble comparator depth from independent mux rows
--  Although emitted sequentially, independent mux gadgets form one
--  depth-3 thermometer step. Each O(n)-wide row reads only the previous
--  thermometer, below the row's base, so width does not affect depth.
--  muxSeq-bound lifts mux-bound using runLevels-++ and stable wire
--  levels. Stacking N such rows yields O(N) depth.
--  Uses --safe --without-K and zero postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthComp where

open import Data.Nat using (ℕ; zero; suc; _+_; _⊔_; _<_; _≤_; s≤s; z≤n)
open import Data.Nat.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-identityʳ; +-suc; +-comm; m≤m⊔n; m≤n+m; n≤1+n)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.Unit using (⊤; tt)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; cong; trans)

open import Extraction.Netlist using (Op)
open import Extraction.NetDepth using (getL; maxL; opLevel; runLevels; ⊔-lub; runLevels-++)
open import Extraction.NetDepthBlock using (runLevels-stable; getL-++-prefix)
open import Extraction.NetDepthMux using (muxOps; mux-bound; n≤m⊔n)

------------------------------------------------------------------------
--  A block grows the environment by its operation count, one wire per gate.

runLevels-len : (lv : List ℕ) (ops : List Op) →
                length (runLevels lv ops) ≡ length lv + length ops
runLevels-len lv []         = sym (+-identityʳ (length lv))
runLevels-len lv (op ∷ ops) =
  trans (runLevels-len (lv ++ (opLevel lv op ∷ [])) ops)
        (trans (cong (_+ length ops) (lensnoc lv (opLevel lv op)))
               (sym (+-suc (length lv) (length ops))))
  where
    lensnoc : (xs : List ℕ) (y : ℕ) → length (xs ++ (y ∷ [])) ≡ suc (length xs)
    lensnoc []       y = refl
    lensnoc (x ∷ xs) y = cong suc (lensnoc xs y)

--  A mux's four gates increase the environment length by four.
muxOps-len : (lv : List ℕ) (s a b : ℕ) →
             length (runLevels lv (muxOps s a b (length lv))) ≡ 4 + length lv
muxOps-len lv s a b =
  trans (runLevels-len lv (muxOps s a b (length lv)))
        (+-comm (length lv) 4)

------------------------------------------------------------------------
--  Place muxes at successive positions, with each reading below len.
--  The triple (s,a,b) gives a mux's external inputs.

concatMux : List (ℕ × ℕ × ℕ) → (len : ℕ) → List Op
concatMux []                 len = []
concatMux ((s , a , b) ∷ ms) len = muxOps s a b len ++ concatMux ms (4 + len)

--  Require all three inputs of every mux to precede base.
AllInBase : List (ℕ × ℕ × ℕ) → ℕ → Set
AllInBase []                 base = ⊤
AllInBase ((s , a , b) ∷ ms) base = ((s < base) × (a < base) × (b < base)) × AllInBase ms base

------------------------------------------------------------------------
--  For any row width, inputs below base in an lv prefix with levels ≤ M
--  give at most a three-level increase in the maximum.

muxSeq-bound :
  (base M : ℕ) (lv : List ℕ) (ms : List (ℕ × ℕ × ℕ)) →
  base ≤ length lv →
  ((i : ℕ) → i < base → getL lv i ≤ M) →
  AllInBase ms base →
  maxL (runLevels lv (concatMux ms (length lv))) ≤ maxL lv ⊔ suc (suc (suc M))
muxSeq-bound base M lv []                 b≤l H _ =
  m≤m⊔n (maxL lv) (suc (suc (suc M)))
muxSeq-bound base M lv ((s , a , b) ∷ ms) b≤l H ((s<b , a<b , b<b) , rest) =
  ≤-trans (≤-reflexive (cong maxL split)) rec
  where
    s<l : s < length lv
    s<l = ≤-trans s<b b≤l
    a<l : a < length lv
    a<l = ≤-trans a<b b≤l
    b<l : b < length lv
    b<l = ≤-trans b<b b≤l

    lv' = runLevels lv (muxOps s a b (length lv))

    --  Split operations after the first mux, using 4+|lv| = |lv'| for position alignment.
    split : runLevels lv (concatMux ((s , a , b) ∷ ms) (length lv))
          ≡ runLevels lv' (concatMux ms (length lv'))
    split = trans (runLevels-++ lv (muxOps s a b (length lv)) (concatMux ms (4 + length lv)))
                  (cong (runLevels lv') (cong (concatMux ms) (sym (muxOps-len lv s a b))))

    --  The first mux increases the maximum by no more than three.
    head-le : maxL lv' ≤ maxL lv ⊔ suc (suc (suc M))
    head-le = mux-bound lv s a b M s<l a<l b<l (H s s<l′) (H a a<l′) (H b b<l′)
      where s<l′ = s<b ; a<l′ = a<b ; b<l′ = b<b

    --  Establish the recursive premises for the enlarged lv'.
    b≤l' : base ≤ length lv'
    b≤l' = ≤-trans b≤l (≤-trans (m≤n+m (length lv) 4)
                                (≤-reflexive (sym (muxOps-len lv s a b))))
    H' : (i : ℕ) → i < base → getL lv' i ≤ M
    H' i i<b = ≤-trans (≤-reflexive (runLevels-stable lv (muxOps s a b (length lv)) i
                                       (≤-trans i<b b≤l)))
                       (H i i<b)
    rec : maxL (runLevels lv' (concatMux ms (length lv'))) ≤ maxL lv ⊔ suc (suc (suc M))
    rec = ≤-trans (muxSeq-bound base M lv' ms b≤l' H' rest)
                  (⊔-lub head-le (n≤m⊔n (maxL lv) (suc (suc (suc M)))))

------------------------------------------------------------------------
--  Identify mapMB (mkMux bit …) output with the abstract concatMux row,
--  allowing muxSeq-bound to apply to the concrete builder.

open import Extraction.Netlist using (mkMux; mapMB)
open import Data.List using (map)
open import Data.List.Properties using (++-identityʳ)


rowSpecs : ℕ → List (ℕ × ℕ) → List (ℕ × ℕ × ℕ)
rowSpecs bit = map (λ p → bit , proj₁ p , proj₂ p)

mapMB-mux-ops : (bit : ℕ) (ps : List (ℕ × ℕ)) (i : ℕ) →
  proj₂ (proj₂ (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps i))
    ≡ concatMux (rowSpecs bit ps) i
mapMB-mux-ops bit []       i = refl
mapMB-mux-ops bit (p ∷ ps) i =
  cong (muxOps bit (proj₁ p) (proj₂ p) i ++_)
       (trans (++-identityʳ _)
              (mapMB-mux-ops bit ps (suc (suc (suc (suc i))))))
