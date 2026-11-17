------------------------------------------------------------------------
--  Transfer query bounds through oracle post-processing without changing
--  budgets or fixing a preferred direction. An adversary can perform
--  answer transformations inside its decoder. For φ : X → Y → Y',
--  reflectQA turns QAdversary X Y' K q into QAdversary X Y K q with the
--  same probes, applying φ internally. Input dependence matters because
--  ExactQueryMulti's spare outputs depend on the queried x, which the
--  adversary already knows. Labels such as rich and poor describe uses
--  of the lemma, not its types. For a lower-bound transfer, construct
--  rich answers from poor ones: a rich-oracle winner would reflect to
--  a poor-oracle winner at the same budget, transferring impossibility
--  by contraposition. For an upper bound, project rich answers to poor
--  ones and reflect a poor-oracle winner, discarding extra components.
--  ExactQueryMulti uses φ x b=b ∷ aux x and φ x y=head y respectively
--  to inherit both bounds. Scope is non-adaptive QAdversary only, without
--  claims for Adaptive. Only oracle query count is preserved: the new
--  decoder runs φ once per probe and performs extra computation with no
--  time bound. No transfer is claimed for oracles lacking the specified
--  functional relationship. There are no postulates or holes.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.OraclePostProcess where

open import Data.Nat using (ℕ)
open import Data.Bool using (Bool; true)
import Data.Vec as V
open V using (Vec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong)

open import Attack.Oracle using (QAdversary; ask; Recovers)

------------------------------------------------------------------------
--  Section 1: reflect with unchanged probes and budget, pairing each answer
--  with its originating query before decoding the transformed values.

reflectQA : {X Y Y' K : Set} {q : ℕ} →
            (X → Y → Y') → QAdversary X Y' K q → QAdversary X Y K q
reflectQA φ Adv = record
  { probes = QAdversary.probes Adv
  ; decode = λ ans →
      QAdversary.decode Adv (V.zipWith φ (QAdversary.probes Adv) ans)
  }

------------------------------------------------------------------------
--  Section 2: equate pointwise oracle post-processing with transformation
--  of the complete answer vector against its probes. Stdlib 2.3 lacks
--  this lemma in Data.Vec.Properties. Its map-<,>-zip at line 715 pairs two
--  functions of one vector through zip, not arbitrary zipWith; adapting it
--  would require a missing zip/zipWith-uncurry bridge and map-∘, more work
--  than the direct induction. zipWith-map₁/map₂ at lines 666 and 673 move
--  one map, but leave zipWith (λ x y → φ x (g y)) ps ps without a lemma
--  collapsing identical arguments to map. Data.List.Properties' map-zipWith
--  at line 411 concerns lists and a one-sided outer map. Also avoid the
--  name map-zip, already used at Vec.Properties line 720 for
--  map (Product.map f g) (zip xs ys) ≡ zip (map f xs) (map g ys), even
--  though that module is not currently imported.

map-diag-zipWith :
  {X Y Y' : Set} {q : ℕ} (φ : X → Y → Y') (g : X → Y) (ps : Vec X q) →
  V.map (λ x → φ x (g x)) ps ≡ V.zipWith φ ps (V.map g ps)
map-diag-zipWith φ g V.[]       = refl
map-diag-zipWith φ g (x V.∷ ps) = cong (φ x (g x) V.∷_) (map-diag-zipWith φ g ps)

------------------------------------------------------------------------
--  Section 3: running reflection against O equals running the original
--  adversary against λ x → φ x (O x). The literally unchanged probe
--  vector preserves its query budget.

reflect-ask : {X Y Y' K : Set} {q : ℕ} (φ : X → Y → Y') (O : X → Y)
              (Adv : QAdversary X Y' K q) →
              ask (reflectQA φ Adv) O ≡ ask Adv (λ x → φ x (O x))
reflect-ask φ O Adv =
  cong (QAdversary.decode Adv)
       (sym (map-diag-zipWith φ O (QAdversary.probes Adv)))

--  Transfer recovery accordingly. A post-processed-oracle winner yields
--  an act winner, giving the upper-bound direction; contraposition transfers
--  absence of an act winner at q to absence of a transformed-oracle winner.
reflect-Recovers : {X Y Y' K : Set} {q : ℕ} (φ : X → Y → Y') (act : K → X → Y)
                   (Adv : QAdversary X Y' K q) →
                   Recovers Adv (λ k x → φ x (act k x)) →
                   Recovers (reflectQA φ Adv) act
reflect-Recovers φ act Adv rec k = trans (reflect-ask φ (act k) Adv) (rec k)

------------------------------------------------------------------------
--  Section 4: demonstrate computation. advPair reads the first of two
--  answer bits. Reflect through φPair x b=b ∷ x ∷ [] to a one-bit oracle;
--  against identity at probe true it returns true by reduction.

private
  advPair : QAdversary Bool (Vec Bool 2) Bool 1
  advPair = record
    { probes = true V.∷ V.[]
    ; decode = λ ans → V.head (V.head ans)
    }

  φPair : Bool → Bool → Vec Bool 2
  φPair x b = b V.∷ x V.∷ V.[]

  _ : ask (reflectQA φPair advPair) (λ x → x) ≡ true
  _ = refl
