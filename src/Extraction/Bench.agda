------------------------------------------------------------------------
--  Verify the core of netlist extraction (E1, D1-A). The C4 measurement layer
--  emits flat gate-level .bench files for ISCAS/SAT tooling. Here Circuit n m
--  is translated into m Boolean expressions over n inputs, with
--  emit-sound : eval (emit c) xs ≡ ⟦ c ⟧ xs. The proof establishes correct
--  Seq composition and Par/Swap/Dup/Plug routing without simulation. A thin,
--  separate unverified renderer produces the Circuit-to-.bench string. The
--  D1-A substitution of a logarithmic-depth popcount macro for exponential
--  exactlyH at emission remains the simulation-based equivalence step of
--  section 8.6, E3; this module's content is machine-checked. Thr t, used
--  for threshold locking rather than SFLL-HD, expands into nested muxes
--  for at least t of n using atLeast and atLeast-correct. Thus the IR needs
--  no counting node and remains a Boolean-expression DAG. No postulates
--  are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.Bench where

open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Fin using (Fin; _↑ˡ_; _↑ʳ_) renaming (zero to fz; suc to fs)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; _xor_)
open import Data.Bool.Properties using (∧-identityʳ; ∧-zeroʳ; ∨-identityʳ)
open import Data.Vec using (Vec; []; _∷_; _++_; map; tabulate; lookup; take; drop)
open import Data.Vec.Properties using
  (lookup∘tabulate; tabulate∘lookup; tabulate-cong;
   lookup-++ˡ; lookup-++ʳ; take++drop≡id; map-++; map-cong; map-∘; lookup-map)
open import Function using (_∘_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; trans; sym; module ≡-Reasoning)

open import Circuit.Core
open import Circuit.Semantics using (⟦_⟧; ones; _≤b_)

open ≡-Reasoning

private
  variable
    n m p k : ℕ

------------------------------------------------------------------------
--  Define Boolean expressions referring to n input wires.

data Expr (n : ℕ) : Set where
  var  : Fin n → Expr n
  con  : Bool → Expr n
  gnot : Expr n → Expr n
  gand : Expr n → Expr n → Expr n
  gor  : Expr n → Expr n → Expr n
  gxor : Expr n → Expr n → Expr n
  gmux : Expr n → Expr n → Expr n → Expr n     --  sel ∷ a ∷ b

evalE : Expr n → Vec Bool n → Bool
evalE (var i)      xs = lookup xs i
evalE (con b)      xs = b
evalE (gnot e)     xs = not (evalE e xs)
evalE (gand a b)   xs = evalE a xs ∧ evalE b xs
evalE (gor a b)    xs = evalE a xs ∨ evalE b xs
evalE (gxor a b)   xs = evalE a xs xor evalE b xs
evalE (gmux s a b) xs = (evalE a xs ∧ not (evalE s xs)) ∨ (evalE b xs ∧ evalE s xs)

--  Evaluate each wire of the netlist's output bus.
eval : Vec (Expr n) m → Vec Bool n → Vec Bool m
eval es xs = map (λ e → evalE e xs) es

------------------------------------------------------------------------
--  Substitute expressions simultaneously for input variables. This connects
--  Seq's second-stage inputs to first-stage outputs and weakens variables
--  for Par and Swap.

sub : (Fin p → Expr n) → Expr p → Expr n
sub σ (var i)      = σ i
sub σ (con b)      = con b
sub σ (gnot e)     = gnot (sub σ e)
sub σ (gand a b)   = gand (sub σ a) (sub σ b)
sub σ (gor a b)    = gor (sub σ a) (sub σ b)
sub σ (gxor a b)   = gxor (sub σ a) (sub σ b)
sub σ (gmux s a b) = gmux (sub σ s) (sub σ a) (sub σ b)

--  Expand Thr as nested muxes testing whether at least t operands are true.
atLeast : ℕ → Vec (Expr n) k → Expr n
atLeast zero    _        = con true
atLeast (suc t) []       = con false
atLeast (suc t) (e ∷ es) = gmux e (atLeast (suc t) es) (atLeast t es)

------------------------------------------------------------------------
--  Define circuit emission.

emit : Circuit n m → Vec (Expr n) m
emit Id        = tabulate var
emit Not1      = gnot (var fz) ∷ []
emit And2      = gand (var fz) (var (fs fz)) ∷ []
emit Or2       = gor (var fz) (var (fs fz)) ∷ []
emit Xor2      = gxor (var fz) (var (fs fz)) ∷ []
emit Mux21     = gmux (var fz) (var (fs fz)) (var (fs (fs fz))) ∷ []
emit (Seq c d) = map (sub (lookup (emit c))) (emit d)
emit (Par {n₁ = n₁} {n₂ = n₂} c d) =
  map (sub (λ i → var (i ↑ˡ n₂))) (emit c) ++
  map (sub (λ j → var (n₁ ↑ʳ j))) (emit d)
emit (Swap {n = n} {m = m}) =
  tabulate (λ j → var (n ↑ʳ j)) ++ tabulate (λ i → var (i ↑ˡ m))
emit Dup       = var fz ∷ var fz ∷ []
emit (Plug f)  = tabulate (var ∘ f)
emit (Const b) = con b ∷ []
emit (Thr t)   = atLeast t (tabulate var) ∷ []

------------------------------------------------------------------------
--  Collect supporting lemmas.

--  Distribute map over tabulate.
map-tabulate : ∀ {A B : Set} (h : A → B) (g : Fin n → A) →
               map h (tabulate g) ≡ tabulate (h ∘ g)
map-tabulate {n = zero}  h g = refl
map-tabulate {n = suc n} h g = cong (h (g fz) ∷_) (map-tabulate h (g ∘ fs))

--  Represent map by tabulating indexed lookups.
map≡tab : ∀ {A B : Set} (h : A → B) (ys : Vec A n) →
          map h ys ≡ tabulate (λ i → h (lookup ys i))
map≡tab h ys =
  trans (sym (tabulate∘lookup (map h ys)))
        (tabulate-cong (λ i → lookup-map i h ys))

--  Evaluate tabulate var to recover the original input bus.
eval-tab-var : (xs : Vec Bool n) → eval (tabulate var) xs ≡ xs
eval-tab-var xs =
  trans (map-tabulate (λ e → evalE e xs) var) (tabulate∘lookup xs)

--  Recover left and right bus halves under Par/Swap variable weakening.
takeEq : ∀ n {m} (xs : Vec Bool (n + m)) →
         tabulate {n = n} (λ i → lookup xs (i ↑ˡ m)) ≡ take n xs
takeEq n {m} xs =
  trans (tabulate-cong
          (λ i → trans (cong (λ z → lookup z (i ↑ˡ m))
                             (sym (take++drop≡id n xs)))
                       (lookup-++ˡ (take n xs) (drop n xs) i)))
        (tabulate∘lookup (take n xs))

dropEq : ∀ n {m} (xs : Vec Bool (n + m)) →
         tabulate {n = m} (λ j → lookup xs (n ↑ʳ j)) ≡ drop n xs
dropEq n {m} xs =
  trans (tabulate-cong
          (λ j → trans (cong (λ z → lookup z (n ↑ʳ j))
                             (sym (take++drop≡id n xs)))
                       (lookup-++ʳ (take n xs) (drop n xs) j)))
        (tabulate∘lookup (drop n xs))

------------------------------------------------------------------------
--  Prove substitution preserves the intended semantics.

sub-correct : (σ : Fin p → Expr n) (e : Expr p) (xs : Vec Bool n) →
              evalE (sub σ e) xs ≡ evalE e (tabulate (λ i → evalE (σ i) xs))
sub-correct σ (var i)      xs = sym (lookup∘tabulate (λ i → evalE (σ i) xs) i)
sub-correct σ (con b)      xs = refl
sub-correct σ (gnot e)     xs = cong not (sub-correct σ e xs)
sub-correct σ (gand a b)   xs = cong₂ _∧_ (sub-correct σ a xs) (sub-correct σ b xs)
sub-correct σ (gor a b)    xs = cong₂ _∨_ (sub-correct σ a xs) (sub-correct σ b xs)
sub-correct σ (gxor a b)   xs = cong₂ _xor_ (sub-correct σ a xs) (sub-correct σ b xs)
sub-correct σ (gmux s a b) xs =
  cong₂ _∨_ (cong₂ _∧_ (sub-correct σ a xs) (cong not (sub-correct σ s xs)))
            (cong₂ _∧_ (sub-correct σ b xs) (sub-correct σ s xs))

------------------------------------------------------------------------
--  Verify expansion of threshold gates.

--  Simplify muxes explicitly because gmux does not reduce definitionally
--  when a ∧ false remains stuck on a.
mux-true : (a b : Bool) → ((a ∧ not true) ∨ (b ∧ true)) ≡ b
mux-true a b = trans (cong (_∨ (b ∧ true)) (∧-zeroʳ a)) (∧-identityʳ b)

mux-false : (a b : Bool) → ((a ∧ not false) ∨ (b ∧ false)) ≡ a
mux-false a b =
  trans (cong ((a ∧ true) ∨_) (∧-zeroʳ b))
        (trans (∨-identityʳ (a ∧ true)) (∧-identityʳ a))

atLeast-correct : (t : ℕ) (es : Vec (Expr n) k) (xs : Vec Bool n) →
                  evalE (atLeast t es) xs ≡ t ≤b ones (eval es xs)
atLeast-correct zero    es       xs = refl
atLeast-correct (suc t) []       xs = refl
atLeast-correct (suc t) (e ∷ es) xs with evalE e xs
... | true  = trans (mux-true  (evalE (atLeast (suc t) es) xs) (evalE (atLeast t es) xs))
                    (atLeast-correct t es xs)
... | false = trans (mux-false (evalE (atLeast (suc t) es) xs) (evalE (atLeast t es) xs))
                    (atLeast-correct (suc t) es xs)

------------------------------------------------------------------------
--  Prove emitted netlists denote ⟦_⟧. legPar factors the work on each Par
--  half without recursion, leaving emit-sound calls only on structural
--  subterms c and d and satisfying termination checking.

legPar : (xs : Vec Bool n) (σ : Fin p → Expr n) (es : Vec (Expr p) m)
         (ys : Vec Bool p) → tabulate (λ i → evalE (σ i) xs) ≡ ys →
         map (λ e → evalE e xs) (map (sub σ) es) ≡ eval es ys
legPar xs σ es ys eq = begin
  map (λ e → evalE e xs) (map (sub σ) es)
    ≡⟨ sym (map-∘ (λ e → evalE e xs) (sub σ) es) ⟩
  map (λ e → evalE (sub σ e) xs) es
    ≡⟨ map-cong (λ e → sub-correct σ e xs) es ⟩
  map (λ e → evalE e (tabulate (λ i → evalE (σ i) xs))) es
    ≡⟨ cong (λ w → map (λ e → evalE e w) es) eq ⟩
  map (λ e → evalE e ys) es
    ∎

emit-sound : (c : Circuit n m) (xs : Vec Bool n) → eval (emit c) xs ≡ ⟦ c ⟧ xs
emit-sound Id    xs              = eval-tab-var xs
emit-sound Not1  (x ∷ [])        = refl
emit-sound And2  (x ∷ y ∷ [])    = refl
emit-sound Or2   (x ∷ y ∷ [])    = refl
emit-sound Xor2  (x ∷ y ∷ [])    = refl
emit-sound Mux21 (s ∷ a ∷ b ∷ []) = refl
emit-sound Dup   (x ∷ [])        = refl
emit-sound (Const b) []          = refl
emit-sound (Plug f) xs = map-tabulate (λ e → evalE e xs) (var ∘ f)
emit-sound (Seq c d) xs = begin
  map (λ e → evalE e xs) (map (sub σ) (emit d))
    ≡⟨ sym (map-∘ (λ e → evalE e xs) (sub σ) (emit d)) ⟩
  map (λ e → evalE (sub σ e) xs) (emit d)
    ≡⟨ map-cong (λ e → sub-correct σ e xs) (emit d) ⟩
  map (λ e → evalE e env) (emit d)
    ≡⟨ cong (eval (emit d)) env≡c ⟩
  eval (emit d) (⟦ c ⟧ xs)
    ≡⟨ emit-sound d (⟦ c ⟧ xs) ⟩
  ⟦ d ⟧ (⟦ c ⟧ xs)
    ∎
  where
    σ   = lookup (emit c)
    env = tabulate (λ i → evalE (σ i) xs)
    env≡c : env ≡ ⟦ c ⟧ xs
    env≡c = trans (sym (map≡tab (λ e → evalE e xs) (emit c))) (emit-sound c xs)
emit-sound (Par {n₁ = n₁} {n₂ = n₂} c d) xs = begin
  map h (map (sub σ₁) (emit c) ++ map (sub σ₂) (emit d))
    ≡⟨ map-++ h (map (sub σ₁) (emit c)) (map (sub σ₂) (emit d)) ⟩
  map h (map (sub σ₁) (emit c)) ++ map h (map (sub σ₂) (emit d))
    ≡⟨ cong₂ _++_
         (trans (legPar xs σ₁ (emit c) (take n₁ xs) (takeEq n₁ xs))
                (emit-sound c (take n₁ xs)))
         (trans (legPar xs σ₂ (emit d) (drop n₁ xs) (dropEq n₁ xs))
                (emit-sound d (drop n₁ xs))) ⟩
  ⟦ c ⟧ (take n₁ xs) ++ ⟦ d ⟧ (drop n₁ xs)
    ∎
  where
    h  = λ (e : Expr (n₁ + n₂)) → evalE e xs
    σ₁ = λ (i : Fin n₁) → var (i ↑ˡ n₂)
    σ₂ = λ (j : Fin n₂) → var (n₁ ↑ʳ j)
emit-sound (Swap {n = n} {m = m}) xs = begin
  map h (tabulate (λ j → var (n ↑ʳ j)) ++ tabulate (λ i → var (i ↑ˡ m)))
    ≡⟨ map-++ h (tabulate (λ j → var (n ↑ʳ j))) (tabulate (λ i → var (i ↑ˡ m))) ⟩
  map h (tabulate (λ j → var (n ↑ʳ j))) ++ map h (tabulate (λ i → var (i ↑ˡ m)))
    ≡⟨ cong₂ _++_ (map-tabulate {n = m} h (λ j → var (n ↑ʳ j)))
                  (map-tabulate {n = n} h (λ i → var (i ↑ˡ m))) ⟩
  tabulate {n = m} (λ j → lookup xs (n ↑ʳ j)) ++ tabulate {n = n} (λ i → lookup xs (i ↑ˡ m))
    ≡⟨ cong₂ _++_ (dropEq n xs) (takeEq n xs) ⟩
  drop n xs ++ take n xs
    ∎
  where h = λ (e : Expr (n + m)) → evalE e xs
emit-sound (Thr t) xs = begin
  evalE (atLeast t (tabulate var)) xs ∷ []
    ≡⟨ cong (_∷ []) (atLeast-correct t (tabulate var) xs) ⟩
  (t ≤b ones (eval (tabulate var) xs)) ∷ []
    ≡⟨ cong (λ w → (t ≤b ones w) ∷ []) (eval-tab-var xs) ⟩
  (t ≤b ones xs) ∷ []
    ∎
