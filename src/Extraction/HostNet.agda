------------------------------------------------------------------------
--  Bridge real ISCAS hosts to flat shared-wire List Op netlists. This lets
--  Extraction.LockedNet protect hosts whose gates compute f x, rather than
--  receiving that value as an input. This file supplies the gadget compiler:
--  each host gate carries an arbitrary Circuit 2 1, and gadgetOps compiles
--  it over its two fan-in wires. Reuse Extraction.Bench's verified Circuit
--  to Expr emitter on the small two-input gadget, then lay the expression
--  out as shared wires with flatE. Correctness composes flatE's runNet
--  semantics with emit-sound, without postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.HostNet where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; _<_; z≤n; s≤s)
open import Data.Nat.Properties using (≤-trans; ≤-refl; n≤1+n; n<1+n; m≤m+n; +-comm)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; _xor_)
open import Data.Fin using (Fin; zero; suc)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.List.Properties using (length-++; ++-identityʳ)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.Vec.Properties using (lookup-map)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst)

open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import Extraction.NetDepthBuilder using (CntLaw; ret-cnt; fresh-cnt; »=-cnt; mkMux-cnt)
open import Extraction.Bench using
  (Expr; var; con; gnot; gand; gor; gxor; gmux; evalE; eval; emit; emit-sound)
open import Extraction.Netlist using
  (Op; oConst; oNot; oAnd; oOr; oXor; get; evalOp; runNet
  ; Builder; ret; _»=_; fresh; mkConst; mkNot; mkAnd; mkMux)
open import Extraction.NetlistCorrect using (get-snoc-len; get-++-<; runNet-++; runNet-length; runNet-prefix; runNet-mono)

private
  variable
    m : ℕ

------------------------------------------------------------------------
--  Section 1: supporting run operations.

--  Use stdlib +-comm _ 1 for m + 1 ≡ suc m, since 1 + m reduces to suc m.

------------------------------------------------------------------------
--  Section 2: prove that mkMux's four operations compute (a ∧ ¬s) ∨ (b ∧ s).
--  For L = length env, allocate ns=L, t1=L+1, t2=L+2, and out=L+3.

mkMux-val : (s a b : ℕ) (env : List Bool) →
            s < length env → a < length env → b < length env →
            let (out , _ , ops) = mkMux s a b (length env)
            in get (runNet env ops) out
                 ≡ (get env a ∧ not (get env s)) ∨ (get env b ∧ get env s)
mkMux-val s a b env s< a< b< =
    trans (cong (get e4) (sym l3))
   (trans (get-snoc-len e3 outV)
          (cong₂ _∨_ t1≡ t2≡))
  where
    L    = length env
    nsV  = not (get env s)
    e1   = env ++ (nsV ∷ [])
    t1V  = get e1 a ∧ get e1 L
    e2   = e1 ++ (t1V ∷ [])
    t2V  = get e2 b ∧ get e2 s
    e3   = e2 ++ (t2V ∷ [])
    outV = get e3 (suc L) ∨ get e3 (suc (suc L))
    e4   = e3 ++ (outV ∷ [])

    l1 : length e1 ≡ suc L
    l1 = trans (length-++ env {nsV ∷ []}) (+-comm L 1)
    l2 : length e2 ≡ suc (suc L)
    l2 = trans (length-++ e1 {t1V ∷ []}) (trans (cong (_+ 1) l1) (+-comm (suc L) 1))
    l3 : length e3 ≡ suc (suc (suc L))
    l3 = trans (length-++ e2 {t2V ∷ []}) (trans (cong (_+ 1) l2) (+-comm (suc (suc L)) 1))

    b<1    = subst (b <_)     (sym l1) (≤-trans b< (n≤1+n L))     --  b < length e1
    s<1    = subst (s <_)     (sym l1) (≤-trans s< (n≤1+n L))     --  s < length e1
    sucL<2 = subst (suc L <_) (sym l2) (n<1+n (suc L))            --  suc L < length e2

    --  At suc L, wire t1 stores get env a ∧ ¬ get env s.
    t1≡ : get e3 (suc L) ≡ get env a ∧ not (get env s)
    t1≡ = trans (get-++-< e2 (t2V ∷ []) (suc L) sucL<2)
          (trans (cong (get e2) (sym l1))
          (trans (get-snoc-len e1 t1V)
                 (cong₂ _∧_ (get-++-< env (nsV ∷ []) a a<) (get-snoc-len env nsV))))
    --  At suc (suc L), wire t2 stores get env b ∧ get env s.
    t2≡ : get e3 (suc (suc L)) ≡ get env b ∧ get env s
    t2≡ = trans (cong (get e3) (sym l2))
          (trans (get-snoc-len e2 t2V)
                 (cong₂ _∧_ (trans (get-++-< e1 (t1V ∷ []) b b<1) (get-++-< env (nsV ∷ []) b b<))
                            (trans (get-++-< e1 (t1V ∷ []) s s<1) (get-++-< env (nsV ∷ []) s s<))))

------------------------------------------------------------------------
--  Section 3: flatten Expr into shared List Op using ρ to map variables to
--  wires. Fan-out duplicates within the bounded two-input gadget expression,
--  whose small size prevents blow-up.

flatE : Expr m → (Fin m → ℕ) → Builder ℕ
flatE (var i)      ρ = ret (ρ i)
flatE (con b)      ρ = mkConst b
flatE (gnot e)     ρ = flatE e ρ »= λ w → mkNot w
flatE (gand a b)   ρ = flatE a ρ »= λ wa → flatE b ρ »= λ wb → fresh (oAnd wa wb)
flatE (gor a b)    ρ = flatE a ρ »= λ wa → flatE b ρ »= λ wb → fresh (oOr wa wb)
flatE (gxor a b)   ρ = flatE a ρ »= λ wa → flatE b ρ »= λ wb → fresh (oXor wa wb)
flatE (gmux s a b) ρ = flatE s ρ »= λ ws → flatE a ρ »= λ wa →
                       flatE b ρ »= λ wb → mkMux ws wa wb

--  Bundle the conclusions used by flatE-correct.
Spec : (e : Expr m) (ρ : Fin m → ℕ) (vs : Vec Bool m) (env : List Bool) → Set
Spec {m} e ρ vs env =
  let (out , _ , ops) = flatE e ρ (length env)
      env'            = runNet env ops
  in (out < length env')
   × (length env ≤ length env')
   × ((w : ℕ) → w < length env → get env' w ≡ get env w)
   × (get env' out ≡ evalE e vs)

--  CntLaw equates the next identifier to start plus emitted operation count,
--  aligning builder state with environment length.
flatE-cnt : (e : Expr m) (ρ : Fin m → ℕ) → CntLaw (flatE e ρ)
flatE-cnt (var i)      ρ = ret-cnt (ρ i)
flatE-cnt (con b)      ρ = fresh-cnt (oConst b)
flatE-cnt (gnot e)     ρ =
  »=-cnt (flatE e ρ) (λ w → mkNot w) (flatE-cnt e ρ) (λ w → fresh-cnt (oNot w))
flatE-cnt (gand a b)   ρ =
  »=-cnt (flatE a ρ) (λ wa → flatE b ρ »= λ wb → fresh (oAnd wa wb)) (flatE-cnt a ρ)
    (λ wa → »=-cnt (flatE b ρ) (λ wb → fresh (oAnd wa wb)) (flatE-cnt b ρ)
                   (λ wb → fresh-cnt (oAnd wa wb)))
flatE-cnt (gor a b)    ρ =
  »=-cnt (flatE a ρ) (λ wa → flatE b ρ »= λ wb → fresh (oOr wa wb)) (flatE-cnt a ρ)
    (λ wa → »=-cnt (flatE b ρ) (λ wb → fresh (oOr wa wb)) (flatE-cnt b ρ)
                   (λ wb → fresh-cnt (oOr wa wb)))
flatE-cnt (gxor a b)   ρ =
  »=-cnt (flatE a ρ) (λ wa → flatE b ρ »= λ wb → fresh (oXor wa wb)) (flatE-cnt a ρ)
    (λ wa → »=-cnt (flatE b ρ) (λ wb → fresh (oXor wa wb)) (flatE-cnt b ρ)
                   (λ wb → fresh-cnt (oXor wa wb)))
flatE-cnt (gmux s a b) ρ =
  »=-cnt (flatE s ρ) (λ ws → flatE a ρ »= λ wa → flatE b ρ »= λ wb → mkMux ws wa wb)
         (flatE-cnt s ρ)
    (λ ws → »=-cnt (flatE a ρ) (λ wa → flatE b ρ »= λ wb → mkMux ws wa wb) (flatE-cnt a ρ)
      (λ wa → »=-cnt (flatE b ρ) (λ wb → mkMux ws wa wb) (flatE-cnt b ρ)
                     (λ wb → mkMux-cnt ws wa wb)))

------------------------------------------------------------------------
--  Section 4: flatE-correct proves the flattened operations compute the
--  expression value. Explicit start aligns Builder state and length in binary
--  recursion.

FlatSpec : (e : Expr m) (ρ : Fin m → ℕ) (vs : Vec Bool m) (env : List Bool) (start : ℕ) → Set
FlatSpec {m} e ρ vs env start =
  let (out , _ , ops) = flatE e ρ start
      env'            = runNet env ops
  in (out < length env')
   × (length env ≤ length env')
   × ((w : ℕ) → w < length env → get env' w ≡ get env w)
   × (get env' out ≡ evalE e vs)

--  Share binary-operation assembly among gand, gor, and gxor; oceq establishes
--  that oc computes the required operation.
binFlat-correct :
  (oc : ℕ → ℕ → Op) (op : Bool → Bool → Bool)
  (oceq : (e : List Bool) (p q : ℕ) → evalOp e (oc p q) ≡ op (get e p) (get e q))
  (a b : Expr m) (ρ : Fin m → ℕ) (vs : Vec Bool m) (env : List Bool) (start : ℕ) →
  length env ≡ start →
  FlatSpec a ρ vs env start →
  FlatSpec b ρ vs (runNet env (proj₂ (proj₂ (flatE a ρ start))))
                  (proj₁ (proj₂ (flatE a ρ start))) →
  let (out , _ , ops) = (flatE a ρ »= λ wa → flatE b ρ »= λ wb → fresh (oc wa wb)) start
      env'            = runNet env ops
  in (out < length env')
   × (length env ≤ length env')
   × ((w : ℕ) → w < length env → get env' w ≡ get env w)
   × (get env' out ≡ op (evalE a vs) (evalE b vs))
binFlat-correct oc op oceq a b ρ vs env start lenEq SA SB =
    outB< , monoC , presvC , valC
  where
    iA   = proj₁ (proj₂ (flatE a ρ start))
    opsA = proj₂ (proj₂ (flatE a ρ start))
    outA = proj₁ (flatE a ρ start)
    envA = runNet env opsA
    outA<A = proj₁ SA ; monoA = proj₁ (proj₂ SA)
    presvA = proj₁ (proj₂ (proj₂ SA)) ; valA = proj₂ (proj₂ (proj₂ SA))
    lenA≡iA : length envA ≡ iA
    lenA≡iA = trans (runNet-length env opsA)
                    (trans (cong (_+ length opsA) lenEq) (sym (flatE-cnt a ρ start)))
    iB   = proj₁ (proj₂ (flatE b ρ iA))
    opsB = proj₂ (proj₂ (flatE b ρ iA))
    outB = proj₁ (flatE b ρ iA)
    envB = runNet envA opsB
    outB<B = proj₁ SB ; monoB = proj₁ (proj₂ SB)
    presvB = proj₁ (proj₂ (proj₂ SB)) ; valB = proj₂ (proj₂ (proj₂ SB))
    lenB≡iB : length envB ≡ iB
    lenB≡iB = trans (runNet-length envA opsB)
                    (trans (cong (_+ length opsB) lenA≡iA) (sym (flatE-cnt b ρ iA)))
    vAB  = op (get envB outA) (get envB outB)
    envC = envB ++ (vAB ∷ [])
    out  = proj₁ ((flatE a ρ »= λ wa → flatE b ρ »= λ wb → fresh (oc wa wb)) start)
    fullOps = proj₂ (proj₂ ((flatE a ρ »= λ wa → flatE b ρ »= λ wb → fresh (oc wa wb)) start))

    runEq : runNet env fullOps ≡ envC
    runEq = trans (runNet-++ env opsA (opsB ++ (oc outA outB ∷ [])))
            (trans (runNet-++ envA opsB (oc outA outB ∷ []))
                   (cong (λ v → envB ++ (v ∷ [])) (oceq envB outA outB)))

    lenC : length envC ≡ suc (length envB)
    lenC = trans (length-++ envB {vAB ∷ []}) (+-comm (length envB) 1)

    outB< : out < length (runNet env fullOps)
    outB< = subst (λ e → out < length e) (sym runEq)
              (subst (out <_) (sym lenC)
                (subst (_< suc (length envB)) lenB≡iB (n<1+n (length envB))))
    monoC : length env ≤ length (runNet env fullOps)
    monoC = subst (λ e → length env ≤ length e) (sym runEq)
              (≤-trans (≤-trans monoA monoB) (subst (length envB ≤_) (sym lenC) (n≤1+n (length envB))))
    presvC : (w : ℕ) → w < length env → get (runNet env fullOps) w ≡ get env w
    presvC w w< =
      trans (cong (λ e → get e w) runEq)
        (trans (get-++-< envB (vAB ∷ []) w (≤-trans w< (≤-trans monoA monoB)))
        (trans (presvB w (≤-trans w< monoA)) (presvA w w<)))
    valC : get (runNet env fullOps) out ≡ op (evalE a vs) (evalE b vs)
    valC =
      trans (cong (λ e → get e out) runEq)
      (trans (cong (get envC) (sym lenB≡iB))
      (trans (get-snoc-len envB vAB)
             (cong₂ op (trans (presvB outA outA<A) valA)
                       valB)))

--  Show the laid-out gadget expression computes its evalE value.
flatE-correct : (e : Expr m) (ρ : Fin m → ℕ) (vs : Vec Bool m) (env : List Bool) (start : ℕ) →
  length env ≡ start → (∀ i → ρ i < length env) → (∀ i → get env (ρ i) ≡ lookup vs i) →
  FlatSpec e ρ vs env start
flatE-correct (var i) ρ vs env start lenEq ρ< gv =
  ρ< i , ≤-refl , (λ w _ → refl) , gv i
flatE-correct (con b) ρ vs env start lenEq ρ< gv =
    out< , runNet-mono env (oConst b ∷ []) , presv , val
  where
    env' = env ++ (b ∷ [])
    lenE' : length env' ≡ suc start
    lenE' = trans (length-++ env {b ∷ []}) (trans (cong (_+ 1) lenEq) (+-comm start 1))
    out< : start < length env'
    out< = subst (start <_) (sym lenE') (n<1+n start)
    presv : (w : ℕ) → w < length env → get env' w ≡ get env w
    presv w w< = get-++-< env (b ∷ []) w w<
    val : get env' start ≡ b
    val = trans (cong (get env') (sym lenEq)) (get-snoc-len env b)
flatE-correct (gnot e) ρ vs env start lenEq ρ< gv =
    out< , monoN , presvN , valN
  where
    SE = flatE-correct e ρ vs env start lenEq ρ< gv
    iE = proj₁ (proj₂ (flatE e ρ start))
    opsE = proj₂ (proj₂ (flatE e ρ start))
    outE = proj₁ (flatE e ρ start)
    envE = runNet env opsE
    outE<E = proj₁ SE ; monoE = proj₁ (proj₂ SE)
    presvE = proj₁ (proj₂ (proj₂ SE)) ; valE = proj₂ (proj₂ (proj₂ SE))
    lenE≡iE : length envE ≡ iE
    lenE≡iE = trans (runNet-length env opsE)
                    (trans (cong (_+ length opsE) lenEq) (sym (flatE-cnt e ρ start)))
    vN   = not (get envE outE)
    env' = envE ++ (vN ∷ [])
    fullOps = proj₂ (proj₂ (flatE (gnot e) ρ start))
    runEq : runNet env fullOps ≡ env'
    runEq = runNet-++ env opsE (oNot outE ∷ [])
    lenN : length env' ≡ suc (length envE)
    lenN = trans (length-++ envE {vN ∷ []}) (+-comm (length envE) 1)
    out< : iE < length (runNet env fullOps)
    out< = subst (λ l → iE < length l) (sym runEq)
             (subst (iE <_) (sym lenN) (subst (_< suc (length envE)) lenE≡iE (n<1+n (length envE))))
    monoN : length env ≤ length (runNet env fullOps)
    monoN = subst (λ l → length env ≤ length l) (sym runEq)
              (≤-trans monoE (subst (length envE ≤_) (sym lenN) (n≤1+n (length envE))))
    presvN : (w : ℕ) → w < length env → get (runNet env fullOps) w ≡ get env w
    presvN w w< = trans (cong (λ l → get l w) runEq)
                    (trans (get-++-< envE (vN ∷ []) w (≤-trans w< monoE)) (presvE w w<))
    valN : get (runNet env fullOps) iE ≡ not (evalE e vs)
    valN = trans (cong (λ l → get l iE) runEq)
             (trans (cong (get env') (sym lenE≡iE))
                    (trans (get-snoc-len envE vN) (cong not valE)))
flatE-correct (gand a b) ρ vs env start lenEq ρ< gv =
  binFlat-correct oAnd _∧_ (λ _ _ _ → refl) a b ρ vs env start lenEq SA SB
  where
    SA = flatE-correct a ρ vs env start lenEq ρ< gv
    iA = proj₁ (proj₂ (flatE a ρ start)) ; opsA = proj₂ (proj₂ (flatE a ρ start))
    envA = runNet env opsA
    monoA = proj₁ (proj₂ SA) ; presvA = proj₁ (proj₂ (proj₂ SA))
    lenA≡iA = trans (runNet-length env opsA)
                    (trans (cong (_+ length opsA) lenEq) (sym (flatE-cnt a ρ start)))
    SB = flatE-correct b ρ vs envA iA lenA≡iA
           (λ i → ≤-trans (ρ< i) monoA) (λ i → trans (presvA (ρ i) (ρ< i)) (gv i))
flatE-correct (gor a b) ρ vs env start lenEq ρ< gv =
  binFlat-correct oOr _∨_ (λ _ _ _ → refl) a b ρ vs env start lenEq SA SB
  where
    SA = flatE-correct a ρ vs env start lenEq ρ< gv
    iA = proj₁ (proj₂ (flatE a ρ start)) ; opsA = proj₂ (proj₂ (flatE a ρ start))
    envA = runNet env opsA
    monoA = proj₁ (proj₂ SA) ; presvA = proj₁ (proj₂ (proj₂ SA))
    lenA≡iA = trans (runNet-length env opsA)
                    (trans (cong (_+ length opsA) lenEq) (sym (flatE-cnt a ρ start)))
    SB = flatE-correct b ρ vs envA iA lenA≡iA
           (λ i → ≤-trans (ρ< i) monoA) (λ i → trans (presvA (ρ i) (ρ< i)) (gv i))
flatE-correct (gxor a b) ρ vs env start lenEq ρ< gv =
  binFlat-correct oXor _xor_ (λ _ _ _ → refl) a b ρ vs env start lenEq SA SB
  where
    SA = flatE-correct a ρ vs env start lenEq ρ< gv
    iA = proj₁ (proj₂ (flatE a ρ start)) ; opsA = proj₂ (proj₂ (flatE a ρ start))
    envA = runNet env opsA
    monoA = proj₁ (proj₂ SA) ; presvA = proj₁ (proj₂ (proj₂ SA))
    lenA≡iA = trans (runNet-length env opsA)
                    (trans (cong (_+ length opsA) lenEq) (sym (flatE-cnt a ρ start)))
    SB = flatE-correct b ρ vs envA iA lenA≡iA
           (λ i → ≤-trans (ρ< i) monoA) (λ i → trans (presvA (ρ i) (ρ< i)) (gv i))
flatE-correct (gmux s a b) ρ vs env start lenEq ρ< gv =
    out< , monoM , presvM , valM
  where
    SS = flatE-correct s ρ vs env start lenEq ρ< gv
    iS = proj₁ (proj₂ (flatE s ρ start)) ; opsS = proj₂ (proj₂ (flatE s ρ start))
    outS = proj₁ (flatE s ρ start) ; envS = runNet env opsS
    monoS = proj₁ (proj₂ SS) ; presvS = proj₁ (proj₂ (proj₂ SS)) ; valS = proj₂ (proj₂ (proj₂ SS))
    outS<S = proj₁ SS
    lenS≡iS = trans (runNet-length env opsS)
                    (trans (cong (_+ length opsS) lenEq) (sym (flatE-cnt s ρ start)))
    SA = flatE-correct a ρ vs envS iS lenS≡iS
           (λ i → ≤-trans (ρ< i) monoS) (λ i → trans (presvS (ρ i) (ρ< i)) (gv i))
    iA = proj₁ (proj₂ (flatE a ρ iS)) ; opsA = proj₂ (proj₂ (flatE a ρ iS))
    outA = proj₁ (flatE a ρ iS) ; envA = runNet envS opsA
    monoA = proj₁ (proj₂ SA) ; presvA = proj₁ (proj₂ (proj₂ SA)) ; valA = proj₂ (proj₂ (proj₂ SA))
    outA<A = proj₁ SA
    lenA≡iA = trans (runNet-length envS opsA)
                    (trans (cong (_+ length opsA) lenS≡iS) (sym (flatE-cnt a ρ iS)))
    SB = flatE-correct b ρ vs envA iA lenA≡iA
           (λ i → ≤-trans (ρ< i) (≤-trans monoS monoA))
           (λ i → trans (presvA (ρ i) (≤-trans (ρ< i) monoS))
                        (trans (presvS (ρ i) (ρ< i)) (gv i)))
    iB = proj₁ (proj₂ (flatE b ρ iA)) ; opsB = proj₂ (proj₂ (flatE b ρ iA))
    outB = proj₁ (flatE b ρ iA) ; envB = runNet envA opsB
    monoB = proj₁ (proj₂ SB) ; presvB = proj₁ (proj₂ (proj₂ SB)) ; valB = proj₂ (proj₂ (proj₂ SB))
    outB<B = proj₁ SB
    lenB≡iB = trans (runNet-length envA opsB)
                    (trans (cong (_+ length opsB) lenA≡iA) (sym (flatE-cnt b ρ iA)))
    --  Establish bounds for the fan-in wire indices.
    outS<A : outS < length envA
    outS<A = ≤-trans outS<S monoA
    outS<B : outS < length envB
    outS<B = ≤-trans outS<S (≤-trans monoA monoB)
    outA<B : outA < length envB
    outA<B = ≤-trans outA<A monoB
    --  Use lenB≡iB to align mkMux at iB with mkMux-val stated at length envB.
    muxOps = proj₂ (proj₂ (mkMux outS outA outB iB))
    muxOut = proj₁ (mkMux outS outA outB iB)
    fullOps = proj₂ (proj₂ (flatE (gmux s a b) ρ start))
    out = proj₁ (flatE (gmux s a b) ρ start)
    runEq : runNet env fullOps ≡ runNet envB muxOps
    runEq = trans (runNet-++ env opsS (opsA ++ opsB ++ muxOps))
            (trans (runNet-++ envS opsA (opsB ++ muxOps))
                   (runNet-++ envA opsB muxOps))
    Pm : ℕ → Set
    Pm st = get (runNet envB (proj₂ (proj₂ (mkMux outS outA outB st))))
                (proj₁ (mkMux outS outA outB st))
              ≡ (get envB outA ∧ not (get envB outS)) ∨ (get envB outB ∧ get envB outS)
    mv : get (runNet envB muxOps) muxOut
           ≡ (get envB outA ∧ not (get envB outS)) ∨ (get envB outB ∧ get envB outS)
    mv = subst Pm lenB≡iB (mkMux-val outS outA outB envB outS<B outA<B outB<B)
    getEnvB-S : get envB outS ≡ evalE s vs
    getEnvB-S = trans (presvB outS outS<A) (trans (presvA outS outS<S) valS)
    getEnvB-A : get envB outA ≡ evalE a vs
    getEnvB-A = trans (presvB outA outA<A) valA
    getEnvB-B : get envB outB ≡ evalE b vs
    getEnvB-B = valB
    valM : get (runNet env fullOps) out ≡ evalE (gmux s a b) vs
    valM = trans (cong (λ l → get l out) runEq)
           (trans mv
                  (cong₂ _∨_ (cong₂ _∧_ getEnvB-A (cong not getEnvB-S))
                             (cong₂ _∧_ getEnvB-B getEnvB-S)))
    monoM : length env ≤ length (runNet env fullOps)
    monoM = subst (λ l → length env ≤ length l) (sym runEq)
              (≤-trans (≤-trans monoS (≤-trans monoA monoB)) (runNet-mono envB muxOps))
    presvM : (w : ℕ) → w < length env → get (runNet env fullOps) w ≡ get env w
    presvM w w< = trans (cong (λ l → get l w) runEq)
                    (trans (runNet-prefix envB muxOps w (≤-trans w< (≤-trans monoS (≤-trans monoA monoB))))
                    (trans (presvB w (≤-trans w< (≤-trans monoS monoA)))
                    (trans (presvA w (≤-trans w< monoS)) (presvS w w<))))
    nextG≡len : proj₁ (proj₂ (flatE (gmux s a b) ρ start)) ≡ length (runNet env fullOps)
    nextG≡len = trans (flatE-cnt (gmux s a b) ρ start)
                      (trans (cong (_+ length fullOps) (sym lenEq)) (sym (runNet-length env fullOps)))
    out< : out < length (runNet env fullOps)
    out< = subst (out <_) nextG≡len (n<1+n out)

------------------------------------------------------------------------
--  Section 5: compile a host gate's Circuit 2 1 into flat operations referencing
--  its two fan-ins, reusing emit and emit-sound.

ρ2 : (wa wb : ℕ) → Fin 2 → ℕ
ρ2 wa wb zero        = wa
ρ2 wa wb (suc zero)  = wb

gadgetOps : Circuit 2 1 → (wa wb : ℕ) → Builder ℕ
gadgetOps g wa wb = flatE (lookup (emit g) zero) (ρ2 wa wb)

gadgetOps-cnt : (g : Circuit 2 1) (wa wb : ℕ) → CntLaw (gadgetOps g wa wb)
gadgetOps-cnt g wa wb = flatE-cnt (lookup (emit g) zero) (ρ2 wa wb)

--  The compiled gadget denotes the gate applied to its two fan-in values.
gadget-correct : (g : Circuit 2 1) (wa wb : ℕ) (env : List Bool) →
  wa < length env → wb < length env →
  let (out , _ , ops) = gadgetOps g wa wb (length env)
      env'            = runNet env ops
  in (out < length env')
   × (length env ≤ length env')
   × ((w : ℕ) → w < length env → get env' w ≡ get env w)
   × (get env' out ≡ lookup (⟦ g ⟧ (get env wa ∷ get env wb ∷ [])) zero)
gadget-correct g wa wb env wa< wb< =
    proj₁ SF , proj₁ (proj₂ SF) , proj₁ (proj₂ (proj₂ SF)) , valG
  where
    vs : Vec Bool 2
    vs = get env wa ∷ get env wb ∷ []
    ρ< : (i : Fin 2) → ρ2 wa wb i < length env
    ρ< zero       = wa<
    ρ< (suc zero) = wb<
    gv : (i : Fin 2) → get env (ρ2 wa wb i) ≡ lookup vs i
    gv zero       = refl
    gv (suc zero) = refl
    SF = flatE-correct (lookup (emit g) zero) (ρ2 wa wb) vs env (length env) refl ρ< gv
    --  By emit-sound, evaluating the selected Expr yields the gate's output bit.
    valG : get (runNet env (proj₂ (proj₂ (gadgetOps g wa wb (length env)))))
               (proj₁ (gadgetOps g wa wb (length env)))
             ≡ lookup (⟦ g ⟧ vs) zero
    valG = trans (proj₂ (proj₂ (proj₂ SF)))
                 (trans (sym (lookup-map zero (λ e → evalE e vs) (emit g)))
                        (cong (λ v → lookup v zero) (emit-sound g vs)))
