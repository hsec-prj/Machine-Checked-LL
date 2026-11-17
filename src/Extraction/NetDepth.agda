------------------------------------------------------------------------
--  Structural depth of flat operation lists, folded alongside runNet.
--  opLevel assigns constants level zero and each logical primitive one
--  plus its largest fan-in level. netDepth takes the maximum over every
--  allocated wire, including unused branches, starting from supplied
--  input levels. This differs from a unit-gate primary-output metric and
--  from post-mapping synthesis depth. getL is total with default zero;
--  interpreting the fold as a DAG path requires earlier-wire references.
--  netDepth-app-≤ bounds append overhead by the added operation count.
--  Extraction.NetDepthExact gives tighter comparator/block bounds and
--  the fused-depth equation; Extraction.NetDepthHost separates inherited
--  host depth from added cone depth. Their reference, input-level and
--  host-dominance premises are part of each result, not measured defaults.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepth where

open import Data.Nat using (ℕ; zero; suc; _+_; _⊔_; _≤_; z≤n; s≤s)
open import Data.Nat.Properties
  using (≤-refl; ≤-trans; ⊔-mono-≤; ⊔-idem; m≤m⊔n; +-identityʳ; +-suc; +-mono-≤; n≤1+n)
open import Data.List using (List; []; _∷_; _++_; length)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; sym; trans; module ≡-Reasoning)
open ≡-Reasoning

open import Extraction.Netlist using (Op; oConst; oNot; oAnd; oOr; oXor)

------------------------------------------------------------------------
--  Fold wire levels: constants have level zero; logical gates add one.

--  Look up levels as get looks up values, with zero for out-of-range indices.
getL : List ℕ → ℕ → ℕ
getL []       _       = 0
getL (x ∷ _)  zero    = x
getL (x ∷ xs) (suc i) = getL xs i

--  Take the maximum in a list of wire levels.
maxL : List ℕ → ℕ
maxL []       = 0
maxL (x ∷ xs) = x ⊔ maxL xs

--  Compute one gate's output level from the current environment.
opLevel : List ℕ → Op → ℕ
opLevel lv (oConst _) = 0
opLevel lv (oNot a)   = suc (getL lv a)
opLevel lv (oAnd a b) = suc (getL lv a ⊔ getL lv b)
opLevel lv (oOr a b)  = suc (getL lv a ⊔ getL lv b)
opLevel lv (oXor a b) = suc (getL lv a ⊔ getL lv b)

--  Extend the level environment in wire order, following runNet's structure.
runLevels : List ℕ → List Op → List ℕ
runLevels lv []         = lv
runLevels lv (op ∷ ops) = runLevels (lv ++ (opLevel lv op ∷ [])) ops

--  Take the greatest level over all allocated wires, not only outputs,
--  starting from the supplied input levels (zero for primary inputs).
netDepth : List ℕ → List Op → ℕ
netDepth lv ops = maxL (runLevels lv ops)

------------------------------------------------------------------------
--  Use the least-upper-bound property of ⊔.

⊔-lub : {a b c : ℕ} → a ≤ c → b ≤ c → a ⊔ b ≤ c
⊔-lub {c = c} a≤c b≤c = ≤-trans (⊔-mono-≤ a≤c b≤c) (≤-reflexive (⊔-idem c))
  where
    ≤-reflexive : {x y : ℕ} → x ≡ y → x ≤ y
    ≤-reflexive refl = ≤-refl

------------------------------------------------------------------------
--  A retrieved wire level is bounded by the environment maximum.

getL-≤-maxL : (lv : List ℕ) (a : ℕ) → getL lv a ≤ maxL lv
getL-≤-maxL []       a       = z≤n
getL-≤-maxL (x ∷ xs) zero    = m≤m⊔n x (maxL xs)
getL-≤-maxL (x ∷ xs) (suc i) = ≤-trans (getL-≤-maxL xs i) (n≤m⊔n x (maxL xs))
  where
    n≤m⊔n : (m n : ℕ) → n ≤ m ⊔ n
    n≤m⊔n zero    n = ≤-refl
    n≤m⊔n (suc m) zero    = z≤n
    n≤m⊔n (suc m) (suc n) = s≤s (n≤m⊔n m n)

------------------------------------------------------------------------
--  Appending one level updates maxL by joining with that level.

maxL-snoc : (xs : List ℕ) (y : ℕ) → maxL (xs ++ (y ∷ [])) ≡ maxL xs ⊔ y
maxL-snoc []       y = ⊔-comm′ y 0
  where  --  maxL [y] = y ⊔ 0; maxL [] ⊔ y = 0 ⊔ y
    ⊔-comm′ : (a b : ℕ) → a ⊔ b ≡ b ⊔ a
    ⊔-comm′ zero    zero    = refl
    ⊔-comm′ zero    (suc b) = refl
    ⊔-comm′ (suc a) zero    = refl
    ⊔-comm′ (suc a) (suc b) = cong suc (⊔-comm′ a b)
maxL-snoc (x ∷ xs) y =
  begin
    x ⊔ maxL (xs ++ (y ∷ []))   ≡⟨ cong (x ⊔_) (maxL-snoc xs y) ⟩
    x ⊔ (maxL xs ⊔ y)           ≡⟨ sym (⊔-assoc x (maxL xs) y) ⟩
    (x ⊔ maxL xs) ⊔ y
  ∎
  where
    ⊔-assoc : (a b c : ℕ) → (a ⊔ b) ⊔ c ≡ a ⊔ (b ⊔ c)
    ⊔-assoc zero    b c = refl
    ⊔-assoc (suc a) zero    c = refl
    ⊔-assoc (suc a) (suc b) zero    = refl
    ⊔-assoc (suc a) (suc b) (suc c) = cong suc (⊔-assoc a b c)

------------------------------------------------------------------------
--  A gate's output is at most one level above the current maximum.

opLevel-≤ : (lv : List ℕ) (op : Op) → opLevel lv op ≤ suc (maxL lv)
opLevel-≤ lv (oConst _) = z≤n
opLevel-≤ lv (oNot a)   = s≤s (getL-≤-maxL lv a)
opLevel-≤ lv (oAnd a b) = s≤s (⊔-lub (getL-≤-maxL lv a) (getL-≤-maxL lv b))
opLevel-≤ lv (oOr a b)  = s≤s (⊔-lub (getL-≤-maxL lv a) (getL-≤-maxL lv b))
opLevel-≤ lv (oXor a b) = s≤s (⊔-lub (getL-≤-maxL lv a) (getL-≤-maxL lv b))

------------------------------------------------------------------------
--  Bound the maximum-level increase of an operation block by its length.

≤-reflexive : {x y : ℕ} → x ≡ y → x ≤ y
≤-reflexive refl = ≤-refl

runLevels-max-≤ : (lv : List ℕ) (ops : List Op) →
                  maxL (runLevels lv ops) ≤ maxL lv + length ops
runLevels-max-≤ lv []         = ≤-reflexive (sym (+-identityʳ (maxL lv)))
runLevels-max-≤ lv (op ∷ ops) =
  ≤-trans (runLevels-max-≤ (lv ++ (opLevel lv op ∷ [])) ops)
          (≤-trans (+-mono-≤ step ≤-refl)
                   (≤-reflexive (sym (+-suc (maxL lv) (length ops)))))
  where
    --  Establish maxL (lv ++ [opLevel lv op]) ≤ suc (maxL lv).
    step : maxL (lv ++ (opLevel lv op ∷ [])) ≤ suc (maxL lv)
    step = ≤-trans (≤-reflexive (maxL-snoc lv (opLevel lv op)))
                   (⊔-lub (≤-trans (m≤m⊔n (maxL lv) 0) (≤-step′)) (opLevel-≤ lv op))
      where
        ≤-step′ : maxL lv ⊔ 0 ≤ suc (maxL lv)
        ≤-step′ = ⊔-lub (n≤1+n (maxL lv)) z≤n

------------------------------------------------------------------------
--  Distribute runLevels over append, as for runNet.

runLevels-++ : (lv : List ℕ) (xs ys : List Op) →
               runLevels lv (xs ++ ys) ≡ runLevels (runLevels lv xs) ys
runLevels-++ lv []         ys = refl
runLevels-++ lv (op ∷ xs)  ys = runLevels-++ (lv ++ (opLevel lv op ∷ [])) xs ys

------------------------------------------------------------------------
--  Prove the emitted-netlist overhead bound: appending ys increases depth
--  by at most length ys.

netDepth-app-≤ : (lv : List ℕ) (xs ys : List Op) →
                 netDepth lv (xs ++ ys) ≤ netDepth lv xs + length ys
netDepth-app-≤ lv xs ys =
  ≤-trans (≤-reflexive (cong maxL (runLevels-++ lv xs ys)))
          (runLevels-max-≤ (runLevels lv xs) ys)

--  Specialise to hostOps followed by lockOps: total depth is at most host
--  depth plus lock gate count, an overhead independent of the host.
netDepth-locked-≤ : (lv : List ℕ) (hostOps lockOps : List Op) →
                    netDepth lv (hostOps ++ lockOps) ≤ netDepth lv hostOps + length lockOps
netDepth-locked-≤ = netDepth-app-≤
