------------------------------------------------------------------------
--  Formalise polynomial FALL functional analysis (iv). FunctionalAnalysis's
--  recoverOracle removes the structural assumption by scanning all 2ⁿ inputs
--  through countT over allVecs n. It proves recovery in principle but does
--  not implement FALL's polynomial analysis. Here inspect distNode k =
--  λ x → HD x k, connected to the verified gate-level netlist by
--  distNode-netlist. Flipping input bit i increases distance by one when
--  xᵢ = kᵢ and decreases it by one otherwise. Comparing the flipped distance
--  with the distance at any reference x, including 0ⁿ, reveals kᵢ. The
--  HD-flipAt-agree and HD-flipAt-disagree laws establish these changes;
--  recoverBitPoly-correct proves exact bit recovery. Applying n comparisons
--  gives fall-poly-recovers-key: recoverKeyPoly (distNode k) x ≡ k, using
--  n+1 distance queries, the reference plus n flips. This polynomial
--  procedure replaces recoverOracle's exponential scan without adding
--  primitives or postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.FALLPoly where

open import Data.Nat using (ℕ; zero; suc; _+_; _≡ᵇ_)
open import Data.Nat.Properties using (+-suc)
open import Data.Bool using (Bool; true; false; not; _xor_; if_then_else_)
open import Data.Fin using (Fin) renaming (zero to fz; suc to fs)
open import Data.Vec using (Vec; _∷_; lookup; tabulate)
open import Data.Vec.Properties using (tabulate-cong; tabulate∘lookup)
open import Data.Empty using (⊥; ⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; _≢_)

open import SFLL.HammingDistance using (HD; b2n; xor-self)
open import Attack.FunctionalAnalysis using (distNode)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Supporting facts about individual bits.

t≢f : true ≢ false
t≢f ()

f≢t : false ≢ true
f≢t ()

--  XOR of a bit and its own negation equals true.
not-xor-self : (a : Bool) → (not a xor a) ≡ true
not-xor-self false = refl
not-xor-self true  = refl

--  Unequal bits XOR to true; negating one makes it equal to the other,
--  whose XOR is then ⊥.
xor-≢-true : (a b : Bool) → a ≢ b → (a xor b) ≡ true
xor-≢-true false false ne = ⊥-elim (ne refl)
xor-≢-true false true  _  = refl
xor-≢-true true  false _  = refl
xor-≢-true true  true  ne = ⊥-elim (ne refl)

not-xor-≢-false : (a b : Bool) → a ≢ b → (not a xor b) ≡ false
not-xor-≢-false false false ne = ⊥-elim (ne refl)
not-xor-≢-false false true  _  = refl
not-xor-≢-false true  false _  = refl
not-xor-≢-false true  true  ne = ⊥-elim (ne refl)

--  Prove m ≡ᵇ m is true and m ≡ᵇ m+2 is false.
≡ᵇ-refl : (m : ℕ) → (m ≡ᵇ m) ≡ true
≡ᵇ-refl zero    = refl
≡ᵇ-refl (suc m) = ≡ᵇ-refl m

≡ᵇ-ss-false : (m : ℕ) → (m ≡ᵇ suc (suc m)) ≡ false
≡ᵇ-ss-false zero    = refl
≡ᵇ-ss-false (suc m) = ≡ᵇ-ss-false m

------------------------------------------------------------------------
--  Define single-bit flipping and establish the ±1 distance laws.

flipAt : Fin n → Vec Bool n → Vec Bool n
flipAt fz     (x ∷ xs) = not x ∷ xs
flipAt (fs i) (x ∷ xs) = x ∷ flipAt i xs

--  Flipping an agreeing coordinate xᵢ = kᵢ increases distance by one.
HD-flipAt-agree : (i : Fin n) (x k : Vec Bool n) → lookup x i ≡ lookup k i →
                  HD (flipAt i x) k ≡ suc (HD x k)
HD-flipAt-agree fz     (a ∷ xs) (b ∷ ks) eq
  rewrite eq | not-xor-self b | xor-self b = refl
HD-flipAt-agree (fs i) (a ∷ xs) (b ∷ ks) eq =
  trans (cong (b2n (a xor b) +_) (HD-flipAt-agree i xs ks eq))
        (+-suc (b2n (a xor b)) (HD xs ks))

--  Flipping a disagreeing coordinate xᵢ ≠ kᵢ decreases distance by one.
HD-flipAt-disagree : (i : Fin n) (x k : Vec Bool n) → lookup x i ≢ lookup k i →
                     HD x k ≡ suc (HD (flipAt i x) k)
HD-flipAt-disagree fz     (a ∷ xs) (b ∷ ks) ne
  rewrite xor-≢-true a b ne | not-xor-≢-false a b ne = refl
HD-flipAt-disagree (fs i) (a ∷ xs) (b ∷ ks) ne =
  trans (cong (b2n (a xor b) +_) (HD-flipAt-disagree i xs ks ne))
        (+-suc (b2n (a xor b)) (HD (flipAt i xs) ks))

------------------------------------------------------------------------
--  Extract one key bit by comparing distances before and after a flip.

--  Return xᵢ when flipping increases distance, indicating agreement;
--  otherwise return ¬xᵢ.
recoverBitPoly : (dist : Vec Bool n → ℕ) (x : Vec Bool n) (i : Fin n) → Bool
recoverBitPoly dist x i =
  if (dist (flipAt i x) ≡ᵇ suc (dist x)) then lookup x i else not (lookup x i)

--  Prove exact bit extraction from one comparison at any reference x.
recoverBitPoly-correct : (k x : Vec Bool n) (i : Fin n) →
                         recoverBitPoly (distNode k) x i ≡ lookup k i
recoverBitPoly-correct k x i with lookup x i in lx | lookup k i in lk
... | true  | true  =
  cong (λ c → if c then true else not true)
       (trans (cong (_≡ᵇ suc (HD x k)) (HD-flipAt-agree i x k (trans lx (sym lk))))
              (≡ᵇ-refl (suc (HD x k))))
... | false | false =
  cong (λ c → if c then false else not false)
       (trans (cong (_≡ᵇ suc (HD x k)) (HD-flipAt-agree i x k (trans lx (sym lk))))
              (≡ᵇ-refl (suc (HD x k))))
... | true  | false =
  cong (λ c → if c then true else not true)
       (trans (cong (λ d → HD (flipAt i x) k ≡ᵇ suc d)
                    (HD-flipAt-disagree i x k (λ e → t≢f (trans (sym lx) (trans e lk)))))
              (≡ᵇ-ss-false (HD (flipAt i x) k)))
... | false | true  =
  cong (λ c → if c then false else not false)
       (trans (cong (λ d → HD (flipAt i x) k ≡ᵇ suc d)
                    (HD-flipAt-disagree i x k (λ e → f≢t (trans (sym lx) (trans e lk)))))
              (≡ᵇ-ss-false (HD (flipAt i x) k)))

------------------------------------------------------------------------
--  Recover all bits using n flip comparisons, with polynomial cost.

recoverKeyPoly : (dist : Vec Bool n → ℕ) (x : Vec Bool n) → Vec Bool n
recoverKeyPoly {n} dist x = tabulate (recoverBitPoly dist x)

--  From any reference x, recover the complete key in n+1 distance queries: the
--  reference and n single-bit flips. This is polynomial rather than the 2ⁿ
--  scan of Attack.FunctionalAnalysis.recoverOracle.
fall-poly-recovers-key : (k x : Vec Bool n) → recoverKeyPoly (distNode k) x ≡ k
fall-poly-recovers-key k x =
  trans (tabulate-cong (recoverBitPoly-correct k x)) (tabulate∘lookup k)
