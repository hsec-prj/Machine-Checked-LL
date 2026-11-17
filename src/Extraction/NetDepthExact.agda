------------------------------------------------------------------------
--  Refine thermometer-fold cost to two levels per later step.
--  NetDepthPop.fold-bound inherits mux-bound's three-level charge
--  to all MUX inputs. NetDepthMerged.mux-level-spec distinguishes
--  three levels above select from two above data. Each row
--  selects on the current bit and reads the previous accumulator;
--  after the first step the accumulator dominates that bit,
--  so subsequent steps add exactly two. Carry this accounting
--  through the restore cone. stepMap-spec equates a row's maximum
--  with maxL lv joined with rowMax, the maximum of its muxLvl
--  values, parameterised by input levels. accLvl/fold-tight use
--  accLvl D S (suc n) = 2 + (accLvl D S n ⊔ suc S);
--  accLvl-closed bounds this by (D ⊔ suc S) + 2n, while
--  n = 0 returns D. popOn-tight, restoreNet-tight, and
--  lockedBlock-tight give maxL lv ⊔ (R + 2n + c), charging
--  data/key input level R. The unfused cone term improves
--  from R + 6n + 9 to R + 2n + 4. Added-depth, +2
--  host-composition, and strict-separation corollaries in their
--  *-tight forms then require only R + 2n + 4 ≤ getL lv fWire,
--  rather than NetDepthHost's R + 6n + 9. The equation
--  lockedBlockMerged-depth-exact gives 2 + getL lv fWire + 2|lits|
--  when R + 2|xs| + 4 ≤ suc (getL lv fWire) + 2|lits|
--  and maxL lv ≤ getL lv fWire. Both premises matter: the
--  chain must dominate the restore cone, and a deeper host
--  would otherwise dominate the result. §7 derives the
--  unchanged lockedBlock-bound, restoreNet-bound, and
--  lockHostBlock-bound propositions from the tighter results.
--  All depths are structural longest paths of emitted gates,
--  not post-mapping synthesis depths. stepMap-spec and the
--  fused-depth theorem are equations; fold-tight and descendants
--  are upper bounds attained in §8 examples. The standalone
--  comparator's 2N + 3 depth for N ≥ 1 matches the refined
--  prediction. Use --safe --without-K with zero postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthExact where

open import Data.Bool using (Bool; true; false)
open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _⊔_; _≤_; _<_; s≤s; z≤n)
open import Data.Nat.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; ≤-antisym; m≤m⊔n; m≤n⊔m; ⊔-mono-≤;
         ⊔-assoc; ⊔-identityʳ; m≥n⇒m⊔n≡m; n≤1+n; m≤m+n; m≤n+m; +-comm; +-suc;
         +-identityʳ; +-mono-≤; *-suc; *-monoʳ-≤; suc-injective)
open import Data.List using (List; []; _∷_; _++_; length; replicate)
open import Data.List.Properties using (++-identityʳ)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; cong; cong₂; trans; subst)

open import Extraction.NetlistCorrect using (stepTh-cnt)
open import Extraction.LockedNet using (xorPairs-cnt; constWires-cnt; restoreNet-cnt; popOnBuilder-cnt)
open import Extraction.Netlist using
  (Op; oConst; oNot; oAnd; oOr; oXor; Builder; stepTh; zipL; tailL; nth;
   mkMux; foldlMB; upFrom)
open import Extraction.NetDepth using
  (getL; maxL; opLevel; runLevels; runLevels-++; getL-≤-maxL; ⊔-lub; maxL-snoc)
open import Extraction.NetDepthBlock using
  (getL-++-prefix; length-snoc; runLevels-stable)
open import Extraction.NetDepthMux using (muxOps; getL-snoc-last)
open import Extraction.NetDepthComp using (runLevels-len; muxOps-len)
open import Extraction.NetDepthFold using (run-len-state)
open import Extraction.NetDepthBuilder using (CntLaw; foldlMB-cnt-general)
open import Extraction.NetDepthMerged using (muxLvl; mux-level-spec; maxL-mono)
open import Extraction.NetDepthPop using (stepMap; mapMB-outs<)

------------------------------------------------------------------------
--  §0 Supply list and level facts needed for the refined accounting.

--  Extending by one wire can raise a lookup only to that new wire's level.
getL-snoc-≤ : (e : List ℕ) (y i : ℕ) → getL (e ++ (y ∷ [])) i ≤ getL e i ⊔ y
getL-snoc-≤ []       y zero    = m≤n⊔m 0 y
getL-snoc-≤ []       y (suc i) = z≤n
getL-snoc-≤ (x ∷ e)  y zero    = m≤m⊔n x y
getL-snoc-≤ (x ∷ e)  y (suc i) = getL-snoc-≤ e y i

--  Generalise the thermometer row's All transport to arbitrary
--  predicates; NetDepthPop's versions fix the predicate to _< L.
tailL-P : {P : ℕ → Set} (zs : List ℕ) → All P zs → All P (tailL zs)
tailL-P []       _        = []
tailL-P (z ∷ zs) (_ ∷ ps) = ps

zipL-P : {P : ℕ → Set} (as cs : List ℕ) → All P as → All P cs →
         All (λ p → P (proj₁ p) × P (proj₂ p)) (zipL as cs)
zipL-P []       cs       _          _          = []
zipL-P (a ∷ as) []       _          _          = []
zipL-P (a ∷ as) (c ∷ cs) (pa ∷ pas) (pc ∷ pcs) = (pa , pc) ∷ zipL-P as cs pas pcs

nth-P : {P : ℕ → Set} (zs : List ℕ) (k d : ℕ) → All P zs → P d → P (nth zs k d)
nth-P []       k       d _        pd = pd
nth-P (z ∷ zs) zero    d (pz ∷ _) pd = pz
nth-P (z ∷ zs) (suc k) d (_ ∷ ps) pd = nth-P zs k d ps pd

replicate-P : {P : ℕ → Set} (n x : ℕ) → P x → All P (replicate n x)
replicate-P zero    x px = []
replicate-P (suc n) x px = px ∷ replicate-P n x px

private
  All-≤ : {a b : ℕ} (zs : List ℕ) → a ≤ b → All (_< a) zs → All (_< b) zs
  All-≤ []       _   []        = []
  All-≤ (z ∷ zs) a≤b (pz ∷ ps) = ≤-trans pz a≤b ∷ All-≤ zs a≤b ps

  --  Transport inherited-wire level preservation through a block as All.
  All-stable : (lv : List ℕ) (ops : List Op) (D : ℕ) (zs : List ℕ) →
               All (_< length lv) zs → All (λ w → getL lv w ≤ D) zs →
               All (λ w → getL (runLevels lv ops) w ≤ D) zs
  All-stable lv ops D []       []        []        = []
  All-stable lv ops D (z ∷ zs) (pz ∷ ps) (hz ∷ hs) =
    ≤-trans (≤-reflexive (runLevels-stable lv ops z pz)) hz
      ∷ All-stable lv ops D zs ps hs

  lenMono : (lv : List ℕ) (ops : List Op) → length lv ≤ length (runLevels lv ops)
  lenMono lv ops = ≤-trans (m≤m+n (length lv) (length ops))
                           (≤-reflexive (sym (runLevels-len lv ops)))

------------------------------------------------------------------------
--  §1 Compute one thermometer row exactly. muxSeq-bound uses
--  maxL lv ⊔ (M+3) for a uniform input ceiling M, whereas
--  the true maximum joins individual muxLvl values, distinguishing
--  three levels above select from two above data.

rowMax : (lv : List ℕ) (bit : ℕ) (ps : List (ℕ × ℕ)) → ℕ
rowMax lv bit []       = 0
rowMax lv bit (p ∷ ps) = muxLvl lv bit (proj₁ p) (proj₂ p) ⊔ rowMax lv bit ps

private
  --  Keep muxLvl stable because it reads only inherited wires.
  muxLvl-stable : (lv : List ℕ) (ops : List Op) (s a b : ℕ) →
                  s < length lv → a < length lv → b < length lv →
                  muxLvl (runLevels lv ops) s a b ≡ muxLvl lv s a b
  muxLvl-stable lv ops s a b s< a< b< =
    cong (λ z → suc (suc z))
      (cong₂ _⊔_ (cong₂ _⊔_ (runLevels-stable lv ops a a<)
                            (cong suc (runLevels-stable lv ops s s<)))
                 (cong₂ _⊔_ (runLevels-stable lv ops b b<)
                            (runLevels-stable lv ops s s<)))

  rowMax-stable : (lv : List ℕ) (ops : List Op) (bit : ℕ) (ps : List (ℕ × ℕ)) →
                  bit < length lv →
                  All (λ p → (proj₁ p < length lv) × (proj₂ p < length lv)) ps →
                  rowMax (runLevels lv ops) bit ps ≡ rowMax lv bit ps
  rowMax-stable lv ops bit []       _   _                  = refl
  rowMax-stable lv ops bit (p ∷ ps) bt< ((a< , b<) ∷ rest) =
    cong₂ _⊔_ (muxLvl-stable lv ops bit (proj₁ p) (proj₂ p) bt< a< b<)
              (rowMax-stable lv ops bit ps bt< rest)

--  Prove the row's final maximum is maxL lv ⊔ rowMax and
--  all newly allocated wires are at most rowMax. This
--  input-level equation imposes no coarse input ceiling.
stepMap-spec :
  (lv : List ℕ) (bit : ℕ) (ps : List (ℕ × ℕ)) (st : ℕ) → st ≡ length lv →
  bit < length lv →
  All (λ p → (proj₁ p < length lv) × (proj₂ p < length lv)) ps →
  (maxL (runLevels lv (proj₂ (proj₂ (stepMap bit ps st)))) ≡ maxL lv ⊔ rowMax lv bit ps)
  × All (λ w → getL (runLevels lv (proj₂ (proj₂ (stepMap bit ps st)))) w
                 ≤ rowMax lv bit ps)
        (proj₁ (stepMap bit ps st))
stepMap-spec lv bit []       st refl bt< _ = sym (⊔-identityʳ (maxL lv)) , []
stepMap-spec lv bit (p ∷ ps) st refl bt< ((a< , b<) ∷ rest) = maxEq , outs
  where
    i  = length lv
    a  = proj₁ p
    b  = proj₂ p
    hd = muxOps bit a b i
    lv1 = runLevels lv hd
    spec = mux-level-spec lv bit a b bt< a< b<

    lenlv1 : length lv1 ≡ 4 + i
    lenlv1 = muxOps-len lv bit a b

    --  Place the remaining row immediately after the head MUX.
    tl = proj₂ (proj₂ (stepMap bit ps (4 + i)))

    bt<1 : bit < length lv1
    bt<1 = ≤-trans bt< (lenMono lv hd)
    rest1 : All (λ q → (proj₁ q < length lv1) × (proj₂ q < length lv1)) ps
    rest1 = go ps rest
      where
        go : (qs : List (ℕ × ℕ)) →
             All (λ q → (proj₁ q < i) × (proj₂ q < i)) qs →
             All (λ q → (proj₁ q < length lv1) × (proj₂ q < length lv1)) qs
        go []       []              = []
        go (q ∷ qs) ((q1 , q2) ∷ r) =
          (≤-trans q1 (lenMono lv hd) , ≤-trans q2 (lenMono lv hd)) ∷ go qs r

    IH = stepMap-spec lv1 bit ps (4 + i) (sym lenlv1) bt<1 rest1

    rmEq : rowMax lv1 bit ps ≡ rowMax lv bit ps
    rmEq = rowMax-stable lv hd bit ps bt< rest

    --  Split row operations into the head block followed by the tail row.
    opsEq : proj₂ (proj₂ (stepMap bit (p ∷ ps) i)) ≡ hd ++ tl
    opsEq = cong (hd ++_) (++-identityʳ tl)

    runEq : runLevels lv (proj₂ (proj₂ (stepMap bit (p ∷ ps) i))) ≡ runLevels lv1 tl
    runEq = trans (cong (runLevels lv) opsEq) (runLevels-++ lv hd tl)

    maxEq : maxL (runLevels lv (proj₂ (proj₂ (stepMap bit (p ∷ ps) i))))
              ≡ maxL lv ⊔ rowMax lv bit (p ∷ ps)
    maxEq = trans (cong maxL runEq)
            (trans (proj₁ IH)
            (trans (cong₂ _⊔_ (proj₂ spec) rmEq)
                   (⊔-assoc (maxL lv) (muxLvl lv bit a b) (rowMax lv bit ps))))

    --  Read the head MUX output in the final environment.
    headOut : getL (runLevels lv1 tl) (suc (suc (suc i))) ≤ rowMax lv bit (p ∷ ps)
    headOut =
      ≤-trans (≤-reflexive
                (trans (runLevels-stable lv1 tl (suc (suc (suc i)))
                         (≤-trans (s≤s (s≤s (s≤s (s≤s ≤-refl)))) (≤-reflexive (sym lenlv1))))
                       (proj₁ spec)))
              (m≤m⊔n (muxLvl lv bit a b) (rowMax lv bit ps))

    outs : All (λ w → getL (runLevels lv (proj₂ (proj₂ (stepMap bit (p ∷ ps) i)))) w
                        ≤ rowMax lv bit (p ∷ ps))
               (proj₁ (stepMap bit (p ∷ ps) i))
    outs = subst (λ e → All (λ w → getL e w ≤ rowMax lv bit (p ∷ ps))
                            (suc (suc (suc i)) ∷ proj₁ (stepMap bit ps (4 + i))))
                 (sym runEq)
                 (headOut ∷ weaken (proj₁ (stepMap bit ps (4 + i))) (proj₂ IH))
      where
        weaken : (ws : List ℕ) →
                 All (λ w → getL (runLevels lv1 tl) w ≤ rowMax lv1 bit ps) ws →
                 All (λ w → getL (runLevels lv1 tl) w ≤ rowMax lv bit (p ∷ ps)) ws
        weaken []       []        = []
        weaken (w ∷ ws) (pw ∷ qs) =
          ≤-trans pw (≤-trans (≤-reflexive rmEq)
                              (m≤n⊔m (muxLvl lv bit a b) (rowMax lv bit ps)))
            ∷ weaken ws qs

------------------------------------------------------------------------
--  §2 Let accLvl D S n track n steps from accumulator level D
--  with bit level S. Each row costs 2 + (previous ⊔ suc S).
--  After the first step the accumulator dominates the bit
--  and further steps add two; the old fold-bound charged
--  three by merging select and data into one ceiling.

accLvl : ℕ → ℕ → ℕ → ℕ
accLvl D S zero    = D
accLvl D S (suc n) = suc (suc (accLvl D S n ⊔ suc S))

D≤accLvl : (D S n : ℕ) → D ≤ accLvl D S n
D≤accLvl D S zero    = ≤-refl
D≤accLvl D S (suc n) =
  ≤-trans (D≤accLvl D S n)
          (≤-trans (m≤m⊔n (accLvl D S n) (suc S))
                   (≤-trans (n≤1+n (accLvl D S n ⊔ suc S))
                            (n≤1+n (suc (accLvl D S n ⊔ suc S)))))

accLvl-mono : (D S : ℕ) {n m : ℕ} → n ≤ m → accLvl D S n ≤ accLvl D S m
accLvl-mono D S {m = m} z≤n         = D≤accLvl D S m
accLvl-mono D S       (s≤s n≤m) = s≤s (s≤s (⊔-mono-≤ (accLvl-mono D S n≤m) ≤-refl))

--  Peel the first step: folding the remainder from its raised
--  accumulator equals folding everything from the original state.
accLvl-shift : (D S m k : ℕ) → accLvl (accLvl D S m) S k ≡ accLvl D S (m + k)
accLvl-shift D S m zero    = cong (accLvl D S) (sym (+-identityʳ m))
accLvl-shift D S m (suc k) =
  trans (cong (λ z → suc (suc (z ⊔ suc S))) (accLvl-shift D S m k))
        (cong (accLvl D S) (sym (+-suc m k)))

private
  open import Data.Nat.Solver using (module +-*-Solver)
  open +-*-Solver using (solve; _:+_; _:*_; con; _:=_)

  arith2 : (x k : ℕ) → suc (suc (x + 2 * k)) ≡ x + 2 * suc k
  arith2 = solve 2 (λ x k → con 2 :+ (x :+ con 2 :* k) := x :+ con 2 :* (con 1 :+ k)) refl

--  Give (D ⊔ suc S) + 2n as the closed form for n ≥ 1.
--  At zero steps the accumulator stays D, which is why
--  accLvl remains the primary statement.
accLvl-closed : (D S n : ℕ) → accLvl D S n ≤ (D ⊔ suc S) + 2 * n
accLvl-closed D S zero    = ≤-trans (m≤m⊔n D (suc S)) (≤-reflexive (sym (+-identityʳ _)))
accLvl-closed D S (suc n) =
  ≤-trans (s≤s (s≤s (⊔-lub (accLvl-closed D S n)
                           (≤-trans (m≤n⊔m D (suc S)) (m≤m+n (D ⊔ suc S) (2 * n))))))
          (≤-reflexive (arith2 (D ⊔ suc S) n))

------------------------------------------------------------------------
--  Bound a row using separate data and select ceilings.

rowMax-≤ : (lv : List ℕ) (bit : ℕ) (ps : List (ℕ × ℕ)) (D S : ℕ) →
  getL lv bit ≤ S →
  All (λ p → (getL lv (proj₁ p) ≤ D) × (getL lv (proj₂ p) ≤ D)) ps →
  rowMax lv bit ps ≤ suc (suc (D ⊔ suc S))
rowMax-≤ lv bit []       D S _  _                = z≤n
rowMax-≤ lv bit (p ∷ ps) D S hb ((ha , hc) ∷ rr) =
  ⊔-lub mux≤ (rowMax-≤ lv bit ps D S hb rr)
  where
    mux≤ : muxLvl lv bit (proj₁ p) (proj₂ p) ≤ suc (suc (D ⊔ suc S))
    mux≤ = s≤s (s≤s (⊔-lub (⊔-lub (≤-trans ha (m≤m⊔n D (suc S)))
                                  (≤-trans (s≤s hb) (m≤n⊔m D (suc S))))
                           (⊔-lub (≤-trans hc (m≤m⊔n D (suc S)))
                                  (≤-trans hb (≤-trans (n≤1+n S) (m≤n⊔m D (suc S)))))))

------------------------------------------------------------------------
--  For n steps with bits ≤ S and accumulator ≤ D, bound
--  the final maximum by maxL lv ⊔ accLvl D S n and
--  the accumulator by accLvl D S n.

fold-tight :
  (trueW : ℕ) (acc bs lv : List ℕ) (D S st : ℕ) → st ≡ length lv →
  trueW < length lv → All (_< length lv) acc → All (_< length lv) bs →
  getL lv trueW ≤ D →
  All (λ w → getL lv w ≤ D) acc →
  All (λ w → getL lv w ≤ S) bs →
  (maxL (runLevels lv (proj₂ (proj₂ (foldlMB (stepTh trueW) acc bs st))))
     ≤ maxL lv ⊔ accLvl D S (length bs))
  × All (λ w → getL (runLevels lv (proj₂ (proj₂ (foldlMB (stepTh trueW) acc bs st)))) w
                 ≤ accLvl D S (length bs))
        (proj₁ (foldlMB (stepTh trueW) acc bs st))
fold-tight trueW acc []       lv D S st refl tw< accv bsv twD accD bsS =
  m≤m⊔n (maxL lv) D , accD
fold-tight trueW acc (x ∷ xs) lv D S st refl tw< accv (x< ∷ xsv) twD accD (xS ∷ xsS) =
  maxB , outsB
  where
    L    = length lv
    row  = zipL (tailL acc) acc
    smOps = proj₂ (proj₂ (stepMap x row L))
    lvS  = runLevels lv smOps
    outs = proj₁ (stepMap x row L)
    sid  = proj₁ (proj₂ (stepMap x row L))
    acc' = trueW ∷ outs

    D' : ℕ
    D' = accLvl D S 1
    k  = length xs

    --  Identify step operations with the row; accumulator ret emits none.
    sopsEq : proj₂ (proj₂ (stepTh trueW acc x L)) ≡ smOps
    sopsEq = ++-identityʳ smOps

    runS : runLevels lv (proj₂ (proj₂ (stepTh trueW acc x L))) ≡ lvS
    runS = cong (runLevels lv) sopsEq

    ranges : All (λ p → (proj₁ p < L) × (proj₂ p < L)) row
    ranges = zipL-P (tailL acc) acc (tailL-P acc accv) accv
    levels : All (λ p → (getL lv (proj₁ p) ≤ D) × (getL lv (proj₂ p) ≤ D)) row
    levels = zipL-P (tailL acc) acc (tailL-P acc accD) accD

    spec = stepMap-spec lv x row L refl x< ranges

    rm≤ : rowMax lv x row ≤ D'
    rm≤ = rowMax-≤ lv x row D S xS levels

    maxS : maxL lvS ≤ maxL lv ⊔ D'
    maxS = ≤-trans (≤-reflexive (proj₁ spec)) (⊔-mono-≤ ≤-refl rm≤)

    --  Identify the post-step state with extended environment length.
    sid≡ : sid ≡ length lvS
    sid≡ = trans (run-len-state (stepTh trueW acc x) (stepTh-cnt trueW acc x) lv)
                 (cong length runS)

    L≤S : L ≤ length lvS
    L≤S = ≤-trans (lenMono lv smOps) (≤-refl)

    --  Keep the raised accumulator in range and within its one-step ceiling.
    acc'v : All (_< length lvS) acc'
    acc'v = ≤-trans tw< L≤S
              ∷ All-≤ outs (≤-reflexive sid≡) (mapMB-outs< x row L)
    acc'D : All (λ w → getL lvS w ≤ D') acc'
    acc'D = ≤-trans (≤-reflexive (runLevels-stable lv smOps trueW tw<))
                    (≤-trans twD (D≤accLvl D S 1))
              ∷ weaken outs (proj₂ spec)
      where
        weaken : (ws : List ℕ) → All (λ w → getL lvS w ≤ rowMax lv x row) ws →
                 All (λ w → getL lvS w ≤ D') ws
        weaken []       []        = []
        weaken (w ∷ ws) (pw ∷ qs) = ≤-trans pw rm≤ ∷ weaken ws qs

    xsv' : All (_< length lvS) xs
    xsv' = All-≤ xs L≤S xsv
    xsS' : All (λ w → getL lvS w ≤ S) xs
    xsS' = All-stable lv smOps S xs xsv xsS

    IH = fold-tight trueW acc' xs lvS D' S sid sid≡ (≤-trans tw< L≤S) acc'v xsv'
           (≤-trans (≤-reflexive (runLevels-stable lv smOps trueW tw<))
                    (≤-trans twD (D≤accLvl D S 1)))
           acc'D xsS'

    shift : accLvl D' S k ≡ accLvl D S (suc k)
    shift = accLvl-shift D S 1 k

    --  Split operations at the step and run the remainder on the grown environment.
    restOps = proj₂ (proj₂ (foldlMB (stepTh trueW) acc' xs sid))
    split : runLevels lv (proj₂ (proj₂ (foldlMB (stepTh trueW) acc (x ∷ xs) L)))
              ≡ runLevels lvS restOps
    split = trans (runLevels-++ lv (proj₂ (proj₂ (stepTh trueW acc x L))) restOps)
                  (cong (λ e → runLevels e restOps) runS)

    maxB : maxL (runLevels lv (proj₂ (proj₂ (foldlMB (stepTh trueW) acc (x ∷ xs) L))))
             ≤ maxL lv ⊔ accLvl D S (suc k)
    maxB = ≤-trans (≤-reflexive (cong maxL split))
             (≤-trans (proj₁ IH)
               (⊔-lub (≤-trans maxS (⊔-mono-≤ ≤-refl
                        (accLvl-mono D S {1} {suc k} (s≤s z≤n))))
                      (≤-trans (≤-reflexive shift) (m≤n⊔m (maxL lv) (accLvl D S (suc k))))))

    outsB : All (λ w → getL (runLevels lv (proj₂ (proj₂
                          (foldlMB (stepTh trueW) acc (x ∷ xs) L)))) w
                  ≤ accLvl D S (suc k))
                (proj₁ (foldlMB (stepTh trueW) acc' xs sid))
    outsB = subst (λ e → All (λ w → getL e w ≤ accLvl D S (suc k))
                             (proj₁ (foldlMB (stepTh trueW) acc' xs sid)))
                  (sym split)
                  (go (proj₁ (foldlMB (stepTh trueW) acc' xs sid)) (proj₂ IH))
      where
        go : (ws : List ℕ) →
             All (λ w → getL (runLevels lvS restOps) w ≤ accLvl D' S k) ws →
             All (λ w → getL (runLevels lvS restOps) w ≤ accLvl D S (suc k)) ws
        go []       []        = []
        go (w ∷ ws) (pw ∷ qs) = ≤-trans pw (≤-reflexive shift) ∷ go ws qs

------------------------------------------------------------------------
--  §3 Charge the comparator and restore cone to their input levels.
--  NetDepthPop.netDepth-popOn adds 3|bs| + 2 to the whole environment
--  maximum. Here the comparator reads only bs and later steps cost two,
--  yielding maxL lv ⊔ (…): a deeper host can dominate the maximum
--  without the comparator being stacked on top of it.

open import Extraction.Netlist using (fresh; ret; _»=_; mkConst)
open import Extraction.LockedNet using
  (popOnBuilder; restoreNet; xorPairs; constWires; lockedBlock)
open import Extraction.NetDepthPop using (xorPairs-outs<; xorPairs-len≤; snocXor≤)

--  Add one XOR level above data/key inputs, independent of their number.
xorPairs-lvl :
  (lv xs keys : List ℕ) (R st : ℕ) → st ≡ length lv →
  All (_< length lv) xs → All (_< length lv) keys →
  All (λ w → getL lv w ≤ R) xs → All (λ w → getL lv w ≤ R) keys →
  (maxL (runLevels lv (proj₂ (proj₂ (xorPairs xs keys st)))) ≤ maxL lv ⊔ suc R)
  × All (λ w → getL (runLevels lv (proj₂ (proj₂ (xorPairs xs keys st)))) w ≤ suc R)
        (proj₁ (xorPairs xs keys st))
xorPairs-lvl lv []       keys     R st refl _ _ _ _ = m≤m⊔n (maxL lv) (suc R) , []
xorPairs-lvl lv (a ∷ as) []       R st refl _ _ _ _ = m≤m⊔n (maxL lv) (suc R) , []
xorPairs-lvl lv (a ∷ as) (c ∷ cs) R st refl (a< ∷ as<) (c< ∷ cs<) (aR ∷ asR) (cR ∷ csR) =
  maxB , (headB ∷ tailB)
  where
    L  = length lv
    XL = opLevel lv (oXor a c)
    lv1 = lv ++ (XL ∷ [])
    rest = proj₂ (proj₂ (xorPairs as cs (suc L)))
    outs = proj₁ (xorPairs as cs (suc L))

    len1 : length lv1 ≡ suc L
    len1 = length-snoc lv XL

    XL≤ : XL ≤ suc R
    XL≤ = s≤s (⊔-lub aR cR)

    as<1 : All (_< length lv1) as
    as<1 = All-≤ as (≤-trans (n≤1+n L) (≤-reflexive (sym len1))) as<
    cs<1 : All (_< length lv1) cs
    cs<1 = All-≤ cs (≤-trans (n≤1+n L) (≤-reflexive (sym len1))) cs<
    asR1 : All (λ w → getL lv1 w ≤ R) as
    asR1 = go as as< asR
      where
        go : (zs : List ℕ) → All (_< L) zs → All (λ w → getL lv w ≤ R) zs →
             All (λ w → getL lv1 w ≤ R) zs
        go []       []        []        = []
        go (z ∷ zs) (pz ∷ ps) (hz ∷ hs) =
          ≤-trans (≤-reflexive (getL-++-prefix lv (XL ∷ []) z pz)) hz ∷ go zs ps hs
    csR1 : All (λ w → getL lv1 w ≤ R) cs
    csR1 = go cs cs< csR
      where
        go : (zs : List ℕ) → All (_< L) zs → All (λ w → getL lv w ≤ R) zs →
             All (λ w → getL lv1 w ≤ R) zs
        go []       []        []        = []
        go (z ∷ zs) (pz ∷ ps) (hz ∷ hs) =
          ≤-trans (≤-reflexive (getL-++-prefix lv (XL ∷ []) z pz)) hz ∷ go zs ps hs

    IH = xorPairs-lvl lv1 as cs R (suc L) (sym len1) as<1 cs<1 asR1 csR1

    runEq : runLevels lv (proj₂ (proj₂ (xorPairs (a ∷ as) (c ∷ cs) L)))
              ≡ runLevels lv1 rest
    runEq = cong (runLevels lv1) (++-identityʳ rest)

    maxB : maxL (runLevels lv (proj₂ (proj₂ (xorPairs (a ∷ as) (c ∷ cs) L)))) ≤ maxL lv ⊔ suc R
    maxB = ≤-trans (≤-reflexive (cong maxL runEq))
             (≤-trans (proj₁ IH)
               (⊔-lub (≤-trans (≤-reflexive (maxL-snoc lv XL))
                               (⊔-lub (m≤m⊔n (maxL lv) (suc R)) (≤-trans XL≤ (m≤n⊔m (maxL lv) (suc R)))))
                      (m≤n⊔m (maxL lv) (suc R))))

    headB : getL (runLevels lv (proj₂ (proj₂ (xorPairs (a ∷ as) (c ∷ cs) L)))) L ≤ suc R
    headB = ≤-trans (≤-reflexive
                      (trans (cong (λ e → getL e L) runEq)
                             (trans (runLevels-stable lv1 rest L (≤-reflexive (sym len1)))
                                    (getL-snoc-last lv XL))))
                    XL≤

    tailB : All (λ w → getL (runLevels lv (proj₂ (proj₂ (xorPairs (a ∷ as) (c ∷ cs) L)))) w ≤ suc R) outs
    tailB = subst (λ e → All (λ w → getL e w ≤ suc R) outs) (sym runEq) (proj₂ IH)

------------------------------------------------------------------------
--  For comparator wires bs at level ≤ R, bound the cone by
--  accLvl 0 R |bs| + 2: fold from two level-zero constants,
--  then add not/and. Join with inherited host depth.

popOn-tight :
  (lv bs : List ℕ) (h R D st : ℕ) → st ≡ length lv →
  All (_< length lv) bs → All (λ w → getL lv w ≤ R) bs →
  maxL (runLevels lv (proj₂ (proj₂ (popOnBuilder bs h st))))
    ≤ maxL lv ⊔ suc (suc (accLvl D R (length bs)))
popOn-tight lv bs h R D st refl bs< bsR =
  ≤-trans (≤-reflexive (cong maxL split)) bound
  where
    L    = length lv
    N    = length bs
    T    = accLvl D R N
    acc0 = L ∷ replicate N (suc L)
    e2   = (lv ++ (0 ∷ [])) ++ (0 ∷ [])
    fld  = λ s → foldlMB (stepTh L) acc0 bs s
    FOLDOPS = proj₂ (proj₂ (fld (suc (suc L))))
    notG  = nth (proj₁ (fld (suc (suc L)))) (suc h) (suc L)
    andG1 = nth (proj₁ (fld (suc (suc L)))) h (suc L)
    andG2 = proj₁ (proj₂ (fld (suc (suc L))))

    split : runLevels lv (proj₂ (proj₂ (popOnBuilder bs h L)))
          ≡ runLevels e2 (FOLDOPS ++ (oNot notG ∷ oAnd andG1 andG2 ∷ []))
    split = refl

    len-e2 : length e2 ≡ suc (suc L)
    len-e2 = trans (length-snoc (lv ++ (0 ∷ [])) 0) (cong suc (length-snoc lv 0))

    maxL-e2 : maxL e2 ≡ maxL lv
    maxL-e2 = trans (maxL-snoc (lv ++ (0 ∷ [])) 0)
                    (trans (⊔-identityʳ _)
                           (trans (maxL-snoc lv 0) (⊔-identityʳ (maxL lv))))

    --  Place both constants at level zero and preserve inherited levels.
    tw≡ : getL e2 L ≡ 0
    tw≡ = trans (getL-++-prefix (lv ++ (0 ∷ [])) (0 ∷ []) L
                   (≤-reflexive (sym (length-snoc lv 0))))
                (getL-snoc-last lv 0)
    fw≡ : getL e2 (suc L) ≡ 0
    fw≡ = trans (cong (getL e2) (sym (length-snoc lv 0)))
                (getL-snoc-last (lv ++ (0 ∷ [])) 0)
    e2-stable : (w : ℕ) → w < L → getL e2 w ≡ getL lv w
    e2-stable w w< = trans (getL-++-prefix (lv ++ (0 ∷ [])) (0 ∷ []) w
                             (≤-trans w< (≤-trans (n≤1+n L) (≤-reflexive (sym (length-snoc lv 0))))))
                           (getL-++-prefix lv (0 ∷ []) w w<)

    L<e2 : L < length e2
    L<e2 = ≤-trans (s≤s (n≤1+n L)) (≤-reflexive (sym len-e2))
    sL<e2 : suc L < length e2
    sL<e2 = ≤-reflexive (sym len-e2)
    L≤e2 : L ≤ length e2
    L≤e2 = ≤-trans (n≤1+n L) (≤-trans (n≤1+n (suc L)) (≤-reflexive (sym len-e2)))

    accv : All (_< length e2) acc0
    accv = L<e2 ∷ replicate-P N (suc L) sL<e2
    accD : All (λ w → getL e2 w ≤ D) acc0
    accD = ≤-trans (≤-reflexive tw≡) z≤n ∷ replicate-P N (suc L) (≤-trans (≤-reflexive fw≡) z≤n)
    bsv : All (_< length e2) bs
    bsv = All-≤ bs L≤e2 bs<
    bsR' : All (λ w → getL e2 w ≤ R) bs
    bsR' = go bs bs< bsR
      where
        go : (zs : List ℕ) → All (_< L) zs → All (λ w → getL lv w ≤ R) zs →
             All (λ w → getL e2 w ≤ R) zs
        go []       []        []        = []
        go (z ∷ zs) (pz ∷ ps) (hz ∷ hs) = ≤-trans (≤-reflexive (e2-stable z pz)) hz ∷ go zs ps hs

    FOLD = fold-tight L acc0 bs e2 D R (suc (suc L)) (sym len-e2)
             L<e2 accv bsv (≤-trans (≤-reflexive tw≡) z≤n) accD bsR'

    efold = runLevels e2 FOLDOPS
    fold≤ : maxL efold ≤ maxL lv ⊔ T
    fold≤ = ≤-trans (proj₁ FOLD) (⊔-mono-≤ (≤-reflexive maxL-e2) ≤-refl)

    --  Restrict head-gate reads to thermometer wires or the false constant.
    fwT : getL efold (suc L) ≤ T
    fwT = ≤-trans (≤-reflexive (trans (runLevels-stable e2 FOLDOPS (suc L) sL<e2) fw≡)) z≤n
    notG≤ : getL efold notG ≤ T
    notG≤ = nth-P (proj₁ (fld (suc (suc L)))) (suc h) (suc L) (proj₂ FOLD) fwT
    andG1≤ : getL efold andG1 ≤ T
    andG1≤ = nth-P (proj₁ (fld (suc (suc L)))) h (suc L) (proj₂ FOLD) fwT

    notLvl = opLevel efold (oNot notG)
    e3     = efold ++ (notLvl ∷ [])
    andLvl = opLevel e3 (oAnd andG1 andG2)

    notLvl≤ : notLvl ≤ suc T
    notLvl≤ = s≤s notG≤

    --  Identify the not output's identifier with the fold's final state.
    andG2≡ : andG2 ≡ length efold
    andG2≡ = trans (foldlMB-cnt-general (stepTh L) (λ ac y → stepTh-cnt L ac y) acc0 bs
                      (suc (suc L)))
                   (trans (cong (_+ length FOLDOPS) (sym len-e2))
                          (sym (runLevels-len e2 FOLDOPS)))

    andLvl≤ : andLvl ≤ suc (suc T)
    andLvl≤ = s≤s (⊔-lub (≤-trans (getL-snoc-≤ efold notLvl andG1)
                                  (⊔-lub (≤-trans andG1≤ (n≤1+n T)) notLvl≤))
                         (≤-trans (≤-reflexive (trans (cong (getL e3) andG2≡)
                                                      (getL-snoc-last efold notLvl)))
                                  notLvl≤))

    bound : maxL (runLevels e2 (FOLDOPS ++ (oNot notG ∷ oAnd andG1 andG2 ∷ [])))
              ≤ maxL lv ⊔ suc (suc T)
    bound = ≤-trans (≤-reflexive (trans (cong maxL (runLevels-++ e2 FOLDOPS _))
                                        (trans (maxL-snoc e3 andLvl)
                                               (cong (_⊔ andLvl) (maxL-snoc efold notLvl)))))
              (⊔-lub (⊔-lub (≤-trans fold≤ (⊔-mono-≤ ≤-refl
                                             (≤-trans (n≤1+n T) (n≤1+n (suc T)))))
                            (≤-trans notLvl≤ (≤-trans (n≤1+n (suc T))
                                               (m≤n⊔m (maxL lv) (suc (suc T))))))
                     (≤-trans andLvl≤ (m≤n⊔m (maxL lv) (suc (suc T)))))

------------------------------------------------------------------------
--  Compose the restore cone's +1 XOR layer with its comparator,
--  measuring both from data/key level R.

restoreNet-tight :
  (lv xs keys : List ℕ) (h R st : ℕ) → st ≡ length lv →
  All (_< length lv) xs → All (_< length lv) keys →
  All (λ w → getL lv w ≤ R) xs → All (λ w → getL lv w ≤ R) keys →
  maxL (runLevels lv (proj₂ (proj₂ (restoreNet xs keys h st))))
    ≤ maxL lv ⊔ suc (suc (accLvl (suc R) (suc R) (length (proj₁ (xorPairs xs keys (length lv))))))
restoreNet-tight lv xs keys h R st refl xs< keys< xsR keysR =
  ≤-trans (≤-reflexive (cong maxL split)) bound
  where
    L     = length lv
    XOPS  = proj₂ (proj₂ (xorPairs xs keys L))
    rbits = proj₁ (xorPairs xs keys L)
    xid   = proj₁ (proj₂ (xorPairs xs keys L))
    lv1   = runLevels lv XOPS
    T     = accLvl (suc R) (suc R) (length rbits)

    split : runLevels lv (proj₂ (proj₂ (restoreNet xs keys h L)))
          ≡ runLevels lv1 (proj₂ (proj₂ (popOnBuilder rbits h xid)))
    split = runLevels-++ lv XOPS (proj₂ (proj₂ (popOnBuilder rbits h xid)))

    XL = xorPairs-lvl lv xs keys R L refl xs< keys< xsR keysR

    xid≡ : xid ≡ length lv1
    xid≡ = run-len-state (xorPairs xs keys) (xorPairs-cnt xs keys) lv

    rbits< : All (_< length lv1) rbits
    rbits< = All-≤ rbits (≤-reflexive xid≡) (xorPairs-outs< xs keys L)

    bound : maxL (runLevels lv1 (proj₂ (proj₂ (popOnBuilder rbits h xid))))
              ≤ maxL lv ⊔ suc (suc T)
    bound = ≤-trans (popOn-tight lv1 rbits h (suc R) (suc R) xid xid≡ rbits< (proj₂ XL))
                    (⊔-lub (≤-trans (proj₁ XL)
                             (⊔-lub (m≤m⊔n (maxL lv) (suc (suc T)))
                                    (≤-trans (≤-trans (D≤accLvl (suc R) (suc R) (length rbits))
                                                      (≤-trans (n≤1+n T) (n≤1+n (suc T))))
                                             (m≤n⊔m (maxL lv) (suc (suc T))))))
                           (m≤n⊔m (maxL lv) (suc (suc T))))

------------------------------------------------------------------------
--  §4 Compose constants, two parallel restore cones, and two
--  output XORs. Both cones read primary data/key wires, so
--  only one cone depth contributes: R + 2|xs| + 6 replaces
--  the earlier R + 6|xs| + 9 estimate.

open import Extraction.NetDepthHost using
  (newMax; netDepth-split; getL-new; constWires-outs≥; newMax-flatten;
   flat; length-flat; maxL-flat; lockCone; cone-RefsOK; RefOK; lockedBlock-added)
open import Extraction.NetDepthPop using (constWires-outs<; constWires-mono)

private
  arith4 : (r n : ℕ) → suc (suc (suc (suc r) + 2 * n)) ≡ r + 2 * n + 4
  arith4 = solve 2 (λ r n → con 3 :+ (con 1 :+ r) :+ con 2 :* n := r :+ con 2 :* n :+ con 4) refl

--  Since oConst has no fan-in, the constant layer adds no
--  depth to the maximum or the key wires it creates.
constWires-newMax : (lv : List ℕ) (bs : List Bool) (i : ℕ) →
                    newMax lv (proj₂ (proj₂ (constWires bs i))) ≡ 0
constWires-newMax lv []       i = refl
constWires-newMax lv (b ∷ bs) i =
  trans (cong (newMax (lv ++ (0 ∷ []))) (++-identityʳ (proj₂ (proj₂ (constWires bs (suc i))))))
        (constWires-newMax (lv ++ (0 ∷ [])) bs (suc i))

constWires-flat : (lv : List ℕ) (bs : List Bool) (i : ℕ) →
                  maxL (runLevels lv (proj₂ (proj₂ (constWires bs i)))) ≡ maxL lv
constWires-flat lv bs i =
  trans (netDepth-split lv (proj₂ (proj₂ (constWires bs i))))
        (trans (cong (maxL lv ⊔_) (constWires-newMax lv bs i)) (⊔-identityʳ (maxL lv)))

--  Use R + 2|xs| + 4 as the restore cone's closed input-level bound.
restoreNet-tight-closed :
  (lv xs keys : List ℕ) (h R st : ℕ) → st ≡ length lv →
  All (_< length lv) xs → All (_< length lv) keys →
  All (λ w → getL lv w ≤ R) xs → All (λ w → getL lv w ≤ R) keys →
  maxL (runLevels lv (proj₂ (proj₂ (restoreNet xs keys h st))))
    ≤ maxL lv ⊔ (R + 2 * length xs + 4)
restoreNet-tight-closed lv xs keys h R st refl xs< keys< xsR keysR =
  ≤-trans (restoreNet-tight lv xs keys h R (length lv) refl xs< keys< xsR keysR)
          (⊔-mono-≤ ≤-refl top)
  where
    Nr = length (proj₁ (xorPairs xs keys (length lv)))
    top : suc (suc (accLvl (suc R) (suc R) Nr)) ≤ R + 2 * length xs + 4
    top = ≤-trans (s≤s (s≤s (≤-trans (accLvl-closed (suc R) (suc R) Nr)
                              (+-mono-≤ (⊔-lub (n≤1+n (suc R)) ≤-refl)
                                        (*-monoʳ-≤ 2 (xorPairs-len≤ xs keys (length lv)))))))
                  (≤-reflexive (arith4 R (length xs)))

------------------------------------------------------------------------
--  Bound constants and both restore cones independently of the
--  host. Shared primary inputs put the cones side by side,
--  removing most slack from the earlier 6|xs| + 9 charge.

lockCone-tight :
  (lv xs keys : List ℕ) (ksec : List Bool) (h R st : ℕ) → st ≡ length lv →
  All (_< length lv) xs → All (_< length lv) keys →
  All (λ w → getL lv w ≤ R) xs → All (λ w → getL lv w ≤ R) keys →
  maxL (runLevels lv (proj₂ (proj₂ (lockCone xs keys ksec h st))))
    ≤ maxL lv ⊔ (R + 2 * length xs + 4)
lockCone-tight lv xs keys ksec h R st refl xs< keys< xsR keysR =
  ≤-trans (≤-reflexive (cong maxL split-cone)) b2
  where
    L    = length lv
    A    = R + 2 * length xs + 4
    cwO  = proj₂ (proj₂ (constWires ksec L))
    e-c  = runLevels lv cwO
    cwid = proj₁ (proj₂ (constWires ksec L))
    kw   = proj₁ (constWires ksec L)
    r1O  = proj₂ (proj₂ (restoreNet xs kw h cwid))
    e1   = runLevels e-c r1O
    r1id = proj₁ (proj₂ (restoreNet xs kw h cwid))
    r2O  = proj₂ (proj₂ (restoreNet xs keys h r1id))
    e2   = runLevels e1 r2O

    split-cone : runLevels lv (proj₂ (proj₂ (lockCone xs keys ksec h L))) ≡ e2
    split-cone = trans (runLevels-++ lv cwO (r1O ++ r2O)) (runLevels-++ e-c r1O r2O)

    lv≤c : L ≤ length e-c
    lv≤c = lenMono lv cwO
    cwid≡ : cwid ≡ length e-c
    cwid≡ = run-len-state (constWires ksec) (constWires-cnt ksec) lv
    c≤1 : length e-c ≤ length e1
    c≤1 = lenMono e-c r1O
    r1id≡ : r1id ≡ length e1
    r1id≡ = trans (restoreNet-cnt xs kw h cwid)
                  (trans (cong (_+ length r1O) cwid≡) (sym (runLevels-len e-c r1O)))

    maxc : maxL e-c ≡ maxL lv
    maxc = constWires-flat lv ksec L

    --  Keep key constants in range and at level zero.
    kw< : All (_< length e-c) kw
    kw< = All-≤ kw (≤-reflexive cwid≡) (constWires-outs< ksec L)
    kwR : All (λ w → getL e-c w ≤ R) kw
    kwR = go kw (constWires-outs≥ ksec L)
      where
        go : (ws : List ℕ) → All (L ≤_) ws → All (λ w → getL e-c w ≤ R) ws
        go []       []        = []
        go (w ∷ ws) (pw ∷ ps) =
          ≤-trans (≤-trans (getL-new lv cwO w pw) (≤-reflexive (constWires-newMax lv ksec L))) z≤n
            ∷ go ws ps

    xs<c : All (_< length e-c) xs
    xs<c = All-≤ xs lv≤c xs<
    keys<c : All (_< length e-c) keys
    keys<c = All-≤ keys lv≤c keys<
    xsRc : All (λ w → getL e-c w ≤ R) xs
    xsRc = All-stable lv cwO R xs xs< xsR
    keysRc : All (λ w → getL e-c w ≤ R) keys
    keysRc = All-stable lv cwO R keys keys< keysR

    b1 : maxL e1 ≤ maxL lv ⊔ A
    b1 = ≤-trans (restoreNet-tight-closed e-c xs kw h R cwid cwid≡ xs<c kw< xsRc kwR)
                 (⊔-mono-≤ (≤-reflexive maxc) ≤-refl)

    xs<1 : All (_< length e1) xs
    xs<1 = All-≤ xs (≤-trans lv≤c c≤1) xs<
    keys<1 : All (_< length e1) keys
    keys<1 = All-≤ keys (≤-trans lv≤c c≤1) keys<
    xsR1 : All (λ w → getL e1 w ≤ R) xs
    xsR1 = All-stable e-c r1O R xs xs<c xsRc
    keysR1 : All (λ w → getL e1 w ≤ R) keys
    keysR1 = All-stable e-c r1O R keys keys<c keysRc

    b2 : maxL e2 ≤ maxL lv ⊔ A
    b2 = ≤-trans (restoreNet-tight-closed e1 xs keys h R r1id r1id≡ xs<1 keys<1 xsR1 keysR1)
                 (⊔-lub b1 (m≤n⊔m (maxL lv) A))

------------------------------------------------------------------------
--  Append two output XORs to the unfused cone.

lockedBlock-tight :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire R st : ℕ) → st ≡ length lv →
  All (_< length lv) xs → All (_< length lv) keys →
  All (λ w → getL lv w ≤ R) xs → All (λ w → getL lv w ≤ R) keys →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire st))))
    ≤ suc (suc (maxL lv ⊔ (R + 2 * length xs + 4)))
lockedBlock-tight lv xs keys ksec h fWire R st refl xs< keys< xsR keysR =
  ≤-trans (≤-reflexive (cong maxL split-all)) chain
  where
    L    = length lv
    A    = R + 2 * length xs + 4
    cwO  = proj₂ (proj₂ (constWires ksec L))
    e-c  = runLevels lv cwO
    cwid = proj₁ (proj₂ (constWires ksec L))
    kw   = proj₁ (constWires ksec L)
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

    split-all : runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire L)))
              ≡ runLevels e3 x2O
    split-all = trans (runLevels-++ lv cwO _)
                (trans (runLevels-++ e-c r1O _)
                (trans (runLevels-++ e1 r2O _)
                       (runLevels-++ e2 x1O x2O)))

    split-cone : runLevels lv (proj₂ (proj₂ (lockCone xs keys ksec h L))) ≡ e2
    split-cone = trans (runLevels-++ lv cwO (r1O ++ r2O)) (runLevels-++ e-c r1O r2O)

    b2 : maxL e2 ≤ maxL lv ⊔ A
    b2 = ≤-trans (≤-reflexive (cong maxL (sym split-cone)))
                 (lockCone-tight lv xs keys ksec h R L refl xs< keys< xsR keysR)

    b3 : maxL e3 ≤ suc (maxL lv ⊔ A)
    b3 = ≤-trans (snocXor≤ e2 fWire pW) (s≤s b2)

    chain : maxL (runLevels e3 x2O) ≤ suc (suc (maxL lv ⊔ A))
    chain = ≤-trans (snocXor≤ e3 r2id rW) (s≤s b3)

------------------------------------------------------------------------
--  §5 Derive host-independent results under a premise weakened
--  by 4n + 5 levels. NetDepthHost's +2 conclusion needed
--  a host output at least R + 6n + 9; the refined cone
--  requires only R + 2n + 4, extending applicability to
--  shallower hosts and smaller key widths.

open import Data.Sum using (inj₁)
open import Extraction.NetDepthHost using (getL-flat; lockedBlock-added-gen)

private
  flat-levels : (L R b : ℕ) (zs : List ℕ) → b ≤ L → All (_< b) zs →
                All (λ w → getL (flat L R) w ≤ R) zs
  flat-levels L R b []       _  []        = []
  flat-levels L R b (z ∷ zs) b≤ (pz ∷ ps) =
    ≤-reflexive (getL-flat L R z (≤-trans pz b≤)) ∷ flat-levels L R b zs b≤ ps

  flat-range : (L R b : ℕ) (zs : List ℕ) → b ≤ L → All (_< b) zs →
               All (_< length (flat L R)) zs
  flat-range L R b zs b≤ p =
    All-≤ zs (≤-reflexive (sym (length-flat L R))) (All-≤ zs b≤ p)

--  Bound host-erased cone depth by R + 2|xs| + 4.
cone-added-tight :
  (lv xs keys : List ℕ) (ksec : List Bool) (h b R : ℕ) →
  b ≤ length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  newMax lv (proj₂ (proj₂ (lockCone xs keys ksec h (length lv))))
    ≤ R + 2 * length xs + 4
cone-added-tight lv xs keys ksec h b R b≤ Hlev xs<b keys<b =
  ≤-trans (newMax-flatten lv coneOps b R b≤ Hlev coneOK)
          (≤-trans (lockCone-tight E xs keys ksec h R L (sym lenE)
                      (flat-range L R b xs b≤ xs<b) (flat-range L R b keys b≤ keys<b)
                      (flat-levels L R b xs b≤ xs<b) (flat-levels L R b keys b≤ keys<b))
                   (⊔-lub (≤-trans (maxL-flat L R) (≤-trans (m≤m+n R (2 * length xs))
                                                            (m≤m+n (R + 2 * length xs) 4)))
                          ≤-refl))
  where
    L = length lv
    E = flat L R
    coneOps = proj₂ (proj₂ (lockCone xs keys ksec h L))
    lenE : length E ≡ L
    lenE = length-flat L R
    coneOK = cone-RefsOK b L xs keys ksec h L ≤-refl
               (in-prefix xs xs<b) (in-prefix keys keys<b)
      where
        in-prefix : (zs : List ℕ) → All (_< b) zs → All (RefOK b L) zs
        in-prefix []       []        = []
        in-prefix (z ∷ zs) (pz ∷ ps) = inj₁ pz ∷ in-prefix zs ps

--  Give the refined counterpart of NetDepthHost.lockedBlock-added.
lockedBlock-added-tight :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  newMax lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))
    ≤ suc (suc (getL lv fWire ⊔ (R + 2 * length xs + 4)))
lockedBlock-added-tight lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b =
  lockedBlock-added-gen lv xs keys ksec h fWire (R + 2 * length xs + 4) fW<
    (cone-added-tight lv xs keys ksec h b R b≤ Hlev xs<b keys<b)

--  Derive host-independent +2 with the premise reduced by 4n + 5 levels.
lockedBlock-adds-2-tight :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  R + 2 * length xs + 4 ≤ getL lv fWire →
  newMax lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))
    ≤ getL lv fWire + 2
lockedBlock-adds-2-tight lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b A≤F =
  ≤-trans (lockedBlock-added-tight lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b)
          (≤-reflexive (trans (cong (λ z → suc (suc z)) (m≥n⇒m⊔n≡m A≤F))
                              (+-comm 2 (getL lv fWire))))

lockedBlock-depth-adds-2-tight :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  R + 2 * length xs + 4 ≤ getL lv fWire →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv)))))
    ≤ maxL lv + 2
lockedBlock-depth-adds-2-tight lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b A≤F =
  ≤-trans (≤-reflexive (netDepth-split lv
             (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))))
          (⊔-lub (m≤m+n (maxL lv) 2)
                 (≤-trans (lockedBlock-adds-2-tight lv xs keys ksec h fWire b R
                             b≤ fW< Hlev xs<b keys<b A≤F)
                          (+-mono-≤ (getL-≤-maxL lv fWire) (≤-refl {2}))))

------------------------------------------------------------------------
--  Compose with the host to refine NetDepthHost.lockHostBlock-adds-2.

open import Data.Fin using (Fin; zero)
open import Data.Vec using (Vec; lookup)
open import Locking.NetlistToCircuit using (Netlist)
open import Extraction.HostNetlist using (netlistWires; netlistWires-cnt)
open import Extraction.LockHost using (lockHostBlock)
open import Extraction.LockHostMerged using (lockHostBlockMerged)
open import Extraction.NetDepthHost using (length-upFrom)
open import Extraction.NetDepthMerged using (hostOut<; lockHostBlockMerged-depth-lower)
open import Extraction.NetDepthPop using (upFrom-<)

--  Bound total locked-host overhead by two levels when its
--  cone output reaches R + 2n + 4, replacing the earlier
--  R + 6n + 9 requirement.
lockHostBlock-adds-2-tight :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (h : ℕ) (lv : List ℕ) (R : ℕ) →
  n + n ≤ length lv →
  ((i : ℕ) → i < n + n → getL lv i ≤ R) →
  R + 2 * n + 4 ≤ getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
                       (lookup (proj₁ (netlistWires nl (length lv))) zero) →
  maxL (runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv)))))
    ≤ maxL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))) + 2
lockHostBlock-adds-2-tight {n} nl ksec h lv R nn≤ Hlev A≤F =
  ≤-trans (≤-reflexive (cong maxL split)) atEH
  where
    hOps  = proj₂ (proj₂ (netlistWires nl (length lv)))
    eH    = runLevels lv hOps
    wid   = proj₁ (proj₂ (netlistWires nl (length lv)))
    fWire = lookup (proj₁ (netlistWires nl (length lv))) zero
    lbO   = proj₂ (proj₂ (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire wid))

    split : runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv))))
              ≡ runLevels eH lbO
    split = runLevels-++ lv hOps lbO

    lv≤H : length lv ≤ length eH
    lv≤H = lenMono lv hOps
    wid≡ : wid ≡ length eH
    wid≡ = run-len-state (netlistWires nl) (netlistWires-cnt nl) lv

    A≤F' : R + 2 * length (upFrom 0 n) + 4 ≤ getL eH fWire
    A≤F' = ≤-trans (≤-reflexive (cong (λ z → R + 2 * z + 4) (length-upFrom n 0))) A≤F

    atEH : maxL (runLevels eH lbO) ≤ maxL eH + 2
    atEH = ≤-trans (≤-reflexive
                     (cong (λ s → maxL (runLevels eH (proj₂ (proj₂
                             (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire s)))))
                           wid≡))
                   (lockedBlock-depth-adds-2-tight eH (upFrom 0 n) (upFrom n n) ksec h fWire
                      (n + n) R (≤-trans nn≤ lv≤H)
                      (hostOut< nl lv (≤-trans (m≤m+n n n) nn≤))
                      (λ i i< → ≤-trans (≤-reflexive (runLevels-stable lv hOps i (≤-trans i< nn≤)))
                                        (Hlev i i<))
                      (upFrom-< n 0 (m≤m+n n n)) (upFrom-< n n ≤-refl) A≤F')

--  Separate the fused emitter under the same weaker premise.
unfused-strictly-shallower-tight :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (lv : List ℕ) (R : ℕ) →
  length ksec ≡ n → 1 ≤ n → n + n ≤ length lv →
  ((i : ℕ) → i < n + n → getL lv i ≤ R) →
  R + 2 * n + 4 ≤ getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
                       (lookup (proj₁ (netlistWires nl (length lv))) zero) →
  maxL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
    ≤ getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
           (lookup (proj₁ (netlistWires nl (length lv))) zero) →
  All (λ x → suc (getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))) x)
               ≤ getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
                      (lookup (proj₁ (netlistWires nl (length lv))) zero))
      (upFrom 0 n) →
  maxL (runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec 0 (length lv)))))
    < maxL (runLevels lv (proj₂ (proj₂ (lockHostBlockMerged nl ksec (length lv)))))
unfused-strictly-shallower-tight {n} nl ksec lv R ksecLen n≥1 nn≤ Hlev A≤F mx≤F deep =
  ≤-trans (s≤s (≤-trans (lockHostBlock-adds-2-tight nl ksec 0 lv R nn≤ Hlev A≤F)
                        (≤-trans (+-mono-≤ mx≤F (≤-refl {2}))
                                 (+-mono-≤ (≤-refl {getL eH fWire}) (*-monoʳ-≤ 2 n≥1)))))
          (lockHostBlockMerged-depth-lower nl ksec lv ksecLen
             (upFrom-< n 0 (≤-trans (m≤m+n n n) nn≤)) deep)
  where
    eH    = runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))
    fWire = lookup (proj₁ (netlistWires nl (length lv))) zero

------------------------------------------------------------------------
--  §6 Obtain an equation for fused depth. NetDepthMerged
--  bounded it below by 2|lits| + 1 above the host wire
--  and above by maxL lv + 5|xs| + 6. Charging restore
--  to input levels removes that upper-bound slack when the
--  fused chain on the host output dominates the parallel
--  restore cone, closing the bracket.

open import Extraction.LockedNetMerged using
  (cubeLits; cubeLits-cnt; fuseXorCube; fuseXorCube-cnt; fuseXorCube-out<;
   lockedBlockMerged)
open import Extraction.NetDepthMerged using
  (cubeLits-bound; cubeLits-levels; cubeLits-outs<; cubeLits-len≤;
   fuseXorCube-≤; fuseXorCube-out-level)

--  If the read host wire dominates all host wires and the
--  fused chain dominates restore, prove critical-path depth
--  getL lv fWire + 2|lits| + 2 exactly.
lockedBlockMerged-depth-exact :
  (lv xs keys : List ℕ) (ksec : List Bool) (fWire R : ℕ) →
  fWire < length lv → All (_< length lv) xs → All (_< length lv) keys →
  All (λ w → getL lv w ≤ R) xs → All (λ w → getL lv w ≤ R) keys →
  All (λ x → suc (getL lv x) ≤ getL lv fWire) xs →
  maxL lv ≤ getL lv fWire →
  R + 2 * length xs + 4
    ≤ suc (getL lv fWire) + 2 * length (proj₁ (cubeLits xs ksec (length lv))) →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlockMerged xs keys ksec fWire (length lv)))))
    ≡ suc (suc (getL lv fWire) + 2 * length (proj₁ (cubeLits xs ksec (length lv))))
lockedBlockMerged-depth-exact lv xs keys ksec fWire R fW< xs< keys< xsR keysR deep mx≤F cone≤ =
  trans (cong maxL split-all) (≤-antisym up down)
  where
    L    = length lv
    cR   = cubeLits xs ksec L
    lits = proj₁ cR
    iC   = proj₁ (proj₂ cR)
    cOps = proj₂ (proj₂ cR)
    e-c  = runLevels lv cOps
    fR   = fuseXorCube fWire lits iC
    t    = proj₁ fR
    iF   = proj₁ (proj₂ fR)
    fOps = proj₂ (proj₂ fR)
    e-f  = runLevels e-c fOps
    rR   = restoreNet xs keys 0 iF
    rW   = proj₁ rR
    rOps = proj₂ (proj₂ rR)
    e-r  = runLevels e-f rOps

    F = getL lv fWire
    P = suc F + 2 * length lits
    XL = opLevel e-r (oXor t rW)

    split-all :
      runLevels lv (proj₂ (proj₂ (lockedBlockMerged xs keys ksec fWire L)))
        ≡ runLevels e-r (oXor t rW ∷ [])
    split-all = trans (runLevels-++ lv cOps (fOps ++ (rOps ++ (oXor t rW ∷ []))))
                (trans (runLevels-++ e-c fOps (rOps ++ (oXor t rW ∷ [])))
                       (runLevels-++ e-f rOps (oXor t rW ∷ [])))

    iC≡ : iC ≡ length e-c
    iC≡ = run-len-state (cubeLits xs ksec) (cubeLits-cnt xs ksec) lv
    lv≤c : L ≤ length e-c
    lv≤c = lenMono lv cOps
    c≤f : length e-c ≤ length e-f
    c≤f = lenMono e-c fOps
    iF≡ : iF ≡ length e-f
    iF≡ = trans (fuseXorCube-cnt fWire lits iC)
                (trans (cong (_+ length fOps) iC≡) (sym (runLevels-len e-c fOps)))

    fStable : getL e-c fWire ≡ F
    fStable = runLevels-stable lv cOps fWire fW<

    litsRange : All (_< length e-c) lits
    litsRange = All-≤ lits (≤-reflexive iC≡) (cubeLits-outs< xs ksec L xs<)
    litsShallow : All (λ l → getL e-c l ≤ getL e-c fWire) lits
    litsShallow = go lits (cubeLits-levels lv xs ksec F xs< deep)
      where
        go : (ws : List ℕ) → All (λ w → getL e-c w ≤ F) ws →
             All (λ w → getL e-c w ≤ getL e-c fWire) ws
        go []       []        = []
        go (w ∷ ws) (pw ∷ ps) = ≤-trans pw (≤-reflexive (sym fStable)) ∷ go ws ps

    --  Stage one: literals add at most one level; with host
    --  wires no deeper than fWire, this stays below the fused chain.
    maxc≤ : maxL e-c ≤ P
    maxc≤ = ≤-trans (cubeLits-bound lv xs ksec xs<)
                    (≤-trans (s≤s mx≤F) (m≤m+n (suc F) (2 * length lits)))

    --  Stage two: place the chain exactly 2|lits| + 1 above fWire.
    QL : ℕ → Set
    QL s = getL (runLevels e-c (proj₂ (proj₂ (fuseXorCube fWire lits s))))
                (proj₁ (fuseXorCube fWire lits s))
             ≡ suc (getL e-c fWire) + 2 * length lits
    tLvl-f : getL e-f t ≡ P
    tLvl-f = trans (subst QL (sym iC≡)
                      (fuseXorCube-out-level e-c fWire lits (≤-trans fW< lv≤c)
                         litsRange litsShallow))
                   (cong (λ z → suc z + 2 * length lits) fStable)

    QM : ℕ → Set
    QM s = maxL (runLevels e-c (proj₂ (proj₂ (fuseXorCube fWire lits s))))
             ≤ maxL e-c ⊔ (suc (getL e-c fWire) + 2 * length lits)
    maxf≤ : maxL e-f ≤ P
    maxf≤ = ≤-trans (subst QM (sym iC≡)
                      (proj₂ (fuseXorCube-≤ e-c fWire lits (getL e-c fWire)
                                (≤-trans fW< lv≤c) litsRange ≤-refl litsShallow)))
                    (⊔-lub maxc≤ (≤-reflexive (cong (λ z → suc z + 2 * length lits) fStable)))

    --  Stage three: charge the single restore cone to input levels.
    xs<f : All (_< length e-f) xs
    xs<f = All-≤ xs (≤-trans lv≤c c≤f) xs<
    keys<f : All (_< length e-f) keys
    keys<f = All-≤ keys (≤-trans lv≤c c≤f) keys<
    xsRf : All (λ w → getL e-f w ≤ R) xs
    xsRf = All-stable e-c fOps R xs (All-≤ xs lv≤c xs<) (All-stable lv cOps R xs xs< xsR)
    keysRf : All (λ w → getL e-f w ≤ R) keys
    keysRf = All-stable e-c fOps R keys (All-≤ keys lv≤c keys<)
                        (All-stable lv cOps R keys keys< keysR)

    maxr≤ : maxL e-r ≤ P
    maxr≤ = ≤-trans (restoreNet-tight-closed e-f xs keys 0 R iF iF≡ xs<f keys<f xsRf keysRf)
                    (⊔-lub maxf≤ cone≤)

    --  Stage four: put the output XOR exactly one level above the chain.
    tLvl-r : getL e-r t ≡ P
    tLvl-r = trans (runLevels-stable e-f rOps t
                      (≤-trans (fuseXorCube-out< fWire lits iC) (≤-reflexive iF≡)))
                   tLvl-f

    XL≤ : XL ≤ suc P
    XL≤ = s≤s (⊔-lub (≤-reflexive tLvl-r) (≤-trans (getL-≤-maxL e-r rW) maxr≤))
    XL≥ : suc P ≤ XL
    XL≥ = s≤s (≤-trans (≤-reflexive (sym tLvl-r)) (m≤m⊔n (getL e-r t) (getL e-r rW)))

    up : maxL (runLevels e-r (oXor t rW ∷ [])) ≤ suc P
    up = ≤-trans (≤-reflexive (maxL-snoc e-r XL))
                 (⊔-lub (≤-trans maxr≤ (n≤1+n P)) XL≤)
    down : suc P ≤ maxL (runLevels e-r (oXor t rW ∷ []))
    down = ≤-trans XL≥ (≤-trans (m≤n⊔m (maxL e-r) XL)
                                (≤-reflexive (sym (maxL-snoc e-r XL))))

------------------------------------------------------------------------
--  §7 Re-derive the existing restore, block, and host bounds
--  from tighter results. Their original modules retain names,
--  types, and proofs, with no downstream weakening. Taking
--  R = maxL lv discharges input-level premises by getL-≤-maxL.

private
  arith69 : (m n : ℕ) → suc (suc (m + 2 * n + 4)) + (4 * n + 3) ≡ m + 6 * n + 9
  arith69 = solve 2 (λ m n → (con 2 :+ (m :+ con 2 :* n :+ con 4)) :+ (con 4 :* n :+ con 3)
                               := m :+ con 6 :* n :+ con 9) refl

  arith30 : (m : ℕ) → suc (suc (suc m)) ≡ suc m + 3 * 0 + 2
  arith30 = solve 1 (λ m → con 3 :+ m := (con 1 :+ m) :+ con 3 :* con 0 :+ con 2) refl

  arith3k : (m k : ℕ) → suc (suc (suc (suc m) + 2 * suc k)) + k ≡ suc m + 3 * suc k + 2
  arith3k = solve 2 (λ m k → (con 2 :+ ((con 2 :+ m) :+ con 2 :* (con 1 :+ k))) :+ k
                               := (con 1 :+ m) :+ con 3 :* (con 1 :+ k) :+ con 2) refl

  allMax : (lv : List ℕ) (zs : List ℕ) → All (λ w → getL lv w ≤ maxL lv) zs
  allMax lv []       = []
  allMax lv (z ∷ zs) = getL-≤-maxL lv z ∷ allMax lv zs

  --  Compare the accumulator ceiling with the old three-level step charge.
  accLvl-vs-3 : (M N : ℕ) → suc (suc (accLvl (suc M) (suc M) N)) ≤ suc M + 3 * N + 2
  accLvl-vs-3 M zero    = ≤-reflexive (arith30 M)
  accLvl-vs-3 M (suc k) =
    ≤-trans (s≤s (s≤s (≤-trans (accLvl-closed (suc M) (suc M) (suc k))
                               (+-mono-≤ (⊔-lub (n≤1+n (suc M)) ≤-refl)
                                         (≤-refl {2 * suc k})))))
            (≤-trans (m≤m+n (suc (suc (suc (suc M) + 2 * suc k))) k)
                     (≤-reflexive (arith3k M k)))

--  Derive NetDepthPop.restoreNet-bound from restoreNet-tight.
restoreNet-bound-from-tight :
  (lv xs keys : List ℕ) (h : ℕ) →
  All (_< length lv) xs → All (_< length lv) keys →
  maxL (runLevels lv (proj₂ (proj₂ (restoreNet xs keys h (length lv)))))
    ≤ suc (maxL lv) + 3 * length (proj₁ (xorPairs xs keys (length lv))) + 2
restoreNet-bound-from-tight lv xs keys h xs< keys< =
  ≤-trans (restoreNet-tight lv xs keys h (maxL lv) (length lv) refl xs< keys<
             (allMax lv xs) (allMax lv keys))
          (⊔-lub (≤-trans (n≤1+n (maxL lv))
                    (≤-trans (m≤m+n (suc (maxL lv)) (3 * Nr)) (m≤m+n (suc (maxL lv) + 3 * Nr) 2)))
                 (accLvl-vs-3 (maxL lv) Nr))
  where Nr = length (proj₁ (xorPairs xs keys (length lv)))

--  Derive NetDepthPop.lockedBlock-bound from lockedBlock-tight.
lockedBlock-bound-from-tight :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire : ℕ) →
  All (_< length lv) xs → All (_< length lv) keys →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv)))))
    ≤ maxL lv + 6 * length xs + 9
lockedBlock-bound-from-tight lv xs keys ksec h fWire xs< keys< =
  ≤-trans (lockedBlock-tight lv xs keys ksec h fWire (maxL lv) (length lv) refl xs< keys<
             (allMax lv xs) (allMax lv keys))
          (≤-trans (s≤s (s≤s (⊔-lub (≤-trans (m≤m+n (maxL lv) (2 * length xs))
                                             (m≤m+n (maxL lv + 2 * length xs) 4))
                                    ≤-refl)))
                   (≤-trans (m≤m+n (suc (suc (maxL lv + 2 * length xs + 4))) (4 * length xs + 3))
                            (≤-reflexive (arith69 (maxL lv) (length xs)))))

--  Derive LockHost.lockHostBlock-bound from lockedBlock-tight.
lockHostBlock-bound-from-tight :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (h : ℕ) (lv : List ℕ) →
  All (_< length lv) (upFrom 0 n) → All (_< length lv) (upFrom n n) →
  maxL (runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv)))))
    ≤ maxL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))) + 6 * n + 9
lockHostBlock-bound-from-tight {n} nl ksec h lv xsv keysv =
  ≤-trans (≤-reflexive (cong maxL split))
          (≤-trans lb≤ (≤-reflexive (cong (λ z → maxL eH + 6 * z + 9) (length-upFrom n 0))))
  where
    hOps  = proj₂ (proj₂ (netlistWires nl (length lv)))
    eH    = runLevels lv hOps
    wid   = proj₁ (proj₂ (netlistWires nl (length lv)))
    fWire = lookup (proj₁ (netlistWires nl (length lv))) zero
    lbO   = proj₂ (proj₂ (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire wid))

    split : runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv))))
              ≡ runLevels eH lbO
    split = runLevels-++ lv hOps lbO

    lv≤H : length lv ≤ length eH
    lv≤H = lenMono lv hOps
    wid≡ : wid ≡ length eH
    wid≡ = run-len-state (netlistWires nl) (netlistWires-cnt nl) lv

    lb≤ : maxL (runLevels eH lbO) ≤ maxL eH + 6 * length (upFrom 0 n) + 9
    lb≤ = ≤-trans (≤-reflexive
                    (cong (λ s → maxL (runLevels eH (proj₂ (proj₂
                            (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire s)))))
                          wid≡))
                  (lockedBlock-bound-from-tight eH (upFrom 0 n) (upFrom n n) ksec h fWire
                     (All-≤ (upFrom 0 n) lv≤H xsv) (All-≤ (upFrom n n) lv≤H keysv))

------------------------------------------------------------------------
--  §8 Check non-vacuity, attainment, and recovered slack using
--  NetDepthMerged/NetDepthHost's two- and three-bit cubes,
--  zero-level data/keys, and host-output level 40.

private
  open import Extraction.Netlist using (popcountEqNet)

  --  (a) For standalone comparators, the 2N + 3 depth at N ≥ 1
  --  matches popOn-tight; the earlier bound was 3N + 2.
  _ : maxL (runLevels (0 ∷ []) (proj₂ (proj₂ (popOnBuilder (0 ∷ []) 0 1)))) ≡ 5
  _ = refl
  _ : maxL (runLevels (0 ∷ 0 ∷ []) (proj₂ (proj₂ (popOnBuilder (0 ∷ 1 ∷ []) 0 2)))) ≡ 7
  _ = refl
  _ : maxL (runLevels (0 ∷ 0 ∷ 0 ∷ []) (proj₂ (proj₂ (popOnBuilder (0 ∷ 1 ∷ 2 ∷ []) 0 3)))) ≡ 9
  _ = refl

  --  Instantiate the theorem as the attained bounds 5 ≤ 5, 7 ≤ 7, and 9 ≤ 9.
  cmp1 : maxL (runLevels (0 ∷ []) (proj₂ (proj₂ (popOnBuilder (0 ∷ []) 0 1)))) ≤ 5
  cmp1 = popOn-tight (0 ∷ []) (0 ∷ []) 0 0 0 1 refl (s≤s z≤n ∷ []) (z≤n ∷ [])
  cmp2 : maxL (runLevels (0 ∷ 0 ∷ []) (proj₂ (proj₂ (popOnBuilder (0 ∷ 1 ∷ []) 0 2)))) ≤ 7
  cmp2 = popOn-tight (0 ∷ 0 ∷ []) (0 ∷ 1 ∷ []) 0 0 0 2 refl
           (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ []) (z≤n ∷ z≤n ∷ [])
  cmp3 : maxL (runLevels (0 ∷ 0 ∷ 0 ∷ []) (proj₂ (proj₂ (popOnBuilder (0 ∷ 1 ∷ 2 ∷ []) 0 3)))) ≤ 9
  cmp3 = popOn-tight (0 ∷ 0 ∷ 0 ∷ []) (0 ∷ 1 ∷ 2 ∷ []) 0 0 0 3 refl
           (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ s≤s (s≤s (s≤s z≤n)) ∷ []) (z≤n ∷ z≤n ∷ z≤n ∷ [])

  --  Check standalone popcountEqNet agrees, where the earlier
  --  netDepth-comparator estimates were 5, 8, and 11.
  _ : maxL (runLevels (replicate 1 0) (proj₁ (popcountEqNet 1 0))) ≡ 5
  _ = refl
  _ : maxL (runLevels (replicate 2 0) (proj₁ (popcountEqNet 2 0))) ≡ 7
  _ = refl
  _ : maxL (runLevels (replicate 3 0) (proj₁ (popcountEqNet 3 0))) ≡ 9
  _ = refl

  --  (b) On flat level-zero inputs, restore attains
  --  R + 2n + 4 = 8, versus the old 1 + 3·2 + 2 = 9 bound.
  _ : maxL (runLevels (0 ∷ 0 ∷ 0 ∷ 0 ∷ [])
              (proj₂ (proj₂ (restoreNet (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) 0 4)))) ≡ 8
  _ = refl
  cone2 : maxL (runLevels (0 ∷ 0 ∷ 0 ∷ 0 ∷ [])
                 (proj₂ (proj₂ (restoreNet (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) 0 4)))) ≤ 8
  cone2 = restoreNet-tight-closed (0 ∷ 0 ∷ 0 ∷ 0 ∷ []) (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) 0 0 4 refl
            (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ [])
            (s≤s (s≤s (s≤s z≤n)) ∷ s≤s (s≤s (s≤s (s≤s z≤n))) ∷ [])
            (z≤n ∷ z≤n ∷ []) (z≤n ∷ z≤n ∷ [])

  --  (c) On the flat environment, the full unfused block attains
  --  R + 2n + 6 = 10, versus the old 6·2 + 9 = 21 estimate.
  _ : maxL (runLevels (0 ∷ 0 ∷ 0 ∷ 0 ∷ 0 ∷ [])
              (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                              (true ∷ false ∷ []) 0 4 5)))) ≡ 10
  _ = refl
  block-flat : maxL (runLevels (0 ∷ 0 ∷ 0 ∷ 0 ∷ 0 ∷ [])
                      (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                      (true ∷ false ∷ []) 0 4 5)))) ≤ 10
  block-flat = lockedBlock-tight (0 ∷ 0 ∷ 0 ∷ 0 ∷ 0 ∷ []) (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                 (true ∷ false ∷ []) 0 4 0 5 refl
                 (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ [])
                 (s≤s (s≤s (s≤s z≤n)) ∷ s≤s (s≤s (s≤s (s≤s z≤n))) ∷ [])
                 (z≤n ∷ z≤n ∷ []) (z≤n ∷ z≤n ∷ [])

------------------------------------------------------------------------
--  Use the level-40 host with the weaker requirement
--  R + 2n + 4 = 8 ≤ 40 instead of R + 6n + 9 = 21 ≤ 40.

private
  lv2 : List ℕ
  lv2 = 0 ∷ 0 ∷ 0 ∷ 0 ∷ 40 ∷ []
  lv3 : List ℕ
  lv3 = 0 ∷ 0 ∷ 0 ∷ 0 ∷ 0 ∷ 0 ∷ 40 ∷ []

  inputs2 : (i : ℕ) → i < 4 → getL lv2 i ≤ 0
  inputs2 zero                            _ = z≤n
  inputs2 (suc zero)                      _ = z≤n
  inputs2 (suc (suc zero))                _ = z≤n
  inputs2 (suc (suc (suc zero)))          _ = z≤n
  inputs2 (suc (suc (suc (suc i)))) (s≤s (s≤s (s≤s (s≤s ()))))

  inputs3 : (i : ℕ) → i < 6 → getL lv3 i ≤ 0
  inputs3 zero                                        _ = z≤n
  inputs3 (suc zero)                                  _ = z≤n
  inputs3 (suc (suc zero))                            _ = z≤n
  inputs3 (suc (suc (suc zero)))                      _ = z≤n
  inputs3 (suc (suc (suc (suc zero))))                _ = z≤n
  inputs3 (suc (suc (suc (suc (suc zero)))))          _ = z≤n
  inputs3 (suc (suc (suc (suc (suc (suc i)))))) (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s ()))))))

  --  Recover unfused depth 42 from the new 8 ≤ 40 premise.
  unfused2-tight : maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                                       (true ∷ false ∷ []) 0 4 5)))) ≤ 42
  unfused2-tight =
    lockedBlock-depth-adds-2-tight lv2 (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) (true ∷ false ∷ []) 0 4 4 0
      (s≤s (s≤s (s≤s (s≤s z≤n)))) ≤-refl inputs2
      (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ [])
      (s≤s (s≤s (s≤s z≤n)) ∷ s≤s (s≤s (s≤s (s≤s z≤n))) ∷ [])
      (m≤n+m 8 32)

  unfused3-tight : maxL (runLevels lv3 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
                                                       (true ∷ false ∷ true ∷ []) 0 6 7)))) ≤ 42
  unfused3-tight =
    lockedBlock-depth-adds-2-tight lv3 (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
      (true ∷ false ∷ true ∷ []) 0 6 6 0
      (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n)))))) ≤-refl inputs3
      (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ s≤s (s≤s (s≤s z≤n)) ∷ [])
      (s≤s (s≤s (s≤s (s≤s z≤n))) ∷ s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))
        ∷ s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))) ∷ [])
      (m≤n+m 10 30)

  --  Obtain fused depths 46 and 48 exactly. The two-bit
  --  NetDepthMerged bracket was 45 ≤ depth ≤ 56; the new
  --  equation has no slack.
  fused2-exact : maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlockMerged (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                                      (true ∷ false ∷ []) 4 5)))) ≡ 46
  fused2-exact =
    lockedBlockMerged-depth-exact lv2 (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) (true ∷ false ∷ []) 4 0
      ≤-refl (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ [])
      (s≤s (s≤s (s≤s z≤n)) ∷ s≤s (s≤s (s≤s (s≤s z≤n))) ∷ [])
      (z≤n ∷ z≤n ∷ []) (z≤n ∷ z≤n ∷ [])
      (s≤s z≤n ∷ s≤s z≤n ∷ []) ≤-refl (m≤n+m 8 37)

  fused3-exact : maxL (runLevels lv3 (proj₂ (proj₂ (lockedBlockMerged (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
                                                      (true ∷ false ∷ true ∷ []) 6 7)))) ≡ 48
  fused3-exact =
    lockedBlockMerged-depth-exact lv3 (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
      (true ∷ false ∷ true ∷ []) 6 0
      ≤-refl (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ s≤s (s≤s (s≤s z≤n)) ∷ [])
      (s≤s (s≤s (s≤s (s≤s z≤n))) ∷ s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))
        ∷ s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))) ∷ [])
      (z≤n ∷ z≤n ∷ z≤n ∷ []) (z≤n ∷ z≤n ∷ z≤n ∷ [])
      (s≤s z≤n ∷ s≤s z≤n ∷ s≤s z≤n ∷ []) ≤-refl (m≤n+m 10 37)
