------------------------------------------------------------------------
--  Account for the structural depth of cube fusion. Earlier
--  unfused bounds give host depth + 6n + 9. LockedNetMerged
--  removes cube constants using f (+) (l & L) = if l then
--  f (+) L else f, but needs its own depth analysis: one
--  MUX per literal is stacked on the host output, whereas
--  the unfused cube cone runs alongside the host. Provide
--  both directions. mux-level-spec computes the four-gate
--  MUX output exactly, refining mux-bound's uniform three-level
--  charge to expose two levels above data input b.
--  fuseXorCube-out-level gives exactly 2|lits| + 1 above
--  the host wire when all literals are no deeper.
--  fuseXorCube-<=, cubeLits-bound, lockedBlockMerged-bound,
--  and lockHostBlockMerged-bound provide upper bounds, the
--  last matching the unfused theorem's shape and premises
--  with +5n+6 instead of +6n+9 because fusion emits one
--  comparator cone. lockedBlockMerged-depth-lower and its
--  host form locate a cost of at least 2n + 1 above the
--  host output under their premises. This lower bound
--  separates emitters despite fusion's smaller coarse upper
--  bound. Results concern the emitted operation list's
--  structural longest path, netDepth = maxL after runLevels.
--  No theorem relates this to post-mapping depth after
--  resynthesis, nor bounds total gate counts. The separate
--  lockedBlockMerged-constCount result counts two constants
--  versus |ksec| + 4. Scope is h = 0. §7 computes unfused
--  depth 42 for two- and three-bit cubes over a level-40
--  host, compared with fused 46 and 48. NetDepthHost
--  generalises that host independence and the strict
--  separation for n ≥ 1. Use --safe --without-K, with no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthMerged where

open import Data.Bool using (Bool; true; false)
open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _⊔_; _≤_; _<_; s≤s; z≤n)
open import Data.Nat.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; ≤-antisym; m≤m⊔n; m≤n⊔m; ⊔-mono-≤;
         m≤n⇒m⊔n≡n; m≥n⇒m⊔n≡m; +-identityʳ; +-comm; +-suc; n≤1+n; +-mono-≤;
         *-monoʳ-≤; m≤m+n; suc-injective)
open import Data.List using (List; []; _∷_; _++_; length; replicate)
open import Data.List.Properties using (++-identityʳ; length-replicate)
open import Data.Fin using (Fin; zero; toℕ)
open import Data.Vec using (Vec; lookup) renaming (replicate to vreplicate)
open import Data.Vec.Properties using (lookup-replicate)
open import Data.List.Relation.Unary.All as All using (All; []; _∷_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Unit using (tt)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; cong; cong₂; trans; subst)

open import Extraction.NetDepthBuilder using (cnt-mono)
open import Extraction.LockedNetMerged using (cubeLits-cnt)
open import Extraction.Netlist using
  (Op; oNot; oAnd; oOr; oXor; Builder; mkMux; get; runNet; upFrom)
open import Extraction.NetlistCorrect using (runNet-length)
open import Locking.NetlistToCircuit using (Netlist)
open import Extraction.HostNetlist using
  (netlistWires; netlistWires-cnt; netlistWires-correct)
open import Extraction.LockHostMerged using (lockHostBlockMerged)
open import Extraction.NetDepth using
  (getL; maxL; opLevel; runLevels; runLevels-++; getL-≤-maxL; ⊔-lub; maxL-snoc)
open import Extraction.NetDepthBlock using
  (getL-++-prefix; length-snoc; runLevels-stable; AllRefs<; runLevels-parallel)
open import Extraction.NetDepthMux using (muxOps; getL-snoc-last)
open import Extraction.NetDepthComp using (runLevels-len)
open import Extraction.NetDepthFold using (run-len-state)
open import Extraction.LockedNet using (restoreNet; xorPairs; lockedBlock)
open import Extraction.NetDepthPop using (restoreNet-bound; xorPairs-len≤; snocXor≤)
open import Extraction.LockedNetMerged using (fuseXorCube; fuseXorCube-cnt; fuseXorCube-out<; cubeLits; lockedBlockMerged)

open import Data.Nat.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:+_; _:*_; con; _:=_)

private
  --  Charge exactly two additional levels for each cube literal.
  arith2 : (m k : ℕ) → suc (suc (m + 2 * k)) ≡ m + 2 * suc k
  arith2 = solve 2 (λ m k → con 2 :+ (m :+ con 2 :* k) := m :+ con 2 :* (con 1 :+ k)) refl

  --  Sum the literal, fusion-chain, restore-cone, and output-XOR stages.
  arithBlock : (m l x : ℕ) →
    suc (suc (suc (suc m) + 2 * l) + 3 * x + 2) ≡ m + 2 * l + 3 * x + 6
  arithBlock = solve 3 (λ m l x →
    con 1 :+ ((con 1 :+ ((con 2 :+ m) :+ con 2 :* l)) :+ con 3 :* x :+ con 2)
      := m :+ con 2 :* l :+ con 3 :* x :+ con 6) refl

  arithCoarse : (m x : ℕ) → m + 2 * x + 3 * x + 6 ≡ m + 5 * x + 6
  arithCoarse = solve 2 (λ m x →
    m :+ con 2 :* x :+ con 3 :* x :+ con 6 := m :+ con 5 :* x :+ con 6) refl

------------------------------------------------------------------------
--  §0 Use runLevels' nondecreasing depth and imported stability
--  of previously allocated wire levels throughout.

maxL-mono : (lv : List ℕ) (ops : List Op) → maxL lv ≤ maxL (runLevels lv ops)
maxL-mono lv []         = ≤-refl
maxL-mono lv (op ∷ ops) =
  ≤-trans (≤-trans (m≤m⊔n (maxL lv) (opLevel lv op))
                   (≤-reflexive (sym (maxL-snoc lv (opLevel lv op)))))
          (maxL-mono (lv ++ (opLevel lv op ∷ [])) ops)

------------------------------------------------------------------------
--  §1 Compute the MUX's output level from all three input levels.
--  mux-bound's M+3 estimate suffices for comparator step wires,
--  but the fused chain needs the two-level path b → oAnd b s
--  → oOr. Account explicitly for the select and other data
--  paths through the closed muxLvl expression.

muxLvl : (lv : List ℕ) (s a b : ℕ) → ℕ
muxLvl lv s a b =
  suc (suc ((getL lv a ⊔ suc (getL lv s)) ⊔ (getL lv b ⊔ getL lv s)))

--  Identify the output level with muxLvl and the new running
--  maximum with its join, since all three internal levels are dominated.
mux-level-spec :
  (lv : List ℕ) (s a b : ℕ) → s < length lv → a < length lv → b < length lv →
  (getL (runLevels lv (muxOps s a b (length lv))) (suc (suc (suc (length lv))))
     ≡ muxLvl lv s a b)
  × (maxL (runLevels lv (muxOps s a b (length lv))) ≡ maxL lv ⊔ muxLvl lv s a b)
mux-level-spec lv s a b s< a< b< = outEq , maxEq
  where
    i  = length lv
    L1 = opLevel lv (oNot s)
    e1 = lv ++ (L1 ∷ [])
    L2 = opLevel e1 (oAnd a i)
    e2 = e1 ++ (L2 ∷ [])
    L3 = opLevel e2 (oAnd b s)
    e3 = e2 ++ (L3 ∷ [])
    L4 = opLevel e3 (oOr (suc i) (suc (suc i)))
    e4 = e3 ++ (L4 ∷ [])

    le1 : length e1 ≡ suc i
    le1 = length-snoc lv L1
    le2 : length e2 ≡ suc (suc i)
    le2 = trans (length-snoc e1 L2) (cong suc le1)
    le3 : length e3 ≡ suc (suc (suc i))
    le3 = trans (length-snoc e2 L3) (cong suc le2)

    s<e1 : s < length e1
    s<e1 = ≤-trans s< (≤-trans (n≤1+n i) (≤-reflexive (sym le1)))
    b<e1 : b < length e1
    b<e1 = ≤-trans b< (≤-trans (n≤1+n i) (≤-reflexive (sym le1)))

    --  Express all four gate levels in the initial environment.
    L2≡ : L2 ≡ suc (getL lv a ⊔ L1)
    L2≡ = cong suc (cong₂ _⊔_ (getL-++-prefix lv (L1 ∷ []) a a<)
                              (getL-snoc-last lv L1))
    L3≡ : L3 ≡ suc (getL lv b ⊔ getL lv s)
    L3≡ = cong suc (cong₂ _⊔_
            (trans (getL-++-prefix e1 (L2 ∷ []) b b<e1)
                   (getL-++-prefix lv (L1 ∷ []) b b<))
            (trans (getL-++-prefix e1 (L2 ∷ []) s s<e1)
                   (getL-++-prefix lv (L1 ∷ []) s s<)))
    L4≡ : L4 ≡ suc (L2 ⊔ L3)
    L4≡ = cong suc (cong₂ _⊔_ g-si g-ssi)
      where
        g-si : getL e3 (suc i) ≡ L2
        g-si = trans (getL-++-prefix e2 (L3 ∷ []) (suc i) (≤-reflexive (sym le2)))
                     (trans (cong (getL e2) (sym le1)) (getL-snoc-last e1 L2))
        g-ssi : getL e3 (suc (suc i)) ≡ L3
        g-ssi = trans (cong (getL e3) (sym le2)) (getL-snoc-last e2 L3)

    L4≡mux : L4 ≡ muxLvl lv s a b
    L4≡mux = trans L4≡ (cong suc (cong₂ _⊔_ L2≡ L3≡))

    outEq : getL e4 (suc (suc (suc i))) ≡ muxLvl lv s a b
    outEq = trans (trans (cong (getL e4) (sym le3)) (getL-snoc-last e3 L4)) L4≡mux

    --  Bound each internal wire by the output level.
    L1≤L2 : L1 ≤ L2
    L1≤L2 = ≤-trans (m≤n⊔m (getL lv a) L1)
                    (≤-trans (n≤1+n (getL lv a ⊔ L1)) (≤-reflexive (sym L2≡)))
    L2≤L4 : L2 ≤ L4
    L2≤L4 = ≤-trans (m≤m⊔n L2 L3) (≤-trans (n≤1+n (L2 ⊔ L3)) (≤-reflexive (sym L4≡)))
    L3≤L4 : L3 ≤ L4
    L3≤L4 = ≤-trans (m≤n⊔m L2 L3) (≤-trans (n≤1+n (L2 ⊔ L3)) (≤-reflexive (sym L4≡)))

    maxEq : maxL e4 ≡ maxL lv ⊔ muxLvl lv s a b
    maxEq = ≤-antisym up down
      where
        M4 = maxL lv ⊔ muxLvl lv s a b
        L4≤M4 : L4 ≤ M4
        L4≤M4 = ≤-trans (≤-reflexive L4≡mux) (m≤n⊔m (maxL lv) (muxLvl lv s a b))
        expand : maxL e4 ≡ (((maxL lv ⊔ L1) ⊔ L2) ⊔ L3) ⊔ L4
        expand = trans (maxL-snoc e3 L4)
                 (cong (_⊔ L4) (trans (maxL-snoc e2 L3)
                 (cong (_⊔ L3) (trans (maxL-snoc e1 L2)
                 (cong (_⊔ L2) (maxL-snoc lv L1))))))
        up : maxL e4 ≤ M4
        up = ≤-trans (≤-reflexive expand)
               (⊔-lub (⊔-lub (⊔-lub (⊔-lub (m≤m⊔n (maxL lv) (muxLvl lv s a b))
                                           (≤-trans L1≤L2 (≤-trans L2≤L4 L4≤M4)))
                                    (≤-trans L2≤L4 L4≤M4))
                             (≤-trans L3≤L4 L4≤M4))
                      L4≤M4)
        down : M4 ≤ maxL e4
        down = ⊔-lub (maxL-mono lv (muxOps s a b i))
                     (≤-trans (≤-reflexive (sym L4≡mux))
                              (≤-trans (≤-reflexive (sym (trans (cong (getL e4) (sym le3))
                                                                (getL-snoc-last e3 L4))))
                                       (getL-≤-maxL e4 (suc (suc (suc i))))))

------------------------------------------------------------------------
--  §2 Describe the serial fused perturb chain. fuseXorCube
--  starts with an inverter over f and stacks one MUX per
--  literal on its predecessor. Its 2·|lits| + 1 host-relative
--  levels are the structural cost of avoiding an explicit cube.

private
  lenMono : (lv : List ℕ) (ops : List Op) → length lv ≤ length (runLevels lv ops)
  lenMono lv ops = ≤-trans (m≤m+n (length lv) (length ops))
                           (≤-reflexive (sym (runLevels-len lv ops)))

  All-≤ : {P Q : ℕ → Set} (zs : List ℕ) → ({z : ℕ} → P z → Q z) → All P zs → All Q zs
  All-≤ []       _ []        = []
  All-≤ (z ∷ zs) h (pz ∷ ps) = h pz ∷ All-≤ zs h ps

--  Under literal levels no greater than f, obtain the exact
--  chain output level getL lv f + 2·|lits| + 1.
fuseXorCube-out-level :
  (lv : List ℕ) (f : ℕ) (lits : List ℕ) →
  f < length lv → All (_< length lv) lits →
  All (λ l → getL lv l ≤ getL lv f) lits →
  getL (runLevels lv (proj₂ (proj₂ (fuseXorCube f lits (length lv)))))
       (proj₁ (fuseXorCube f lits (length lv)))
    ≡ suc (getL lv f) + 2 * length lits
fuseXorCube-out-level lv f []       f< _ _ =
  trans (getL-snoc-last lv (suc (getL lv f))) (sym (+-identityʳ (suc (getL lv f))))
fuseXorCube-out-level lv f (l ∷ ls) f< (l< ∷ ls<) (lF ∷ lsF) =
  trans (cong (λ e → getL e (suc (suc (suc iC)))) runEq) (trans qIC muxSimp)
  where
    L      = length lv
    recR   = fuseXorCube f ls L
    g      = proj₁ recR
    iC     = proj₁ (proj₂ recR)
    recOps = proj₂ (proj₂ recR)
    envG   = runLevels lv recOps

    F = getL lv f
    S = getL lv l
    P = suc F + 2 * length ls

    lenG : iC ≡ length envG
    lenG = run-len-state (fuseXorCube f ls) (fuseXorCube-cnt f ls) lv

    f<G : f < length envG
    f<G = ≤-trans f< (lenMono lv recOps)
    l<G : l < length envG
    l<G = ≤-trans l< (lenMono lv recOps)
    g<G : g < length envG
    g<G = subst (g <_) lenG (fuseXorCube-out< f ls L)

    fG : getL envG f ≡ F
    fG = runLevels-stable lv recOps f f<
    lG : getL envG l ≡ S
    lG = runLevels-stable lv recOps l l<
    gG : getL envG g ≡ P
    gG = fuseXorCube-out-level lv f ls f< ls< lsF

    Q : ℕ → Set
    Q s = getL (runLevels envG (proj₂ (proj₂ (mkMux l f g s))))
               (proj₁ (mkMux l f g s))
            ≡ muxLvl envG l f g
    qIC : Q iC
    qIC = subst Q (sym lenG) (proj₁ (mux-level-spec envG l f g l<G f<G g<G))

    runEq : runLevels lv (recOps ++ proj₂ (proj₂ (mkMux l f g iC)))
              ≡ runLevels envG (proj₂ (proj₂ (mkMux l f g iC)))
    runEq = runLevels-++ lv recOps (proj₂ (proj₂ (mkMux l f g iC)))

    S≤P : S ≤ P
    S≤P = ≤-trans lF (≤-trans (n≤1+n F) (m≤m+n (suc F) (2 * length ls)))
    sel≤P : (F ⊔ suc S) ≤ P
    sel≤P = ≤-trans (⊔-lub (n≤1+n F) (s≤s lF)) (m≤m+n (suc F) (2 * length ls))

    muxSimp : muxLvl envG l f g ≡ suc (getL lv f) + 2 * length (l ∷ ls)
    muxSimp =
      trans (cong (λ z → suc (suc z))
                  (trans (cong₂ _⊔_ (cong₂ _⊔_ fG (cong suc lG))
                                    (cong₂ _⊔_ gG lG))
                         (trans (cong ((F ⊔ suc S) ⊔_) (m≥n⇒m⊔n≡m S≤P))
                                (m≤n⇒m⊔n≡n sel≤P))))
            (arith2 (suc F) (length ls))

--  Without ordering premises, bound a chain whose inputs are
--  at most R by R + 2·|lits| + 1, joined with the inherited
--  maximum for whole-block depth.
fuseXorCube-≤ :
  (lv : List ℕ) (f : ℕ) (lits : List ℕ) (R : ℕ) →
  f < length lv → All (_< length lv) lits →
  getL lv f ≤ R → All (λ l → getL lv l ≤ R) lits →
  (getL (runLevels lv (proj₂ (proj₂ (fuseXorCube f lits (length lv)))))
        (proj₁ (fuseXorCube f lits (length lv)))
     ≤ suc R + 2 * length lits)
  × (maxL (runLevels lv (proj₂ (proj₂ (fuseXorCube f lits (length lv)))))
     ≤ maxL lv ⊔ (suc R + 2 * length lits))
fuseXorCube-≤ lv f []       R f< _ fR _ =
    ≤-trans (≤-reflexive (getL-snoc-last lv (suc (getL lv f))))
            (≤-trans (s≤s fR) (≤-reflexive (sym (+-identityʳ (suc R)))))
  , ≤-trans (≤-reflexive (maxL-snoc lv (suc (getL lv f))))
            (⊔-mono-≤ ≤-refl (≤-trans (s≤s fR) (≤-reflexive (sym (+-identityʳ (suc R))))))
fuseXorCube-≤ lv f (l ∷ ls) R f< (l< ∷ ls<) fR (lR ∷ lsR) = outB , maxB
  where
    L      = length lv
    recR   = fuseXorCube f ls L
    g      = proj₁ recR
    iC     = proj₁ (proj₂ recR)
    recOps = proj₂ (proj₂ recR)
    envG   = runLevels lv recOps

    P  = suc R + 2 * length ls
    P' = suc R + 2 * length (l ∷ ls)

    lenG : iC ≡ length envG
    lenG = run-len-state (fuseXorCube f ls) (fuseXorCube-cnt f ls) lv

    f<G : f < length envG
    f<G = ≤-trans f< (lenMono lv recOps)
    l<G : l < length envG
    l<G = ≤-trans l< (lenMono lv recOps)
    g<G : g < length envG
    g<G = subst (g <_) lenG (fuseXorCube-out< f ls L)

    IH = fuseXorCube-≤ lv f ls R f< ls< fR lsR

    fG≤ : getL envG f ≤ R
    fG≤ = ≤-trans (≤-reflexive (runLevels-stable lv recOps f f<)) fR
    lG≤ : getL envG l ≤ R
    lG≤ = ≤-trans (≤-reflexive (runLevels-stable lv recOps l l<)) lR
    gG≤ : getL envG g ≤ P
    gG≤ = proj₁ IH

    P≤P' : P ≤ P'
    P≤P' = +-mono-≤ (≤-refl {suc R}) (*-monoʳ-≤ 2 (n≤1+n (length ls)))

    --  Bound the MUX output by two levels above its chain predecessor.
    mux≤ : muxLvl envG l f g ≤ P'
    mux≤ = ≤-trans (s≤s (s≤s (⊔-lub (⊔-lub (≤-trans fG≤ (≤-trans (n≤1+n R) (m≤m+n (suc R) (2 * length ls))))
                                           (≤-trans (s≤s lG≤) (m≤m+n (suc R) (2 * length ls))))
                                    (⊔-lub gG≤ (≤-trans lG≤ (≤-trans (n≤1+n R) (m≤m+n (suc R) (2 * length ls))))))))
                   (≤-reflexive (arith2 (suc R) (length ls)))

    QO : ℕ → Set
    QO s = getL (runLevels envG (proj₂ (proj₂ (mkMux l f g s))))
                (proj₁ (mkMux l f g s))
             ≡ muxLvl envG l f g
    QM : ℕ → Set
    QM s = maxL (runLevels envG (proj₂ (proj₂ (mkMux l f g s))))
             ≡ maxL envG ⊔ muxLvl envG l f g
    spec = mux-level-spec envG l f g l<G f<G g<G
    qO : QO iC
    qO = subst QO (sym lenG) (proj₁ spec)
    qM : QM iC
    qM = subst QM (sym lenG) (proj₂ spec)

    runEq : runLevels lv (recOps ++ proj₂ (proj₂ (mkMux l f g iC)))
              ≡ runLevels envG (proj₂ (proj₂ (mkMux l f g iC)))
    runEq = runLevels-++ lv recOps (proj₂ (proj₂ (mkMux l f g iC)))

    outB : getL (runLevels lv (recOps ++ proj₂ (proj₂ (mkMux l f g iC))))
                (suc (suc (suc iC)))
             ≤ P'
    outB = ≤-trans (≤-reflexive (trans (cong (λ e → getL e (suc (suc (suc iC)))) runEq) qO)) mux≤

    maxB : maxL (runLevels lv (recOps ++ proj₂ (proj₂ (mkMux l f g iC)))) ≤ maxL lv ⊔ P'
    maxB = ≤-trans (≤-reflexive (trans (cong maxL runEq) qM))
                   (⊔-lub (≤-trans (proj₂ IH)
                                   (⊔-lub (m≤m⊔n (maxL lv) P') (≤-trans P≤P' (m≤n⊔m (maxL lv) P'))))
                          (≤-trans mux≤ (m≤n⊔m (maxL lv) P')))

------------------------------------------------------------------------
--  §3 Treat cubeLits as a parallel layer: a true cube bit
--  reuses its data wire, while false adds one inverter.
--  Every literal is therefore at most one level above its source.

private
  All<-weaken : {a b : ℕ} (zs : List ℕ) → a ≤ b → All (_< a) zs → All (_< b) zs
  All<-weaken values bound = All.map (λ proof → ≤-trans proof bound)

--  Bound literal-list length by data-list length, with equality
--  when the cube supplies one bit per data wire.
cubeLits-len≤ : (xs : List ℕ) (bits : List Bool) (i : ℕ) →
                length (proj₁ (cubeLits xs bits i)) ≤ length xs
cubeLits-len≤ []       bits         i = z≤n
cubeLits-len≤ (x ∷ xs) []           i = z≤n
cubeLits-len≤ (x ∷ xs) (true  ∷ bs) i = s≤s (cubeLits-len≤ xs bs i)
cubeLits-len≤ (x ∷ xs) (false ∷ bs) i = s≤s (cubeLits-len≤ xs bs (suc i))

cubeLits-len : (xs : List ℕ) (bits : List Bool) (i : ℕ) → length xs ≡ length bits →
               length (proj₁ (cubeLits xs bits i)) ≡ length xs
cubeLits-len []       []           i _  = refl
cubeLits-len (x ∷ xs) (true  ∷ bs) i eq = cong suc (cubeLits-len xs bs i (suc-injective eq))
cubeLits-len (x ∷ xs) (false ∷ bs) i eq = cong suc (cubeLits-len xs bs (suc i) (suc-injective eq))

cubeLits-mono : (xs : List ℕ) (bits : List Bool) (i : ℕ) →
                i ≤ proj₁ (proj₂ (cubeLits xs bits i))
cubeLits-mono wires bits start = cnt-mono (cubeLits wires bits) (cubeLits-cnt wires bits) start

cubeLits-outs< : (xs : List ℕ) (bits : List Bool) (i : ℕ) → All (_< i) xs →
                 All (_< proj₁ (proj₂ (cubeLits xs bits i))) (proj₁ (cubeLits xs bits i))
cubeLits-outs< []       bits         i _         = []
cubeLits-outs< (x ∷ xs) []           i _         = []
cubeLits-outs< (x ∷ xs) (true  ∷ bs) i (px ∷ ps) =
  ≤-trans px (cubeLits-mono xs bs i) ∷ cubeLits-outs< xs bs i ps
cubeLits-outs< (x ∷ xs) (false ∷ bs) i (px ∷ ps) =
  cubeLits-mono xs bs (suc i)
    ∷ cubeLits-outs< xs bs (suc i) (All<-weaken xs (n≤1+n i) ps)

--  Show all emitted literal gates read data wires, establishing parallelism.
cubeLits-AllRefs : (L : ℕ) (xs : List ℕ) (bits : List Bool) (i : ℕ) →
                   All (_< L) xs → AllRefs< L (proj₂ (proj₂ (cubeLits xs bits i)))
cubeLits-AllRefs L []       bits         i _         = tt
cubeLits-AllRefs L (x ∷ xs) []           i _         = tt
cubeLits-AllRefs L (x ∷ xs) (true  ∷ bs) i (_ ∷ ps)  =
  subst (AllRefs< L) (sym (++-identityʳ (proj₂ (proj₂ (cubeLits xs bs i)))))
        (cubeLits-AllRefs L xs bs i ps)
cubeLits-AllRefs L (x ∷ xs) (false ∷ bs) i (px ∷ ps) =
  px , subst (AllRefs< L) (sym (++-identityʳ (proj₂ (proj₂ (cubeLits xs bs (suc i))))))
             (cubeLits-AllRefs L xs bs (suc i) ps)

--  Bound literal-layer overhead by one level for every cube.
cubeLits-bound : (lv : List ℕ) (xs : List ℕ) (bits : List Bool) →
  All (_< length lv) xs →
  maxL (runLevels lv (proj₂ (proj₂ (cubeLits xs bits (length lv))))) ≤ suc (maxL lv)
cubeLits-bound lv xs bits xsv =
  runLevels-parallel lv (proj₂ (proj₂ (cubeLits xs bits (length lv)))) (length lv) ≤-refl
    (cubeLits-AllRefs (length lv) xs bits (length lv) xsv)

--  If data wires lie at least one level below d, all their
--  literals lie at most at d.
cubeLits-levels : (lv : List ℕ) (xs : List ℕ) (bits : List Bool) (d : ℕ) →
  All (_< length lv) xs → All (λ x → suc (getL lv x) ≤ d) xs →
  All (λ w → getL (runLevels lv (proj₂ (proj₂ (cubeLits xs bits (length lv))))) w ≤ d)
      (proj₁ (cubeLits xs bits (length lv)))
cubeLits-levels lv []       bits         d _         _         = []
cubeLits-levels lv (x ∷ xs) []           d _         _         = []
cubeLits-levels lv (x ∷ xs) (true  ∷ bs) d (px ∷ ps) (hx ∷ hs) =
  subst (λ e → All (λ w → getL e w ≤ d) (x ∷ ws)) (sym eqE) (headOK ∷ IH)
  where
    recOps = proj₂ (proj₂ (cubeLits xs bs (length lv)))
    ws     = proj₁ (cubeLits xs bs (length lv))
    E0     = runLevels lv recOps
    eqE : runLevels lv (recOps ++ []) ≡ E0
    eqE = cong (runLevels lv) (++-identityʳ recOps)
    headOK : getL E0 x ≤ d
    headOK = ≤-trans (≤-reflexive (runLevels-stable lv recOps x px))
                     (≤-trans (n≤1+n (getL lv x)) hx)
    IH : All (λ w → getL E0 w ≤ d) ws
    IH = cubeLits-levels lv xs bs d ps hs
cubeLits-levels lv (x ∷ xs) (false ∷ bs) d (px ∷ ps) (hx ∷ hs) =
  subst (λ e → All (λ w → getL e w ≤ d) (length lv ∷ ws')) (sym eqE) (headOK ∷ IH)
  where
    i    = length lv
    lv1  = lv ++ (suc (getL lv x) ∷ [])
    ll1 : length lv1 ≡ suc i
    ll1 = length-snoc lv (suc (getL lv x))
    ws'    = proj₁ (cubeLits xs bs (suc i))
    recOps = proj₂ (proj₂ (cubeLits xs bs (suc i)))
    E0     = runLevels lv1 recOps
    eqE : runLevels lv1 (recOps ++ []) ≡ E0
    eqE = cong (runLevels lv1) (++-identityʳ recOps)

    i<lv1 : i < length lv1
    i<lv1 = ≤-reflexive (sym ll1)
    headOK : getL E0 i ≤ d
    headOK = ≤-trans (≤-reflexive (trans (runLevels-stable lv1 recOps i i<lv1)
                                         (getL-snoc-last lv (suc (getL lv x)))))
                     hx

    ps1 : All (_< length lv1) xs
    ps1 = All<-weaken xs (≤-trans (n≤1+n i) (≤-reflexive (sym ll1))) ps
    hs1 : All (λ z → suc (getL lv1 z) ≤ d) xs
    hs1 = go xs ps hs
      where
        go : (zs : List ℕ) → All (_< length lv) zs → All (λ z → suc (getL lv z) ≤ d) zs →
             All (λ z → suc (getL lv1 z) ≤ d) zs
        go []       _           _           = []
        go (z ∷ zs) (pz ∷ pzs)  (hz ∷ hzs)  =
          ≤-trans (≤-reflexive (cong suc (getL-++-prefix lv (suc (getL lv x) ∷ []) z pz))) hz
            ∷ go zs pzs hzs

    Pst : ℕ → Set
    Pst s = All (λ w → getL (runLevels lv1 (proj₂ (proj₂ (cubeLits xs bs s)))) w ≤ d)
                (proj₁ (cubeLits xs bs s))
    IH : Pst (suc i)
    IH = subst Pst ll1 (cubeLits-levels lv1 xs bs d ps1 hs1)

------------------------------------------------------------------------
--  §4 Compose the fused block's four stages: parallel literals
--  (+1), serial fusion (+2 per literal), one restore cone
--  instead of two, and the final XOR.

private
  allGetL≤ : (e : List ℕ) (zs : List ℕ) → All (λ z → getL e z ≤ maxL e) zs
  allGetL≤ e []       = []
  allGetL≤ e (z ∷ zs) = getL-≤-maxL e z ∷ allGetL≤ e zs

--  Provide the depth companion to lockedBlockMerged-locked:
--  at most 5|xs| + 6 added levels, compared with the unfused
--  6|xs| + 9 bound containing a second comparator cone.
lockedBlockMerged-bound :
  (lv xs keys : List ℕ) (ksec : List Bool) (fWire : ℕ) →
  fWire < length lv → All (_< length lv) xs → All (_< length lv) keys →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlockMerged xs keys ksec fWire (length lv)))))
    ≤ maxL lv + 5 * length xs + 6
lockedBlockMerged-bound lv xs keys ksec fWire fW< xsv keysv =
  ≤-trans (≤-reflexive (cong maxL split-all)) chain
  where
    cR   = cubeLits xs ksec (length lv)
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

    split-all :
      runLevels lv (proj₂ (proj₂ (lockedBlockMerged xs keys ksec fWire (length lv))))
        ≡ runLevels e-r (oXor t rW ∷ [])
    split-all = trans (runLevels-++ lv cOps (fOps ++ (rOps ++ (oXor t rW ∷ []))))
                (trans (runLevels-++ e-c fOps (rOps ++ (oXor t rW ∷ [])))
                       (runLevels-++ e-f rOps (oXor t rW ∷ [])))

    lv≤c : length lv ≤ length e-c
    lv≤c = lenMono lv cOps
    c≤f : length e-c ≤ length e-f
    c≤f = lenMono e-c fOps
    iC≡ : iC ≡ length e-c
    iC≡ = run-len-state (cubeLits xs ksec) (cubeLits-cnt xs ksec) lv
    iF≡ : iF ≡ length e-f
    iF≡ = trans (fuseXorCube-cnt fWire lits iC)
                (trans (cong (_+ length fOps) iC≡) (sym (runLevels-len e-c fOps)))

    --  Stage one: construct the literal layer.
    b-c : maxL e-c ≤ suc (maxL lv)
    b-c = cubeLits-bound lv xs ksec xsv

    --  Stage two: add two fusion-chain levels per literal.
    litsRange : All (_< length e-c) lits
    litsRange = All<-weaken lits (≤-reflexive iC≡) (cubeLits-outs< xs ksec (length lv) xsv)

    b-f : maxL e-f ≤ suc (suc (maxL lv)) + 2 * length lits
    b-f = ≤-trans (≤-reflexive (cong (λ s → maxL (runLevels e-c (proj₂ (proj₂ (fuseXorCube fWire lits s))))) iC≡))
            (≤-trans (proj₂ (fuseXorCube-≤ e-c fWire lits (maxL e-c)
                               (≤-trans fW< lv≤c) litsRange
                               (getL-≤-maxL e-c fWire) (allGetL≤ e-c lits)))
                     (≤-trans (⊔-lub (≤-trans (n≤1+n (maxL e-c))
                                              (m≤m+n (suc (maxL e-c)) (2 * length lits)))
                                     ≤-refl)
                              (+-mono-≤ (s≤s b-c) (≤-refl {2 * length lits}))))

    --  Stage three: build the single restore cone.
    b-r : maxL e-r ≤ suc (suc (suc (maxL lv)) + 2 * length lits) + 3 * length xs + 2
    b-r = ≤-trans (≤-reflexive (cong (λ s → maxL (runLevels e-f (proj₂ (proj₂ (restoreNet xs keys 0 s))))) iF≡))
            (≤-trans (restoreNet-bound e-f xs keys 0
                        (All<-weaken xs (≤-trans lv≤c c≤f) xsv)
                        (All<-weaken keys (≤-trans lv≤c c≤f) keysv))
                     (+-mono-≤ (+-mono-≤ (s≤s b-f)
                                         (*-monoʳ-≤ 3 (xorPairs-len≤ xs keys (length e-f))))
                               (≤-refl {2})))

    --  Stage four: add the output XOR and use |lits| ≤ |xs|
    --  to obtain the coarse bound.
    chain : maxL (runLevels e-r (oXor t rW ∷ [])) ≤ maxL lv + 5 * length xs + 6
    chain = ≤-trans (snocXor≤ e-r t rW)
              (≤-trans (s≤s b-r)
                (≤-trans (≤-reflexive (arithBlock (maxL lv) (length lits) (length xs)))
                  (≤-trans (+-mono-≤ (+-mono-≤ (+-mono-≤ (≤-refl {maxL lv})
                                                         (*-monoʳ-≤ 2 (cubeLits-len≤ xs ksec (length lv))))
                                               (≤-refl {3 * length xs}))
                                     (≤-refl {6}))
                           (≤-reflexive (arithCoarse (maxL lv) (length xs))))))

------------------------------------------------------------------------
--  §5 Locate the depth cost with a lower bound. Coarse
--  environment-wide upper bounds alone cannot separate emitters.
--  The fused chain lies on the host output, adding at least
--  2·|cube| + 1 above it under the stated premises. The
--  unfused block instead reads fWire at an output XOR and
--  keeps both comparator cones beside the host.

lockedBlockMerged-depth-lower :
  (lv xs keys : List ℕ) (ksec : List Bool) (fWire : ℕ) →
  fWire < length lv → All (_< length lv) xs →
  All (λ x → suc (getL lv x) ≤ getL lv fWire) xs →
  suc (getL lv fWire) + 2 * length (proj₁ (cubeLits xs ksec (length lv)))
    ≤ maxL (runLevels lv (proj₂ (proj₂ (lockedBlockMerged xs keys ksec fWire (length lv)))))
lockedBlockMerged-depth-lower lv xs keys ksec fWire fW< xsv xsDeep =
  ≤-trans (≤-reflexive (trans (cong (λ z → suc z + 2 * length lits) (sym fStable))
                              (sym qIC)))
          (≤-trans (getL-≤-maxL e-f t)
                   (≤-trans (maxL-mono e-f (rOps ++ (oXor t rW ∷ [])))
                            (≤-reflexive (sym (cong maxL split-all)))))
  where
    cR   = cubeLits xs ksec (length lv)
    lits = proj₁ cR
    iC   = proj₁ (proj₂ cR)
    cOps = proj₂ (proj₂ cR)
    e-c  = runLevels lv cOps
    fR   = fuseXorCube fWire lits iC
    t    = proj₁ fR
    fOps = proj₂ (proj₂ fR)
    e-f  = runLevels e-c fOps
    rR   = restoreNet xs keys 0 (proj₁ (proj₂ fR))
    rW   = proj₁ rR
    rOps = proj₂ (proj₂ rR)

    split-all :
      runLevels lv (proj₂ (proj₂ (lockedBlockMerged xs keys ksec fWire (length lv))))
        ≡ runLevels e-f (rOps ++ (oXor t rW ∷ []))
    split-all = trans (runLevels-++ lv cOps (fOps ++ (rOps ++ (oXor t rW ∷ []))))
                      (runLevels-++ e-c fOps (rOps ++ (oXor t rW ∷ [])))

    iC≡ : iC ≡ length e-c
    iC≡ = run-len-state (cubeLits xs ksec) (cubeLits-cnt xs ksec) lv
    lv≤c : length lv ≤ length e-c
    lv≤c = lenMono lv cOps

    fStable : getL e-c fWire ≡ getL lv fWire
    fStable = runLevels-stable lv cOps fWire fW<

    litsRange : All (_< length e-c) lits
    litsRange = All<-weaken lits (≤-reflexive iC≡) (cubeLits-outs< xs ksec (length lv) xsv)
    litsShallow : All (λ l → getL e-c l ≤ getL e-c fWire) lits
    litsShallow = go lits (cubeLits-levels lv xs ksec (getL lv fWire) xsv xsDeep)
      where
        go : (zs : List ℕ) → All (λ w → getL e-c w ≤ getL lv fWire) zs →
             All (λ w → getL e-c w ≤ getL e-c fWire) zs
        go []       []        = []
        go (z ∷ zs) (pz ∷ ps) = ≤-trans pz (≤-reflexive (sym fStable)) ∷ go zs ps

    QL : ℕ → Set
    QL s = getL (runLevels e-c (proj₂ (proj₂ (fuseXorCube fWire lits s))))
                (proj₁ (fuseXorCube fWire lits s))
             ≡ suc (getL e-c fWire) + 2 * length lits
    qIC : QL iC
    qIC = subst QL (sym iC≡)
            (fuseXorCube-out-level e-c fWire lits (≤-trans fW< lv≤c) litsRange litsShallow)

------------------------------------------------------------------------
--  §6 Compose with the host, mirroring LockHost.lockHostBlock-bound.

private
  lenUpFrom : (k j : ℕ) → length (upFrom j k) ≡ k
  lenUpFrom zero    j = refl
  lenUpFrom (suc k) j = cong suc (lenUpFrom k (suc j))

  upFromAll-≤ : (j k L : ℕ) → All (_< L) (upFrom j (suc k)) → j + suc k ≤ L
  upFromAll-≤ j zero    L (px ∷ _)  = subst (_≤ L) (sym (+-comm j 1)) px
  upFromAll-≤ j (suc k) L (_  ∷ ps) =
    subst (_≤ L) (sym (+-suc j (suc k))) (upFromAll-≤ (suc j) k L ps)

  inputs-≤ : (k L : ℕ) → All (_< L) (upFrom 0 k) → k ≤ L
  inputs-≤ zero    L _ = z≤n
  inputs-≤ (suc k) L p = upFromAll-≤ 0 k L p

  falses : ℕ → List Bool
  falses m = replicate m false

  get-falses : (m j : ℕ) → get (falses m) j ≡ false
  get-falses zero    j       = refl
  get-falses (suc m) zero    = refl
  get-falses (suc m) (suc j) = get-falses m j

--  Prove bus-position zero names an allocated or input wire.
--  This index property can be extracted from value-level layout
--  at a dummy input, since Boolean and level environments
--  have matching lengths throughout.
hostOut< : {n G : ℕ} (nl : Netlist n (suc G)) (lv : List ℕ) → n ≤ length lv →
  lookup (proj₁ (netlistWires nl (length lv))) zero
    < length (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
hostOut< {n} nl lv n≤lv =
  subst (lookup (proj₁ (netlistWires nl (length lv))) zero <_)
        (sym (runLevels-len lv (proj₂ (proj₂ (netlistWires nl (length lv))))))
        (subst P lenE bndP)
  where
    env = falses (length lv)
    lenE : length env ≡ length lv
    lenE = length-replicate (length lv)
    x0 : Vec Bool n
    x0 = vreplicate n false
    inR : (i : Fin n) → get env (toℕ i) ≡ lookup x0 i
    inR i = trans (get-falses (length lv) (toℕ i)) (sym (lookup-replicate i false))

    P : ℕ → Set
    P m = lookup (proj₁ (netlistWires nl m)) zero
            < m + length (proj₂ (proj₂ (netlistWires nl m)))
    bndP : P (length env)
    bndP = subst (lookup (proj₁ (netlistWires nl (length env))) zero <_)
                 (runNet-length env (proj₂ (proj₂ (netlistWires nl (length env)))))
                 (proj₁ (netlistWires-correct nl x0 env (subst (n ≤_) (sym lenE) n≤lv) inR)
                    zero)

--  Bound lockHostBlockMerged's emitted netlist by host depth
--  +5n+6. LockHostMerged.lockHostMerged-locked identifies it
--  with the h = 0 locked host; the bound has the same shape
--  and premises as the unfused host-depth +6n+9 theorem.
lockHostBlockMerged-bound :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (lv : List ℕ) →
  All (_< length lv) (upFrom 0 n) → All (_< length lv) (upFrom n n) →
  maxL (runLevels lv (proj₂ (proj₂ (lockHostBlockMerged nl ksec (length lv)))))
    ≤ maxL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))) + 5 * n + 6
lockHostBlockMerged-bound {n} nl ksec lv xsv keysv =
  ≤-trans (≤-reflexive (cong maxL split))
          (≤-trans lb≤ (≤-reflexive (cong (λ z → maxL eH + 5 * z + 6) (lenUpFrom n 0))))
  where
    hOps  = proj₂ (proj₂ (netlistWires nl (length lv)))
    eH    = runLevels lv hOps
    wid   = proj₁ (proj₂ (netlistWires nl (length lv)))
    ws    = proj₁ (netlistWires nl (length lv))
    fWire = lookup ws zero
    lbO   = proj₂ (proj₂ (lockedBlockMerged (upFrom 0 n) (upFrom n n) ksec fWire wid))

    split : runLevels lv (proj₂ (proj₂ (lockHostBlockMerged nl ksec (length lv))))
              ≡ runLevels eH lbO
    split = runLevels-++ lv hOps lbO

    lv≤H : length lv ≤ length eH
    lv≤H = lenMono lv hOps
    wid≡ : wid ≡ length eH
    wid≡ = run-len-state (netlistWires nl) (netlistWires-cnt nl) lv

    lb≤ : maxL (runLevels eH lbO) ≤ maxL eH + 5 * length (upFrom 0 n) + 6
    lb≤ = ≤-trans (≤-reflexive (cong (λ s → maxL (runLevels eH (proj₂ (proj₂ (lockedBlockMerged (upFrom 0 n) (upFrom n n) ksec fWire s))))) wid≡))
                  (lockedBlockMerged-bound eH (upFrom 0 n) (upFrom n n) ksec fWire
                     (hostOut< nl lv (inputs-≤ n (length lv) xsv))
                     (All<-weaken (upFrom 0 n) lv≤H xsv)
                     (All<-weaken (upFrom n n) lv≤H keysv))

--  For that artifact, prove at least 2n+1 levels above
--  the host output when it is at least one level above
--  data inputs. The unfused emitter has no such general
--  lower bound, because its cube cone never reads fWire,
--  as §7's computations demonstrate.
lockHostBlockMerged-depth-lower :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (lv : List ℕ) →
  length ksec ≡ n → All (_< length lv) (upFrom 0 n) →
  All (λ x → suc (getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))) x)
               ≤ getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
                      (lookup (proj₁ (netlistWires nl (length lv))) zero))
      (upFrom 0 n) →
  suc (getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
            (lookup (proj₁ (netlistWires nl (length lv))) zero))
    + 2 * n
    ≤ maxL (runLevels lv (proj₂ (proj₂ (lockHostBlockMerged nl ksec (length lv)))))
lockHostBlockMerged-depth-lower {n} nl ksec lv ksecLen xsv deep =
  ≤-trans (≤-reflexive (cong (λ z → suc (getL eH fWire) + 2 * z) (sym litLen)))
          (≤-trans (subst Pst (sym wid≡) atEH)
                   (≤-reflexive (sym (cong maxL split))))
  where
    hOps  = proj₂ (proj₂ (netlistWires nl (length lv)))
    eH    = runLevels lv hOps
    wid   = proj₁ (proj₂ (netlistWires nl (length lv)))
    ws    = proj₁ (netlistWires nl (length lv))
    fWire = lookup ws zero
    lbO   = proj₂ (proj₂ (lockedBlockMerged (upFrom 0 n) (upFrom n n) ksec fWire wid))

    split : runLevels lv (proj₂ (proj₂ (lockHostBlockMerged nl ksec (length lv))))
              ≡ runLevels eH lbO
    split = runLevels-++ lv hOps lbO

    lv≤H : length lv ≤ length eH
    lv≤H = lenMono lv hOps
    wid≡ : wid ≡ length eH
    wid≡ = run-len-state (netlistWires nl) (netlistWires-cnt nl) lv

    Pst : ℕ → Set
    Pst s = suc (getL eH fWire) + 2 * length (proj₁ (cubeLits (upFrom 0 n) ksec s))
              ≤ maxL (runLevels eH (proj₂ (proj₂ (lockedBlockMerged (upFrom 0 n) (upFrom n n) ksec fWire s))))

    atEH : Pst (length eH)
    atEH = lockedBlockMerged-depth-lower eH (upFrom 0 n) (upFrom n n) ksec fWire
             (hostOut< nl lv (inputs-≤ n (length lv) xsv))
             (All<-weaken (upFrom 0 n) lv≤H xsv) deep

    litLen : length (proj₁ (cubeLits (upFrom 0 n) ksec wid)) ≡ n
    litLen = trans (cubeLits-len (upFrom 0 n) ksec wid
                      (trans (lenUpFrom n 0) (sym ksecLen)))
                   (lenUpFrom n 0)

------------------------------------------------------------------------
--  §7 Check non-vacuity and compare emitters on a host-dominated
--  environment: data wires 0,1(2) and keys at level zero,
--  with the final host-output wire at level 40, above either cone.

private
  lv2 : List ℕ
  lv2 = 0 ∷ 0 ∷ 0 ∷ 0 ∷ 40 ∷ []
  lv3 : List ℕ
  lv3 = 0 ∷ 0 ∷ 0 ∷ 0 ∷ 0 ∷ 0 ∷ 40 ∷ []

  --  For a two-bit fused cube, compute 40 + 2·2 + 2.
  _ : maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlockMerged (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                          (true ∷ false ∷ []) 4 5)))) ≡ 46
  _ = refl
  --  For three fused bits, one extra literal adds two levels.
  _ : maxL (runLevels lv3 (proj₂ (proj₂ (lockedBlockMerged (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
                                          (true ∷ false ∷ true ∷ []) 6 7)))) ≡ 48
  _ = refl
  --  For both unfused cubes, compute 40 + 2. The cube cone
  --  reads only data/constants and runs alongside the host,
  --  so changing cube width leaves this depth unchanged.
  _ : maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                          (true ∷ false ∷ []) 0 4 5)))) ≡ 42
  _ = refl
  _ : maxL (runLevels lv3 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
                                          (true ∷ false ∷ true ∷ []) 0 6 7)))) ≡ 42
  _ = refl

  --  At the two-bit example, instantiate §5 as 45 ≤ 46,
  --  one level below the computed depth, checking non-vacuity.
  _ : 45 ≤ 46
  _ = lockedBlockMerged-depth-lower lv2 (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) (true ∷ false ∷ []) 4
        ≤-refl (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ []) (s≤s z≤n ∷ s≤s z≤n ∷ [])

  --  At the same example, §4 gives 46 ≤ 56. Its ten levels
  --  of slack come from charging the restore cone to the whole
  --  environment maximum instead of its input wires.
  _ : 46 ≤ 56
  _ = lockedBlockMerged-bound lv2 (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) (true ∷ false ∷ []) 4
        ≤-refl (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ [])
        (s≤s (s≤s (s≤s z≤n)) ∷ s≤s (s≤s (s≤s (s≤s z≤n))) ∷ [])
