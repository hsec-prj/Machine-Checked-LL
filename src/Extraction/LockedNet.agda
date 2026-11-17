------------------------------------------------------------------------
--  Verify a flat keyed locked netlist (M1 stage B).
--  Netlist/NetlistCorrect certify shared-wire popcountEqNet
--  for every N, but its inputs are fixed to 0..N-1.
--  Whole SFLL-HD emission needs sharing, since Circuit-to-Expr
--  emit duplicates fan-out and becomes impractical beyond c17,
--  and key input wires, since a fixed key permits constant
--  folding away the lock. Generalise the comparator to
--  arbitrary bs as popcountEqNetOn, proving it tests the
--  number of true bs wires against h by instantiating
--  fold-inv. Then compose the XOR prefix, two comparators,
--  and three-way XOR to denote locked h ksec key f x.
--  Reuse the 805-line all-N proof: fold-inv already accepts
--  an abstract input-wire list. Introduce no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockedNet where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; _<_; z≤n; s≤s; _≡ᵇ_)
open import Data.Nat.Properties
  using (+-identityʳ; ≤-trans; ≤-refl; n≤1+n; n<1+n; m≤m+n; +-mono-≤; +-comm)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_)
open import Data.List using (List; []; _∷_; _++_; replicate; length)
open import Data.List.Properties using (length-++; ++-assoc; ++-identityʳ; length-replicate)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst; subst₂)
open import Data.Vec using (Vec)
import Data.Vec as Vec
open import Data.String using (String)
open import SFLL.HammingDistance using (b2n; HD)
open import SFLL.HD using (prot; locked)
open import Extraction.NetDepthBuilder using (CntLaw; ret-cnt; fresh-cnt; »=-cnt)
open import Extraction.Netlist using (oConst)
open import Extraction.Render using (renderNet)

open import Extraction.Netlist using
  ( Op; oNot; oAnd; oXor; get; evalOp; runNet
  ; Builder; ret; _»=_; fresh; mkConst; mkNot; mkAnd
  ; nth; stepTh; foldlMB; upFrom )
open import Extraction.NetlistCorrect using (get-snoc-len; get-++-<; runNet-++; runNet-length; runNet-prefix; runNet-mono; out-eq; leb; AllLt; AllLt-mono; AllLt-replicate; sumB; nth-AllLt; fold-inv; read-th; foldlMB-cnt; nth-replicate; length-toList)

------------------------------------------------------------------------
--  §1 Establish sumB facts for true-bit counts on wire lists.

--  Bound the count by the number of summed wires.
sumB-bound : (env : List Bool) (bs : List ℕ) → sumB env bs ≤ length bs
sumB-bound env []       = z≤n
sumB-bound env (b ∷ bs) = +-mono-≤ b2n≤1 (sumB-bound env bs)
  where
    b2n≤1 : b2n (get env b) ≤ 1
    b2n≤1 with get env b
    ... | true  = s≤s z≤n
    ... | false = z≤n

--  Preserve counts on in-range wires when appending fresh values.
sumB-prefix : (env ext : List Bool) (bs : List ℕ) →
              AllLt (length env) bs →
              sumB (env ++ ext) bs ≡ sumB env bs
sumB-prefix env ext []       _        = refl
sumB-prefix env ext (b ∷ bs) (b< , r) =
  cong₂ _+_ (cong b2n (get-++-< env ext b b<)) (sumB-prefix env ext bs r)

------------------------------------------------------------------------
--  §2 Run the comparator on any input-wire list.

--  Use popBuilder's construction but fold over supplied bs
--  instead of upTo N, producing [count of true bs wires = h].
popOnBuilder : (bs : List ℕ) (h : ℕ) → Builder ℕ
popOnBuilder bs h =
  mkConst true  »= λ tw →
  mkConst false »= λ fw →
  foldlMB (stepTh tw) (tw ∷ replicate (length bs) fw) bs »= λ thF →
  mkNot (nth thF (suc h) fw) »= λ ng →
  mkAnd (nth thF h fw) ng

--  Return operations and output wire with fresh allocation beginning at start.
popcountEqNetOn : (bs : List ℕ) (h start : ℕ) → List Op × ℕ
popcountEqNetOn bs h start =
  let (outId , _ , ops) = popOnBuilder bs h start
  in ops , outId

------------------------------------------------------------------------
--  §3 With bs in range in env₀, prove the comparator
--  allocated after env₀ outputs [sumB env₀ bs = h].

popcountEqNetOn-correct :
  (bs : List ℕ) (h : ℕ) (env₀ : List Bool) →
  AllLt (length env₀) bs →
  let (ops , outId) = popcountEqNetOn bs h (length env₀)
  in get (runNet env₀ ops) outId ≡ (sumB env₀ bs ≡ᵇ h)
popcountEqNetOn-correct bs h env₀ allbs =
    trans (cong (λ l → get l outId) trace)
   (trans (cong (get (eN ++ (andVal ∷ []))) outId≡lenEN)
   (trans (get-snoc-len eN andVal)
   (trans (cong₂ _∧_ get-eN-nth get-eN-ng)
   (trans (cong₂ (λ a b → a ∧ not b) (rt h) (rt (suc h)))
          (out-eq h cnt)))))
  where
    L   = length env₀
    nb  = length bs
    cnt = sumB env₀ bs
    e1  = env₀ ++ (true ∷ [])
    e2  = e1 ++ (false ∷ [])
    th0 = L ∷ replicate nb (suc L)

    --  Name comparator components as in popBuilder's local decomposition.
    foldB   = foldlMB (stepTh L) th0 bs (suc (suc L))
    thF     = proj₁ foldB
    cF      = proj₁ (proj₂ foldB)
    foldOps = proj₂ (proj₂ foldB)
    eF      = runNet e2 foldOps
    outId   = proj₁ (popOnBuilder bs h L)

    len-e1 : length e1 ≡ suc L
    len-e1 = trans (length-++ env₀ {true ∷ []}) (+-comm L 1)
    len-e2 : length e2 ≡ suc (suc L)
    len-e2 = trans (length-++ e1 {false ∷ []})
                   (trans (cong (_+ 1) len-e1) (+-comm (suc L) 1))

    lenth0 : length th0 ≡ suc nb
    lenth0 = cong suc (length-replicate nb)

    tW≡ : get e2 L ≡ true
    tW≡ = trans (get-++-< e1 (false ∷ []) L (subst (L <_) (sym len-e1) (n<1+n L)))
                (get-snoc-len env₀ true)
    tW< : L < length e2
    tW< = subst (L <_) (sym len-e2) (s≤s (n≤1+n L))
    fW≡ : get e2 (suc L) ≡ false
    fW≡ = trans (cong (get e2) (sym len-e1)) (get-snoc-len e1 false)
    fW< : suc L < length e2
    fW< = subst (suc L <_) (sym len-e2) (n<1+n (suc L))

    allth0 : AllLt (length e2) th0
    allth0 = tW< , AllLt-replicate nb (suc L) (length e2) fW<
    allbs2 : AllLt (length e2) bs
    allbs2 = AllLt-mono (subst (L ≤_) (sym len-e2) (≤-trans (n≤1+n L) (n≤1+n (suc L)))) bs allbs

    inv0 : (j : ℕ) → j < suc nb → get e2 (nth th0 j (suc L)) ≡ leb j 0
    inv0 zero    _       = tW≡
    inv0 (suc m) (s≤s e) =
      trans (cong (get e2) (nth-replicate nb (suc L) m (suc L) e)) fW≡

    FI = fold-inv nb L (suc L) bs th0 0 e2 (suc (suc L))
                  len-e2 lenth0 tW≡ tW< fW≡ fW< allth0 allbs2 inv0
    FI2    = proj₁ FI
    FI-len = proj₁ (proj₂ FI)
    FI-all = proj₁ (proj₂ (proj₂ FI))
    FI-fW  = proj₁ (proj₂ (proj₂ (proj₂ (proj₂ FI))))
    FI-inv = proj₂ (proj₂ (proj₂ (proj₂ (proj₂ FI))))

    count0 : 0 + sumB e2 bs ≡ cnt
    count0 = trans (sumB-prefix e1 (false ∷ []) bs
                      (AllLt-mono (subst (L ≤_) (sym len-e1) (n≤1+n L)) bs allbs))
                   (sumB-prefix env₀ (true ∷ []) bs allbs)

    invW : (j : ℕ) → j < suc nb → get eF (nth thF j (suc L)) ≡ leb j cnt
    invW j j< = trans (FI-inv j j<) (cong (leb j) count0)

    rt : (j : ℕ) → get eF (nth thF j (suc L)) ≡ leb j cnt
    rt = read-th nb (suc L) eF thF cnt FI-len FI-fW (sumB-bound env₀ bs) invW

    leneF≡cF : length eF ≡ cF
    leneF≡cF = trans (runNet-length e2 foldOps)
                     (trans (cong (_+ length foldOps) len-e2)
                            (sym (foldlMB-cnt L th0 bs (suc (suc L)))))

    notVal : Bool
    notVal = not (get eF (nth thF (suc h) (suc L)))
    eN     = eF ++ (notVal ∷ [])
    andVal : Bool
    andVal = get eN (nth thF h (suc L)) ∧ get eN cF

    sucL<eF : suc L < length eF
    sucL<eF = ≤-trans fW< FI2

    lenEN : length eN ≡ suc cF
    lenEN = trans (length-++ eF {notVal ∷ []})
                  (trans (+-comm (length eF) 1) (cong suc leneF≡cF))
    outId≡lenEN : outId ≡ length eN
    outId≡lenEN = sym lenEN

    trace : runNet env₀ (proj₂ (proj₂ (popOnBuilder bs h L)))
              ≡ eN ++ (andVal ∷ [])
    trace = runNet-++ e2 foldOps
              (oNot (nth thF (suc h) (suc L)) ∷ oAnd (nth thF h (suc L)) cF ∷ [])

    get-eN-nth : get eN (nth thF h (suc L)) ≡ get eF (nth thF h (suc L))
    get-eN-nth = get-++-< eF (notVal ∷ []) (nth thF h (suc L))
                          (nth-AllLt thF h (suc L) FI-all sucL<eF)
    get-eN-ng : get eN cF ≡ not (get eF (nth thF (suc h) (suc L)))
    get-eN-ng = trans (cong (get eN) (sym leneF≡cF)) (get-snoc-len eF notVal)

------------------------------------------------------------------------
--  §4 Begin restore with one fresh XOR wire per data/key pair.

--  Count pairwise x_i xor key_i values from two wire lists in env.
sumXorL : List Bool → List ℕ → List ℕ → ℕ
sumXorL env []       _        = 0
sumXorL env (_ ∷ _)  []       = 0
sumXorL env (a ∷ as) (b ∷ bs) = b2n (get env a xor get env b) + sumXorL env as bs

--  Retain values of in-range wires after environment extension.
sumXorL-prefix : (env ext : List Bool) (as bs : List ℕ) →
                 AllLt (length env) as → AllLt (length env) bs →
                 sumXorL (env ++ ext) as bs ≡ sumXorL env as bs
sumXorL-prefix env ext []       _        _         _         = refl
sumXorL-prefix env ext (a ∷ _)  []       _         _         = refl
sumXorL-prefix env ext (a ∷ as) (b ∷ bs) (a< , ra) (b< , rb) =
  cong₂ _+_ (cong b2n (cong₂ _xor_ (get-++-< env ext a a<) (get-++-< env ext b b<)))
            (sumXorL-prefix env ext as bs ra rb)

--  Emit one oXor x_i key_i per pair and return the output-wire list.
xorPairs : List ℕ → List ℕ → Builder (List ℕ)
xorPairs []       _        = ret []
xorPairs (a ∷ _)  []       = ret []
xorPairs (a ∷ as) (b ∷ bs) =
  fresh (oXor a b) »= λ w → xorPairs as bs »= λ ws → ret (w ∷ ws)

xorPairs-cnt : (as bs : List ℕ) → CntLaw (xorPairs as bs)
xorPairs-cnt []       bs       = ret-cnt {A = List ℕ} []
xorPairs-cnt (a ∷ _)  []       = ret-cnt {A = List ℕ} []
xorPairs-cnt (a ∷ as) (b ∷ bs) =
  »=-cnt (fresh (oXor a b))
         (λ w → xorPairs as bs »= λ ws → ret (w ∷ ws))
         (fresh-cnt (oXor a b))
         (λ w → »=-cnt (xorPairs as bs)
                       (λ ws → ret (w ∷ ws))
                       (xorPairs-cnt as bs)
                       (λ ws → ret-cnt (w ∷ ws)))

--  Verify the XOR prefix extends env with pairwise XORs,
--  preserves inherited wires, keeps outputs in range, and
--  makes their sum equal the Hamming distance.
xorPairs-spec : (as bs : List ℕ) (env : List Bool) (start : ℕ) →
  length env ≡ start →
  AllLt (length env) as → AllLt (length env) bs →
  let r    = xorPairs as bs start
      ws   = proj₁ r
      ops  = proj₂ (proj₂ r)
      env' = runNet env ops
  in (length env ≤ length env')
   × AllLt (length env') ws
   × ((w : ℕ) → w < length env → get env' w ≡ get env w)
   × (sumB env' ws ≡ sumXorL env as bs)
xorPairs-spec []       bs       env start _    _         _ =
  ≤-refl , _ , (λ w _ → refl) , refl
xorPairs-spec (a ∷ _)  []       env start _    _         _ =
  ≤-refl , _ , (λ w _ → refl) , refl
xorPairs-spec (a ∷ as) (b ∷ bs) env start lenEq (a< , ra) (b< , rb) =
    le , allws , presv , cnt
  where
    v    = get env a xor get env b
    env₁ = env ++ (v ∷ [])

    env≤env₁ : length env ≤ length env₁
    env≤env₁ = subst (length env ≤_) (sym (length-++ env {v ∷ []})) (m≤m+n (length env) 1)
    len₁ : length env₁ ≡ suc start
    len₁ = trans (length-++ env {v ∷ []}) (trans (cong (_+ 1) lenEq) (+-comm start 1))

    ra₁ = AllLt-mono env≤env₁ as ra
    rb₁ = AllLt-mono env≤env₁ bs rb

    --  Recurse in env₁ at suc start, the fresh allocator's next state.
    recR   = xorPairs as bs (suc start)
    recOps = proj₂ (proj₂ recR)
    envR   = runNet env₁ recOps

    IH = xorPairs-spec as bs env₁ (suc start) len₁ ra₁ rb₁
    IH1 = proj₁ IH
    IH2 = proj₁ (proj₂ IH)
    IH3 = proj₁ (proj₂ (proj₂ IH))
    IH4 = proj₂ (proj₂ (proj₂ IH))

    run-eq : runNet env (proj₂ (proj₂ (xorPairs (a ∷ as) (b ∷ bs) start))) ≡ envR
    run-eq = trans (runNet-++ env (oXor a b ∷ []) (recOps ++ []))
                   (cong (runNet env₁) (++-identityʳ recOps))

    le : length env ≤ length (runNet env (proj₂ (proj₂ (xorPairs (a ∷ as) (b ∷ bs) start))))
    le = subst (λ e → length env ≤ length e) (sym run-eq) (≤-trans env≤env₁ IH1)

    start<envR : start < length envR
    start<envR = ≤-trans (subst (start <_) (sym len₁) (n<1+n start)) IH1

    allws : AllLt (length (runNet env (proj₂ (proj₂ (xorPairs (a ∷ as) (b ∷ bs) start)))))
                  (proj₁ (xorPairs (a ∷ as) (b ∷ bs) start))
    allws = subst (λ e → AllLt (length e) (proj₁ (xorPairs (a ∷ as) (b ∷ bs) start)))
                  (sym run-eq) (start<envR , IH2)

    presv : (w : ℕ) → w < length env →
            get (runNet env (proj₂ (proj₂ (xorPairs (a ∷ as) (b ∷ bs) start)))) w ≡ get env w
    presv w w< =
      trans (cong (λ e → get e w) run-eq)
            (trans (IH3 w (≤-trans w< env≤env₁))
                   (get-++-< env (v ∷ []) w w<))

    vval : get envR start ≡ v
    vval = trans (IH3 start (subst (start <_) (sym len₁) (n<1+n start)))
                 (trans (cong (get env₁) (sym lenEq)) (get-snoc-len env v))

    cnt : sumB (runNet env (proj₂ (proj₂ (xorPairs (a ∷ as) (b ∷ bs) start))))
              (proj₁ (xorPairs (a ∷ as) (b ∷ bs) start))
            ≡ sumXorL env (a ∷ as) (b ∷ bs)
    cnt = trans (cong (λ e → sumB e (proj₁ (xorPairs (a ∷ as) (b ∷ bs) start))) run-eq)
                (cong₂ _+_ (cong b2n vval)
                           (trans IH4 (sumXorL-prefix env (v ∷ []) as bs ra rb)))

------------------------------------------------------------------------
--  §5 Compute [HD(x,key) = h] with the key supplied on input wires.

--  XOR the data/key pairs, then apply the comparator.
restoreNet : (xs keys : List ℕ) (h : ℕ) → Builder ℕ
restoreNet xs keys h = xorPairs xs keys »= λ rbits → popOnBuilder rbits h

--  Return restore-cone operations and output wire allocated from start.
restoreEqNet : (xs keys : List ℕ) (h start : ℕ) → List Op × ℕ
restoreEqNet xs keys h start =
  let (out , _ , ops) = restoreNet xs keys h start
  in ops , out

--  Prove restore computes [HD(x,key) = h], equivalently
--  [count of x⊕key = h], using keys input wires rather than constants.
restoreEqNet-correct :
  (xs keys : List ℕ) (h : ℕ) (env : List Bool) →
  AllLt (length env) xs → AllLt (length env) keys →
  let (ops , out) = restoreEqNet xs keys h (length env)
  in get (runNet env ops) out ≡ (sumXorL env xs keys ≡ᵇ h)
restoreEqNet-correct xs keys h env allxs allkeys =
    trans (cong (λ e → get e out) (runNet-++ env xops compOps))
   (trans (subst P lenEnvR (popcountEqNetOn-correct rbits h envR allrbits))
          (cong (_≡ᵇ h) (sumB-rbits)))
  where
    xr     = xorPairs xs keys (length env)
    rbits  = proj₁ xr
    i₁     = proj₁ (proj₂ xr)
    xops   = proj₂ (proj₂ xr)
    envR   = runNet env xops

    XS = xorPairs-spec xs keys env (length env) refl allxs allkeys
    allrbits : AllLt (length envR) rbits
    allrbits = proj₁ (proj₂ XS)
    sumB-rbits : sumB envR rbits ≡ sumXorL env xs keys
    sumB-rbits = proj₂ (proj₂ (proj₂ XS))

    lenEnvR : length envR ≡ i₁
    lenEnvR = trans (runNet-length env xops) (sym (xorPairs-cnt xs keys (length env)))

    compOps = proj₂ (proj₂ (popOnBuilder rbits h i₁))
    out     = proj₁ (popOnBuilder rbits h i₁)

    --  Transport popcountEqNetOn-correct from length envR to state i₁.
    P : ℕ → Set
    P s = get (runNet envR (proj₂ (proj₂ (popOnBuilder rbits h s))))
              (proj₁ (popOnBuilder rbits h s))
            ≡ (sumB envR rbits ≡ᵇ h)

------------------------------------------------------------------------
--  §6 Bridge wire readings to bit vectors and identify keyed counts with HD.

--  Define ReadsAs env ws vs by equality of wire ws !! i
--  and bit vs !! i at every index.
data ReadsAs (env : List Bool) : List ℕ → List Bool → Set where
  []ᴿ  : ReadsAs env [] []
  _∷ᴿ_ : ∀ {w v ws vs} → get env w ≡ v → ReadsAs env ws vs →
         ReadsAs env (w ∷ ws) (v ∷ vs)

--  When wires read x and key, equate their XOR count with Hamming distance.
sumXorL-HD : ∀ {n} (env : List Bool) (xs keys : List ℕ) (x key : Vec Bool n) →
             ReadsAs env xs (Vec.toList x) → ReadsAs env keys (Vec.toList key) →
             sumXorL env xs keys ≡ HD x key
sumXorL-HD env _ _ Vec.[]        Vec.[]        []ᴿ        []ᴿ        = refl
sumXorL-HD env _ _ (xv Vec.∷ xs) (yv Vec.∷ ys) (ex ∷ᴿ rx) (ey ∷ᴿ ry) =
  cong₂ _+_ (cong b2n (cong₂ _xor_ ex ey)) (sumXorL-HD env _ _ xs ys rx ry)

--  Read the first post-prefix wire at the prefix boundary.
get-at-len : (pre rest : List Bool) → get (pre ++ rest) (length pre) ≡ get rest 0
get-at-len []         rest = refl
get-at-len (p ∷ pre)  rest = get-at-len pre rest

--  Use upFrom |pre| |seg| to read seg from pre ++ seg ++ post.
reads-mid : (pre seg post : List Bool) →
            ReadsAs (pre ++ seg ++ post) (upFrom (length pre) (length seg)) seg
reads-mid pre []        post = []ᴿ
reads-mid pre (s ∷ seg) post =
  get-at-len pre ((s ∷ seg) ++ post)
    ∷ᴿ subst₂ (λ e o → ReadsAs e (upFrom o (length seg)) seg) eq leq
              (reads-mid (pre ++ s ∷ []) seg post)
  where
    eq : (pre ++ s ∷ []) ++ seg ++ post ≡ pre ++ (s ∷ seg) ++ post
    eq = trans (++-assoc pre (s ∷ []) (seg ++ post)) refl
    leq : length (pre ++ s ∷ []) ≡ suc (length pre)
    leq = trans (length-++ pre {s ∷ []}) (+-comm (length pre) 1)

------------------------------------------------------------------------
--  §7 Preserve inherited wires and their counts across sub-netlist execution.

--  Keep an in-range wire count unchanged when every referenced value is preserved.
sumXorL-pres : (e1 e2 : List Bool) (xs keys : List ℕ) (L : ℕ) →
               AllLt L xs → AllLt L keys →
               ((w : ℕ) → w < L → get e1 w ≡ get e2 w) →
               sumXorL e1 xs keys ≡ sumXorL e2 xs keys
sumXorL-pres e1 e2 []       _        L _         _         _ = refl
sumXorL-pres e1 e2 (a ∷ _)  []       L _         _         _ = refl
sumXorL-pres e1 e2 (a ∷ as) (b ∷ bs) L (a< , ra) (b< , rb) g =
  cong₂ _+_ (cong b2n (cong₂ _xor_ (g a a<) (g b b<)))
            (sumXorL-pres e1 e2 as bs L ra rb g)

--  Preserve ReadsAs through a sub-netlist for in-range read wires.
ReadsAs-runNet : (env : List Bool) (ops : List Op) (ws : List ℕ) (vs : List Bool) →
                 AllLt (length env) ws → ReadsAs env ws vs →
                 ReadsAs (runNet env ops) ws vs
ReadsAs-runNet env ops []       []       _         []ᴿ        = []ᴿ
ReadsAs-runNet env ops (w ∷ ws) (v ∷ vs) (w< , r) (e ∷ᴿ rest) =
  trans (runNet-prefix env ops w w<) e ∷ᴿ ReadsAs-runNet env ops ws vs r rest

------------------------------------------------------------------------
--  §8 Combine constant-secret perturbation, input-key restoration, and f by XOR.

--  Use CntLaw to align every stage's next identifier with its new environment length.
popOnBuilder-cnt : (bs : List ℕ) (h : ℕ) → CntLaw (popOnBuilder bs h)
popOnBuilder-cnt bs h =
  »=-cnt (mkConst true) (λ tw → mkConst false »= λ fw →
            foldlMB (stepTh tw) (tw ∷ replicate (length bs) fw) bs »= λ thF →
            mkNot (nth thF (suc h) fw) »= λ ng → mkAnd (nth thF h fw) ng)
         (fresh-cnt (oConst true))
    (λ tw → »=-cnt (mkConst false) (λ fw →
              foldlMB (stepTh tw) (tw ∷ replicate (length bs) fw) bs »= λ thF →
              mkNot (nth thF (suc h) fw) »= λ ng → mkAnd (nth thF h fw) ng)
           (fresh-cnt (oConst false))
      (λ fw → »=-cnt (foldlMB (stepTh tw) (tw ∷ replicate (length bs) fw) bs)
                (λ thF → mkNot (nth thF (suc h) fw) »= λ ng → mkAnd (nth thF h fw) ng)
                (foldlMB-cnt tw (tw ∷ replicate (length bs) fw) bs)
        (λ thF → »=-cnt (mkNot (nth thF (suc h) fw)) (λ ng → mkAnd (nth thF h fw) ng)
                   (fresh-cnt (oNot (nth thF (suc h) fw)))
          (λ ng → fresh-cnt (oAnd (nth thF h fw) ng)))))

restoreNet-cnt : (xs keys : List ℕ) (h : ℕ) → CntLaw (restoreNet xs keys h)
restoreNet-cnt xs keys h =
  »=-cnt (xorPairs xs keys) (λ rbits → popOnBuilder rbits h)
         (xorPairs-cnt xs keys) (λ rbits → popOnBuilder-cnt rbits h)

--  Allocate ksec constants so the perturb cone can reuse xorPairs.
constWires : List Bool → Builder (List ℕ)
constWires []       = ret []
constWires (b ∷ bs) = fresh (oConst b) »= λ w → constWires bs »= λ ws → ret (w ∷ ws)

constWires-cnt : (bs : List Bool) → CntLaw (constWires bs)
constWires-cnt []       = ret-cnt {A = List ℕ} []
constWires-cnt (b ∷ bs) =
  »=-cnt (fresh (oConst b)) (λ w → constWires bs »= λ ws → ret (w ∷ ws))
         (fresh-cnt (oConst b))
         (λ w → »=-cnt (constWires bs) (λ ws → ret (w ∷ ws))
                       (constWires-cnt bs) (λ ws → ret-cnt (w ∷ ws)))

--  Read the exact secret bits from the allocated, in-range constant wires.
constWires-spec : (bs : List Bool) (env : List Bool) (start : ℕ) → length env ≡ start →
  let r    = constWires bs start
      ws   = proj₁ r
      env' = runNet env (proj₂ (proj₂ r))
  in AllLt (length env') ws × ReadsAs env' ws bs
constWires-spec []       env start _     = _ , []ᴿ
constWires-spec (b ∷ bs) env start lenEq = allws , reads
  where
    env₁ = env ++ (b ∷ [])
    recOps = proj₂ (proj₂ (constWires bs (suc start)))
    len₁ : length env₁ ≡ suc start
    len₁ = trans (length-++ env {b ∷ []}) (trans (cong (_+ 1) lenEq) (+-comm start 1))
    envR = runNet env₁ recOps

    IH = constWires-spec bs env₁ (suc start) len₁
    IH-all = proj₁ IH
    IH-rd  = proj₂ IH

    run-eq : runNet env (proj₂ (proj₂ (constWires (b ∷ bs) start))) ≡ envR
    run-eq = trans (runNet-++ env (oConst b ∷ []) (recOps ++ []))
                   (cong (runNet env₁) (++-identityʳ recOps))

    start<envR : start < length envR
    start<envR = ≤-trans (subst (start <_) (sym len₁) (n<1+n start))
                         (runNet-mono env₁ recOps)

    headEq : get envR start ≡ b
    headEq = trans (runNet-prefix env₁ recOps
                      start (subst (start <_) (sym len₁) (n<1+n start)))
                   (trans (cong (get env₁) (sym lenEq)) (get-snoc-len env b))

    allws : AllLt (length (runNet env (proj₂ (proj₂ (constWires (b ∷ bs) start)))))
                  (proj₁ (constWires (b ∷ bs) start))
    allws = subst (λ e → AllLt (length e) (proj₁ (constWires (b ∷ bs) start)))
                  (sym run-eq) (start<envR , IH-all)

    reads : ReadsAs (runNet env (proj₂ (proj₂ (constWires (b ∷ bs) start))))
                    (proj₁ (constWires (b ∷ bs) start)) (b ∷ bs)
    reads = subst (λ e → ReadsAs e (proj₁ (constWires (b ∷ bs) start)) (b ∷ bs))
                  (sym run-eq) (headEq ∷ᴿ IH-rd)

--  Place the comparator output last, below the next free identifier.
popOnBuilder-out< : (bs : List ℕ) (h s : ℕ) →
                    proj₁ (popOnBuilder bs h s) < proj₁ (proj₂ (popOnBuilder bs h s))
popOnBuilder-out< bs h s = n<1+n (proj₁ (popOnBuilder bs h s))

restoreNet-out< : (xs keys : List ℕ) (h s : ℕ) →
                  proj₁ (restoreNet xs keys h s) < proj₁ (proj₂ (restoreNet xs keys h s))
restoreNet-out< xs keys h s =
  popOnBuilder-out< (proj₁ (xorPairs xs keys s)) h (proj₁ (proj₂ (xorPairs xs keys s)))

--  Build the keyed block as perturb(const ksec) ⊕ restore(input key) ⊕ f.
lockedBlock : (xs keys : List ℕ) (ksecBits : List Bool) (h fWire : ℕ) → Builder ℕ
lockedBlock xs keys ksecBits h fWire =
  constWires ksecBits »= λ kw →
  restoreNet xs kw h   »= λ pW →
  restoreNet xs keys h »= λ rW →
  fresh (oXor fWire pW) »= λ t →
  fresh (oXor t rW)

--  Return the locked block's operation list and output wire.
lockedBlockNet : (xs keys : List ℕ) (ksecBits : List Bool) (h fWire start : ℕ) → List Op × ℕ
lockedBlockNet xs keys ksecBits h fWire start =
  let (out , _ , ops) = lockedBlock xs keys ksecBits h fWire start
  in ops , out

--  With xs reading data, keys reading applied-key inputs,
--  ksec embedded as constants, and fWire holding f x,
--  prove the emitted block computes
--  (f x ⊕ [HD(x,ksec)=h]) ⊕ [HD(x,key)=h],
--  exactly locked h ksec key f x.
lockedBlock-correct :
  (xs keys : List ℕ) {n : ℕ} (x key ksec : Vec Bool n) (h fWire : ℕ) (env : List Bool) →
  AllLt (length env) xs → AllLt (length env) keys → fWire < length env →
  ReadsAs env xs (Vec.toList x) → ReadsAs env keys (Vec.toList key) →
  let (out , _ , ops) = lockedBlock xs keys (Vec.toList ksec) h fWire (length env)
  in get (runNet env ops) out
       ≡ (get env fWire xor prot h ksec x) xor prot h key x
lockedBlock-correct xs keys x key ksec h fWire env allxs allkeys fWire< xsReads keysReads =
    trans voChain finalEq
  where
    E     = length env
    ksecL = Vec.toList ksec
    --  Stage C: allocate the ksec constants.
    kw    = proj₁ (constWires ksecL E)
    iC    = proj₁ (proj₂ (constWires ksecL E))
    cOps  = proj₂ (proj₂ (constWires ksecL E))
    env₁  = runNet env cOps
    --  Stage P: compare xs with constant-key wires kw for perturbation.
    pW    = proj₁ (restoreNet xs kw h iC)
    iP    = proj₁ (proj₂ (restoreNet xs kw h iC))
    pOps  = proj₂ (proj₂ (restoreNet xs kw h iC))
    env₂  = runNet env₁ pOps
    --  Stage R: compare xs with input-key wires keys for restoration.
    rW    = proj₁ (restoreNet xs keys h iP)
    iR    = proj₁ (proj₂ (restoreNet xs keys h iP))
    rOps  = proj₂ (proj₂ (restoreNet xs keys h iP))
    env₃  = runNet env₂ rOps
    --  Append the two output XORs.
    vt    = evalOp env₃ (oXor fWire pW)
    env₄  = env₃ ++ (vt ∷ [])
    vo    = evalOp env₄ (oXor iR rW)
    env₅  = env₄ ++ (vo ∷ [])
    fullOps = proj₂ (proj₂ (lockedBlock xs keys ksecL h fWire E))
    out     = proj₁ (lockedBlock xs keys ksecL h fWire E)

    --  Establish nondecreasing environment length at every stage.
    E≤1 = runNet-mono env  cOps
    E≤2 = ≤-trans E≤1 (runNet-mono env₁ pOps)
    E≤3 = ≤-trans E≤2 (runNet-mono env₂ rOps)

    --  Align states and lengths through CntLaw and runNet-length.
    iC≡ : iC ≡ length env₁
    iC≡ = trans (constWires-cnt ksecL E) (sym (runNet-length env cOps))
    iP≡ : iP ≡ length env₂
    iP≡ = trans (restoreNet-cnt xs kw h iC)
                (trans (cong (_+ length pOps) iC≡) (sym (runNet-length env₁ pOps)))
    iR≡ : iR ≡ length env₃
    iR≡ = trans (restoreNet-cnt xs keys h iP)
                (trans (cong (_+ length rOps) iP≡) (sym (runNet-length env₂ rOps)))

    --  Peel four concatenated blocks to identify full execution with env₅.
    runEq : runNet env fullOps ≡ env₅
    runEq = trans (runNet-++ env cOps (pOps ++ rOps ++ (oXor fWire pW ∷ []) ++ (oXor iR rW ∷ [])))
            (trans (runNet-++ env₁ pOps (rOps ++ (oXor fWire pW ∷ []) ++ (oXor iR rW ∷ [])))
            (trans (runNet-++ env₂ rOps ((oXor fWire pW ∷ []) ++ (oXor iR rW ∷ [])))
                   (runNet-++ env₃ (oXor fWire pW ∷ []) (oXor iR rW ∷ []))))

    --  Identify the final allocated output wire as length env₄.
    out≡len4 : out ≡ length env₄
    out≡len4 = trans (cong suc iR≡) (sym (trans (length-++ env₃ {vt ∷ []}) (+-comm (length env₃) 1)))

    voChain : get (runNet env fullOps) out ≡ vo
    voChain = trans (cong (λ e → get e out) runEq)
                    (trans (cong (get env₅) out≡len4) (get-snoc-len env₄ vo))

    --  Transport fWire's value back to the initial environment.
    fWire<1 = ≤-trans fWire< E≤1
    fWire<2 = ≤-trans fWire< E≤2
    fWirePres : get env₃ fWire ≡ get env fWire
    fWirePres = trans (runNet-prefix env₂ rOps fWire fWire<2)
                (trans (runNet-prefix env₁ pOps fWire fWire<1)
                       (runNet-prefix env cOps fWire fWire<))

    --  Identify perturbation with prot h ksec x.
    csC = constWires-spec ksecL env E refl
    allkw   : AllLt (length env₁) kw
    allkw   = proj₁ csC
    kwReads : ReadsAs env₁ kw ksecL
    kwReads = proj₂ csC
    allxs₁  = AllLt-mono E≤1 xs allxs
    xsReads₁ = ReadsAs-runNet env cOps xs (Vec.toList x) allxs xsReads

    Pp : ℕ → Set
    Pp s = get (runNet env₁ (proj₂ (proj₂ (restoreNet xs kw h s))))
               (proj₁ (restoreNet xs kw h s))
             ≡ (sumXorL env₁ xs kw ≡ᵇ h)
    pCorrect : get env₂ pW ≡ (sumXorL env₁ xs kw ≡ᵇ h)
    pCorrect = subst Pp (sym iC≡) (restoreEqNet-correct xs kw h env₁ allxs₁ allkw)
    pW<2 : pW < length env₂
    pW<2 = subst (pW <_) iP≡ (restoreNet-out< xs kw h iC)
    pProt : get env₃ pW ≡ prot h ksec x
    pProt = trans (runNet-prefix env₂ rOps pW pW<2)
                  (trans pCorrect (cong (_≡ᵇ h) (sumXorL-HD env₁ xs kw x ksec xsReads₁ kwReads)))

    --  Identify restoration with prot h key x.
    allxs₂   = AllLt-mono E≤2 xs allxs
    allkeys₂ = AllLt-mono E≤2 keys allkeys
    xsReads₂ = ReadsAs-runNet env₁ pOps xs (Vec.toList x)
                 allxs₁ xsReads₁
    keysReads₁ = ReadsAs-runNet env cOps keys (Vec.toList key) allkeys keysReads
    keysReads₂ = ReadsAs-runNet env₁ pOps keys (Vec.toList key)
                   (AllLt-mono E≤1 keys allkeys) keysReads₁

    Pr : ℕ → Set
    Pr s = get (runNet env₂ (proj₂ (proj₂ (restoreNet xs keys h s))))
               (proj₁ (restoreNet xs keys h s))
             ≡ (sumXorL env₂ xs keys ≡ᵇ h)
    rCorrect : get env₃ rW ≡ (sumXorL env₂ xs keys ≡ᵇ h)
    rCorrect = subst Pr (sym iP≡) (restoreEqNet-correct xs keys h env₂ allxs₂ allkeys₂)
    rProt : get env₃ rW ≡ prot h key x
    rProt = trans rCorrect (cong (_≡ᵇ h) (sumXorL-HD env₂ xs keys x key xsReads₂ keysReads₂))

    --  Combine the two XOR results.
    getEnv₄iR : get env₄ iR ≡ vt
    getEnv₄iR = trans (cong (get env₄) iR≡) (get-snoc-len env₃ vt)
    rW<3 : rW < length env₃
    rW<3 = subst (rW <_) iR≡ (restoreNet-out< xs keys h iP)
    getEnv₄rW : get env₄ rW ≡ get env₃ rW
    getEnv₄rW = get-++-< env₃ (vt ∷ []) rW rW<3
    vt-eq : vt ≡ (get env fWire xor prot h ksec x)
    vt-eq = cong₂ _xor_ fWirePres pProt

    finalEq : vo ≡ (get env fWire xor prot h ksec x) xor prot h key x
    finalEq = trans (cong₂ _xor_ getEnv₄iR getEnv₄rW)
                    (cong₂ _xor_ vt-eq rProt)

--  Under the required data/key/f readings, prove exact
--  denotation locked h ksec key f x. This shared-wire,
--  key-input counterpart of EfficientLock.locked-circuit-eff
--  certifies the actual artifact consumed by synthesis or SAT tooling.
lockedBlock-locked :
  (xs keys : List ℕ) {n : ℕ} (x key ksec : Vec Bool n) (h fWire : ℕ)
  (f : Vec Bool n → Bool) (env : List Bool) →
  AllLt (length env) xs → AllLt (length env) keys → fWire < length env →
  ReadsAs env xs (Vec.toList x) → ReadsAs env keys (Vec.toList key) →
  get env fWire ≡ f x →
  let (out , _ , ops) = lockedBlock xs keys (Vec.toList ksec) h fWire (length env)
  in get (runNet env ops) out ≡ locked h ksec key f x
lockedBlock-locked xs keys x key ksec h fWire f env axs aks fw< rx rk fEq =
  trans (lockedBlock-correct xs keys x key ksec h fWire env axs aks fw< rx rk)
        (cong (λ b → (b xor prot h ksec x) xor prot h key x) fEq)

------------------------------------------------------------------------
--  §9 Render the verified block as .bench with primary
--  wires x(0..n-1), key(n..2n-1), and f(2n). The key
--  remains an input and the secret is embedded; sharing
--  avoids fan-out expansion in the artifact certified by lockedBlock-locked.

lockedFlatBench : (n : ℕ) (ksecBits : List Bool) (h : ℕ) → String
lockedFlatBench n ksecBits h =
  let xs    = upFrom 0 n
      keys  = upFrom n n
      fWire = n + n
      (ops , out) = lockedBlockNet xs keys ksecBits h fWire (suc (n + n))
  in renderNet (suc (n + n)) ops out
