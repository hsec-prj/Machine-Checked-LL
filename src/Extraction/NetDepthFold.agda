------------------------------------------------------------------------
--  Synchronize builders with runLevels and accumulate linear row depth
--  `run-len-state` preserves agreement between an `CntLaw` builder's state
--  and the environment length, providing the global relation needed by
--  the row bound. `rows-acc` allows each mux row to read only below the
--  current length and increase the maximum level by at most 3. Choosing
--  the current `maxL` as each row's ceiling discharges the below-base
--  condition with `getL-≤-maxL`. Thus N thermometer steps reach at most
--  `maxL + 3N`, an abstract O(N) comparator-depth bound.
--  Uses `--safe --without-K` and no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthFold where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _<_; _≤_)
open import Data.Nat.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-identityʳ; +-assoc; +-comm; *-suc; m≤m+n; +-mono-≤)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.Unit using (⊤; tt)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; cong; trans)

open import Extraction.Netlist using (Op; Builder)
open import Extraction.NetDepth using (getL; maxL; runLevels; runLevels-++; getL-≤-maxL; ⊔-lub)
open import Extraction.NetDepthBuilder using (CntLaw)
open import Extraction.NetDepthComp
  using (runLevels-len; concatMux; AllInBase; muxSeq-bound)

------------------------------------------------------------------------
--  Relate the final builder state to the full level-environment length.

run-len-state : {A : Set} (m : Builder A) → CntLaw m → (lv : List ℕ) →
                proj₁ (proj₂ (m (length lv)))
                  ≡ length (runLevels lv (proj₂ (proj₂ (m (length lv)))))
run-len-state m im lv =
  trans (im (length lv)) (sym (runLevels-len lv (proj₂ (proj₂ (m (length lv))))))

------------------------------------------------------------------------
--  Lay out rows at successive positions and check each row against the
--  current length; both definitions thread the same growing environment.

concatRows : (lv : List ℕ) → List (List (ℕ × ℕ × ℕ)) → List Op
concatRows lv []           = []
concatRows lv (row ∷ rows) =
  concatMux row (length lv) ++ concatRows (runLevels lv (concatMux row (length lv))) rows

ValidRows : (lv : List ℕ) → List (List (ℕ × ℕ × ℕ)) → Set
ValidRows lv []           = ⊤
ValidRows lv (row ∷ rows) =
  AllInBase row (length lv) × ValidRows (runLevels lv (concatMux row (length lv))) rows

------------------------------------------------------------------------
--  Accumulate N row bounds to obtain maxL + 3N.

rows-acc : (lv : List ℕ) (rows : List (List (ℕ × ℕ × ℕ))) → ValidRows lv rows →
           maxL (runLevels lv (concatRows lv rows)) ≤ maxL lv + 3 * length rows
rows-acc lv []           _              = ≤-reflexive (sym (+-identityʳ (maxL lv)))
rows-acc lv (row ∷ rows) (rowv , restv) =
  ≤-trans (≤-reflexive (cong maxL split))
          (≤-trans rec (≤-trans (+-mono-≤ head≤ ≤-refl) arith))
  where
    lv' = runLevels lv (concatMux row (length lv))

    head≤ : maxL lv' ≤ maxL lv + 3
    head≤ = ≤-trans (muxSeq-bound (length lv) (maxL lv) lv row ≤-refl
                       (λ i _ → getL-≤-maxL lv i) rowv)
                    (⊔-lub (m≤m+n (maxL lv) 3) (≤-reflexive (+-comm 3 (maxL lv))))

    split : runLevels lv (concatRows lv (row ∷ rows))
          ≡ runLevels lv' (concatRows lv' rows)
    split = runLevels-++ lv (concatMux row (length lv)) (concatRows lv' rows)

    rec : maxL (runLevels lv' (concatRows lv' rows)) ≤ maxL lv' + 3 * length rows
    rec = rows-acc lv' rows restv

    arith : (maxL lv + 3) + 3 * length rows ≤ maxL lv + 3 * suc (length rows)
    arith = ≤-reflexive (trans (+-assoc (maxL lv) 3 (3 * length rows))
                               (cong (maxL lv +_) (sym (*-suc 3 (length rows)))))
