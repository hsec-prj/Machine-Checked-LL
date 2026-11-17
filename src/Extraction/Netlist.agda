------------------------------------------------------------------------
--  Define flat named-wire netlists and efficient popcount equality. The
--  Expr tree in Extraction.Bench renders exactlyH exponentially, with
--  muxCount following the proved Pascal recurrence. Explicit shared wires
--  avoid that growth. Op lists use primary wires 0..n-1, with gate k
--  defining n+k and referring only to earlier wires. runNet grows its
--  environment in wire order; a small allocating Builder removes manual
--  identifier arithmetic. popcountEqNet N h uses thermometer values
--  th[j]=[count ≥ j], one mux per stage/level and O(N²) shared gates, to
--  produce [weight = h]. Although this is a separate IR from exactlyH,
--  Extraction.NetlistCorrect.netEval-correct proves
--  netEval N h xs ≡ (weight xs ≡ᵇ h) for all N, h, and xs. This matches
--  SFLL.Netlist.exactlyH-spec's single-bit circuit result at every width.
--  BenchRoundTrip.netlist-text-correct also parses and evaluates rendered
--  text back to netEval. The small-N refl examples below are regression
--  checks supplementing these general proofs, not their justification. No
--  postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.Netlist where

open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; _xor_)
open import Data.List using (List; []; _∷_; _++_; replicate)
open import Data.Vec using (Vec; []; _∷_; toList)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

------------------------------------------------------------------------
--  Define gates and their evaluation semantics.

data Op : Set where
  oConst : Bool → Op
  oNot   : ℕ → Op
  oAnd   : ℕ → ℕ → Op
  oOr    : ℕ → ℕ → Op
  oXor   : ℕ → ℕ → Op

--  Look up a wire identifier, defaulting to false outside the environment.
get : List Bool → ℕ → Bool
get []       _       = false
get (x ∷ _)  zero    = x
get (x ∷ xs) (suc i) = get xs i

evalOp : List Bool → Op → Bool
evalOp env (oConst b) = b
evalOp env (oNot a)   = not (get env a)
evalOp env (oAnd a b) = get env a ∧ get env b
evalOp env (oOr a b)  = get env a ∨ get env b
evalOp env (oXor a b) = get env a xor get env b

--  Evaluate gates sequentially while extending the wire environment.
runNet : List Bool → List Op → List Bool
runNet env []         = env
runNet env (op ∷ ops) = runNet (env ++ (evalOp env op ∷ [])) ops

------------------------------------------------------------------------
--  Use the next unused identifier as Builder state and accumulate emitted operations.

Builder : Set → Set
Builder A = ℕ → A × ℕ × List Op

ret : ∀ {A} → A → Builder A
ret a i = a , i , []

infixl 1 _»=_
_»=_ : ∀ {A B} → Builder A → (A → Builder B) → Builder B
(m »= f) i = let (a , i₁ , o₁) = m i
                 (b , i₂ , o₂) = f a i₁
             in b , i₂ , (o₁ ++ o₂)

--  Allocate a gate and return its newly defined wire.
fresh : Op → Builder ℕ
fresh op i = i , suc i , (op ∷ [])

mkConst : Bool → Builder ℕ
mkConst b = fresh (oConst b)

mkNot : ℕ → Builder ℕ
mkNot a = fresh (oNot a)

mkAnd : ℕ → ℕ → Builder ℕ
mkAnd a b = fresh (oAnd a b)

--  Implement mux(s,a,b) as (a ∧ ¬s) ∨ (b ∧ s), selecting b for true s,
--  otherwise a.
mkMux : ℕ → ℕ → ℕ → Builder ℕ
mkMux s a b =
  mkNot s »= λ ns →
  mkAnd a ns »= λ t1 →
  mkAnd b s »= λ t2 →
  fresh (oOr t1 t2)

------------------------------------------------------------------------
--  Keep list helpers local to avoid changing import dependencies.

upFrom : ℕ → ℕ → List ℕ      --  [j, j+1, …, j+k-1]
upFrom j zero    = []
upFrom j (suc k) = j ∷ upFrom (suc j) k

upTo : ℕ → List ℕ            --  [0, 1, …, n-1]
upTo n = upFrom 0 n

tailL : List ℕ → List ℕ
tailL []       = []
tailL (_ ∷ xs) = xs

zipL : List ℕ → List ℕ → List (ℕ × ℕ)
zipL []       _        = []
zipL (_ ∷ _)  []       = []
zipL (x ∷ xs) (y ∷ ys) = (x , y) ∷ zipL xs ys

nth : List ℕ → ℕ → ℕ → ℕ      --  nth list i default
nth []       _       d = d
nth (x ∷ _)  zero    d = x
nth (x ∷ xs) (suc i) d = nth xs i d

mapMB : ∀ {B} → (ℕ × ℕ → Builder B) → List (ℕ × ℕ) → Builder (List B)
mapMB f []       = ret []
mapMB f (x ∷ xs) = f x »= λ y → mapMB f xs »= λ ys → ret (y ∷ ys)

foldlMB : (List ℕ → ℕ → Builder (List ℕ)) → List ℕ → List ℕ → Builder (List ℕ)
foldlMB f acc []       = ret acc
foldlMB f acc (x ∷ xs) = f acc x »= λ acc′ → foldlMB f acc′ xs

------------------------------------------------------------------------
--  Construct thermometer-based popcount equality.

--  For one input bit, set th′[0]=true and th′[j]=mux(bit,th[j],th[j-1]).
--  Since th[j] means count ≥ j, a true bit shifts the thermometer up one level.
stepTh : ℕ → List ℕ → ℕ → Builder (List ℕ)
stepTh trueW th bit =
  mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) (zipL (tailL th) th) »= λ rest →
  ret (trueW ∷ rest)

--  Build operations and return the output-wire identifier.
popBuilder : (N h : ℕ) → Builder ℕ
popBuilder N h =
  mkConst true  »= λ trueW →
  mkConst false »= λ falseW →
  foldlMB (stepTh trueW) (trueW ∷ replicate N falseW) (upTo N) »= λ thF →
  mkNot (nth thF (suc h) falseW) »= λ ng →
  mkAnd (nth thF h falseW) ng

--  Start allocation after the N primary inputs and return the full gate list
--  with its output identifier.
popcountEqNet : (N h : ℕ) → List Op × ℕ
popcountEqNet N h =
  let (outId , _ , ops) = popBuilder N h N
  in ops , outId

--  Evaluate the constructed netlist on an input vector.
netEval : (N h : ℕ) (xs : Vec Bool N) → Bool
netEval N h xs =
  let (ops , outId) = popcountEqNet N h
  in get (runNet (toList xs) ops) outId

------------------------------------------------------------------------
--  Check concrete small widths by refl to catch generator regressions locally.
--  General correctness for every width is NetlistCorrect.netEval-correct;
--  these samples additionally pin exact weight-equals-h behaviour.

private
  --  For N=3, h=2, require exactly two true inputs.
  _ : netEval 3 2 (true  ∷ true  ∷ false ∷ []) ≡ true
  _ = refl
  _ : netEval 3 2 (false ∷ true  ∷ true  ∷ []) ≡ true
  _ = refl
  _ : netEval 3 2 (true  ∷ true  ∷ true  ∷ []) ≡ false
  _ = refl
  _ : netEval 3 2 (true  ∷ false ∷ false ∷ []) ≡ false
  _ = refl
  _ : netEval 3 2 (false ∷ false ∷ false ∷ []) ≡ false
  _ = refl
  --  Check the endpoint radii h=0 and h=N.
  _ : netEval 3 0 (false ∷ false ∷ false ∷ []) ≡ true
  _ = refl
  _ : netEval 3 0 (true  ∷ false ∷ false ∷ []) ≡ false
  _ = refl
  _ : netEval 3 3 (true  ∷ true  ∷ true  ∷ []) ≡ true
  _ = refl
  _ : netEval 3 3 (true  ∷ true  ∷ false ∷ []) ≡ false
  _ = refl
  --  Check the N=4, h=2 instance.
  _ : netEval 4 2 (true  ∷ true  ∷ false ∷ false ∷ []) ≡ true
  _ = refl
  _ : netEval 4 2 (true  ∷ true  ∷ true  ∷ false ∷ []) ≡ false
  _ = refl
