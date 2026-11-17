------------------------------------------------------------------------
--  Connect popBuilder to a linear comparator-depth bound. Accumulator
--  wire identifiers remain below the fresh identifier, so step MUXes
--  read previously allocated wires and satisfy rows-acc's ValidRows
--  premise. mapMB-outs< bounds returned mkMux wires by the final
--  state through mapMB-mono. Use --safe --without-K with no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthPop where

open import Data.Nat using (ℕ; zero; suc; _+_; _⊔_; _<_; _≤_; s≤s; z≤n)
open import Data.Nat.Properties using (≤-refl; ≤-trans; <-≤-trans; n≤1+n; m≤n+m)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.List.Relation.Unary.All as All using (All; []; _∷_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; cong; trans)

open import Extraction.Netlist using (mkMux; mapMB; _»=_; ret; Builder)
open import Extraction.NetDepthBuilder using (CntLaw; cnt-mono)
open import Extraction.NetlistCorrect using (stepTh-cnt)
open import Extraction.LockedNet using (xorPairs-cnt; constWires-cnt; popOnBuilder-cnt; restoreNet-cnt)

------------------------------------------------------------------------
--  Define the mapMB traversal used by one thermometer step.

stepMap : ℕ → List (ℕ × ℕ) → Builder (List ℕ)
stepMap bit = mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p))

--  After stepMap, the fresh identifier is the start plus four per
--  pair, establishing monotonicity in the start state.
mapMB-mono : (bit : ℕ) (ps : List (ℕ × ℕ)) (i : ℕ) →
             i ≤ proj₁ (proj₂ (stepMap bit ps i))
mapMB-mono bit []       i = ≤-refl
mapMB-mono bit (p ∷ ps) i =
  ≤-trans (n≤1+n i) (≤-trans (n≤1+n (suc i))
    (≤-trans (n≤1+n (suc (suc i))) (≤-trans (n≤1+n (suc (suc (suc i))))
      (mapMB-mono bit ps (suc (suc (suc (suc i))))))))

--  Bound every returned stepMap wire below the final fresh identifier.
mapMB-outs< : (bit : ℕ) (ps : List (ℕ × ℕ)) (i : ℕ) →
              All (_< proj₁ (proj₂ (stepMap bit ps i))) (proj₁ (stepMap bit ps i))
mapMB-outs< bit []       i = []
mapMB-outs< bit (p ∷ ps) i =
  head< ∷ mapMB-outs< bit ps (suc (suc (suc (suc i))))
  where
    --  Bound the head MUX output i+3 below the final state.
    head< : suc (suc (suc i)) < proj₁ (proj₂ (stepMap bit ps (suc (suc (suc (suc i))))))
    head< = <-≤-trans (s≤s (s≤s (s≤s (s≤s ≤-refl))))
                     (mapMB-mono bit ps (suc (suc (suc (suc i)))))

------------------------------------------------------------------------
--  Derive AllInBase for a thermometer row from accumulator validity:
--  every MUX reads below the current environment length.

open import Data.List using (map)
open import Extraction.Netlist using (tailL; zipL)
open import Extraction.NetDepthComp using (AllInBase; rowSpecs)

tailL-All : {L : ℕ} (th : List ℕ) → All (_< L) th → All (_< L) (tailL th)
tailL-All []       _        = []
tailL-All (x ∷ xs) (_ ∷ pa) = pa

zipL-All : {L : ℕ} (xs ys : List ℕ) → All (_< L) xs → All (_< L) ys →
           All (λ p → (proj₁ p < L) × (proj₂ p < L)) (zipL xs ys)
zipL-All []       ys       _          _          = []
zipL-All (x ∷ xs) []       _          _          = []
zipL-All (x ∷ xs) (y ∷ ys) (px ∷ pxs) (py ∷ pys) =
  (px , py) ∷ zipL-All xs ys pxs pys

rowSpecs-AllInBase : {L : ℕ} (bit : ℕ) (ps : List (ℕ × ℕ)) → bit < L →
                     All (λ p → (proj₁ p < L) × (proj₂ p < L)) ps →
                     AllInBase (rowSpecs bit ps) L
rowSpecs-AllInBase bit []       _    _              = tt
  where open import Data.Unit using (tt)
rowSpecs-AllInBase bit (p ∷ ps) bit< ((p1 , p2) ∷ pa) =
  (bit< , p1 , p2) , rowSpecs-AllInBase bit ps bit< pa

--  Show the accumulator-derived step row satisfies AllInBase L.
step-AllInBase : {L : ℕ} (bit : ℕ) (th : List ℕ) → bit < L → All (_< L) th →
                 AllInBase (rowSpecs bit (zipL (tailL th) th)) L
step-AllInBase bit th bit< accv =
  rowSpecs-AllInBase bit (zipL (tailL th) th) bit<
    (zipL-All (tailL th) th (tailL-All th accv) accv)

------------------------------------------------------------------------
--  Decompose stepTh to identify its operations with the abstract row.

open import Extraction.Netlist using (stepTh; foldlMB)
open import Extraction.NetDepthComp using (concatMux; mapMB-mux-ops; muxSeq-bound)
open import Data.List.Properties using (++-identityʳ)

stepTh-ops-concatMux : (trueW : ℕ) (th : List ℕ) (bit i : ℕ) →
  proj₂ (proj₂ (stepTh trueW th bit i)) ≡ concatMux (rowSpecs bit (zipL (tailL th) th)) i
stepTh-ops-concatMux trueW th bit i =
  trans (cong (λ z → z ++ []) (mapMB-mux-ops bit (zipL (tailL th) th) i))
        (++-identityʳ (concatMux (rowSpecs bit (zipL (tailL th) th)) i))

------------------------------------------------------------------------
--  Bound a thermometer fold by three added depth levels per step,
--  assuming accumulator validity and in-range input bits.

open import Data.Nat using (_*_)
open import Data.Nat.Properties using (≤-reflexive; +-identityʳ; +-assoc; +-comm; *-suc; m≤m+n; +-mono-≤)
open import Extraction.NetDepth using (maxL; runLevels; runLevels-++; getL-≤-maxL; ⊔-lub)
open import Extraction.NetDepthComp using (runLevels-len)
open import Extraction.NetDepthFold using (run-len-state)
open import Extraction.NetDepthMux using (n≤m⊔n)

private
  All-mono : {a b : ℕ} (zs : List ℕ) → a ≤ b → All (_< a) zs → All (_< b) zs
  All-mono values bound = All.map (λ proof → ≤-trans proof bound)

fold-bound : (trueW : ℕ) (acc xs lv : List ℕ) →
  trueW < length lv → All (_< length lv) acc → All (_< length lv) xs →
  maxL (runLevels lv (proj₂ (proj₂ (foldlMB (stepTh trueW) acc xs (length lv)))))
    ≤ maxL lv + 3 * length xs
fold-bound trueW acc []       lv tw< accv xs<            = ≤-reflexive (sym (+-identityʳ (maxL lv)))
fold-bound trueW acc (x ∷ xs) lv tw< accv (x< ∷ xs<)     =
  ≤-trans (≤-reflexive (cong maxL split))
          (≤-trans rec (≤-trans (+-mono-≤ head≤ ≤-refl) arith))
  where
    row  = rowSpecs x (zipL (tailL acc) acc)
    sops = proj₂ (proj₂ (stepTh trueW acc x (length lv)))
    sid  = proj₁ (proj₂ (stepTh trueW acc x (length lv)))
    acc' = proj₁ (stepTh trueW acc x (length lv))
    lvS  = runLevels lv sops                       --  environment after concrete step operations
    lv1  = runLevels lv (concatMux row (length lv)) --  environment after the abstract row

    lv1≡ : lvS ≡ lv1
    lv1≡ = cong (runLevels lv) (stepTh-ops-concatMux trueW acc x (length lv))

    --  Use the abstract row to bound the head step's maximum increase by three.
    head≤ : maxL lv1 ≤ maxL lv + 3
    head≤ = ≤-trans (muxSeq-bound (length lv) (maxL lv) lv row ≤-refl
                       (λ i _ → getL-≤-maxL lv i) (step-AllInBase x acc x< accv))
                    (⊔-lub (m≤m+n (maxL lv) 3) (≤-reflexive (+-comm 3 (maxL lv))))

    --  Split fold operations into step ++ rest, running rest at length lvS.
    split : runLevels lv (proj₂ (proj₂ (foldlMB (stepTh trueW) acc (x ∷ xs) (length lv))))
          ≡ runLevels lvS (proj₂ (proj₂ (foldlMB (stepTh trueW) acc' xs sid)))
    split = runLevels-++ lv sops (proj₂ (proj₂ (foldlMB (stepTh trueW) acc' xs sid)))

    --  Identify sid with the new environment length, length lvS.
    sid≡ : sid ≡ length lvS
    sid≡ = run-len-state (stepTh trueW acc x) (stepTh-cnt trueW acc x) lv

    --  Transport accumulator validity, bits, and trueW to the extended environment.
    len≤ : length lv ≤ length lvS
    len≤ = ≤-trans (m≤m+n (length lv) (length sops)) (≤-reflexive (sym (runLevels-len lv sops)))
    tw<' : trueW < length lvS
    tw<' = ≤-trans tw< len≤
    accv' : All (_< length lvS) acc'
    accv' = ≤-trans tw< len≤ ∷
            All-mono (proj₁ (stepMap x (zipL (tailL acc) acc) (length lv)))
                     (≤-reflexive sid≡)
                     (mapMB-outs< x (zipL (tailL acc) acc) (length lv))
    xs<' : All (_< length lvS) xs
    xs<' = All-mono xs len≤ xs<

    --  Recurse in the extended environment after transporting sid to length lvS.
    rec : maxL (runLevels lvS (proj₂ (proj₂ (foldlMB (stepTh trueW) acc' xs sid))))
          ≤ maxL lv1 + 3 * length xs
    rec rewrite sid≡ | sym lv1≡ = fold-bound trueW acc' xs lvS tw<' accv' xs<'

    arith : (maxL lv + 3) + 3 * length xs ≤ maxL lv + 3 * suc (length xs)
    arith = ≤-reflexive (trans (+-assoc (maxL lv) 3 (3 * length xs))
                               (cong (maxL lv +_) (sym (*-suc 3 (length xs)))))

------------------------------------------------------------------------
--  Establish initial popcount validity: after two constants, seed
--  thermometer wires and input bits lie below environment length N+2.

open import Data.List using (replicate)
open import Extraction.Netlist using (upTo; upFrom)

replicate-< : {L : ℕ} (n x : ℕ) → x < L → All (_< L) (replicate n x)
replicate-< zero    x x< = []
replicate-< (suc n) x x< = x< ∷ replicate-< n x x<

upFrom-< : {L : ℕ} (n j : ℕ) → j + n ≤ L → All (_< L) (upFrom j n)
upFrom-< zero    j j+n≤ = []
upFrom-< (suc n) j j+n≤ = j<L ∷ upFrom-< n (suc j) sj+n≤
  where
    open import Data.Nat.Properties using (≤-trans; m≤m+n; +-suc)
    j<L : suc j ≤ _
    j<L = ≤-trans (≤-trans (s≤s (m≤m+n j n)) (≤-reflexive (sym (+-suc j n)))) j+n≤
    sj+n≤ : suc j + n ≤ _
    sj+n≤ = ≤-trans (≤-reflexive (sym (+-suc j n))) j+n≤

------------------------------------------------------------------------
--  Prove netDepth(popcountEqNet N h) ≤ 3N + 2.

open import Data.Bool using (true; false)
open import Extraction.Netlist using (popBuilder; popcountEqNet; nth; Op; oConst; oNot; oAnd)
open import Extraction.NetDepth using (opLevel; maxL-snoc)

private
  maxL-rep0 : (n : ℕ) → maxL (replicate n 0) ≡ 0
  maxL-rep0 zero    = refl
  maxL-rep0 (suc n) = maxL-rep0 n

  len-upFrom : (n j : ℕ) → length (upFrom j n) ≡ n
  len-upFrom zero    j = refl
  len-upFrom (suc n) j = cong suc (len-upFrom n (suc j))

  len-snoc : (xs : List ℕ) (y : ℕ) → length (xs ++ (y ∷ [])) ≡ suc (length xs)
  len-snoc []       y = refl
  len-snoc (x ∷ xs) y = cong suc (len-snoc xs y)

  len-rep : (n : ℕ) → length (replicate n 0) ≡ n
  len-rep zero    = refl
  len-rep (suc n) = cong suc (len-rep n)

--  Bound maxL by M ⊔ suc (suc M) through the not/and tail,
--  which adds one level per gate.
private
  notAnd≤ : (e : List ℕ) (M : ℕ) → maxL e ≤ M → (g1 g2 g3 : ℕ) →
            maxL (runLevels e (oNot g1 ∷ oAnd g2 g3 ∷ [])) ≤ suc (suc M)
  notAnd≤ e M me≤ g1 g2 g3 =
    ≤-trans (≤-reflexive (maxL-snoc (e ++ (opLevel e (oNot g1) ∷ [])) _))
            (⊔-lub e2≤ al≤)
    where
      open import Data.Nat.Properties using (n≤1+n)
      nl≤ : opLevel e (oNot g1) ≤ suc M
      nl≤ = s≤s (≤-trans (getL-≤-maxL e g1) me≤)
      e1≤ : maxL (e ++ (opLevel e (oNot g1) ∷ [])) ≤ suc M
      e1≤ = ≤-trans (≤-reflexive (maxL-snoc e (opLevel e (oNot g1))))
                    (⊔-lub (≤-trans me≤ (n≤1+n M)) nl≤)
      e2≤ : maxL (e ++ (opLevel e (oNot g1) ∷ [])) ≤ suc (suc M)
      e2≤ = ≤-trans e1≤ (n≤1+n (suc M))
      al≤ : opLevel (e ++ (opLevel e (oNot g1) ∷ [])) (oAnd g2 g3) ≤ suc (suc M)
      al≤ = s≤s (⊔-lub (≤-trans (getL-≤-maxL (e ++ (opLevel e (oNot g1) ∷ [])) g2) e1≤)
                       (≤-trans (getL-≤-maxL (e ++ (opLevel e (oNot g1) ∷ [])) g3) e1≤))

netDepth-comparator : (N h : ℕ) →
  maxL (runLevels (replicate N 0) (proj₁ (popcountEqNet N h))) ≤ 3 * N + 2
netDepth-comparator N h = ≤-trans (≤-reflexive (cong maxL split)) bound
  where
    acc0 = N ∷ replicate N (suc N)
    e2   = (replicate N 0 ++ (0 ∷ [])) ++ (0 ∷ [])
    fld  = λ st → foldlMB (stepTh N) acc0 (upTo N) st
    FOLDOPS = proj₂ (proj₂ (fld (suc (suc N))))
    notG = nth (proj₁ (fld (suc (suc N)))) (suc h) (suc N)
    andG1 = nth (proj₁ (fld (suc (suc N)))) h (suc N)
    andG2 = proj₁ (proj₂ (fld (suc (suc N))))

    --  Expand popcountEqNet into constants, fold, and not/and by refl,
    --  then reduce to runLevels on e2.
    split : runLevels (replicate N 0) (proj₁ (popcountEqNet N h))
          ≡ runLevels e2 (FOLDOPS ++ (oNot notG ∷ oAnd andG1 andG2 ∷ []))
    split = refl

    len-e2 : length e2 ≡ suc (suc N)
    len-e2 = trans (len-snoc (replicate N 0 ++ (0 ∷ [])) 0)
                   (cong suc (trans (len-snoc (replicate N 0) 0) (cong suc (len-rep N))))

    maxL-e2 : maxL e2 ≡ 0
    maxL-e2 = trans (maxL-snoc (replicate N 0 ++ (0 ∷ [])) 0)
                    (cong (λ z → z ⊔ 0)
                          (trans (maxL-snoc (replicate N 0) 0)
                                 (cong (λ z → z ⊔ 0) (maxL-rep0 N))))

    --  Apply fold-bound at e2 with state length e2 = N+2 and
    --  transport its conclusion to FOLDOPS.
    fold≤ : maxL (runLevels e2 FOLDOPS) ≤ 3 * N
    fold≤ = ≤-trans (≤-reflexive (cong (λ st → maxL (runLevels e2 (proj₂ (proj₂ (fld st))))) (sym len-e2)))
                    (≤-trans (fold-bound N acc0 (upTo N) e2 tw< accv bitsv)
                             (≤-trans (≤-reflexive (cong (λ z → z + 3 * length (upTo N)) maxL-e2))
                                      (≤-reflexive (cong (λ z → 0 + 3 * z) (len-upFrom N 0)))))
      where
        open import Data.Nat.Properties using (m≤m+n; ≤-trans; n≤1+n)
        tw< : N < length e2
        tw< = ≤-trans (s≤s (n≤1+n N)) (≤-reflexive (sym len-e2))
        accv : All (_< length e2) acc0
        accv = ≤-trans (s≤s (n≤1+n N)) (≤-reflexive (sym len-e2))
               ∷ replicate-< N (suc N) (≤-reflexive (sym len-e2))
        bitsv : All (_< length e2) (upTo N)
        bitsv = upFrom-< N 0 (≤-trans (≤-trans (n≤1+n N) (n≤1+n (suc N)))
                                      (≤-reflexive (sym len-e2)))

    --  Combine e3 = runLevels e2 FOLDOPS with at most two levels for not/and.
    bound : maxL (runLevels e2 (FOLDOPS ++ (oNot notG ∷ oAnd andG1 andG2 ∷ [])))
          ≤ 3 * N + 2
    bound = ≤-trans (≤-reflexive (cong maxL (runLevels-++ e2 FOLDOPS _)))
                    (≤-trans (notAnd≤ (runLevels e2 FOLDOPS) (3 * N) fold≤ notG andG1 andG2)
                             (≤-reflexive (+-comm 2 (3 * N))))

------------------------------------------------------------------------
--  Generalise the comparator bound to arbitrary environments:
--  popOnBuilder bs h has depth ≤ maxL + 3|bs| + 2. It is popBuilder
--  folded over supplied wires bs, the in-context form needed by locking.

open import Extraction.LockedNet using (popOnBuilder)
open import Data.Nat.Properties using (⊔-identityʳ)

netDepth-popOn : (lv bs : List ℕ) (h : ℕ) → All (_< length lv) bs →
  maxL (runLevels lv (proj₂ (proj₂ (popOnBuilder bs h (length lv))))) ≤ maxL lv + 3 * length bs + 2
netDepth-popOn lv bs h bsv = ≤-trans (≤-reflexive (cong maxL split)) bound
  where
    L    = length lv
    acc0 = L ∷ replicate (length bs) (suc L)
    e2   = (lv ++ (0 ∷ [])) ++ (0 ∷ [])
    fld  = λ st → foldlMB (stepTh L) acc0 bs st
    FOLDOPS = proj₂ (proj₂ (fld (suc (suc L))))
    notG  = nth (proj₁ (fld (suc (suc L)))) (suc h) (suc L)
    andG1 = nth (proj₁ (fld (suc (suc L)))) h (suc L)
    andG2 = proj₁ (proj₂ (fld (suc (suc L))))

    split : runLevels lv (proj₂ (proj₂ (popOnBuilder bs h L)))
          ≡ runLevels e2 (FOLDOPS ++ (oNot notG ∷ oAnd andG1 andG2 ∷ []))
    split = refl

    len-e2 : length e2 ≡ suc (suc L)
    len-e2 = trans (len-snoc (lv ++ (0 ∷ [])) 0)
                   (cong suc (trans (len-snoc lv 0) (cong suc refl)))

    maxL-e2 : maxL e2 ≡ maxL lv
    maxL-e2 = trans (maxL-snoc (lv ++ (0 ∷ [])) 0)
                    (trans (⊔-identityʳ _)
                           (trans (maxL-snoc lv 0) (⊔-identityʳ (maxL lv))))

    L≤e2 : L ≤ length e2
    L≤e2 = ≤-trans (n≤1+n L) (≤-trans (n≤1+n (suc L)) (≤-reflexive (sym len-e2)))

    fold≤ : maxL (runLevels e2 FOLDOPS) ≤ maxL lv + 3 * length bs
    fold≤ = ≤-trans (≤-reflexive (cong (λ st → maxL (runLevels e2 (proj₂ (proj₂ (fld st))))) (sym len-e2)))
                    (≤-trans (fold-bound L acc0 bs e2 tw< accv bitsv)
                             (≤-reflexive (cong (λ z → z + 3 * length bs) maxL-e2)))
      where
        tw< : L < length e2
        tw< = ≤-trans (s≤s (n≤1+n L)) (≤-reflexive (sym len-e2))
        accv : All (_< length e2) acc0
        accv = ≤-trans (s≤s (n≤1+n L)) (≤-reflexive (sym len-e2))
               ∷ replicate-< (length bs) (suc L) (≤-reflexive (sym len-e2))
        bitsv : All (_< length e2) bs
        bitsv = All-mono bs L≤e2 bsv

    bound : maxL (runLevels e2 (FOLDOPS ++ (oNot notG ∷ oAnd andG1 andG2 ∷ [])))
          ≤ maxL lv + 3 * length bs + 2
    bound = ≤-trans (≤-reflexive (cong maxL (runLevels-++ e2 FOLDOPS _)))
                    (≤-trans (notAnd≤ (runLevels e2 FOLDOPS) (maxL lv + 3 * length bs) fold≤ notG andG1 andG2)
                             (≤-reflexive (+-comm 2 (maxL lv + 3 * length bs))))

------------------------------------------------------------------------
--  Bound restoreNet's parallel XOR layer followed by the comparator
--  on its outputs by suc (maxL lv) + 3|rbits| + 2.

open import Extraction.Netlist using (oXor)
open import Extraction.LockedNet using (xorPairs; restoreNet)
open import Extraction.NetDepthBlock using (runLevels-parallel; AllRefs<)

open import Data.Unit using (tt)

open import Relation.Binary.PropositionalEquality using (subst)

xorPairs-mono : (xs keys : List ℕ) (i : ℕ) → i ≤ proj₁ (proj₂ (xorPairs xs keys i))
xorPairs-mono wires keys start = cnt-mono (xorPairs wires keys) (xorPairs-cnt wires keys) start

xorPairs-outs< : (xs keys : List ℕ) (i : ℕ) →
                 All (_< proj₁ (proj₂ (xorPairs xs keys i))) (proj₁ (xorPairs xs keys i))
xorPairs-outs< []       keys     i = []
xorPairs-outs< (a ∷ as) []       i = []
xorPairs-outs< (a ∷ as) (b ∷ bs) i =
  <-≤-trans ≤-refl (xorPairs-mono as bs (suc i)) ∷ xorPairs-outs< as bs (suc i)

xorPairs-AllRefs : (L : ℕ) (xs keys : List ℕ) (i : ℕ) →
                   All (_< L) xs → All (_< L) keys →
                   AllRefs< L (proj₂ (proj₂ (xorPairs xs keys i)))
xorPairs-AllRefs L []       keys     i _          _          = tt
xorPairs-AllRefs L (a ∷ as) []       i _          _          = tt
xorPairs-AllRefs L (a ∷ as) (b ∷ bs) i (pa ∷ pas) (pb ∷ pbs) =
  (pa , pb) ,
  subst (AllRefs< L) (sym (++-identityʳ (proj₂ (proj₂ (xorPairs as bs (suc i))))))
        (xorPairs-AllRefs L as bs (suc i) pas pbs)

--  NetDepthExact.restoreNet-tight later charges input levels and
--  two levels per step. restoreNet-bound-from-tight re-derives this
--  unchanged statement from that stronger result.
restoreNet-bound : (lv xs keys : List ℕ) (h : ℕ) →
  All (_< length lv) xs → All (_< length lv) keys →
  maxL (runLevels lv (proj₂ (proj₂ (restoreNet xs keys h (length lv)))))
    ≤ suc (maxL lv) + 3 * length (proj₁ (xorPairs xs keys (length lv))) + 2
restoreNet-bound lv xs keys h xsv keysv =
  ≤-trans (≤-reflexive (cong maxL split))
          (≤-trans popOn≤ (+-mono-≤ (+-mono-≤ xor≤ ≤-refl) ≤-refl))
  where
    XOPS  = proj₂ (proj₂ (xorPairs xs keys (length lv)))
    rbits = proj₁ (xorPairs xs keys (length lv))
    xid   = proj₁ (proj₂ (xorPairs xs keys (length lv)))
    lv1   = runLevels lv XOPS

    split : runLevels lv (proj₂ (proj₂ (restoreNet xs keys h (length lv))))
          ≡ runLevels lv1 (proj₂ (proj₂ (popOnBuilder rbits h xid)))
    split = runLevels-++ lv XOPS (proj₂ (proj₂ (popOnBuilder rbits h xid)))

    xor≤ : maxL lv1 ≤ suc (maxL lv)
    xor≤ = runLevels-parallel lv XOPS (length lv) ≤-refl
             (xorPairs-AllRefs (length lv) xs keys (length lv) xsv keysv)

    xid≡ : xid ≡ length lv1
    xid≡ = run-len-state (xorPairs xs keys) (xorPairs-cnt xs keys) lv

    rbitsv : All (_< length lv1) rbits
    rbitsv = All-mono rbits (≤-reflexive xid≡) (xorPairs-outs< xs keys (length lv))

    popOn≤ : maxL (runLevels lv1 (proj₂ (proj₂ (popOnBuilder rbits h xid))))
           ≤ maxL lv1 + 3 * length rbits + 2
    popOn≤ rewrite xid≡ = netDepth-popOn lv1 rbits h rbitsv

------------------------------------------------------------------------
--  Treat constWires as a fan-in-free constant layer at level zero.

open import Data.Bool using (Bool)

open import Extraction.LockedNet using (constWires)

constWires-mono : (bs : List Bool) (i : ℕ) → i ≤ proj₁ (proj₂ (constWires bs i))
constWires-mono bits start = cnt-mono (constWires bits) (constWires-cnt bits) start

constWires-outs< : (bs : List Bool) (i : ℕ) →
                   All (_< proj₁ (proj₂ (constWires bs i))) (proj₁ (constWires bs i))
constWires-outs< []       i = []
constWires-outs< (b ∷ bs) i =
  <-≤-trans ≤-refl (constWires-mono bs (suc i)) ∷ constWires-outs< bs (suc i)

constWires-AllRefs : (L : ℕ) (bs : List Bool) (i : ℕ) →
                     AllRefs< L (proj₂ (proj₂ (constWires bs i)))
constWires-AllRefs L []       i = tt
constWires-AllRefs L (b ∷ bs) i =
  tt , subst (AllRefs< L) (sym (++-identityʳ (proj₂ (proj₂ (constWires bs (suc i))))))
             (constWires-AllRefs L bs (suc i))

constWires-bound : (lv : List ℕ) (bs : List Bool) →
  maxL (runLevels lv (proj₂ (proj₂ (constWires bs (length lv))))) ≤ suc (maxL lv)
constWires-bound lv bs =
  runLevels-parallel lv (proj₂ (proj₂ (constWires bs (length lv)))) (length lv) ≤-refl
    (constWires-AllRefs (length lv) bs (length lv))

------------------------------------------------------------------------
--  Compose constants, perturb restoreNet, keyed restoreNet, and
--  two XORs. Depth ≤ maxL lv + 6|xs| + 9 gives O(N) added depth
--  even though the lock has O(N²) gates.

open import Extraction.LockedNet using (lockedBlock)



--  Bound the XOR-output list length by the data-list length.
xorPairs-len≤ : (xs keys : List ℕ) (i : ℕ) → length (proj₁ (xorPairs xs keys i)) ≤ length xs
xorPairs-len≤ []       keys     i = z≤n
xorPairs-len≤ (a ∷ as) []       i = z≤n
xorPairs-len≤ (a ∷ as) (b ∷ bs) i = s≤s (xorPairs-len≤ as bs (suc i))

--  A single XOR increases depth by at most one level.
snocXor≤ : (e : List ℕ) (a b : ℕ) → maxL (runLevels e (oXor a b ∷ [])) ≤ suc (maxL e)
snocXor≤ e a b =
  ≤-trans (≤-reflexive (maxL-snoc e (opLevel e (oXor a b))))
          (⊔-lub (≤-trans (m≤m+n (maxL e) 1) (≤-reflexive (+-comm (maxL e) 1)))
                (s≤s (⊔-lub (getL-≤-maxL e a) (getL-≤-maxL e b))))

------------------------------------------------------------------------
--  Establish comparator/restore CntLaw to align stage states.



------------------------------------------------------------------------
--  Prove the full lockedBlock bound maxL lv + 6|xs| + 9,
--  giving O(N) added host depth despite O(N²) gate count.



open import Data.Nat.Properties using (*-monoʳ-≤)
open import Data.Nat.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:+_; _:*_; con; _:=_)

private
  a1 : (m x : ℕ) → suc (m + 1) + 3 * x + 2 ≡ m + 3 * x + 4
  a1 = solve 2 (λ m x → con 1 :+ (m :+ con 1) :+ (con 3 :* x) :+ con 2 := m :+ (con 3 :* x) :+ con 4) refl
  a2 : (m x : ℕ) → suc (m + 3 * x + 4) + 3 * x + 2 ≡ m + 6 * x + 7
  a2 = solve 2 (λ m x → con 1 :+ (m :+ (con 3 :* x) :+ con 4) :+ (con 3 :* x) :+ con 2 := m :+ (con 6 :* x) :+ con 7) refl
  a3 : (m x : ℕ) → suc (m + 6 * x + 7) ≡ m + 6 * x + 8
  a3 = solve 2 (λ m x → con 1 :+ (m :+ (con 6 :* x) :+ con 7) := m :+ (con 6 :* x) :+ con 8) refl
  aF : (m x : ℕ) → suc (m + 6 * x + 8) ≡ m + 6 * x + 9
  aF = solve 2 (λ m x → con 1 :+ (m :+ (con 6 :* x) :+ con 8) := m :+ (con 6 :* x) :+ con 9) refl

--  NetDepthExact.lockedBlock-tight later gives input-level
--  R + 2|xs| + 6 because the cones run in parallel, and
--  lockedBlock-bound-from-tight derives this original bound again.
lockedBlock-bound : (lv xs keys : List ℕ) (ksec : List Bool) (h fWire : ℕ) →
  All (_< length lv) xs → All (_< length lv) keys →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv)))))
    ≤ maxL lv + 6 * length xs + 9
lockedBlock-bound lv xs keys ksec h fWire xsv keysv =
  ≤-trans (≤-reflexive (cong maxL split-all)) chain
  where
    cwO  = proj₂ (proj₂ (constWires ksec (length lv)))
    e-c  = runLevels lv cwO
    cwid = proj₁ (proj₂ (constWires ksec (length lv)))
    kw   = proj₁ (constWires ksec (length lv))
    r1O  = proj₂ (proj₂ (restoreNet xs kw h cwid))
    e1   = runLevels e-c r1O
    r1id = proj₁ (proj₂ (restoreNet xs kw h cwid))
    pW   = proj₁ (restoreNet xs kw h cwid)
    r2O  = proj₂ (proj₂ (restoreNet xs keys h r1id))
    e2   = runLevels e1 r2O
    r2id = proj₁ (proj₂ (restoreNet xs keys h r1id))
    rW   = proj₁ (restoreNet xs keys h r1id)
    x1O  = oXor fWire pW ∷ []
    e3   = runLevels e2 x1O
    x2O  = oXor r2id rW ∷ []

    split-all : runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))
              ≡ runLevels e3 x2O
    split-all = trans (runLevels-++ lv cwO _)
                (trans (runLevels-++ e-c r1O _)
                (trans (runLevels-++ e1 r2O _)
                       (runLevels-++ e2 x1O x2O)))

    lv≤c : length lv ≤ length e-c
    lv≤c = ≤-trans (m≤m+n (length lv) (length cwO)) (≤-reflexive (sym (runLevels-len lv cwO)))
    cwid≡ : cwid ≡ length e-c
    cwid≡ = run-len-state (constWires ksec) (constWires-cnt ksec) lv
    c≤1 : length e-c ≤ length e1
    c≤1 = ≤-trans (m≤m+n (length e-c) (length r1O)) (≤-reflexive (sym (runLevels-len e-c r1O)))
    r1id≡ : r1id ≡ length e1
    r1id≡ = trans (restoreNet-cnt xs kw h cwid)
                  (trans (cong (λ z → z + length r1O) cwid≡) (sym (runLevels-len e-c r1O)))

    b-c : maxL e-c ≤ maxL lv + 1
    b-c = ≤-trans (constWires-bound lv ksec) (≤-reflexive (+-comm 1 (maxL lv)))

    b1 : maxL e1 ≤ maxL lv + 3 * length xs + 4
    b1 = ≤-trans (≤-reflexive (cong (λ s → maxL (runLevels e-c (proj₂ (proj₂ (restoreNet xs kw h s))))) cwid≡))
          (≤-trans (restoreNet-bound e-c xs kw h (All-mono xs lv≤c xsv) kwv)
            (≤-trans (+-mono-≤ (+-mono-≤ (s≤s b-c) (*-monoʳ-≤ 3 (xorPairs-len≤ xs kw (length e-c)))) ≤-refl)
                     (≤-reflexive (a1 (maxL lv) (length xs)))))
      where
        kwv : All (_< length e-c) kw
        kwv = All-mono kw (≤-reflexive cwid≡) (constWires-outs< ksec (length lv))

    b2 : maxL e2 ≤ maxL lv + 6 * length xs + 7
    b2 = ≤-trans (≤-reflexive (cong (λ s → maxL (runLevels e1 (proj₂ (proj₂ (restoreNet xs keys h s))))) r1id≡))
          (≤-trans (restoreNet-bound e1 xs keys h (All-mono xs (≤-trans lv≤c c≤1) xsv)
                                                  (All-mono keys (≤-trans lv≤c c≤1) keysv))
            (≤-trans (+-mono-≤ (+-mono-≤ (s≤s b1) (*-monoʳ-≤ 3 (xorPairs-len≤ xs keys (length e1)))) ≤-refl)
                     (≤-reflexive (a2 (maxL lv) (length xs)))))

    b3 : maxL e3 ≤ maxL lv + 6 * length xs + 8
    b3 = ≤-trans (snocXor≤ e2 fWire pW) (≤-trans (s≤s b2) (≤-reflexive (a3 (maxL lv) (length xs))))

    chain : maxL (runLevels e3 x2O) ≤ maxL lv + 6 * length xs + 9
    chain = ≤-trans (snocXor≤ e3 r2id rW) (≤-trans (s≤s b3) (≤-reflexive (aF (maxL lv) (length xs))))
