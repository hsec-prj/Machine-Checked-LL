------------------------------------------------------------------------
--  Realise SFLL-HD protection at gate level. Paper 2's semantic test
--  prot h k x = HD x k ≡ᵇ h in SFLL.HD might otherwise leave OCR claims
--  about an abstract predicate alone. Build the test in Circuit.Core's DSL,
--  including Plug, and prove denotational agreement. Factor protection as
--  [weight (x xor k)=h], completing Tier C: xorK applies per-wire key XOR
--  and xorK-weight gives weight (⟦ xorK k ⟧ x) ≡ HD x k. exactlyH n h
--  uses two-dimensional recursion, muxing sub-counters on duplicated input
--  via dupAll and Const base drivers; exactlyH-spec gives
--  ⟦ exactlyH n h ⟧ v ≡ (weight v ≡ᵇ h) ∷ []. Compose xorK and exactlyH
--  as prot-circuit, with prot-circuit-correct giving prot h k x ∷ [].
--  Finally locked-circuit XORs the host and two protected tests;
--  locked-circuit-correct yields locked h ksec kapp f x ∷ []. Thus the
--  semantic prot/locked OCR results apply unchanged to this synthesised
--  netlist. No postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.Netlist where

open import Data.Nat using (ℕ; zero; suc; _+_; _≡ᵇ_)
open import Data.Bool using (Bool; false; true; not; _∧_; _∨_; _xor_)
open import Data.Bool.Properties using (∧-identityʳ; ∧-zeroʳ; ∨-identityʳ)
open import Data.Fin using (Fin; splitAt)
open import Data.Sum using (_⊎_; inj₁; inj₂; [_,_]′)
open import Data.Vec using (Vec; []; _∷_; _++_; take; drop; zipWith; tabulate; lookup)
open import Data.Vec.Properties using (lookup-splitAt; tabulate∘lookup; tabulate-cong)
open import Function using (id)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; trans; sym)

open import Circuit.Core
open import Circuit.Semantics
open import Circuit.Util.Vec using (take-++; drop-++)
open import SFLL.HammingDistance using (HD; b2n)
open import SFLL.HD using (prot; locked)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Define semantic Hamming weight, or popcount, on wire values.

weight : Vec Bool n → ℕ
weight []       = 0
weight (b ∷ bs) = b2n b + weight bs

--  Identify HD with the weight of coordinatewise x xor k.
HD≡weight-xor : (x k : Vec Bool n) → HD x k ≡ weight (zipWith _xor_ x k)
HD≡weight-xor []       []       = refl
HD≡weight-xor (x ∷ xs) (k ∷ ks) =
  cong (b2n (x xor k) +_) (HD≡weight-xor xs ks)

------------------------------------------------------------------------
--  Implement key XOR as a gate-level layer.

--  For a constant key bit, use a wire when false and an inverter when true:
--  x xor false=x and x xor true=not x.
gateXor : Bool → Circuit 1 1
gateXor false = Id
gateXor true  = Not1

gateXor-spec : (b x : Bool) → ⟦ gateXor b ⟧ (x ∷ []) ≡ (x xor b) ∷ []
gateXor-spec false false = refl
gateXor-spec false true  = refl
gateXor-spec true  false = refl
gateXor-spec true  true  = refl

--  Place one gateXor per key bit in parallel.
xorK : Vec Bool n → Circuit n n
xorK []       = Id
xorK (k ∷ ks) = Par {n₁ = 1} (gateXor k) (xorK ks)

--  Prove the layer denotes coordinatewise XOR with the key.
xorK-spec : (k x : Vec Bool n) → ⟦ xorK k ⟧ x ≡ zipWith _xor_ x k
xorK-spec []       []       = refl
xorK-spec (k ∷ ks) (x ∷ xs) =
  cong₂ _++_
    (trans (cong ⟦ gateXor k ⟧ (take-++ (x ∷ []) xs)) (gateXor-spec k x))
    (trans (cong ⟦ xorK ks ⟧ (drop-++ (x ∷ []) xs)) (xorK-spec ks xs))

------------------------------------------------------------------------
--  Reduce protection through xorK k to popcount of its gate-level output.

xorK-weight : (k x : Vec Bool n) → weight (⟦ xorK k ⟧ x) ≡ HD x k
xorK-weight k x =
  trans (cong weight (xorK-spec k x)) (sym (HD≡weight-xor x k))

------------------------------------------------------------------------
--  Duplicate the remaining input bus to feed both sub-counters.

--  Route output i of v ++ v to input [ id, id ]′ (splitAt n i).
dupIx : (n : ℕ) → Fin (n + n) → Fin n
dupIx n i = [ id , id ]′ (splitAt n i)

dupAll : (n : ℕ) → Circuit n (n + n)
dupAll n = Plug (dupIx n)

dup-lookup : (v : Vec Bool n) (i : Fin (n + n)) →
             lookup v (dupIx n i) ≡ lookup (v ++ v) i
dup-lookup {n} v i = trans (sumL (splitAt n i)) (sym (lookup-splitAt n v v i))
  where
    sumL : (s : Fin n ⊎ Fin n) →
           lookup v ([ id , id ]′ s) ≡ [ lookup v , lookup v ]′ s
    sumL (inj₁ x) = refl
    sumL (inj₂ y) = refl

dupAll-spec : (n : ℕ) (v : Vec Bool n) → ⟦ dupAll n ⟧ v ≡ v ++ v
dupAll-spec n v = trans (tabulate-cong (dup-lookup v)) (tabulate∘lookup (v ++ v))

------------------------------------------------------------------------
--  Construct equality to weight h by two-dimensional recursion. For head b,
--  select exactly h−1 on the rest when true, otherwise exactly h. Mux21
--  combines the two sub-counters run over duplicated rest.

--  Define a single-output false constant by discarding inputs and driving zero.
cFalse : (n : ℕ) → Circuit n 1
cFalse n = Seq (Plug {n} {0} (λ ())) (Const false)

cFalse-spec : (n : ℕ) (v : Vec Bool n) → ⟦ cFalse n ⟧ v ≡ false ∷ []
cFalse-spec n v = refl

--  Use the head bit to select between two sub-results at one recursion level.
mkLevel : (n : ℕ) → Circuit n 1 → Circuit n 1 → Circuit (suc n) 1
mkLevel n sf st =
  Seq (Par {n₁ = 1} Id (dupAll n))
      (Seq (Par {n₁ = 1} Id (Par {n₁ = n} sf st)) Mux21)

--  Express that level's semantics through the subcircuit denotations.
level-reduce : (n : ℕ) (sf st : Circuit n 1) (b : Bool) (rest : Vec Bool n)
               (af at : Bool)
               (pf : ⟦ sf ⟧ rest ≡ af ∷ []) (pt : ⟦ st ⟧ rest ≡ at ∷ []) →
               ⟦ mkLevel n sf st ⟧ (b ∷ rest)
                 ≡ ((af ∧ not b) ∨ (at ∧ b)) ∷ []
level-reduce n sf st b rest af at pf pt =
  trans (cong (λ w → ⟦ Mux21 ⟧ (⟦ Par {n₁ = 1} Id (Par {n₁ = n} sf st) ⟧ w)) stepA)
        (cong ⟦ Mux21 ⟧ stepB)
  where
    stepA : ⟦ Par {n₁ = 1} Id (dupAll n) ⟧ (b ∷ rest) ≡ b ∷ (rest ++ rest)
    stepA = cong₂ _++_ (take-++ (b ∷ []) rest)
                       (trans (cong ⟦ dupAll n ⟧ (drop-++ (b ∷ []) rest))
                              (dupAll-spec n rest))
    stepB : ⟦ Par {n₁ = 1} Id (Par {n₁ = n} sf st) ⟧ (b ∷ (rest ++ rest))
              ≡ b ∷ af ∷ at ∷ []
    stepB = cong₂ _++_ (take-++ (b ∷ []) (rest ++ rest))
              (trans (cong ⟦ Par {n₁ = n} sf st ⟧ (drop-++ (b ∷ []) (rest ++ rest)))
                     (cong₂ _++_ (trans (cong ⟦ sf ⟧ (take-++ rest rest)) pf)
                                 (trans (cong ⟦ st ⟧ (drop-++ rest rest)) pt)))

--  Make exactlyH n h output the indicator [weight v=h].
exactlyH : (n h : ℕ) → Circuit n 1
exactlyH zero    zero    = Const true
exactlyH zero    (suc h) = Const false
exactlyH (suc n) zero    = mkLevel n (exactlyH n zero)    (cFalse n)
exactlyH (suc n) (suc h) = mkLevel n (exactlyH n (suc h)) (exactlyH n h)

--  Simplify (af ∧ ¬b) ∨ (at ∧ b): false b selects af and true b selects at.
mux-false : (af at : Bool) → ((af ∧ not false) ∨ (at ∧ false)) ≡ af
mux-false af at =
  trans (cong ((af ∧ true) ∨_) (∧-zeroʳ at))
        (trans (∨-identityʳ (af ∧ true)) (∧-identityʳ af))

mux-true : (af at : Bool) → ((af ∧ not true) ∨ (at ∧ true)) ≡ at
mux-true af at =
  trans (cong (_∨ (at ∧ true)) (∧-zeroʳ af)) (∧-identityʳ at)

exactlyH-spec : (n h : ℕ) (v : Vec Bool n) →
                ⟦ exactlyH n h ⟧ v ≡ (weight v ≡ᵇ h) ∷ []
exactlyH-spec zero    zero    []         = refl
exactlyH-spec zero    (suc h) []         = refl
exactlyH-spec (suc n) zero    (false ∷ rest) =
  trans (level-reduce n (exactlyH n zero) (cFalse n) false rest
           (weight rest ≡ᵇ zero) false
           (exactlyH-spec n zero rest) (cFalse-spec n rest))
        (cong (_∷ []) (mux-false (weight rest ≡ᵇ zero) false))
exactlyH-spec (suc n) zero    (true ∷ rest) =
  trans (level-reduce n (exactlyH n zero) (cFalse n) true rest
           (weight rest ≡ᵇ zero) false
           (exactlyH-spec n zero rest) (cFalse-spec n rest))
        (cong (_∷ []) (mux-true (weight rest ≡ᵇ zero) false))
exactlyH-spec (suc n) (suc h) (false ∷ rest) =
  trans (level-reduce n (exactlyH n (suc h)) (exactlyH n h) false rest
           (weight rest ≡ᵇ suc h) (weight rest ≡ᵇ h)
           (exactlyH-spec n (suc h) rest) (exactlyH-spec n h rest))
        (cong (_∷ []) (mux-false (weight rest ≡ᵇ suc h) (weight rest ≡ᵇ h)))
exactlyH-spec (suc n) (suc h) (true ∷ rest) =
  trans (level-reduce n (exactlyH n (suc h)) (exactlyH n h) true rest
           (weight rest ≡ᵇ suc h) (weight rest ≡ᵇ h)
           (exactlyH-spec n (suc h) rest) (exactlyH-spec n h rest))
        (cong (_∷ []) (mux-true (weight rest ≡ᵇ suc h) (weight rest ≡ᵇ h)))

------------------------------------------------------------------------
--  Assemble the full gate-level protection test and prove correctness.

prot-circuit : (h : ℕ) (k : Vec Bool n) → Circuit n 1
prot-circuit {n} h k = Seq (xorK k) (exactlyH n h)

prot-circuit-correct : (h : ℕ) (k x : Vec Bool n) →
                       ⟦ prot-circuit h k ⟧ x ≡ prot h k x ∷ []
prot-circuit-correct {n} h k x =
  trans (exactlyH-spec n h (⟦ xorK k ⟧ x))
        (cong (λ w → (w ≡ᵇ h) ∷ []) (xorK-weight k x))

------------------------------------------------------------------------
--  Complete the lock with ⟦ locked-circuit ⟧ ≡ locked, where
--  locked h ksec kapp f x = (f x xor prot h ksec x) xor prot h kapp x.
--  Triplicate inputs for the host and two tests, then XOR their single-bit outputs.

--  Route three bus copies as v ↦ v ++ (v ++ v).
tripleIx : (n : ℕ) → Fin (n + (n + n)) → Fin n
tripleIx n i = [ id , dupIx n ]′ (splitAt n i)

tripleAll : (n : ℕ) → Circuit n (n + (n + n))
tripleAll n = Plug (tripleIx n)

tripleAll-spec : (n : ℕ) (v : Vec Bool n) → ⟦ tripleAll n ⟧ v ≡ v ++ (v ++ v)
tripleAll-spec n v =
  trans (tabulate-cong triple-lookup) (tabulate∘lookup (v ++ (v ++ v)))
  where
    sumL : (s : Fin n ⊎ Fin (n + n)) →
           lookup v ([ id , dupIx n ]′ s) ≡ [ lookup v , lookup (v ++ v) ]′ s
    sumL (inj₁ x) = refl
    sumL (inj₂ y) = dup-lookup v y
    triple-lookup : (i : Fin (n + (n + n))) →
                    lookup v (tripleIx n i) ≡ lookup (v ++ (v ++ v)) i
    triple-lookup i = trans (sumL (splitAt n i)) (sym (lookup-splitAt n v (v ++ v) i))

--  Compute three-wire XOR as (a xor b) xor c.
xor3 : Circuit 3 1
xor3 = Seq (Par {n₁ = 2} Xor2 Id) Xor2

xor3-spec : (a b c : Bool) → ⟦ xor3 ⟧ (a ∷ b ∷ c ∷ []) ≡ ((a xor b) xor c) ∷ []
xor3-spec a b c =
  cong ⟦ Xor2 ⟧
    (cong₂ _++_ (cong ⟦ Xor2 ⟧ (take-++ (a ∷ b ∷ []) (c ∷ [])))
                (drop-++ (a ∷ b ∷ []) (c ∷ [])))

--  Combine host Cf denoting f and the two protected tests through xor3.
locked-circuit : (Cf : Circuit n 1) (h : ℕ) (ksec kapp : Vec Bool n) → Circuit n 1
locked-circuit {n} Cf h ksec kapp =
  Seq (tripleAll n)
      (Seq (Par {n₁ = n} Cf
              (Par {n₁ = n} (prot-circuit h ksec) (prot-circuit h kapp)))
           xor3)

locked-circuit-correct :
  (Cf : Circuit n 1) (f : Vec Bool n → Bool)
  (cf-ok : (x : Vec Bool n) → ⟦ Cf ⟧ x ≡ f x ∷ [])
  (h : ℕ) (ksec kapp x : Vec Bool n) →
  ⟦ locked-circuit Cf h ksec kapp ⟧ x ≡ locked h ksec kapp f x ∷ []
locked-circuit-correct {n} Cf f cf-ok h ksec kapp x =
  trans (cong (λ w → ⟦ xor3 ⟧ (⟦ mid ⟧ w)) (tripleAll-spec n x))
        (trans (cong ⟦ xor3 ⟧ stepM)
               (xor3-spec (f x) (prot h ksec x) (prot h kapp x)))
  where
    mid = Par {n₁ = n} Cf (Par {n₁ = n} (prot-circuit h ksec) (prot-circuit h kapp))
    stepM : ⟦ mid ⟧ (x ++ (x ++ x))
              ≡ f x ∷ prot h ksec x ∷ prot h kapp x ∷ []
    stepM = cong₂ _++_
      (trans (cong ⟦ Cf ⟧ (take-++ x (x ++ x))) (cf-ok x))
      (trans (cong ⟦ Par {n₁ = n} (prot-circuit h ksec) (prot-circuit h kapp) ⟧
                   (drop-++ x (x ++ x)))
             (cong₂ _++_
               (trans (cong ⟦ prot-circuit h ksec ⟧ (take-++ x x))
                      (prot-circuit-correct h ksec x))
               (trans (cong ⟦ prot-circuit h kapp ⟧ (drop-++ x x))
                      (prot-circuit-correct h kapp x))))
