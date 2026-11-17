------------------------------------------------------------------------
--  Prove host independence for the unfused emitter. Earlier
--  NetDepthPop.lockedBlock-bound and LockHost.lockHostBlock-bound
--  give maxL lv + 6n + 9, retaining host depth in the locking cost.
--  The actual cone reads only data/key primary inputs and meets
--  the host at one wire in its final two gates. NetDepthMerged
--  computed depth 42 for both two- and three-bit cubes on a
--  level-40 host; establish the general reason here. newMax measures
--  levels on newly allocated wires, and netDepth-split proves
--  maxL (runLevels lv ops) ≡ maxL lv ⊔ newMax lv ops. getL-new
--  also bounds block output wires. AllRefsOK/newMax-mono/newMax-flatten
--  erase unrelated host levels: a block reading only prefix inputs
--  below b or its own wires adds no more depth than on an
--  environment flattened to input level R. cone-RefsOK proves
--  constants and both restore cones read only xs, keys, and newly
--  allocated wires, never fWire. lockedBlock-added consequently
--  bounds added depth by (getL lv fWire ⊔ (R + 6|xs| + 9)) + 2,
--  without maxL lv on the right. When the host output dominates
--  the lock cone, lockedBlock-adds-2, lockedBlock-depth-adds-2,
--  and whole-host lockHostBlock-adds-2 give a constant upper
--  overhead two independent of host and key width. Combined with
--  the fused lower bound of 2n + 1 above the same wire,
--  lockedBlock-vs-Merged/unfused-strictly-shallower prove strict
--  separation for n ≥ 1. Scope is emitted-gate structural depth,
--  maxL after runLevels, not post-mapping synthesis depth. The
--  +2 upper bound requires R + 6|xs| + 9 ≤ getL lv fWire; it
--  is attained by both §8 cubes at depth 42. Whole-host composition
--  assumes data and key occupy the first 2n wires, as lockHostBlock
--  lays them out. Use --safe --without-K without postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetDepthHost where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _⊔_; _≤_; _<_; s≤s; z≤n)
open import Data.Nat.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; m≤m⊔n; m≤n⊔m; ⊔-mono-≤; ⊔-assoc; ⊔-identityʳ;
         m≤n⇒m<n∨m≡n; n≤1+n; m≤m+n; +-comm; +-mono-≤; suc-injective)
open import Data.List using (List; []; _∷_; _++_; length; replicate)
open import Data.List.Properties using (++-identityʳ; ++-assoc; length-replicate)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Unit using (⊤; tt)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; cong; cong₂; trans; subst)

open import Extraction.LockedNet using (xorPairs-cnt; constWires-cnt; restoreNet-cnt)
open import Extraction.NetlistCorrect using (stepTh-cnt)
open import Extraction.Netlist using (Op; oConst; oNot; oAnd; oOr; oXor)
open import Extraction.NetDepth using
  (getL; maxL; opLevel; runLevels; runLevels-++; getL-≤-maxL; ⊔-lub; maxL-snoc)
open import Extraction.NetDepthBlock using
  (getL-++-prefix; length-snoc; runLevels-stable)
open import Extraction.NetDepthMux using (getL-snoc-last)

------------------------------------------------------------------------
--  §0 Measure a block's own allocated-wire maximum as newMax.
--  Earlier maxL (runLevels lv ops) bounds included host depth
--  by construction. netDepth-split combines the inherited maximum
--  with newMax to recover total depth, isolating what the block adds.

newMax : List ℕ → List Op → ℕ
newMax lv []         = 0
newMax lv (op ∷ ops) = opLevel lv op ⊔ newMax (lv ++ (opLevel lv op ∷ [])) ops

--  Split total depth into the join of inherited depth and the
--  new-wire maximum, the decomposition used for host independence.
netDepth-split : (lv : List ℕ) (ops : List Op) →
                 maxL (runLevels lv ops) ≡ maxL lv ⊔ newMax lv ops
netDepth-split lv []         = sym (⊔-identityʳ (maxL lv))
netDepth-split lv (op ∷ ops) =
  trans (netDepth-split (lv ++ (opLevel lv op ∷ [])) ops)
        (trans (cong (_⊔ newMax (lv ++ (opLevel lv op ∷ [])) ops)
                     (maxL-snoc lv (opLevel lv op)))
               (⊔-assoc (maxL lv) (opLevel lv op)
                        (newMax (lv ++ (opLevel lv op ∷ [])) ops)))

newMax-≤-run : (lv : List ℕ) (ops : List Op) → newMax lv ops ≤ maxL (runLevels lv ops)
newMax-≤-run lv ops =
  ≤-trans (m≤n⊔m (maxL lv) (newMax lv ops))
          (≤-reflexive (sym (netDepth-split lv ops)))

newMax-++ : (lv : List ℕ) (xs ys : List Op) →
            newMax lv (xs ++ ys) ≡ newMax lv xs ⊔ newMax (runLevels lv xs) ys
newMax-++ lv []        ys = refl
newMax-++ lv (op ∷ xs) ys =
  trans (cong (opLevel lv op ⊔_) (newMax-++ (lv ++ (opLevel lv op ∷ [])) xs ys))
        (sym (⊔-assoc (opLevel lv op) (newMax (lv ++ (opLevel lv op ∷ [])) xs)
                      (newMax (runLevels (lv ++ (opLevel lv op ∷ [])) xs) ys)))

--  Use zero for out-of-range lookups to distinguish allocated
--  wires from inherited ones.
getL-oob : (lv : List ℕ) (i : ℕ) → length lv ≤ i → getL lv i ≡ 0
getL-oob []       i       _       = refl
getL-oob (x ∷ lv) zero    ()
getL-oob (x ∷ lv) (suc i) (s≤s p) = getL-oob lv i p

--  Bound every allocated wire by newMax, including block outputs
--  rather than only the running maximum.
getL-new : (lv : List ℕ) (ops : List Op) (w : ℕ) → length lv ≤ w →
           getL (runLevels lv ops) w ≤ newMax lv ops
getL-new lv []         w lv≤w = ≤-trans (≤-reflexive (getL-oob lv w lv≤w)) z≤n
getL-new lv (op ∷ ops) w lv≤w with m≤n⇒m<n∨m≡n lv≤w
... | inj₁ l<w =
  ≤-trans (getL-new (lv ++ (opLevel lv op ∷ [])) ops w
                    (≤-trans (≤-reflexive (length-snoc lv (opLevel lv op))) l<w))
          (m≤n⊔m (opLevel lv op) (newMax (lv ++ (opLevel lv op ∷ [])) ops))
... | inj₂ eq =
  ≤-trans (≤-reflexive
            (trans (runLevels-stable (lv ++ (opLevel lv op ∷ [])) ops w
                     (≤-trans (s≤s (≤-reflexive (sym eq)))
                              (≤-reflexive (sym (length-snoc lv (opLevel lv op))))))
                   (trans (cong (getL (lv ++ (opLevel lv op ∷ []))) (sym eq))
                          (getL-snoc-last lv (opLevel lv op)))))
          (m≤m⊔n (opLevel lv op) (newMax (lv ++ (opLevel lv op ∷ [])) ops))

------------------------------------------------------------------------
--  §1 Restrict reads to external inputs below prefix b or newly
--  allocated wires at indices ≥ lo. Other environment levels cannot
--  affect the block. newMax-flatten then bounds its new depth by
--  execution on an environment with every inherited level set to R.

RefOK : (b lo : ℕ) → ℕ → Set
RefOK b lo a = (a < b) ⊎ (lo ≤ a)

opRefsOK : (b lo : ℕ) → Op → Set
opRefsOK b lo (oConst _) = ⊤
opRefsOK b lo (oNot a)   = RefOK b lo a
opRefsOK b lo (oAnd a c) = RefOK b lo a × RefOK b lo c
opRefsOK b lo (oOr  a c) = RefOK b lo a × RefOK b lo c
opRefsOK b lo (oXor a c) = RefOK b lo a × RefOK b lo c

AllRefsOK : (b lo : ℕ) → List Op → Set
AllRefsOK b lo []         = ⊤
AllRefsOK b lo (op ∷ ops) = opRefsOK b lo op × AllRefsOK b lo ops

AllRefsOK-++ : (b lo : ℕ) (xs ys : List Op) →
               AllRefsOK b lo xs → AllRefsOK b lo ys → AllRefsOK b lo (xs ++ ys)
AllRefsOK-++ b lo []       ys _        oy = oy
AllRefsOK-++ b lo (x ∷ xs) ys (o , os) oy = o , AllRefsOK-++ b lo xs ys os oy

--  Weaken the read restriction by enlarging the input prefix
--  or lowering the allocation floor.
RefOK-weaken : {b b' lo lo' : ℕ} → b ≤ b' → lo' ≤ lo → (a : ℕ) → RefOK b lo a → RefOK b' lo' a
RefOK-weaken b≤ lo≤ a (inj₁ a<b)  = inj₁ (≤-trans a<b b≤)
RefOK-weaken b≤ lo≤ a (inj₂ lo≤a) = inj₂ (≤-trans lo≤ lo≤a)

opRefsOK-weaken : {b b' lo lo' : ℕ} → b ≤ b' → lo' ≤ lo → (op : Op) →
                  opRefsOK b lo op → opRefsOK b' lo' op
opRefsOK-weaken b≤ lo≤ (oConst _) _         = tt
opRefsOK-weaken b≤ lo≤ (oNot a)   o         = RefOK-weaken b≤ lo≤ a o
opRefsOK-weaken b≤ lo≤ (oAnd a c) (oa , oc) = RefOK-weaken b≤ lo≤ a oa , RefOK-weaken b≤ lo≤ c oc
opRefsOK-weaken b≤ lo≤ (oOr  a c) (oa , oc) = RefOK-weaken b≤ lo≤ a oa , RefOK-weaken b≤ lo≤ c oc
opRefsOK-weaken b≤ lo≤ (oXor a c) (oa , oc) = RefOK-weaken b≤ lo≤ a oa , RefOK-weaken b≤ lo≤ c oc

AllRefsOK-weaken : {b b' lo lo' : ℕ} → b ≤ b' → lo' ≤ lo → (ops : List Op) →
                   AllRefsOK b lo ops → AllRefsOK b' lo' ops
AllRefsOK-weaken b≤ lo≤ []         _        = tt
AllRefsOK-weaken b≤ lo≤ (op ∷ ops) (o , os) =
  opRefsOK-weaken b≤ lo≤ op o , AllRefsOK-weaken b≤ lo≤ ops os

------------------------------------------------------------------------
--  Compare environments only on wires the block is allowed to read.

Dominates : (b lo : ℕ) (lv₁ lv₂ : List ℕ) → Set
Dominates b lo lv₁ lv₂ = (i : ℕ) → RefOK b lo i → getL lv₁ i ≤ getL lv₂ i

getL-snoc-mono : (lv₁ lv₂ : List ℕ) (y₁ y₂ : ℕ) → length lv₁ ≡ length lv₂ → y₁ ≤ y₂ →
                 (i : ℕ) → getL lv₁ i ≤ getL lv₂ i →
                 getL (lv₁ ++ (y₁ ∷ [])) i ≤ getL (lv₂ ++ (y₂ ∷ [])) i
getL-snoc-mono []        []        y₁ y₂ _  y≤ zero    _  = y≤
getL-snoc-mono []        []        y₁ y₂ _  y≤ (suc i) _  = z≤n
getL-snoc-mono []        (z ∷ l₂)  y₁ y₂ () y≤ i       _
getL-snoc-mono (x ∷ l₁)  []        y₁ y₂ () y≤ i       _
getL-snoc-mono (x ∷ l₁)  (z ∷ l₂)  y₁ y₂ le y≤ zero    hi = hi
getL-snoc-mono (x ∷ l₁)  (z ∷ l₂)  y₁ y₂ le y≤ (suc i) hi =
  getL-snoc-mono l₁ l₂ y₁ y₂ (suc-injective le) y≤ i hi

opLevel-mono : (b lo : ℕ) (lv₁ lv₂ : List ℕ) (op : Op) → opRefsOK b lo op →
               Dominates b lo lv₁ lv₂ → opLevel lv₁ op ≤ opLevel lv₂ op
opLevel-mono b lo lv₁ lv₂ (oConst _) _         _   = ≤-refl
opLevel-mono b lo lv₁ lv₂ (oNot a)   o         dom = s≤s (dom a o)
opLevel-mono b lo lv₁ lv₂ (oAnd a c) (oa , oc) dom = s≤s (⊔-mono-≤ (dom a oa) (dom c oc))
opLevel-mono b lo lv₁ lv₂ (oOr  a c) (oa , oc) dom = s≤s (⊔-mono-≤ (dom a oa) (dom c oc))
opLevel-mono b lo lv₁ lv₂ (oXor a c) (oa , oc) dom = s≤s (⊔-mono-≤ (dom a oa) (dom c oc))

--  Prove new-depth monotonicity on read wires alone; unread
--  environment levels have no effect.
newMax-mono : (b lo : ℕ) (lv₁ lv₂ : List ℕ) (ops : List Op) →
  length lv₁ ≡ length lv₂ → Dominates b lo lv₁ lv₂ → AllRefsOK b lo ops →
  newMax lv₁ ops ≤ newMax lv₂ ops
newMax-mono b lo lv₁ lv₂ []         _  _   _         = ≤-refl
newMax-mono b lo lv₁ lv₂ (op ∷ ops) le dom (ro , rr) =
  ⊔-mono-≤ olm (newMax-mono b lo (lv₁ ++ (opLevel lv₁ op ∷ []))
                                 (lv₂ ++ (opLevel lv₂ op ∷ [])) ops le' dom' rr)
  where
    olm : opLevel lv₁ op ≤ opLevel lv₂ op
    olm = opLevel-mono b lo lv₁ lv₂ op ro dom
    le' : length (lv₁ ++ (opLevel lv₁ op ∷ [])) ≡ length (lv₂ ++ (opLevel lv₂ op ∷ []))
    le' = trans (length-snoc lv₁ (opLevel lv₁ op))
                (trans (cong suc le) (sym (length-snoc lv₂ (opLevel lv₂ op))))
    dom' : Dominates b lo (lv₁ ++ (opLevel lv₁ op ∷ [])) (lv₂ ++ (opLevel lv₂ op ∷ []))
    dom' i ok = getL-snoc-mono lv₁ lv₂ (opLevel lv₁ op) (opLevel lv₂ op) le olm i (dom i ok)

------------------------------------------------------------------------
--  Flatten all inherited wires to the declared input level.

flat : ℕ → ℕ → List ℕ
flat k R = replicate k R

length-flat : (k R : ℕ) → length (flat k R) ≡ k
length-flat k R = length-replicate k

getL-flat : (k R i : ℕ) → i < k → getL (flat k R) i ≡ R
getL-flat zero    R i       ()
getL-flat (suc k) R zero    _       = refl
getL-flat (suc k) R (suc i) (s≤s p) = getL-flat k R i p

maxL-flat : (k R : ℕ) → maxL (flat k R) ≤ R
maxL-flat zero    R = z≤n
maxL-flat (suc k) R = ⊔-lub ≤-refl (maxL-flat k R)

--  Erase host depth: with prefix-input levels ≤ R and all other
--  reads local to the block, execution adds no more depth than
--  on the level-R flat environment.
newMax-flatten : (lv : List ℕ) (ops : List Op) (b R : ℕ) →
  b ≤ length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  AllRefsOK b (length lv) ops →
  newMax lv ops ≤ maxL (runLevels (flat (length lv) R) ops)
newMax-flatten lv ops b R b≤ H ok =
  ≤-trans (newMax-mono b (length lv) lv (flat (length lv) R) ops
                       (sym (length-flat (length lv) R)) dom ok)
          (newMax-≤-run (flat (length lv) R) ops)
  where
    dom : Dominates b (length lv) lv (flat (length lv) R)
    dom i (inj₁ i<b)  =
      ≤-trans (H i i<b)
              (≤-reflexive (sym (getL-flat (length lv) R i (≤-trans i<b b≤))))
    dom i (inj₂ lo≤i) = ≤-trans (≤-reflexive (getL-oob lv i lo≤i)) z≤n

------------------------------------------------------------------------
--  §2 Check cone-RefsOK gate by gate. lockedBlock emits constants,
--  perturb restoreNet, keyed restoreNet, and two XORs. Of those
--  five stages, fWire occurs only in the first output XOR. The
--  preceding cone uses xs, keys, and its own newly allocated wires,
--  which is the structural source of host independence.

open import Data.Bool using (Bool)
open import Data.List.Relation.Unary.All as All using (All; []; _∷_)
open import Data.Nat.Properties using (m≤n+m)

open import Extraction.Netlist using
  (Builder; ret; _»=_; fresh; mkConst; mkNot; mkAnd; mkMux; mapMB; foldlMB;
   stepTh; zipL; tailL; nth)
open import Extraction.NetDepthMux using (muxOps)
open import Extraction.NetDepthComp using (concatMux; rowSpecs; mapMB-mux-ops)
open import Extraction.NetDepthBuilder using (cnt-mono)
open import Extraction.NetDepthBuilder using
  (CntLaw; ret-cnt; fresh-cnt; »=-cnt; foldlMB-cnt-general)
open import Extraction.LockedNet using
  (constWires; xorPairs; popOnBuilder; restoreNet; lockedBlock)
open import Extraction.NetDepthPop using (stepMap; mapMB-mono; xorPairs-mono; constWires-mono; stepTh-ops-concatMux)

private
  AllGE-weaken : {a b : ℕ} (zs : List ℕ) → a ≤ b → All (b ≤_) zs → All (a ≤_) zs
  AllGE-weaken []       _   []        = []
  AllGE-weaken (z ∷ zs) a≤b (pz ∷ ps) = ≤-trans a≤b pz ∷ AllGE-weaken zs a≤b ps

  AllGE-replicate : {lo : ℕ} (n x : ℕ) → lo ≤ x → All (lo ≤_) (replicate n x)
  AllGE-replicate zero    x p = []
  AllGE-replicate (suc n) x p = p ∷ AllGE-replicate n x p

  nth-GE : {lo : ℕ} (zs : List ℕ) (k d : ℕ) → All (lo ≤_) zs → lo ≤ d → lo ≤ nth zs k d
  nth-GE []       k       d _        pd = pd
  nth-GE (z ∷ zs) zero    d (pz ∷ _) pd = pz
  nth-GE (z ∷ zs) (suc k) d (_ ∷ ps) pd = nth-GE zs k d ps pd

  tailL-GE : {lo : ℕ} (zs : List ℕ) → All (lo ≤_) zs → All (lo ≤_) (tailL zs)
  tailL-GE []       _        = []
  tailL-GE (z ∷ zs) (_ ∷ ps) = ps

  GE→OK : {lo : ℕ} (b : ℕ) (zs : List ℕ) → All (lo ≤_) zs → All (RefOK b lo) zs
  GE→OK b []       []        = []
  GE→OK b (z ∷ zs) (pz ∷ ps) = inj₂ pz ∷ GE→OK b zs ps

  zipL-OK : (b lo : ℕ) (as cs : List ℕ) → All (lo ≤_) as → All (lo ≤_) cs →
            All (λ p → RefOK b lo (proj₁ p) × RefOK b lo (proj₂ p)) (zipL as cs)
  zipL-OK b lo []       cs       _          _          = []
  zipL-OK b lo (a ∷ as) []       _          _          = []
  zipL-OK b lo (a ∷ as) (c ∷ cs) (pa ∷ pas) (pc ∷ pcs) =
    (inj₂ pa , inj₂ pc) ∷ zipL-OK b lo as cs pas pcs

------------------------------------------------------------------------
--  Check the constant stage and XOR prefix.

constWires-RefsOK : (b lo : ℕ) (bs : List Bool) (i : ℕ) →
                    AllRefsOK b lo (proj₂ (proj₂ (constWires bs i)))
constWires-RefsOK b lo []       i = tt
constWires-RefsOK b lo (c ∷ bs) i =
  tt , subst (AllRefsOK b lo)
             (sym (++-identityʳ (proj₂ (proj₂ (constWires bs (suc i))))))
             (constWires-RefsOK b lo bs (suc i))

constWires-outs≥ : (bs : List Bool) (i : ℕ) → All (i ≤_) (proj₁ (constWires bs i))
constWires-outs≥ []       i = []
constWires-outs≥ (c ∷ bs) i =
  ≤-refl ∷ AllGE-weaken (proj₁ (constWires bs (suc i))) (n≤1+n i) (constWires-outs≥ bs (suc i))

xorPairs-RefsOK : (b lo : ℕ) (xs keys : List ℕ) (i : ℕ) →
                  All (RefOK b lo) xs → All (RefOK b lo) keys →
                  AllRefsOK b lo (proj₂ (proj₂ (xorPairs xs keys i)))
xorPairs-RefsOK b lo []       keys     i _          _          = tt
xorPairs-RefsOK b lo (a ∷ as) []       i _          _          = tt
xorPairs-RefsOK b lo (a ∷ as) (c ∷ cs) i (pa ∷ pas) (pc ∷ pcs) =
  (pa , pc) , subst (AllRefsOK b lo)
                    (sym (++-identityʳ (proj₂ (proj₂ (xorPairs as cs (suc i))))))
                    (xorPairs-RefsOK b lo as cs (suc i) pas pcs)

xorPairs-outs≥ : (xs keys : List ℕ) (i : ℕ) → All (i ≤_) (proj₁ (xorPairs xs keys i))
xorPairs-outs≥ []       keys     i = []
xorPairs-outs≥ (a ∷ as) []       i = []
xorPairs-outs≥ (a ∷ as) (c ∷ cs) i =
  ≤-refl ∷ AllGE-weaken (proj₁ (xorPairs as cs (suc i))) (n≤1+n i) (xorPairs-outs≥ as cs (suc i))

------------------------------------------------------------------------
--  Check a thermometer row and the fold of rows.

AllMuxOK : (b lo : ℕ) → List (ℕ × ℕ × ℕ) → Set
AllMuxOK b lo []                 = ⊤
AllMuxOK b lo ((s , a , c) ∷ ms) =
  (RefOK b lo s × RefOK b lo a × RefOK b lo c) × AllMuxOK b lo ms

concatMux-RefsOK : (b lo : ℕ) (ms : List (ℕ × ℕ × ℕ)) (st : ℕ) → lo ≤ st →
                   AllMuxOK b lo ms → AllRefsOK b lo (concatMux ms st)
concatMux-RefsOK b lo []                 st _    _ = tt
concatMux-RefsOK b lo ((s , a , c) ∷ ms) st lo≤ ((os , oa , oc) , rest) =
  AllRefsOK-++ b lo (muxOps s a c st) (concatMux ms (4 + st))
    ( os
    , (oa , inj₂ lo≤)
    , (oc , os)
    , (inj₂ (≤-trans lo≤ (n≤1+n st)) , inj₂ (≤-trans lo≤ (≤-trans (n≤1+n st) (n≤1+n (suc st)))))
    , tt )
    (concatMux-RefsOK b lo ms (4 + st) (≤-trans lo≤ (m≤n+m st 4)) rest)

rowSpecs-MuxOK : (b lo bit : ℕ) (ps : List (ℕ × ℕ)) → RefOK b lo bit →
                 All (λ p → RefOK b lo (proj₁ p) × RefOK b lo (proj₂ p)) ps →
                 AllMuxOK b lo (rowSpecs bit ps)
rowSpecs-MuxOK b lo bit []       _    _                = tt
rowSpecs-MuxOK b lo bit (p ∷ ps) obit ((p1 , p2) ∷ pas) =
  (obit , p1 , p2) , rowSpecs-MuxOK b lo bit ps obit pas

stepMap-outs≥ : (bit : ℕ) (ps : List (ℕ × ℕ)) (i : ℕ) → All (i ≤_) (proj₁ (stepMap bit ps i))
stepMap-outs≥ bit []       i = []
stepMap-outs≥ bit (p ∷ ps) i =
  ≤-trans (n≤1+n i) (≤-trans (n≤1+n (suc i)) (n≤1+n (suc (suc i))))
    ∷ AllGE-weaken (proj₁ (stepMap bit ps (suc (suc (suc (suc i))))))
                   (≤-trans (n≤1+n i) (≤-trans (n≤1+n (suc i))
                              (≤-trans (n≤1+n (suc (suc i))) (n≤1+n (suc (suc (suc i)))))))
                   (stepMap-outs≥ bit ps (suc (suc (suc (suc i)))))

step-RefsOK : (b lo tw : ℕ) (acc : List ℕ) (bit st : ℕ) → lo ≤ st → lo ≤ bit →
              All (lo ≤_) acc →
              AllRefsOK b lo (proj₂ (proj₂ (stepTh tw acc bit st)))
step-RefsOK b lo tw acc bit st lo≤st lo≤bit accGE =
  subst (AllRefsOK b lo) (sym (stepTh-ops-concatMux tw acc bit st))
    (concatMux-RefsOK b lo (rowSpecs bit (zipL (tailL acc) acc)) st lo≤st
      (rowSpecs-MuxOK b lo bit (zipL (tailL acc) acc) (inj₂ lo≤bit)
        (zipL-OK b lo (tailL acc) acc (tailL-GE acc accGE) accGE)))

fold-RefsOK : (b lo tw : ℕ) (acc bs : List ℕ) (st : ℕ) →
  lo ≤ st → lo ≤ tw → All (lo ≤_) acc → All (lo ≤_) bs →
  AllRefsOK b lo (proj₂ (proj₂ (foldlMB (stepTh tw) acc bs st)))
  × All (lo ≤_) (proj₁ (foldlMB (stepTh tw) acc bs st))
  × lo ≤ proj₁ (proj₂ (foldlMB (stepTh tw) acc bs st))
fold-RefsOK b lo tw acc []       st lo≤st lo≤tw accGE _           = tt , accGE , lo≤st
fold-RefsOK b lo tw acc (x ∷ xs) st lo≤st lo≤tw accGE (px ∷ pxs) =
    AllRefsOK-++ b lo (proj₂ (proj₂ (stepTh tw acc x st)))
                      (proj₂ (proj₂ (foldlMB (stepTh tw) acc' xs st₁)))
      (step-RefsOK b lo tw acc x st lo≤st px accGE) (proj₁ IH)
  , proj₂ IH
  where
    st₁  = proj₁ (proj₂ (stepTh tw acc x st))
    acc' = proj₁ (stepTh tw acc x st)
    lo≤st₁ : lo ≤ st₁
    lo≤st₁ = ≤-trans lo≤st (mapMB-mono x (zipL (tailL acc) acc) st)
    acc'GE : All (lo ≤_) acc'
    acc'GE = lo≤tw ∷ AllGE-weaken (proj₁ (stepMap x (zipL (tailL acc) acc) st)) lo≤st
                                  (stepMap-outs≥ x (zipL (tailL acc) acc) st)
    IH = fold-RefsOK b lo tw acc' xs st₁ lo≤st₁ lo≤tw acc'GE pxs

------------------------------------------------------------------------
--  Check the comparator and keyed restore cone.

popOn-RefsOK : (b lo : ℕ) (bs : List ℕ) (h i : ℕ) → lo ≤ i → All (lo ≤_) bs →
               AllRefsOK b lo (proj₂ (proj₂ (popOnBuilder bs h i)))
popOn-RefsOK b lo bs h i lo≤i bsGE =
  tt , tt ,
  AllRefsOK-++ b lo (proj₂ (proj₂ (foldlMB (stepTh i) acc0 bs (suc (suc i)))))
                    (oNot (nth thF (suc h) (suc i)) ∷ oAnd (nth thF h (suc i)) s3 ∷ [])
    (proj₁ FR)
    ( inj₂ (nth-GE thF (suc h) (suc i) (proj₁ (proj₂ FR)) lo≤si)
    , (inj₂ (nth-GE thF h (suc i) (proj₁ (proj₂ FR)) lo≤si) , inj₂ (proj₂ (proj₂ FR)))
    , tt )
  where
    acc0 = i ∷ replicate (length bs) (suc i)
    thF  = proj₁ (foldlMB (stepTh i) acc0 bs (suc (suc i)))
    s3   = proj₁ (proj₂ (foldlMB (stepTh i) acc0 bs (suc (suc i))))
    lo≤si : lo ≤ suc i
    lo≤si = ≤-trans lo≤i (n≤1+n i)
    FR = fold-RefsOK b lo i acc0 bs (suc (suc i))
           (≤-trans lo≤si (n≤1+n (suc i))) lo≤i
           (lo≤i ∷ AllGE-replicate (length bs) (suc i) lo≤si) bsGE

restoreNet-RefsOK : (b lo : ℕ) (xs keys : List ℕ) (h i : ℕ) → lo ≤ i →
  All (RefOK b lo) xs → All (RefOK b lo) keys →
  AllRefsOK b lo (proj₂ (proj₂ (restoreNet xs keys h i)))
restoreNet-RefsOK b lo xs keys h i lo≤i xsOK keysOK =
  AllRefsOK-++ b lo (proj₂ (proj₂ (xorPairs xs keys i)))
                    (proj₂ (proj₂ (popOnBuilder (proj₁ (xorPairs xs keys i)) h
                                                (proj₁ (proj₂ (xorPairs xs keys i))))))
    (xorPairs-RefsOK b lo xs keys i xsOK keysOK)
    (popOn-RefsOK b lo (proj₁ (xorPairs xs keys i)) h (proj₁ (proj₂ (xorPairs xs keys i)))
       (≤-trans lo≤i (xorPairs-mono xs keys i))
       (AllGE-weaken (proj₁ (xorPairs xs keys i)) lo≤i (xorPairs-outs≥ xs keys i)))

------------------------------------------------------------------------
--  §3 Replace the inherited maxL lv in the coarse
--  maxL lv + 6|xs| + 9 bound with the data/key input level R
--  and the particular host-wire level getL lv fWire. This
--  separates lock cost from the whole host's critical-path maximum.

open import Extraction.LockedNet using (restoreNet-out<)
open import Extraction.NetDepthFold using (run-len-state)
open import Extraction.NetDepthPop using (lockedBlock-bound)
open import Extraction.NetDepthMerged using (maxL-mono)

private
  All<-weaken : {a c : ℕ} (zs : List ℕ) → a ≤ c → All (_< a) zs → All (_< c) zs
  All<-weaken values bound = All.map (λ proof → ≤-trans proof bound)


--  Show comparator and restore outputs are allocated at or after
--  the start identifier, hence belong to the block rather than the host.
popOn-out≥ : (bs : List ℕ) (h i : ℕ) → i ≤ proj₁ (popOnBuilder bs h i)
popOn-out≥ bs h i =
  ≤-trans (≤-trans (n≤1+n i) (≤-trans (n≤1+n (suc i)) foldMono)) (n≤1+n s3)
  where
    acc0 = i ∷ replicate (length bs) (suc i)
    s3   = proj₁ (proj₂ (foldlMB (stepTh i) acc0 bs (suc (suc i))))
    foldMono : suc (suc i) ≤ s3
    foldMono = cnt-mono (foldlMB (stepTh i) acc0 bs)
                       (foldlMB-cnt-general (stepTh i) (λ acc x → stepTh-cnt i acc x) acc0 bs)
                       (suc (suc i))

restoreNet-out≥ : (xs keys : List ℕ) (h i : ℕ) → i ≤ proj₁ (restoreNet xs keys h i)
restoreNet-out≥ xs keys h i =
  ≤-trans (xorPairs-mono xs keys i)
          (popOn-out≥ (proj₁ (xorPairs xs keys i)) h (proj₁ (proj₂ (xorPairs xs keys i))))

------------------------------------------------------------------------
--  Define the cone as operations emitted before the first fWire read.

lockCone : (xs keys : List ℕ) (ksec : List Bool) (h : ℕ) → Builder ℕ
lockCone xs keys ksec h =
  constWires ksec    »= λ kw →
  restoreNet xs kw h »= λ pW →
  restoreNet xs keys h

lockCone-cnt : (xs keys : List ℕ) (ksec : List Bool) (h : ℕ) →
                 CntLaw (lockCone xs keys ksec h)
lockCone-cnt xs keys ksec h =
  »=-cnt (constWires ksec)
           (λ kw → restoreNet xs kw h »= λ pW → restoreNet xs keys h)
           (constWires-cnt ksec)
           (λ kw → »=-cnt (restoreNet xs kw h) (λ pW → restoreNet xs keys h)
                            (restoreNet-cnt xs kw h)
                            (λ pW → restoreNet-cnt xs keys h))

--  Prove every cone read is a data/key wire below b or a wire
--  the cone allocated; fWire belongs to neither class.
cone-RefsOK : (b lo : ℕ) (xs keys : List ℕ) (ksec : List Bool) (h i : ℕ) → lo ≤ i →
  All (RefOK b lo) xs → All (RefOK b lo) keys →
  AllRefsOK b lo (proj₂ (proj₂ (lockCone xs keys ksec h i)))
cone-RefsOK b lo xs keys ksec h i lo≤i xsOK keysOK =
  AllRefsOK-++ b lo cOps (pOps ++ rOps)
    (constWires-RefsOK b lo ksec i)
    (AllRefsOK-++ b lo pOps rOps
      (restoreNet-RefsOK b lo xs kw h iC lo≤iC xsOK
         (GE→OK b kw (AllGE-weaken kw lo≤i (constWires-outs≥ ksec i))))
      (restoreNet-RefsOK b lo xs keys h iP
         (≤-trans lo≤iC (cnt-mono (restoreNet xs kw h) (restoreNet-cnt xs kw h) iC))
         xsOK keysOK))
  where
    kw   = proj₁ (constWires ksec i)
    iC   = proj₁ (proj₂ (constWires ksec i))
    cOps = proj₂ (proj₂ (constWires ksec i))
    iP   = proj₁ (proj₂ (restoreNet xs kw h iC))
    pOps = proj₂ (proj₂ (restoreNet xs kw h iC))
    rOps = proj₂ (proj₂ (restoreNet xs keys h iP))
    lo≤iC : lo ≤ iC
    lo≤iC = ≤-trans lo≤i (constWires-mono ksec i)

------------------------------------------------------------------------
--  §4 State the resulting added-depth theorem.

private
  in-prefix : (b lo : ℕ) (zs : List ℕ) → All (_< b) zs → All (RefOK b lo) zs
  in-prefix b lo []       []        = []
  in-prefix b lo (z ∷ zs) (pz ∷ ps) = inj₁ pz ∷ in-prefix b lo zs ps

--  Parameterise the tail argument by any cone-depth bound A.
--  Only the final two XORs see the host wire and they add two
--  levels. lockedBlock-added supplies the coarse cone bound;
--  NetDepthExact later supplies a tighter bound to the same lemma.
lockedBlock-added-gen :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire A : ℕ) →
  fWire < length lv →
  newMax lv (proj₂ (proj₂ (lockCone xs keys ksec h (length lv)))) ≤ A →
  newMax lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))
    ≤ suc (suc (getL lv fWire ⊔ A))
lockedBlock-added-gen lv xs keys ksec h fWire A fW< coneBound =
  ≤-trans (≤-reflexive (trans (cong (newMax lv) splitOps) (newMax-++ lv coneOps T)))
          (⊔-lub (≤-trans coneBound A≤goal) tailBound)
  where
    L    = length lv
    kw   = proj₁ (constWires ksec L)
    iC   = proj₁ (proj₂ (constWires ksec L))
    cOps = proj₂ (proj₂ (constWires ksec L))
    pW   = proj₁ (restoreNet xs kw h iC)
    iP   = proj₁ (proj₂ (restoreNet xs kw h iC))
    pOps = proj₂ (proj₂ (restoreNet xs kw h iC))
    rW   = proj₁ (restoreNet xs keys h iP)
    iR   = proj₁ (proj₂ (restoreNet xs keys h iP))
    rOps = proj₂ (proj₂ (restoreNet xs keys h iP))

    coneOps = proj₂ (proj₂ (lockCone xs keys ksec h L))
    T : List Op
    T = oXor fWire pW ∷ oXor iR rW ∷ []
    e-cone = runLevels lv coneOps
    F = getL lv fWire

    splitOps : proj₂ (proj₂ (lockedBlock xs keys ksec h fWire L)) ≡ coneOps ++ T
    splitOps = trans (cong (cOps ++_) (sym (++-assoc pOps rOps T)))
                     (sym (++-assoc cOps (pOps ++ rOps) T))

    A≤goal : A ≤ suc (suc (F ⊔ A))
    A≤goal = ≤-trans (m≤n⊔m F A) (≤-trans (n≤1+n (F ⊔ A)) (n≤1+n (suc (F ⊔ A))))

    --  Handle the two output XORs, the only gates depending on the host wire.
    L1 = opLevel e-cone (oXor fWire pW)
    e1 = e-cone ++ (L1 ∷ [])
    L2 = opLevel e1 (oXor iR rW)

    L≤iC : L ≤ iC
    L≤iC = constWires-mono ksec L
    L≤pW : L ≤ pW
    L≤pW = ≤-trans L≤iC (restoreNet-out≥ xs kw h iC)
    L≤rW : L ≤ rW
    L≤rW = ≤-trans L≤iC (≤-trans (cnt-mono (restoreNet xs kw h) (restoreNet-cnt xs kw h) iC)
                                 (restoreNet-out≥ xs keys h iP))
    pW≤A : getL e-cone pW ≤ A
    pW≤A = ≤-trans (getL-new lv coneOps pW L≤pW) coneBound
    rW≤A : getL e-cone rW ≤ A
    rW≤A = ≤-trans (getL-new lv coneOps rW L≤rW) coneBound

    iR≡ : iR ≡ length e-cone
    iR≡ = run-len-state (lockCone xs keys ksec h) (lockCone-cnt xs keys ksec h) lv

    L1≤ : L1 ≤ suc (F ⊔ A)
    L1≤ = s≤s (⊔-lub (≤-trans (≤-reflexive (runLevels-stable lv coneOps fWire fW<))
                              (m≤m⊔n F A))
                     (≤-trans pW≤A (m≤n⊔m F A)))

    L2≤ : L2 ≤ suc (suc (F ⊔ A))
    L2≤ = s≤s (⊔-lub (≤-trans (≤-reflexive (trans (cong (getL e1) iR≡)
                                                  (getL-snoc-last e-cone L1)))
                              L1≤)
                     (≤-trans (≤-reflexive (getL-++-prefix e-cone (L1 ∷ []) rW
                                             (≤-trans (restoreNet-out< xs keys h iP)
                                                      (≤-reflexive iR≡))))
                              (≤-trans rW≤A (≤-trans (m≤n⊔m F A) (n≤1+n (F ⊔ A))))))

    tailBound : newMax e-cone T ≤ suc (suc (F ⊔ A))
    tailBound = ⊔-lub (≤-trans L1≤ (n≤1+n (suc (F ⊔ A)))) (⊔-lub L2≤ z≤n)

--  Bound added depth by two above the greater of the host wire
--  and the lock cone. The cone depends only on input level R
--  and key width, so maxL lv is absent from the right-hand side.
lockedBlock-added :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  newMax lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))
    ≤ suc (suc (getL lv fWire ⊔ (R + 6 * length xs + 9)))
lockedBlock-added lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b =
  lockedBlock-added-gen lv xs keys ksec h fWire A fW< coneBound
  where
    L    = length lv
    kw   = proj₁ (constWires ksec L)
    iC   = proj₁ (proj₂ (constWires ksec L))
    cOps = proj₂ (proj₂ (constWires ksec L))
    pW   = proj₁ (restoreNet xs kw h iC)
    iP   = proj₁ (proj₂ (restoreNet xs kw h iC))
    pOps = proj₂ (proj₂ (restoreNet xs kw h iC))
    rW   = proj₁ (restoreNet xs keys h iP)
    iR   = proj₁ (proj₂ (restoreNet xs keys h iP))
    rOps = proj₂ (proj₂ (restoreNet xs keys h iP))

    coneOps = proj₂ (proj₂ (lockCone xs keys ksec h L))
    T : List Op
    T = oXor fWire pW ∷ oXor iR rW ∷ []
    E = flat L R
    A = R + 6 * length xs + 9

    splitOps : proj₂ (proj₂ (lockedBlock xs keys ksec h fWire L)) ≡ coneOps ++ T
    splitOps = trans (cong (cOps ++_) (sym (++-assoc pOps rOps T)))
                     (sym (++-assoc cOps (pOps ++ rOps) T))

    coneOK : AllRefsOK b L coneOps
    coneOK = cone-RefsOK b L xs keys ksec h L ≤-refl
               (in-prefix b L xs xs<b) (in-prefix b L keys keys<b)

    lenE : length E ≡ L
    lenE = length-flat L R

    lbAtE : maxL (runLevels E (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire L))))
              ≤ maxL E + 6 * length xs + 9
    lbAtE = ≤-trans (≤-reflexive
                      (cong (λ s → maxL (runLevels E
                              (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire s)))))
                            (sym lenE)))
                    (lockedBlock-bound E xs keys ksec h fWire
                       (All<-weaken xs (≤-trans b≤ (≤-reflexive (sym lenE))) xs<b)
                       (All<-weaken keys (≤-trans b≤ (≤-reflexive (sym lenE))) keys<b))

    coneBound : newMax lv coneOps ≤ A
    coneBound =
      ≤-trans (newMax-flatten lv coneOps b R b≤ Hlev coneOK)
        (≤-trans (maxL-mono (runLevels E coneOps) T)
          (≤-trans (≤-reflexive
                     (trans (cong maxL (sym (runLevels-++ E coneOps T)))
                            (cong (λ z → maxL (runLevels E z)) (sym splitOps))))
            (≤-trans lbAtE (+-mono-≤ (+-mono-≤ (maxL-flat L R) (≤-refl {6 * length xs}))
                                     (≤-refl {9})))))

------------------------------------------------------------------------
--  §5 If the host output is at least as deep as the
--  R + 6|xs| + 9 lock cone, only the two output XOR levels
--  remain as overhead. The constant two is independent of
--  both host and key width.

open import Data.Nat.Properties using (m≥n⇒m⊔n≡m; *-monoʳ-≤)

lockedBlock-host-free :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv)))))
    ≤ maxL lv ⊔ suc (suc (getL lv fWire ⊔ (R + 6 * length xs + 9)))
lockedBlock-host-free lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b =
  ≤-trans (≤-reflexive (netDepth-split lv
             (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))))
          (⊔-mono-≤ ≤-refl
             (lockedBlock-added lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b))

--  Keep all unfused block wires at most two levels above the
--  read host wire, uniformly in host and key width.
lockedBlock-adds-2 :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  R + 6 * length xs + 9 ≤ getL lv fWire →
  newMax lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))
    ≤ getL lv fWire + 2
lockedBlock-adds-2 lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b A≤F =
  ≤-trans (lockedBlock-added lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b)
          (≤-reflexive (trans (cong (λ z → suc (suc z)) (m≥n⇒m⊔n≡m A≤F))
                              (+-comm 2 (getL lv fWire))))

lockedBlock-depth-adds-2 :
  (lv xs keys : List ℕ) (ksec : List Bool) (h fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  R + 6 * length xs + 9 ≤ getL lv fWire →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv)))))
    ≤ maxL lv + 2
lockedBlock-depth-adds-2 lv xs keys ksec h fWire b R b≤ fW< Hlev xs<b keys<b A≤F =
  ≤-trans (≤-reflexive (netDepth-split lv
             (proj₂ (proj₂ (lockedBlock xs keys ksec h fWire (length lv))))))
          (⊔-lub (m≤m+n (maxL lv) 2)
                 (≤-trans (lockedBlock-adds-2 lv xs keys ksec h fWire b R
                             b≤ fW< Hlev xs<b keys<b A≤F)
                          (+-mono-≤ (getL-≤-maxL lv fWire) (≤-refl {2}))))

------------------------------------------------------------------------
--  §6 Compose with a host, giving the host-independent counterpart
--  of LockHost.lockHostBlock-bound.

open import Data.Fin using (Fin; zero)
open import Data.Vec using (Vec; lookup)
open import Locking.NetlistToCircuit using (Netlist)
open import Extraction.HostNetlist using (netlistWires; netlistWires-cnt)
open import Extraction.LockHost using (lockHostBlock)
open import Extraction.LockHostMerged using (lockHostBlockMerged)
open import Extraction.NetDepthMerged using (hostOut<; lockHostBlockMerged-depth-lower)
open import Extraction.NetDepthComp using (runLevels-len)
open import Extraction.NetDepthPop using (upFrom-<)
open import Extraction.Netlist using (upFrom)

length-upFrom : (k j : ℕ) → length (upFrom j k) ≡ k
length-upFrom zero    j = refl
length-upFrom (suc k) j = cong suc (length-upFrom k (suc j))

--  Bound the locked host by the join of original host depth
--  and two above max(host output, R + 6n + 9). Unlike the
--  earlier host-depth + 6n + 9 bound, the cone term is charged
--  to primary-input level R.
lockHostBlock-host-free :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (h : ℕ) (lv : List ℕ) (R : ℕ) →
  n + n ≤ length lv →
  ((i : ℕ) → i < n + n → getL lv i ≤ R) →
  maxL (runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv)))))
    ≤ maxL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
      ⊔ suc (suc (getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
                       (lookup (proj₁ (netlistWires nl (length lv))) zero)
                  ⊔ (R + 6 * n + 9)))
lockHostBlock-host-free {n} nl ksec h lv R nn≤ Hlev =
  ≤-trans (≤-reflexive (cong maxL split))
          (≤-trans atEH
                   (≤-reflexive (cong (λ z → maxL eH ⊔ suc (suc (getL eH fWire ⊔ (R + 6 * z + 9))))
                                      (length-upFrom n 0))))
  where
    hOps  = proj₂ (proj₂ (netlistWires nl (length lv)))
    eH    = runLevels lv hOps
    wid   = proj₁ (proj₂ (netlistWires nl (length lv)))
    ws    = proj₁ (netlistWires nl (length lv))
    fWire = lookup ws zero
    lbO   = proj₂ (proj₂ (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire wid))

    split : runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv))))
              ≡ runLevels eH lbO
    split = runLevels-++ lv hOps lbO

    lv≤H : length lv ≤ length eH
    lv≤H = ≤-trans (m≤m+n (length lv) (length hOps))
                   (≤-reflexive (sym (runLevels-len lv hOps)))
    wid≡ : wid ≡ length eH
    wid≡ = run-len-state (netlistWires nl) (netlistWires-cnt nl) lv

    atEH : maxL (runLevels eH lbO)
             ≤ maxL eH ⊔ suc (suc (getL eH fWire ⊔ (R + 6 * length (upFrom 0 n) + 9)))
    atEH = ≤-trans (≤-reflexive
                     (cong (λ s → maxL (runLevels eH (proj₂ (proj₂
                             (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire s)))))
                           wid≡))
                   (lockedBlock-host-free eH (upFrom 0 n) (upFrom n n) ksec h fWire (n + n) R
                      (≤-trans nn≤ lv≤H)
                      (hostOut< nl lv (≤-trans (m≤m+n n n) nn≤))
                      (λ i i< → ≤-trans (≤-reflexive (runLevels-stable lv hOps i (≤-trans i< nn≤)))
                                        (Hlev i i<))
                      (upFrom-< n 0 (m≤m+n n n))
                      (upFrom-< n n ≤-refl))

--  When the host output dominates the lock cone, the entire
--  locked netlist is at most two levels deeper than the host,
--  for all hosts, cubes, and key widths. This is the theorem
--  corresponding to measured host-independent unfused overhead.
lockHostBlock-adds-2 :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (h : ℕ) (lv : List ℕ) (R : ℕ) →
  n + n ≤ length lv →
  ((i : ℕ) → i < n + n → getL lv i ≤ R) →
  R + 6 * n + 9 ≤ getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
                       (lookup (proj₁ (netlistWires nl (length lv))) zero) →
  maxL (runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv)))))
    ≤ maxL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))) + 2
lockHostBlock-adds-2 {n} nl ksec h lv R nn≤ Hlev A≤F =
  ≤-trans (lockHostBlock-host-free nl ksec h lv R nn≤ Hlev)
          (⊔-lub (m≤m+n (maxL eH) 2)
                 (≤-trans (≤-reflexive (cong (λ z → suc (suc z)) (m≥n⇒m⊔n≡m A≤F)))
                          (≤-trans (s≤s (s≤s (getL-≤-maxL eH fWire)))
                                   (≤-reflexive (+-comm 2 (maxL eH))))))
  where
    eH    = runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))
    fWire = lookup (proj₁ (netlistWires nl (length lv))) zero

------------------------------------------------------------------------
--  §7 Pair the unfused constant upper overhead with the fused
--  lower overhead 2n + 1. If the host output is its deepest
--  wire and dominates the lock cone, the fused netlist is
--  strictly deeper for every n ≥ 1.

unfused-strictly-shallower :
  {n G : ℕ} (nl : Netlist n (suc G)) (ksec : List Bool) (lv : List ℕ) (R : ℕ) →
  length ksec ≡ n → 1 ≤ n → n + n ≤ length lv →
  ((i : ℕ) → i < n + n → getL lv i ≤ R) →
  R + 6 * n + 9 ≤ getL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv)))))
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
unfused-strictly-shallower {n} nl ksec lv R ksecLen n≥1 nn≤ Hlev A≤F mx≤F deep =
  ≤-trans (s≤s (≤-trans (lockHostBlock-adds-2 nl ksec 0 lv R nn≤ Hlev A≤F)
                        (≤-trans (+-mono-≤ mx≤F (≤-refl {2}))
                                 (+-mono-≤ (≤-refl {getL eH fWire}) (*-monoʳ-≤ 2 n≥1)))))
          (lockHostBlockMerged-depth-lower nl ksec lv ksecLen
             (upFrom-< n 0 (≤-trans (m≤m+n n n) nn≤)) deep)
  where
    eH    = runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))
    fWire = lookup (proj₁ (netlistWires nl (length lv))) zero

open import Data.Bool using (true; false)
open import Extraction.LockedNetMerged using (lockedBlockMerged; cubeLits)
open import Extraction.NetDepthMerged using (lockedBlockMerged-depth-lower)

--  State the same separation for blocks without a host netlist.
--  If the read wire is the environment's deepest and dominates
--  the lock cone, any nonempty cube makes the fused block
--  strictly deeper. Both denote the same locked function
--  at h = 0, the fused emitter's supported radius.
lockedBlock-vs-Merged :
  (lv xs keys : List ℕ) (ksec : List Bool) (fWire b R : ℕ) →
  b ≤ length lv → fWire < length lv →
  ((i : ℕ) → i < b → getL lv i ≤ R) →
  All (_< b) xs → All (_< b) keys →
  R + 6 * length xs + 9 ≤ getL lv fWire →
  maxL lv ≤ getL lv fWire →
  All (λ x → suc (getL lv x) ≤ getL lv fWire) xs →
  1 ≤ length (proj₁ (cubeLits xs ksec (length lv))) →
  maxL (runLevels lv (proj₂ (proj₂ (lockedBlock xs keys ksec 0 fWire (length lv)))))
    < maxL (runLevels lv (proj₂ (proj₂ (lockedBlockMerged xs keys ksec fWire (length lv)))))
lockedBlock-vs-Merged lv xs keys ksec fWire b R b≤ fW< Hlev xs<b keys<b A≤F mx≤F deep lits≥1 =
  ≤-trans (s≤s (≤-trans (lockedBlock-depth-adds-2 lv xs keys ksec 0 fWire b R
                           b≤ fW< Hlev xs<b keys<b A≤F)
                        (≤-trans (+-mono-≤ mx≤F (≤-refl {2}))
                                 (+-mono-≤ (≤-refl {getL lv fWire}) (*-monoʳ-≤ 2 lits≥1)))))
          (lockedBlockMerged-depth-lower lv xs keys ksec fWire fW<
             (All<-weaken xs b≤ xs<b) deep)

------------------------------------------------------------------------
--  §8 Exercise the theorem on NetDepthMerged §7's computed
--  instances: data/key levels zero and a host output at level 40.

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

  --  Compute unfused depth 42 for both cubes, independent of width.
  _ : maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                          (true ∷ false ∷ []) 0 4 5)))) ≡ 42
  _ = refl
  _ : maxL (runLevels lv3 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
                                          (true ∷ false ∷ true ∷ []) 0 6 7)))) ≡ 42
  _ = refl

  --  Instantiate the general result as 42 ≤ 42 for both two-
  --  and three-bit cubes, checking non-vacuity and attained bounds.
  unfused2 : maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                                 (true ∷ false ∷ []) 0 4 5)))) ≤ 42
  unfused2 = lockedBlock-depth-adds-2 lv2 (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) (true ∷ false ∷ []) 0 4 4 0
               (s≤s (s≤s (s≤s (s≤s z≤n)))) ≤-refl inputs2
               (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ [])
               (s≤s (s≤s (s≤s z≤n)) ∷ s≤s (s≤s (s≤s (s≤s z≤n))) ∷ [])
               (m≤n+m 21 19)

  unfused3 : maxL (runLevels lv3 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
                                                 (true ∷ false ∷ true ∷ []) 0 6 7)))) ≤ 42
  unfused3 = lockedBlock-depth-adds-2 lv3 (0 ∷ 1 ∷ 2 ∷ []) (3 ∷ 4 ∷ 5 ∷ [])
               (true ∷ false ∷ true ∷ []) 0 6 6 0
               (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n)))))) ≤-refl inputs3
               (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ s≤s (s≤s (s≤s z≤n)) ∷ [])
               (s≤s (s≤s (s≤s (s≤s z≤n))) ∷ s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))
                 ∷ s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))) ∷ [])
               (m≤n+m 27 13)

  --  Instantiate lockedBlock-vs-Merged: unfused depth is at most
  --  42 and fused depth at least 45, consistent with the computed
  --  42 versus 46 and giving a non-vacuous separation.
  contrast-2bit :
    maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                        (true ∷ false ∷ []) 0 4 5))))
      < maxL (runLevels lv2 (proj₂ (proj₂ (lockedBlockMerged (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                            (true ∷ false ∷ []) 4 5))))
  contrast-2bit =
    lockedBlock-vs-Merged lv2 (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) (true ∷ false ∷ []) 4 4 0
      (s≤s (s≤s (s≤s (s≤s z≤n)))) ≤-refl inputs2
      (s≤s z≤n ∷ s≤s (s≤s z≤n) ∷ [])
      (s≤s (s≤s (s≤s z≤n)) ∷ s≤s (s≤s (s≤s (s≤s z≤n))) ∷ [])
      (m≤n+m 21 19) ≤-refl (s≤s z≤n ∷ s≤s z≤n ∷ []) (s≤s z≤n)
