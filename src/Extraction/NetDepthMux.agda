------------------------------------------------------------------------
--  Wire-lookup support for the tight comparator bound
--  The four gates of mkMux have depth 3. When their three input levels
--  are at most M, every resulting level is at most M+3. This gadget bound
--  lifts through mapMB over one thermometer step and foldlMB over N steps,
--  giving an O(N) critical path. mkMux s a b i definitionally reduces to
--  muxOps s a b i, so runLevels evaluates exactly those four operations.
--  The proof relies on lookup of newly appended wires and preservation
--  of prefix lookups, established here before the four-step arithmetic.
--  Uses --safe --without-K with no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthMux where

open import Data.Nat using (ℕ; zero; suc; _<_; _≤_; _⊔_; s≤s; z≤n)
open import Data.Nat.Properties using (≤-reflexive; ≤-refl; ≤-trans; m≤m⊔n; n≤1+n)
open import Data.List using (List; []; _∷_; _++_; length)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; cong; trans)

open import Extraction.Netlist using (Op; oNot; oAnd; oOr)
open import Extraction.NetDepth using (getL; maxL; opLevel; runLevels; ⊔-lub; maxL-snoc)
open import Extraction.NetDepthBlock using (getL-++-prefix; length-snoc)

------------------------------------------------------------------------
--  Define mkMux's four-operation reduct muxOps.
--  The identity mkMux s a b i ≡ (_, _, muxOps s a b i) holds by refl.

muxOps : (s a b i : ℕ) → List Op
muxOps s a b i = oNot s ∷ oAnd a i ∷ oAnd b s ∷ oOr (suc i) (suc (suc i)) ∷ []

------------------------------------------------------------------------
--  Reading the last appended wire returns its assigned level.

getL-snoc-last : (lv : List ℕ) (x : ℕ) → getL (lv ++ (x ∷ [])) (length lv) ≡ x
getL-snoc-last []       x = refl
getL-snoc-last (y ∷ lv) x = getL-snoc-last lv x

--  Express prefix-lookup preservation as an inequality for one snoc,
--  the level-list counterpart of runLevels-stable.
getL-prefix-≤ : (lv : List ℕ) (x a : ℕ) → a < length lv →
                getL (lv ++ (x ∷ [])) a ≤ getL lv a
getL-prefix-≤ lv x a a<l = ≤-reflexive (getL-++-prefix lv (x ∷ []) a a<l)

------------------------------------------------------------------------
--  Bound a mux gadget: external inputs s,a,b below length lv and at
--  levels ≤ M give final maximum ≤ maxL lv ⊔ (M+3). Thus the gadget
--  contributes depth 3.

n≤m⊔n : (m n : ℕ) → n ≤ m ⊔ n
n≤m⊔n zero    n       = ≤-refl
n≤m⊔n (suc m) zero    = z≤n
n≤m⊔n (suc m) (suc n) = s≤s (n≤m⊔n m n)

mux-bound :
  (lv : List ℕ) (s a b M : ℕ) →
  s < length lv → a < length lv → b < length lv →
  getL lv s ≤ M → getL lv a ≤ M → getL lv b ≤ M →
  maxL (runLevels lv (muxOps s a b (length lv))) ≤ maxL lv ⊔ suc (suc (suc M))
mux-bound lv s a b M s<l a<l b<l gs ga gb = goal
  where
    i = length lv
    X = maxL lv ⊔ suc (suc (suc M))

    L1 = opLevel lv (oNot s)                          --  suc (getL lv s)
    e1 = lv ++ L1 ∷ []
    L2 = opLevel e1 (oAnd a i)
    e2 = e1 ++ L2 ∷ []
    L3 = opLevel e2 (oAnd b s)
    e3 = e2 ++ L3 ∷ []
    L4 = opLevel e3 (oOr (suc i) (suc (suc i)))

    --  Record prefix lengths for snoc-last lookups at the allocated positions.
    le1 : length e1 ≡ suc i
    le1 = length-snoc lv L1
    le2 : length e2 ≡ suc (suc i)
    le2 = trans (length-snoc e1 L2) (cong suc le1)

    --  Both s and b remain in range after each snoc.
    s<e1 : s < length e1
    s<e1 = ≤-trans s<l (≤-trans (n≤1+n i) (≤-reflexive (sym le1)))
    b<e1 : b < length e1
    b<e1 = ≤-trans b<l (≤-trans (n≤1+n i) (≤-reflexive (sym le1)))

    --  Bound each of the four internal gate levels by M+3.
    L1≤ : L1 ≤ suc (suc (suc M))
    L1≤ = s≤s (≤-trans gs (≤-trans (n≤1+n M) (n≤1+n (suc M))))

    gae1 : getL e1 a ≤ M
    gae1 = ≤-trans (≤-reflexive (getL-++-prefix lv (L1 ∷ []) a a<l)) ga
    gie1 : getL e1 i ≤ suc M
    gie1 = ≤-trans (≤-reflexive (getL-snoc-last lv L1)) (s≤s gs)
    L2≤ : L2 ≤ suc (suc (suc M))
    L2≤ = s≤s (≤-trans (⊔-lub (≤-trans gae1 (n≤1+n M)) gie1) (n≤1+n (suc M)))

    gbe2 : getL e2 b ≤ M
    gbe2 = ≤-trans (≤-reflexive (getL-++-prefix e1 (L2 ∷ []) b b<e1))
                   (≤-trans (≤-reflexive (getL-++-prefix lv (L1 ∷ []) b b<l)) gb)
    gse2 : getL e2 s ≤ M
    gse2 = ≤-trans (≤-reflexive (getL-++-prefix e1 (L2 ∷ []) s s<e1))
                   (≤-trans (≤-reflexive (getL-++-prefix lv (L1 ∷ []) s s<l)) gs)
    L3≤ : L3 ≤ suc (suc (suc M))
    L3≤ = s≤s (≤-trans (⊔-lub gbe2 gse2) (≤-trans (n≤1+n M) (n≤1+n (suc M))))

    --  L4 reads suc i = length e1, containing L2 ≤ M+2, and suc (suc i)
    --  = length e2, containing L3 ≤ M+1. Hence L4 ≤ M+3.
    si<e2 : suc i < length e2
    si<e2 = ≤-reflexive (sym le2)
    g-si : getL e3 (suc i) ≤ suc (suc M)
    g-si = ≤-trans (≤-reflexive (getL-++-prefix e2 (L3 ∷ []) (suc i) si<e2))
                   (≤-trans (≤-reflexive si≡L2) L2≤′)
      where
        si≡L2 : getL e2 (suc i) ≡ L2
        si≡L2 = trans (cong (getL e2) (sym le1)) (getL-snoc-last e1 L2)
        L2≤′ : L2 ≤ suc (suc M)
        L2≤′ = s≤s (⊔-lub (≤-trans gae1 (n≤1+n M)) gie1)
    g-ssi : getL e3 (suc (suc i)) ≤ suc M
    g-ssi = ≤-trans (≤-reflexive ssi≡L3) L3≤′
      where
        ssi≡L3 : getL e3 (suc (suc i)) ≡ L3
        ssi≡L3 = trans (cong (getL e3) (sym le2)) (getL-snoc-last e2 L3)
        L3≤′ : L3 ≤ suc M
        L3≤′ = s≤s (⊔-lub gbe2 gse2)
    L4≤ : L4 ≤ suc (suc (suc M))
    L4≤ = s≤s (⊔-lub g-si (≤-trans g-ssi (n≤1+n (suc M))))

    --  Combine the bounds to keep each environment maximum below X.
    snocStep : (e : List ℕ) (L : ℕ) → maxL e ≤ X → L ≤ X → maxL (e ++ L ∷ []) ≤ X
    snocStep e L me≤ L≤ = ≤-trans (≤-reflexive (maxL-snoc e L)) (⊔-lub me≤ L≤)

    toX : suc (suc (suc M)) ≤ X
    toX = n≤m⊔n (maxL lv) (suc (suc (suc M)))
    m0 : maxL lv ≤ X
    m0 = m≤m⊔n (maxL lv) (suc (suc (suc M)))
    m1 : maxL e1 ≤ X
    m1 = snocStep lv L1 m0 (≤-trans L1≤ toX)
    m2 : maxL e2 ≤ X
    m2 = snocStep e1 L2 m1 (≤-trans L2≤ toX)
    m3 : maxL e3 ≤ X
    m3 = snocStep e2 L3 m2 (≤-trans L3≤ toX)
    goal : maxL (runLevels lv (muxOps s a b i)) ≤ X
    goal = snocStep e3 L4 m3 (≤-trans L4≤ toX)
