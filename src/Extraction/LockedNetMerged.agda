------------------------------------------------------------------------
--  Certify cube-fused keyed emission. The unfused lockedBlock
--  materialises ksec as constants and [HD(x,ksec)=h] as
--  an isolated comparator output before XORing it into f.
--  Those structural features expose a cube-supported node
--  to resynthesis or DIP/SAT removal. At h = 0 the
--  protected predicate is a minterm cube; use the identity
--  f xor (l ∧ L) ≡ if l then (f xor L) else f (†)
--  recursively, consuming each literal with a MUX carrying
--  the partially fused host value. No dedicated conjunction
--  wire is allocated. fuseXorCube-correct certifies f xor
--  ⋀ lits by instantiating NetlistCorrect.mkMux-run, not
--  trusting the rewrite. cubeLits-spec supplies direct wires
--  for true bits and inverters for false bits; cubeVal-HD0
--  identifies their conjunction with prot 0 ksec x.
--  fusedPerturb-noConst proves the entire perturb operation
--  list has no oConst, unlike constWires ksecBits.
--  lockedBlockMerged-correct/locked prove the full block
--  denotes locked 0 ksec key f x, matching the unfused
--  radius-zero result. §7's lockedBlockMerged-constVals
--  extends the structural claim to the whole block: for
--  all wiring, cubes, and starts, payloads are exactly
--  true ∷ false ∷ [], the restore comparator rails.
--  lockedBlockMerged-perturbPrefix also identifies a
--  nonempty constant-free prefix by concatenation reassociation.
--  The unfused lockedBlock-constVals instead gives ksecBits
--  followed by true,false,true,false, spelling out the secret.
--  §7d/§7e compare the same constVals observation: the fused
--  ksec-independent theorem gives identical payloads for
--  all cubes, while lockedBlock-constVals-determines-ksec
--  equates payload equality with cube equality without
--  even a same-length premise. Its inequality form
--  lockedBlock-constVals-reveals-ksec-gen specialises to
--  the original one-bit example. Scope covers functional
--  equivalence, no perturb-path constants, and the complete
--  block's constant locations. It does not prove that
--  no wire ever carries prot 0 ksec x, which also
--  depends on the host function. The unchanged restore
--  cone retains its key-independent two rails. Fusion
--  does not hide ksec: cubeLits' inverter polarities
--  still encode it. No attack-cost result is claimed.
--  Reuse LockedNet's restoreNet and correctness unchanged
--  as the basis of this additional emitter.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockedNetMerged where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; _<_; _≡ᵇ_)
open import Data.Nat.Properties using (≤-trans; ≤-refl; n<1+n; +-comm)
open import Data.Unit using (⊤; tt)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_)
open import Data.Bool.Properties using (xor-identityʳ; xor-comm; true-xor)
open import Data.List using (List; []; _∷_; _++_; length; map; replicate)
open import Data.Bool.ListAction using (and)
open import Data.List.Properties using
  ( length-++; ++-identityʳ; ++-assoc; ++-cancelʳ
  ; length-++-≤ˡ; length-++-≤ʳ )
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.List.Relation.Unary.All using (All)
  renaming ([] to []ᴬ; _∷_ to _∷ᴬ_)
open import Data.List.Relation.Unary.All.Properties using (++⁺)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; cong; cong₂; sym; trans; subst; module ≡-Reasoning)
open import Function.Bundles using (_⇔_; mk⇔)
open import Data.String using (String)
open import Data.Vec using (Vec)
import Data.Vec as Vec

open import SFLL.HammingDistance using (HD)
open import SFLL.HD using (prot; locked)
open import Extraction.NetDepthBuilder using (mkMux-cnt; CntLaw; ret-cnt; fresh-cnt; »=-cnt)
open import Extraction.Render using (renderNet)
open import Extraction.Netlist using
  ( Op; oConst; oNot; oAnd; oOr; oXor; get; evalOp; runNet
  ; Builder; ret; _»=_; fresh; mkNot; mkAnd; mkMux; upFrom
  ; mapMB; foldlMB; stepTh; zipL; tailL; nth )
open import Extraction.NetlistCorrect using (get-snoc-len; get-++-<; get-++-+k; runNet-++; runNet-length; runNet-prefix; runNet-mono; AllLt; AllLt-mono; muxB; muxB-true; muxB-false; mkMux-run)
open import Extraction.LockedNet using
  ( restoreNet; restoreNet-cnt; restoreNet-out<; restoreEqNet-correct
  ; ReadsAs; []ᴿ; _∷ᴿ_; ReadsAs-runNet; sumXorL; sumXorL-HD
  ; xorPairs; popOnBuilder; constWires; lockedBlock )

------------------------------------------------------------------------
--  §1 Prove the Boolean kernel of fusion identity (†).

--  Use b xor true ≡ not b to fuse an empty cube with one inverter.
xor-trueʳ : (b : Bool) → b xor true ≡ not b
xor-trueʳ b = trans (xor-comm b true) (true-xor b)

--  Express (†) through muxB: selecting fused p xor q
--  or bare p computes p xor (b ∧ q). The constructed
--  side never introduces q alone as a separate gate input.
mux-fuse : (b p q : Bool) → muxB b p (p xor q) ≡ p xor (b ∧ q)
mux-fuse false p q = trans (muxB-false p (p xor q)) (sym (xor-identityʳ p))
mux-fuse true  p q = muxB-true p (p xor q)

------------------------------------------------------------------------
--  §2 Emit f xor ⋀ lits without a dedicated ⋀ lits wire.

--  Use a four-gate MUX per literal while recursively
--  carrying the partially fused value, never materialising the cube.
fuseXorCube : (fWire : ℕ) (lits : List ℕ) → Builder ℕ
fuseXorCube f []       = mkNot f
fuseXorCube f (l ∷ ls) = fuseXorCube f ls »= λ g → mkMux l f g

--  Prove the counter law with one fresh wire per operation.
fuseXorCube-cnt : (f : ℕ) (lits : List ℕ) → CntLaw (fuseXorCube f lits)
fuseXorCube-cnt f []       = fresh-cnt (oNot f)
fuseXorCube-cnt f (l ∷ ls) =
  »=-cnt (fuseXorCube f ls) (λ g → mkMux l f g)
         (fuseXorCube-cnt f ls) (λ g → mkMux-cnt l f g)

--  Identify the output as the final allocated wire.
fuseXorCube-out< : (f : ℕ) (lits : List ℕ) (s : ℕ) →
                   proj₁ (fuseXorCube f lits s) < proj₁ (proj₂ (fuseXorCube f lits s))
fuseXorCube-out< f []       s = n<1+n s
fuseXorCube-out< f (l ∷ ls) s = n<1+n (proj₁ (fuseXorCube f (l ∷ ls) s))

--  Equate the produced environment length with the final builder counter.
fuseXorCube-len : (f : ℕ) (lits : List ℕ) (env : List Bool) →
  length (runNet env (proj₂ (proj₂ (fuseXorCube f lits (length env)))))
    ≡ proj₁ (proj₂ (fuseXorCube f lits (length env)))
fuseXorCube-len f lits env =
  trans (runNet-length env (proj₂ (proj₂ (fuseXorCube f lits (length env)))))
        (sym (fuseXorCube-cnt f lits (length env)))

--  Prove the fused cone's denotation is f xor ⋀ lits.
fuseXorCube-correct :
  (fWire : ℕ) (lits : List ℕ) (env : List Bool) →
  fWire < length env → AllLt (length env) lits →
  let (out , _ , ops) = fuseXorCube fWire lits (length env)
  in get (runNet env ops) out ≡ get env fWire xor and (map (get env) lits)
fuseXorCube-correct fWire []       env fW< _ =
  trans (get-snoc-len env (not (get env fWire))) (sym (xor-trueʳ (get env fWire)))
fuseXorCube-correct fWire (l ∷ ls) env fW< (l< , alls) =
    trans (cong (λ e → get e out) runEq)
   (trans (cong (get (envG ++ vals)) out≡)
   (trans (get-++-+k envG vals 3)
   (trans (trans (cong (λ z → muxB z (get envG fWire) (get envG g)) lPres)
                 (cong₂ (muxB (get env l)) fPres gVal))
          (mux-fuse (get env l) (get env fWire) (and (map (get env) ls))))))
  where
    L      = length env
    recR   = fuseXorCube fWire ls L
    g      = proj₁ recR
    iC     = proj₁ (proj₂ recR)
    recOps = proj₂ (proj₂ recR)
    envG   = runNet env recOps

    muxOps = proj₂ (proj₂ (mkMux l fWire g iC))
    out    = proj₁ (fuseXorCube fWire (l ∷ ls) L)

    vals : List Bool
    vals = not (get envG l)
         ∷ (get envG fWire ∧ not (get envG l))
         ∷ (get envG g ∧ get envG l)
         ∷ muxB (get envG l) (get envG fWire) (get envG g)
         ∷ []

    iC≡ : iC ≡ length envG
    iC≡ = sym (fuseXorCube-len fWire ls env)

    --  Locate the output at offset three past the pre-MUX environment.
    out≡ : out ≡ 3 + length envG
    out≡ = cong (λ n → suc (suc (suc n))) iC≡

    E≤G : length env ≤ length envG
    E≤G = runNet-mono env recOps

    f<G : fWire < length envG
    f<G = ≤-trans fW< E≤G
    l<G : l < length envG
    l<G = ≤-trans l< E≤G
    g<G : g < length envG
    g<G = subst (g <_) iC≡ (fuseXorCube-out< fWire ls L)

    --  Transport exact MUX execution from environment-length
    --  allocation to the builder's counter.
    Qm : ℕ → Set
    Qm s = runNet envG (proj₂ (proj₂ (mkMux l fWire g s))) ≡ envG ++ vals
    muxRun : runNet envG muxOps ≡ envG ++ vals
    muxRun = subst Qm (sym iC≡) (mkMux-run l fWire g envG f<G g<G l<G)

    runEq : runNet env (proj₂ (proj₂ (fuseXorCube fWire (l ∷ ls) L))) ≡ envG ++ vals
    runEq = trans (runNet-++ env recOps muxOps) muxRun

    lPres : get envG l ≡ get env l
    lPres = runNet-prefix env recOps l l<
    fPres : get envG fWire ≡ get env fWire
    fPres = runNet-prefix env recOps fWire fW<
    gVal : get envG g ≡ get env fWire xor and (map (get env) ls)
    gVal = fuseXorCube-correct fWire ls env fW< alls

------------------------------------------------------------------------
--  §3 Emit cube literals as wires: true reuses a data
--  wire with no gate; false inserts an inverter. With
--  no constants, ksec remains represented by inverter polarities.

--  Test in Bool whether value v matches cube bit b.
lit : Bool → Bool → Bool
lit true  v = v
lit false v = not v

--  Evaluate a cube on a bit list, returning true exactly when all positions match.
cubeVal : List Bool → List Bool → Bool
cubeVal []       _        = true
cubeVal (v ∷ vs) []       = true
cubeVal (v ∷ vs) (b ∷ bs) = lit b v ∧ cubeVal vs bs

--  Identify cube evaluation with the radius-zero protected predicate.
cubeVal-HD0 : ∀ {n} (x k : Vec Bool n) →
              cubeVal (Vec.toList x) (Vec.toList k) ≡ prot 0 k x
cubeVal-HD0 Vec.[]              Vec.[]              = refl
cubeVal-HD0 (true  Vec.∷ vs) (true  Vec.∷ bs) = cubeVal-HD0 vs bs
cubeVal-HD0 (true  Vec.∷ vs) (false Vec.∷ bs) = refl
cubeVal-HD0 (false Vec.∷ vs) (true  Vec.∷ bs) = refl
cubeVal-HD0 (false Vec.∷ vs) (false Vec.∷ bs) = cubeVal-HD0 vs bs

--  Emit one literal as either the data wire or its inversion.
litWire : Bool → ℕ → Builder ℕ
litWire true  x = ret x
litWire false x = mkNot x

litWire-cnt : (b : Bool) (x : ℕ) → CntLaw (litWire b x)
litWire-cnt true  x = ret-cnt x
litWire-cnt false x = fresh-cnt (oNot x)

cubeLits : (xs : List ℕ) (bits : List Bool) → Builder (List ℕ)
cubeLits []       _        = ret []
cubeLits (x ∷ xs) []       = ret []
cubeLits (x ∷ xs) (b ∷ bs) =
  litWire b x »= λ w → cubeLits xs bs »= λ ws → ret (w ∷ ws)

cubeLits-cnt : (xs : List ℕ) (bits : List Bool) → CntLaw (cubeLits xs bits)
cubeLits-cnt []       bits     = ret-cnt {A = List ℕ} []
cubeLits-cnt (x ∷ xs) []       = ret-cnt {A = List ℕ} []
cubeLits-cnt (x ∷ xs) (b ∷ bs) =
  »=-cnt (litWire b x) (λ w → cubeLits xs bs »= λ ws → ret (w ∷ ws))
         (litWire-cnt b x)
         (λ w → »=-cnt (cubeLits xs bs) (λ ws → ret (w ∷ ws))
                       (cubeLits-cnt xs bs) (λ ws → ret-cnt (w ∷ ws)))

--  Keep emitted literal wires in range and equate their
--  conjunction with the cube evaluated on data read by xs.
cubeLits-spec :
  (xs : List ℕ) (bits vs : List Bool) (env : List Bool) (start : ℕ) →
  length env ≡ start → AllLt (length env) xs → ReadsAs env xs vs →
  let r    = cubeLits xs bits start
      ws   = proj₁ r
      env' = runNet env (proj₂ (proj₂ r))
  in AllLt (length env') ws × (and (map (get env') ws) ≡ cubeVal vs bits)
cubeLits-spec []       bits         _        env start refl _            []ᴿ =
  tt , refl
cubeLits-spec (x ∷ xs) []           (v ∷ vs) env start refl _            (hd ∷ᴿ rd) =
  tt , refl
cubeLits-spec (x ∷ xs) (true ∷ bs)  (v ∷ vs) env start refl (x< , allxs) (hd ∷ᴿ rd) =
    ( ≤-trans x< (runNet-mono env fullOps)
    , subst (λ e → AllLt (length e) ws') (sym run-eq) IH-all )
  , trans (cong (λ e → and (map (get e) (x ∷ ws'))) run-eq)
          (cong₂ _∧_ (trans (runNet-prefix env recOps x x<) hd) IH-val)
  where
    L       = length env
    recR    = cubeLits xs bs L
    ws'     = proj₁ recR
    recOps  = proj₂ (proj₂ recR)
    envR    = runNet env recOps
    fullOps = proj₂ (proj₂ (cubeLits (x ∷ xs) (true ∷ bs) L))

    run-eq : runNet env fullOps ≡ envR
    run-eq = cong (runNet env) (++-identityʳ recOps)

    IH = cubeLits-spec xs bs vs env L refl allxs rd
    IH-all = proj₁ IH
    IH-val = proj₂ IH
cubeLits-spec (x ∷ xs) (false ∷ bs) (v ∷ vs) env start refl (x< , allxs) (hd ∷ᴿ rd) =
    ( subst (λ e → length env < length e) (sym run-eq)
            (≤-trans L<env₁ (runNet-mono env₁ recOps))
    , subst (λ e → AllLt (length e) ws') (sym run-eq) IH-all )
  , trans (cong (λ e → and (map (get e) (L ∷ ws'))) run-eq)
          (cong₂ _∧_ headVal IH-val)
  where
    L    = length env
    v0   = not (get env x)
    env₁ = env ++ (v0 ∷ [])

    len₁ : length env₁ ≡ suc L
    len₁ = trans (length-++ env {v0 ∷ []}) (+-comm L 1)
    L<env₁ : L < length env₁
    L<env₁ = subst (L <_) (sym len₁) (n<1+n L)
    E≤1 : length env ≤ length env₁
    E≤1 = runNet-mono env (oNot x ∷ [])

    recR    = cubeLits xs bs (suc L)
    ws'     = proj₁ recR
    recOps  = proj₂ (proj₂ recR)
    envR    = runNet env₁ recOps
    fullOps = proj₂ (proj₂ (cubeLits (x ∷ xs) (false ∷ bs) L))

    run-eq : runNet env fullOps ≡ envR
    run-eq = trans (runNet-++ env (oNot x ∷ []) (recOps ++ []))
                   (cong (runNet env₁) (++-identityʳ recOps))

    IH = cubeLits-spec xs bs vs env₁ (suc L) len₁
           (AllLt-mono E≤1 xs allxs)
           (ReadsAs-runNet env (oNot x ∷ []) xs vs allxs rd)
    IH-all = proj₁ IH
    IH-val = proj₂ IH

    headVal : get envR L ≡ not v
    headVal = trans (runNet-prefix env₁ recOps L L<env₁)
                    (trans (get-snoc-len env v0) (cong not hd))

------------------------------------------------------------------------
--  §4 Prove a structural gate-list property: the fused
--  perturb path has no constants. The unfused |ksec|
--  constant wires feed a comparator, exposing a pattern
--  to constant folding and structural reading. Fusion
--  uses only inverters and MUX blocks, leaving ksec in
--  polarity rather than constants; this concerns syntax, not denotation.

isConst : Op → Bool
isConst (oConst _) = true
isConst _          = false

NoConst : List Op → Set
NoConst = All (λ o → isConst o ≡ false)

mkMux-noConst : (s a b i : ℕ) → NoConst (proj₂ (proj₂ (mkMux s a b i)))
mkMux-noConst s a b i = refl ∷ᴬ refl ∷ᴬ refl ∷ᴬ refl ∷ᴬ []ᴬ

fuseXorCube-noConst : (f : ℕ) (lits : List ℕ) (i : ℕ) →
                      NoConst (proj₂ (proj₂ (fuseXorCube f lits i)))
fuseXorCube-noConst f []       i = refl ∷ᴬ []ᴬ
fuseXorCube-noConst f (l ∷ ls) i =
  ++⁺ (fuseXorCube-noConst f ls i)
      (mkMux-noConst l f (proj₁ (fuseXorCube f ls i))
                         (proj₁ (proj₂ (fuseXorCube f ls i))))

cubeLits-noConst : (xs : List ℕ) (bits : List Bool) (i : ℕ) →
                   NoConst (proj₂ (proj₂ (cubeLits xs bits i)))
cubeLits-noConst []       bits         i = []ᴬ
cubeLits-noConst (x ∷ xs) []           i = []ᴬ
cubeLits-noConst (x ∷ xs) (true ∷ bs)  i = ++⁺ (cubeLits-noConst xs bs i) []ᴬ
cubeLits-noConst (x ∷ xs) (false ∷ bs) i =
  refl ∷ᴬ ++⁺ (cubeLits-noConst xs bs (suc i)) []ᴬ

--  Show cube literals followed by fusion remain constant-free.
fusedPerturb-noConst : (xs : List ℕ) (ksecBits : List Bool) (fWire i : ℕ) →
  NoConst (proj₂ (proj₂ ((cubeLits xs ksecBits »= λ lits →
                          fuseXorCube fWire lits) i)))
fusedPerturb-noConst xs ksecBits fWire i =
  ++⁺ (cubeLits-noConst xs ksecBits i)
      (fuseXorCube-noConst fWire (proj₁ (cubeLits xs ksecBits i))
                                 (proj₁ (proj₂ (cubeLits xs ksecBits i))))

------------------------------------------------------------------------
--  §5 Match lockedBlock's interface and radius-zero
--  denotation while fusing perturbation into f instead
--  of emitting an isolated constant-key comparator.

lockedBlockMerged : (xs keys : List ℕ) (ksecBits : List Bool) (fWire : ℕ) → Builder ℕ
lockedBlockMerged xs keys ksecBits fWire =
  cubeLits xs ksecBits   »= λ lits →
  fuseXorCube fWire lits »= λ t →
  restoreNet xs keys 0   »= λ rW →
  fresh (oXor t rW)

--  Return fused-block operations and its output wire.
lockedBlockMergedNet : (xs keys : List ℕ) (ksecBits : List Bool)
                       (fWire start : ℕ) → List Op × ℕ
lockedBlockMergedNet xs keys ksecBits fWire start =
  let (out , _ , ops) = lockedBlockMerged xs keys ksecBits fWire start
  in ops , out

--  Prove (f x ⊕ [HD(x,ksec)=0]) ⊕ [HD(x,key)=0],
--  matching lockedBlock-correct at h = 0, from a
--  perturb path allocating neither a cube wire nor,
--  by fusedPerturb-noConst, a constant gate.
lockedBlockMerged-correct :
  (xs keys : List ℕ) {n : ℕ} (x key ksec : Vec Bool n) (fWire : ℕ) (env : List Bool) →
  AllLt (length env) xs → AllLt (length env) keys → fWire < length env →
  ReadsAs env xs (Vec.toList x) → ReadsAs env keys (Vec.toList key) →
  let (out , _ , ops) = lockedBlockMerged xs keys (Vec.toList ksec) fWire (length env)
  in get (runNet env ops) out
       ≡ (get env fWire xor prot 0 ksec x) xor prot 0 key x
lockedBlockMerged-correct xs keys x key ksec fWire env allxs allkeys fWire<
                          xsReads keysReads =
    trans voChain finalEq
  where
    E     = length env
    ksecL = Vec.toList ksec
    --  Stage C: create cube literals using inverters only.
    lits  = proj₁ (cubeLits xs ksecL E)
    iC    = proj₁ (proj₂ (cubeLits xs ksecL E))
    cOps  = proj₂ (proj₂ (cubeLits xs ksecL E))
    env₁  = runNet env cOps
    --  Stage F: fuse f ⊕ cube without allocating a cube wire.
    t     = proj₁ (fuseXorCube fWire lits iC)
    iF    = proj₁ (proj₂ (fuseXorCube fWire lits iC))
    fOps  = proj₂ (proj₂ (fuseXorCube fWire lits iC))
    env₂  = runNet env₁ fOps
    --  Stage R: reuse restore unchanged on xs and applied-key input wires.
    rW    = proj₁ (restoreNet xs keys 0 iF)
    iR    = proj₁ (proj₂ (restoreNet xs keys 0 iF))
    rOps  = proj₂ (proj₂ (restoreNet xs keys 0 iF))
    env₃  = runNet env₂ rOps
    --  Append the final XOR.
    vo      = evalOp env₃ (oXor t rW)
    env₄    = env₃ ++ (vo ∷ [])
    fullOps = proj₂ (proj₂ (lockedBlockMerged xs keys ksecL fWire E))
    out     = proj₁ (lockedBlockMerged xs keys ksecL fWire E)

    --  Establish environment-length monotonicity stage by stage.
    E≤1 = runNet-mono env  cOps
    E≤2 = ≤-trans E≤1 (runNet-mono env₁ fOps)
    E≤3 = ≤-trans E≤2 (runNet-mono env₂ rOps)

    --  Align allocation states with lengths using CntLaw and runNet-length.
    iC≡ : iC ≡ length env₁
    iC≡ = trans (cubeLits-cnt xs ksecL E) (sym (runNet-length env cOps))
    iF≡ : iF ≡ length env₂
    iF≡ = trans (fuseXorCube-cnt fWire lits iC)
                (trans (cong (_+ length fOps) iC≡) (sym (runNet-length env₁ fOps)))
    iR≡ : iR ≡ length env₃
    iR≡ = trans (restoreNet-cnt xs keys 0 iF)
                (trans (cong (_+ length rOps) iF≡) (sym (runNet-length env₂ rOps)))

    --  Peel three concatenations to identify full execution with env₄.
    runEq : runNet env fullOps ≡ env₄
    runEq = trans (runNet-++ env cOps (fOps ++ rOps ++ (oXor t rW ∷ [])))
            (trans (runNet-++ env₁ fOps (rOps ++ (oXor t rW ∷ [])))
                   (runNet-++ env₂ rOps (oXor t rW ∷ [])))

    voChain : get (runNet env fullOps) out ≡ vo
    voChain = trans (cong (λ e → get e out) runEq)
                    (trans (cong (get env₄) iR≡) (get-snoc-len env₃ vo))

    --  Establish the perturbation component.
    CS = cubeLits-spec xs ksecL (Vec.toList x) env E refl allxs xsReads
    allLits : AllLt (length env₁) lits
    allLits = proj₁ CS
    cubeEq : and (map (get env₁) lits) ≡ cubeVal (Vec.toList x) ksecL
    cubeEq = proj₂ CS
    cubeProt : and (map (get env₁) lits) ≡ prot 0 ksec x
    cubeProt = trans cubeEq (cubeVal-HD0 x ksec)

    fWire<1 : fWire < length env₁
    fWire<1 = ≤-trans fWire< E≤1
    fPres : get env₁ fWire ≡ get env fWire
    fPres = runNet-prefix env cOps fWire fWire<

    Pf : ℕ → Set
    Pf s = get (runNet env₁ (proj₂ (proj₂ (fuseXorCube fWire lits s))))
               (proj₁ (fuseXorCube fWire lits s))
             ≡ get env₁ fWire xor and (map (get env₁) lits)
    tVal : get env₂ t ≡ get env₁ fWire xor and (map (get env₁) lits)
    tVal = subst Pf (sym iC≡) (fuseXorCube-correct fWire lits env₁ fWire<1 allLits)

    t<2 : t < length env₂
    t<2 = subst (t <_) iF≡ (fuseXorCube-out< fWire lits iC)
    tPres : get env₃ t ≡ get env₂ t
    tPres = runNet-prefix env₂ rOps t t<2

    --  Establish restoration using Extraction.LockedNet's result.
    allxs₂   = AllLt-mono E≤2 xs allxs
    allkeys₂ = AllLt-mono E≤2 keys allkeys
    xsReads₁ = ReadsAs-runNet env cOps xs (Vec.toList x) allxs xsReads
    xsReads₂ = ReadsAs-runNet env₁ fOps xs (Vec.toList x)
                 (AllLt-mono E≤1 xs allxs) xsReads₁
    keysReads₁ = ReadsAs-runNet env cOps keys (Vec.toList key) allkeys keysReads
    keysReads₂ = ReadsAs-runNet env₁ fOps keys (Vec.toList key)
                   (AllLt-mono E≤1 keys allkeys) keysReads₁

    Pr : ℕ → Set
    Pr s = get (runNet env₂ (proj₂ (proj₂ (restoreNet xs keys 0 s))))
               (proj₁ (restoreNet xs keys 0 s))
             ≡ (sumXorL env₂ xs keys ≡ᵇ 0)
    rCorrect : get env₃ rW ≡ (sumXorL env₂ xs keys ≡ᵇ 0)
    rCorrect = subst Pr (sym iF≡) (restoreEqNet-correct xs keys 0 env₂ allxs₂ allkeys₂)
    rProt : get env₃ rW ≡ prot 0 key x
    rProt = trans rCorrect
                  (cong (_≡ᵇ 0) (sumXorL-HD env₂ xs keys x key xsReads₂ keysReads₂))

    --  Combine the component results.
    finalEq : vo ≡ (get env fWire xor prot 0 ksec x) xor prot 0 key x
    finalEq = cong₂ _xor_ (trans tPres (trans tVal (cong₂ _xor_ fPres cubeProt)))
                          rProt

--  Prove the fused emitted netlist denotes locked 0
--  ksec key f x exactly, the same function certified
--  for the unfused block, with perturbation integrated into f.
lockedBlockMerged-locked :
  (xs keys : List ℕ) {n : ℕ} (x key ksec : Vec Bool n) (fWire : ℕ)
  (f : Vec Bool n → Bool) (env : List Bool) →
  AllLt (length env) xs → AllLt (length env) keys → fWire < length env →
  ReadsAs env xs (Vec.toList x) → ReadsAs env keys (Vec.toList key) →
  get env fWire ≡ f x →
  let (out , _ , ops) = lockedBlockMerged xs keys (Vec.toList ksec) fWire (length env)
  in get (runNet env ops) out ≡ locked 0 ksec key f x
lockedBlockMerged-locked xs keys x key ksec fWire f env axs aks fw< rx rk fEq =
  trans (lockedBlockMerged-correct xs keys x key ksec fWire env axs aks fw< rx rk)
        (cong (λ b → (b xor prot 0 ksec x) xor prot 0 key x) fEq)

------------------------------------------------------------------------
--  §6 Render the certified fused shared-wire block,
--  mirroring lockedFlatBench with primary wires
--  x(0..n-1), key(n..2n-1), and f(2n).

--  Check evaluation on a small instance: n = 2 and
--  ksec = 10 give prot 0 ksec x = x₀ ∧ ¬x₁.
--  Assign x₀=0,x₁=1,k₀=2,k₁=3,f=4 and allocate the lock from five.
private
  evalMerged : (x₀ x₁ k₀ k₁ fv : Bool) → Bool
  evalMerged x₀ x₁ k₀ k₁ fv =
    let (ops , out) = lockedBlockMergedNet (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                           (true ∷ false ∷ []) 4 5
    in get (runNet (x₀ ∷ x₁ ∷ k₀ ∷ k₁ ∷ fv ∷ []) ops) out

  --  With correct key 10, restore cancels strip and returns f.
  _ : evalMerged true false true false false ≡ false
  _ = refl
  _ : evalMerged true false true false true  ≡ true
  _ = refl
  --  With key 00 at the secret pattern, only strip is active.
  _ : evalMerged true false false false false ≡ true
  _ = refl
  --  With key 00 at its own protected pattern, only restore is active.
  _ : evalMerged false false false false false ≡ true
  _ = refl
  --  Outside both spheres, return f.
  _ : evalMerged false true true true true ≡ true
  _ = refl

lockedMergedFlatBench : (n : ℕ) (ksecBits : List Bool) → String
lockedMergedFlatBench n ksecBits =
  let xs    = upFrom 0 n
      keys  = upFrom n n
      fWire = n + n
      (ops , out) = lockedBlockMergedNet xs keys ksecBits fWire (suc (n + n))
  in renderNet (suc (n + n)) ops out

------------------------------------------------------------------------
--  §7 Lift the perturb-sub-builder result to the full
--  block. Its list is cOps ++ (fOps ++ (rOps ++ [oXor])),
--  so nondefinitional associativity prevents §4 alone
--  from identifying the full prefix. First prove
--  lockedBlockMerged-perturbPrefix by reassociation,
--  with a nonempty NoConst prefix. Then prove the
--  stronger global lockedBlockMerged-constVals: all
--  payloads are exactly true,false for every xs,keys,
--  ksecBits,fWire,start. State cube independence separately.
--  For the unfused emitter, lockedBlock-constVals gives
--  ksecBits followed by four rails; constCount grows
--  as |ksec|+4 rather than two, and distinct cubes
--  produce distinct payloads. These claims concern oConst
--  only: ksec still controls inverter polarity, and
--  no attack-cost or secret-hiding claim follows.
--  Fusion removes constant-based exposure of the isolated cone.

--  Read constant payloads from operations in emission order.
constVals : List Op → List Bool
constVals []              = []
constVals (oConst b ∷ os) = b ∷ constVals os
constVals (oNot _   ∷ os) = constVals os
constVals (oAnd _ _ ∷ os) = constVals os
constVals (oOr  _ _ ∷ os) = constVals os
constVals (oXor _ _ ∷ os) = constVals os

constVals-++ : (as bs : List Op) → constVals (as ++ bs) ≡ constVals as ++ constVals bs
constVals-++ []              bs = refl
constVals-++ (oConst b ∷ as) bs = cong (b ∷_) (constVals-++ as bs)
constVals-++ (oNot _   ∷ as) bs = constVals-++ as bs
constVals-++ (oAnd _ _ ∷ as) bs = constVals-++ as bs
constVals-++ (oOr  _ _ ∷ as) bs = constVals-++ as bs
constVals-++ (oXor _ _ ∷ as) bs = constVals-++ as bs

--  Equate NoConst with an empty constant-payload list.
noConst⇒constVals : {os : List Op} → NoConst os → constVals os ≡ []
noConst⇒constVals {[]}             _         = refl
noConst⇒constVals {oConst _ ∷ _}   (() ∷ᴬ _)
noConst⇒constVals {oNot _   ∷ os}  (_ ∷ᴬ ps) = noConst⇒constVals ps
noConst⇒constVals {oAnd _ _ ∷ os}  (_ ∷ᴬ ps) = noConst⇒constVals ps
noConst⇒constVals {oOr  _ _ ∷ os}  (_ ∷ᴬ ps) = noConst⇒constVals ps
noConst⇒constVals {oXor _ _ ∷ os}  (_ ∷ᴬ ps) = noConst⇒constVals ps

------------------------------------------------------------------------
--  §7a Locate exactly two restore constants, its true/false rails.

xorPairs-noConst : (as bs : List ℕ) (i : ℕ) →
                   NoConst (proj₂ (proj₂ (xorPairs as bs i)))
xorPairs-noConst []       bs       i = []ᴬ
xorPairs-noConst (a ∷ as) []       i = []ᴬ
xorPairs-noConst (a ∷ as) (b ∷ bs) i =
  refl ∷ᴬ ++⁺ (xorPairs-noConst as bs (suc i)) []ᴬ

--  Each thermometer stage/level emits a MUX block without constants.
mapMB-mux-noConst : (bit : ℕ) (ps : List (ℕ × ℕ)) (i : ℕ) →
  NoConst (proj₂ (proj₂ (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps i)))
mapMB-mux-noConst bit []       i = []ᴬ
mapMB-mux-noConst bit (p ∷ ps) i =
  ++⁺ (mkMux-noConst bit (proj₁ p) (proj₂ p) i)
      (++⁺ (mapMB-mux-noConst bit ps
              (proj₁ (proj₂ (mkMux bit (proj₁ p) (proj₂ p) i))))
           []ᴬ)

stepTh-noConst : (tw : ℕ) (th : List ℕ) (bit i : ℕ) →
                 NoConst (proj₂ (proj₂ (stepTh tw th bit i)))
stepTh-noConst tw th bit i = ++⁺ (mapMB-mux-noConst bit (zipL (tailL th) th) i) []ᴬ

foldlMB-stepTh-noConst : (tw : ℕ) (bs acc : List ℕ) (i : ℕ) →
  NoConst (proj₂ (proj₂ (foldlMB (stepTh tw) acc bs i)))
foldlMB-stepTh-noConst tw []       acc i = []ᴬ
foldlMB-stepTh-noConst tw (b ∷ bs) acc i =
  ++⁺ (stepTh-noConst tw acc b i)
      (foldlMB-stepTh-noConst tw bs (proj₁ (stepTh tw acc b i))
                                    (proj₁ (proj₂ (stepTh tw acc b i))))

--  Keep all comparator operations after its two rails constant-free.
popTail-noConst : (bs : List ℕ) (h tw fw i : ℕ) →
  NoConst (proj₂ (proj₂
    ((foldlMB (stepTh tw) (tw ∷ replicate (length bs) fw) bs »= λ thF →
      mkNot (nth thF (suc h) fw) »= λ ng →
      mkAnd (nth thF h fw) ng) i)))
popTail-noConst bs h tw fw i =
  ++⁺ (foldlMB-stepTh-noConst tw bs (tw ∷ replicate (length bs) fw) i)
      (refl ∷ᴬ refl ∷ᴬ []ᴬ)

--  Show the general comparator's constants are exactly true and false.
popOnBuilder-constVals : (bs : List ℕ) (h i : ℕ) →
  constVals (proj₂ (proj₂ (popOnBuilder bs h i))) ≡ true ∷ false ∷ []
popOnBuilder-constVals bs h i =
  cong (λ z → true ∷ false ∷ z)
       (noConst⇒constVals (popTail-noConst bs h i (suc i) (suc (suc i))))

--  Extend the two-rail result to restore at every radius
--  and start, since its XOR prefix introduces no constants.
restoreNet-constVals : (xs keys : List ℕ) (h i : ℕ) →
  constVals (proj₂ (proj₂ (restoreNet xs keys h i))) ≡ true ∷ false ∷ []
restoreNet-constVals xs keys h i = begin
    constVals (xOps ++ pOps)
      ≡⟨ constVals-++ xOps pOps ⟩
    constVals xOps ++ constVals pOps
      ≡⟨ cong (_++ constVals pOps) (noConst⇒constVals (xorPairs-noConst xs keys i)) ⟩
    constVals pOps
      ≡⟨ popOnBuilder-constVals rbits h iX ⟩
    true ∷ false ∷ []
      ∎
  where
    open ≡-Reasoning
    xR    = xorPairs xs keys i
    rbits = proj₁ xR
    iX    = proj₁ (proj₂ xR)
    xOps  = proj₂ (proj₂ xR)
    pOps  = proj₂ (proj₂ (popOnBuilder rbits h iX))

------------------------------------------------------------------------
--  §7b Rule out vacuous constant freedom. Although
--  NoConst [] is trivial, fuseXorCube always ends in
--  an inverter, leaving at least one perturb-path gate.

fuseXorCube-nonempty : (f : ℕ) (lits : List ℕ) (i : ℕ) →
                       0 < length (proj₂ (proj₂ (fuseXorCube f lits i)))
fuseXorCube-nonempty f []       i = n<1+n 0
fuseXorCube-nonempty f (l ∷ ls) i =
  ≤-trans (fuseXorCube-nonempty f ls i)
          (length-++-≤ˡ (proj₂ (proj₂ (fuseXorCube f ls i))))

fusedPerturb-nonempty : (xs : List ℕ) (ksecBits : List Bool) (fWire i : ℕ) →
  0 < length (proj₂ (proj₂ ((cubeLits xs ksecBits »= λ lits →
                             fuseXorCube fWire lits) i)))
fusedPerturb-nonempty xs ksecBits fWire i =
  ≤-trans (fuseXorCube-nonempty fWire lits iC) (length-++-≤ʳ fOps {xs = cOps})
  where
    cR   = cubeLits xs ksecBits i
    lits = proj₁ cR
    iC   = proj₁ (proj₂ cR)
    cOps = proj₂ (proj₂ cR)
    fOps = proj₂ (proj₂ (fuseXorCube fWire lits iC))

------------------------------------------------------------------------
--  §7c Split the block's operation list at the perturb path.

--  Reassociate concatenation to write the emitted block
--  as perturb operations followed by restore and output XOR,
--  connecting fusedPerturb-noConst to the whole block.
lockedBlockMerged-split :
  (xs keys : List ℕ) (ksecBits : List Bool) (fWire start : ℕ) →
  let pR = (cubeLits xs ksecBits »= λ lits → fuseXorCube fWire lits) start
      rR = restoreNet xs keys 0 (proj₁ (proj₂ pR))
  in proj₂ (proj₂ (lockedBlockMerged xs keys ksecBits fWire start))
       ≡ proj₂ (proj₂ pR) ++ (proj₂ (proj₂ rR) ++ (oXor (proj₁ pR) (proj₁ rR) ∷ []))
lockedBlockMerged-split xs keys ksecBits fWire start =
  sym (++-assoc cOps fOps (rOps ++ (oXor t rW ∷ [])))
  where
    cR   = cubeLits xs ksecBits start
    lits = proj₁ cR
    iC   = proj₁ (proj₂ cR)
    cOps = proj₂ (proj₂ cR)
    fR   = fuseXorCube fWire lits iC
    t    = proj₁ fR
    iF   = proj₁ (proj₂ fR)
    fOps = proj₂ (proj₂ fR)
    rR   = restoreNet xs keys 0 iF
    rW   = proj₁ rR
    rOps = proj₂ (proj₂ rR)

--  State the combined prefix result: the emitted block
--  starts with its nonempty, constant-free fused perturb path.
lockedBlockMerged-perturbPrefix :
  (xs keys : List ℕ) (ksecBits : List Bool) (fWire start : ℕ) →
  let pR   = (cubeLits xs ksecBits »= λ lits → fuseXorCube fWire lits) start
      pOps = proj₂ (proj₂ pR)
      rR   = restoreNet xs keys 0 (proj₁ (proj₂ pR))
  in (proj₂ (proj₂ (lockedBlockMerged xs keys ksecBits fWire start))
        ≡ pOps ++ (proj₂ (proj₂ rR) ++ (oXor (proj₁ pR) (proj₁ rR) ∷ [])))
     × NoConst pOps
     × 0 < length pOps
lockedBlockMerged-perturbPrefix xs keys ksecBits fWire start =
    lockedBlockMerged-split xs keys ksecBits fWire start
  , fusedPerturb-noConst xs ksecBits fWire start
  , fusedPerturb-nonempty xs ksecBits fWire start

------------------------------------------------------------------------
--  §7d Give the global location of every block constant.

--  For all wire lists, cubes, and starts, the whole
--  fused block contains only the comparator's true/false constants.
lockedBlockMerged-constVals :
  (xs keys : List ℕ) (ksecBits : List Bool) (fWire start : ℕ) →
  constVals (proj₂ (proj₂ (lockedBlockMerged xs keys ksecBits fWire start)))
    ≡ true ∷ false ∷ []
lockedBlockMerged-constVals xs keys ksecBits fWire start = begin
    constVals (cOps ++ (fOps ++ tailOps))
      ≡⟨ constVals-++ cOps (fOps ++ tailOps) ⟩
    constVals cOps ++ constVals (fOps ++ tailOps)
      ≡⟨ cong (_++ constVals (fOps ++ tailOps))
              (noConst⇒constVals (cubeLits-noConst xs ksecBits start)) ⟩
    constVals (fOps ++ tailOps)
      ≡⟨ constVals-++ fOps tailOps ⟩
    constVals fOps ++ constVals tailOps
      ≡⟨ cong (_++ constVals tailOps)
              (noConst⇒constVals (fuseXorCube-noConst fWire lits iC)) ⟩
    constVals tailOps
      ≡⟨ constVals-++ rOps (oXor t rW ∷ []) ⟩
    constVals rOps ++ []
      ≡⟨ ++-identityʳ (constVals rOps) ⟩
    constVals rOps
      ≡⟨ restoreNet-constVals xs keys 0 iF ⟩
    true ∷ false ∷ []
      ∎
  where
    open ≡-Reasoning
    cR      = cubeLits xs ksecBits start
    lits    = proj₁ cR
    iC      = proj₁ (proj₂ cR)
    cOps    = proj₂ (proj₂ cR)
    fR      = fuseXorCube fWire lits iC
    t       = proj₁ fR
    iF      = proj₁ (proj₂ fR)
    fOps    = proj₂ (proj₂ fR)
    rR      = restoreNet xs keys 0 iF
    rW      = proj₁ rR
    rOps    = proj₂ (proj₂ rR)
    tailOps = rOps ++ (oXor t rW ∷ [])

--  Any two cubes yield identical constant payloads, so
--  this observation carries no secret-cube information.
--  Inverter polarities still depend on ksec, as §7 records.
lockedBlockMerged-constVals-ksec-independent :
  (xs keys : List ℕ) (k₁ k₂ : List Bool) (fWire start : ℕ) →
  constVals (proj₂ (proj₂ (lockedBlockMerged xs keys k₁ fWire start)))
    ≡ constVals (proj₂ (proj₂ (lockedBlockMerged xs keys k₂ fWire start)))
lockedBlockMerged-constVals-ksec-independent xs keys k₁ k₂ fWire start =
  trans (lockedBlockMerged-constVals xs keys k₁ fWire start)
        (sym (lockedBlockMerged-constVals xs keys k₂ fWire start))

lockedBlockMerged-constCount :
  (xs keys : List ℕ) (ksecBits : List Bool) (fWire start : ℕ) →
  length (constVals (proj₂ (proj₂ (lockedBlockMerged xs keys ksecBits fWire start)))) ≡ 2
lockedBlockMerged-constCount xs keys ksecBits fWire start =
  cong length (lockedBlockMerged-constVals xs keys ksecBits fWire start)

------------------------------------------------------------------------
--  §7e Contrast the unfused constants, which spell out ksec.

constWires-constVals : (bs : List Bool) (i : ℕ) →
                       constVals (proj₂ (proj₂ (constWires bs i))) ≡ bs
constWires-constVals []       i = refl
constWires-constVals (b ∷ bs) i =
  cong (b ∷_)
       (trans (cong constVals (++-identityʳ (proj₂ (proj₂ (constWires bs (suc i))))))
              (constWires-constVals bs (suc i)))

--  Show lockedBlock emits |ksec| secret-payload constants
--  before the two comparators' four rails, the structural
--  disclosure removed by fusion.
lockedBlock-constVals :
  (xs keys : List ℕ) (ksecBits : List Bool) (h fWire start : ℕ) →
  constVals (proj₂ (proj₂ (lockedBlock xs keys ksecBits h fWire start)))
    ≡ ksecBits ++ (true ∷ false ∷ true ∷ false ∷ [])
lockedBlock-constVals xs keys ksecBits h fWire start = begin
    constVals (kOps ++ (pOps ++ tailOps))
      ≡⟨ constVals-++ kOps (pOps ++ tailOps) ⟩
    constVals kOps ++ constVals (pOps ++ tailOps)
      ≡⟨ cong (_++ constVals (pOps ++ tailOps)) (constWires-constVals ksecBits start) ⟩
    ksecBits ++ constVals (pOps ++ tailOps)
      ≡⟨ cong (ksecBits ++_) restEq ⟩
    ksecBits ++ (true ∷ false ∷ true ∷ false ∷ [])
      ∎
  where
    open ≡-Reasoning
    kR      = constWires ksecBits start
    kw      = proj₁ kR
    iK      = proj₁ (proj₂ kR)
    kOps    = proj₂ (proj₂ kR)
    pR      = restoreNet xs kw h iK
    pW      = proj₁ pR
    iP      = proj₁ (proj₂ pR)
    pOps    = proj₂ (proj₂ pR)
    rR      = restoreNet xs keys h iP
    rW      = proj₁ rR
    iR      = proj₁ (proj₂ rR)
    rOps    = proj₂ (proj₂ rR)
    xorOps  = (oXor fWire pW ∷ []) ++ (oXor iR rW ∷ [])
    tailOps = rOps ++ xorOps

    railsEq : constVals (rOps ++ xorOps) ≡ true ∷ false ∷ []
    railsEq = trans (constVals-++ rOps xorOps)
                    (trans (++-identityʳ (constVals rOps))
                           (restoreNet-constVals xs keys h iP))

    restEq : constVals (pOps ++ tailOps) ≡ true ∷ false ∷ true ∷ false ∷ []
    restEq = trans (constVals-++ pOps tailOps)
                   (cong₂ _++_ (restoreNet-constVals xs kw h iK) railsEq)

lockedBlock-constCount :
  (xs keys : List ℕ) (ksecBits : List Bool) (h fWire start : ℕ) →
  length (constVals (proj₂ (proj₂ (lockedBlock xs keys ksecBits h fWire start))))
    ≡ length ksecBits + 4
lockedBlock-constCount xs keys ksecBits h fWire start =
  trans (cong length (lockedBlock-constVals xs keys ksecBits h fWire start))
        (length-++ ksecBits)

--  Prove unfused payloads determine the cube, contrasting
--  with the fused constant map. The unfused map from
--  ksec to constVals is injective, so reading payloads
--  identifies the secret exactly. Require no relation
--  between cubes, including equal length: cancellation
--  of the fixed true,false,true,false suffix uses
--  Data.List.Properties.++-cancelʳ, handling unequal
--  lengths by contradiction. Scope remains emitted
--  oConst gates, with no attack-cost conclusion or
--  claim that fusion hides the secret in inverter polarity.
lockedBlock-constVals-injective :
  (xs keys : List ℕ) (c₁ c₂ : List Bool) (h fWire start : ℕ) →
  constVals (proj₂ (proj₂ (lockedBlock xs keys c₁ h fWire start)))
    ≡ constVals (proj₂ (proj₂ (lockedBlock xs keys c₂ h fWire start))) →
  c₁ ≡ c₂
lockedBlock-constVals-injective xs keys c₁ c₂ h fWire start eq =
  ++-cancelʳ (true ∷ false ∷ true ∷ false ∷ []) c₁ c₂
    (trans (sym (lockedBlock-constVals xs keys c₁ h fWire start))
           (trans eq (lockedBlock-constVals xs keys c₂ h fWire start)))

--  Record the immediate reverse implication to make the
--  following equivalence explicitly two-directional.
lockedBlock-constVals-cong :
  (xs keys : List ℕ) (c₁ c₂ : List Bool) (h fWire start : ℕ) →
  c₁ ≡ c₂ →
  constVals (proj₂ (proj₂ (lockedBlock xs keys c₁ h fWire start)))
    ≡ constVals (proj₂ (proj₂ (lockedBlock xs keys c₂ h fWire start)))
lockedBlock-constVals-cong xs keys c₁ c₂ h fWire start =
  cong (λ c → constVals (proj₂ (proj₂ (lockedBlock xs keys c h fWire start))))

--  Equate payload equality with cube equality, making
--  the payload list a faithful representation of ksec.
lockedBlock-constVals-determines-ksec :
  (xs keys : List ℕ) (c₁ c₂ : List Bool) (h fWire start : ℕ) →
  (constVals (proj₂ (proj₂ (lockedBlock xs keys c₁ h fWire start)))
     ≡ constVals (proj₂ (proj₂ (lockedBlock xs keys c₂ h fWire start))))
  ⇔ (c₁ ≡ c₂)
lockedBlock-constVals-determines-ksec xs keys c₁ c₂ h fWire start =
  mk⇔ (lockedBlock-constVals-injective xs keys c₁ c₂ h fWire start)
      (lockedBlock-constVals-cong      xs keys c₁ c₂ h fWire start)

--  Take the contrapositive: all distinct cubes produce
--  distinct unfused constant payloads.
lockedBlock-constVals-reveals-ksec-gen :
  (xs keys : List ℕ) (c₁ c₂ : List Bool) (h fWire start : ℕ) →
  c₁ ≢ c₂ →
  constVals (proj₂ (proj₂ (lockedBlock xs keys c₁ h fWire start)))
    ≢ constVals (proj₂ (proj₂ (lockedBlock xs keys c₂ h fWire start)))
lockedBlock-constVals-reveals-ksec-gen xs keys c₁ c₂ h fWire start c₁≢c₂ eq =
  c₁≢c₂ (lockedBlock-constVals-injective xs keys c₁ c₂ h fWire start eq)

--  Derive the original one-bit result as an instance
--  of the general theorem, retaining its type.
lockedBlock-constVals-reveals-ksec :
  (xs keys : List ℕ) (h fWire start : ℕ) →
  constVals (proj₂ (proj₂ (lockedBlock xs keys (true ∷ []) h fWire start)))
    ≢ constVals (proj₂ (proj₂ (lockedBlock xs keys (false ∷ []) h fWire start)))
lockedBlock-constVals-reveals-ksec xs keys h fWire start =
  lockedBlock-constVals-reveals-ksec-gen xs keys (true ∷ []) (false ∷ [])
                                         h fWire start (λ ())

------------------------------------------------------------------------
--  §7f Compute the contrast at n = 2,ksec = 10,
--  wires x₀=0,x₁=1,k₀=2,k₁=3,f=4, and start five:
--  unfused has six constants and fused has two.

private
  _ : constVals (proj₂ (proj₂ (lockedBlockMerged (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                                 (true ∷ false ∷ []) 4 5)))
        ≡ true ∷ false ∷ []
  _ = refl

  _ : constVals (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                           (true ∷ false ∷ []) 0 4 5)))
        ≡ true ∷ false ∷ true ∷ false ∷ true ∷ false ∷ []
  _ = refl

  --  Compute that changing a cube bit changes unfused payloads.
  _ : constVals (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                           (false ∷ false ∷ []) 0 4 5)))
        ≡ false ∷ false ∷ true ∷ false ∷ true ∷ false ∷ []
  _ = refl

  --  Check unequal-length cubes too, using empty versus
  --  one-bit cubes. This exercises the premise-free
  --  lockedBlock-constVals-injective result beyond a
  --  same-length-only interpretation.
  _ : constVals (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) [] 0 4 5)))
        ≢ constVals (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                               (true ∷ []) 0 4 5)))
  _ = lockedBlock-constVals-reveals-ksec-gen (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ [])
                                             [] (true ∷ []) 0 4 5 (λ ())

  --  Compute their payload lists with lengths four and five.
  _ : constVals (proj₂ (proj₂ (lockedBlock (0 ∷ 1 ∷ []) (2 ∷ 3 ∷ []) [] 0 4 5)))
        ≡ true ∷ false ∷ true ∷ false ∷ []
  _ = refl
