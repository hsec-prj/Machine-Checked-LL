------------------------------------------------------------------------
--  Level stability as a foundation for a tight netlist-depth bound
--  Extraction.NetDepth.netDepth-app-≤ charges an inserted block by its
--  gate count. A tight estimate instead uses critical-path depth: the
--  SFLL thermometer has O(n²) gates but only n successive mux layers,
--  hence O(n) depth. Following individual wire levels through allocation
--  requires stability: appending gates leaves every existing wire's level
--  unchanged because runLevels only extends the level environment.
--  Prove that property here together with its supporting list identities.
--  Uses --safe --without-K and zero postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthBlock where

open import Data.Nat using (ℕ; zero; suc; _<_; s≤s; z≤n; _≤_; _⊔_)
open import Data.Nat.Properties using (≤-trans; ≤-refl; ≤-reflexive; n≤1+n)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.Unit using (⊤; tt)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; sym; trans)

open import Extraction.Netlist using (Op; oConst; oNot; oAnd; oOr; oXor)
open import Extraction.NetDepth using (getL; maxL; opLevel; runLevels; getL-≤-maxL; ⊔-lub; maxL-snoc)

------------------------------------------------------------------------
--  Extending a list after index i leaves getL's prefix lookup unchanged.

getL-++-prefix : (lv ys : List ℕ) (i : ℕ) → i < length lv →
                 getL (lv ++ ys) i ≡ getL lv i
getL-++-prefix []       ys i       ()
getL-++-prefix (x ∷ lv) ys zero    _         = refl
getL-++-prefix (x ∷ lv) ys (suc i) (s≤s i<l) = getL-++-prefix lv ys i i<l

------------------------------------------------------------------------
--  runLevels only increases environment length, so indices originally
--  within lv remain valid throughout evaluation.

length-snoc : (lv : List ℕ) (y : ℕ) → length (lv ++ (y ∷ [])) ≡ suc (length lv)
length-snoc []       y = refl
length-snoc (x ∷ lv) y = cong suc (length-snoc lv y)

<-snoc : (lv : List ℕ) (y : ℕ) (i : ℕ) → i < length lv → i < length (lv ++ (y ∷ []))
<-snoc []       y i       ()
<-snoc (x ∷ lv) y zero    _         = s≤s z≤n
<-snoc (x ∷ lv) y (suc i) (s≤s i<l) = s≤s (<-snoc lv y i i<l)

------------------------------------------------------------------------
--  The central stability result: if i < length lv, any later operation
--  block preserves its current level. runLevels appends levels without
--  overwriting those already allocated.

runLevels-stable : (lv : List ℕ) (ops : List Op) (i : ℕ) → i < length lv →
                   getL (runLevels lv ops) i ≡ getL lv i
runLevels-stable lv []         i i<l = refl
runLevels-stable lv (op ∷ ops) i i<l =
  trans (runLevels-stable (lv ++ (opLevel lv op ∷ [])) ops i
                          (<-snoc lv (opLevel lv op) i i<l))
        (getL-++-prefix lv (opLevel lv op ∷ []) i i<l)

------------------------------------------------------------------------
--  A block reading exclusively below its initial base b forms a parallel
--  layer. Regardless of width, it adds at most one level. In particular,
--  an O(n)-wide comparator step can still have constant depth.

--  Require every fan-in of the gate to lie below b.
opRefs< : ℕ → Op → Set
opRefs< b (oConst _) = ⊤
opRefs< b (oNot a)   = a < b
opRefs< b (oAnd a c) = (a < b) × (c < b)
opRefs< b (oOr a c)  = (a < b) × (c < b)
opRefs< b (oXor a c) = (a < b) × (c < b)

AllRefs< : ℕ → List Op → Set
AllRefs< b []         = ⊤
AllRefs< b (op ∷ ops) = opRefs< b op × AllRefs< b ops

--  If its below-b fan-ins have levels ≤ R, a gate has level ≤ suc R.
opLevel-≤R : (lv : List ℕ) (b R : ℕ) (op : Op) → opRefs< b op →
             ((i : ℕ) → i < b → getL lv i ≤ R) → opLevel lv op ≤ suc R
opLevel-≤R lv b R (oConst _) _           _ = z≤n
opLevel-≤R lv b R (oNot a)   a<b         H = s≤s (H a a<b)
opLevel-≤R lv b R (oAnd a c) (a<b , c<b) H = s≤s (⊔-lub (H a a<b) (H c c<b))
opLevel-≤R lv b R (oOr a c)  (a<b , c<b) H = s≤s (⊔-lub (H a a<b) (H c c<b))
opLevel-≤R lv b R (oXor a c) (a<b , c<b) H = s≤s (⊔-lub (H a a<b) (H c c<b))

--  Parameterize the invariant by the fixed original maximum R.
private
  pll : (R : ℕ) (lv : List ℕ) (ops : List Op) (b : ℕ) →
        b ≤ length lv →
        ((i : ℕ) → i < b → getL lv i ≤ R) →
        AllRefs< b ops →
        maxL lv ≤ suc R →
        maxL (runLevels lv ops) ≤ suc R
  pll R lv []         b b≤l H allr mlv≤ = mlv≤
  pll R lv (op ∷ ops) b b≤l H (ro , rr) mlv≤ =
    pll R (lv ++ (ol ∷ [])) ops b b≤l' H' rr mlv'≤
    where
      ol = opLevel lv op
      ol≤ : ol ≤ suc R
      ol≤ = opLevel-≤R lv b R op ro H
      b≤l' : b ≤ length (lv ++ (ol ∷ []))
      b≤l' = ≤-trans b≤l (≤-trans (n≤1+n (length lv))
                                  (≤-reflexive (sym (length-snoc lv ol))))
      H' : (i : ℕ) → i < b → getL (lv ++ (ol ∷ [])) i ≤ R
      H' i i<b = ≤-trans (≤-reflexive (getL-++-prefix lv (ol ∷ []) i (≤-trans i<b b≤l)))
                         (H i i<b)
      mlv'≤ : maxL (lv ++ (ol ∷ [])) ≤ suc R
      mlv'≤ = ≤-trans (≤-reflexive (maxL-snoc lv ol)) (⊔-lub mlv≤ ol≤)

--  Bound the increase for a parallel layer by one, independently of width.
runLevels-parallel : (lv : List ℕ) (ops : List Op) (b : ℕ) →
                     b ≤ length lv → AllRefs< b ops →
                     maxL (runLevels lv ops) ≤ suc (maxL lv)
runLevels-parallel lv ops b b≤l allr =
  pll (maxL lv) lv ops b b≤l (λ i _ → getL-≤-maxL lv i) allr (n≤1+n (maxL lv))
