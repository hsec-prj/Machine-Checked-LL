------------------------------------------------------------------------
--  Extend footprint bounds to an XOR composition of AND-type Anti-SAT blocks.
--  Attack.FootprintSAT treats one complementary pair with footprint k₁.
--  For m blocks the footprint contains at most m corruption points. The
--  cascade f bs x = f x xor (block₁ ⊕ … ⊕ blockₘ)(x) reduces to f away
--  from every block's first component, as cascade-off proves. A DIP missing
--  all secret corruption points can therefore eliminate only keys whose
--  footprints it hits. Reusing the input-space unprobed-pair pigeonhole
--  argument, two missed points yield distinct block vectors with unqueried
--  footprints. Both remain consistent after q DIPs when 2+q ≤ 2ⁿ. Thus
--  cascade-SAT-lb leaves the whole cascade key undetermined for any block
--  count, generalising the single-point bound without postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CascadeSAT where

open import Data.Nat using (ℕ; suc; _+_; _^_; _≤_; _≡ᵇ_)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_)
open import Data.Bool.Properties using (xor-identityʳ)
open import Data.Fin using (Fin; zero; suc)
open import Data.Vec using (Vec; []; _∷_; lookup; replicate; head)
open import Data.Vec.Properties using (lookup-replicate)
open import Data.Product using (_×_; _,_; proj₁; proj₂; ∃)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; _≢_)

open import SFLL.HD using (prot)
open import SFLL.HammingDistance using (HD-refl)
open import Security.AntiSat using (antiSat; prot0-false)
open import Attack.SARLockQueryBound using (unprobed-pair)
open import Attack.FootprintSAT using (consistentOnK; antiSat-off)

private
  variable
    n q m : ℕ

------------------------------------------------------------------------
--  XOR the outputs of m Anti-SAT blocks with host f to form the cascade.

Block : ℕ → Set
Block n = Vec Bool n × Vec Bool n

cascadeBlocks : Vec (Block n) m → Vec Bool n → Bool
cascadeBlocks []       x = false
cascadeBlocks (b ∷ bs) x = antiSat (proj₁ b) (proj₂ b) x xor cascadeBlocks bs x

cascade : (f : Vec Bool n → Bool) → Vec (Block n) m → Vec Bool n → Bool
cascade f bs x = f x xor cascadeBlocks bs x

------------------------------------------------------------------------
--  Outside all first-component footprint points, the cascade equals f.

cascadeBlocks-off : (bs : Vec (Block n) m) (x : Vec Bool n) →
                    ((j : Fin m) → proj₁ (lookup bs j) ≢ x) →
                    cascadeBlocks bs x ≡ false
cascadeBlocks-off []       x av = refl
cascadeBlocks-off (b ∷ bs) x av =
  cong₂ _xor_
    (antiSat-off (proj₁ b) (proj₂ b) x (λ e → av zero (sym e)))
    (cascadeBlocks-off bs x (λ j → av (suc j)))

cascade-off : (f : Vec Bool n → Bool) (bs : Vec (Block n) m) (x : Vec Bool n) →
              ((j : Fin m) → proj₁ (lookup bs j) ≢ x) →
              cascade f bs x ≡ f x
cascade-off f bs x av =
  trans (cong (f x xor_) (cascadeBlocks-off bs x av)) (xor-identityʳ (f x))

------------------------------------------------------------------------
--  A block-vector key whose footprint avoids every probe agrees with the
--  secret on those probes, since both evaluations reduce to f.

cascade-consistent :
  (f : Vec Bool n → Bool) (bs ksec : Vec (Block n) m) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) (j : Fin m) → proj₁ (lookup ksec j) ≢ lookup xs i) →
  ((i : Fin q) (j : Fin m) → proj₁ (lookup bs   j) ≢ lookup xs i) →
  consistentOnK (cascade f) ksec xs bs
cascade-consistent f bs ksec xs avsec avk i =
  trans (cascade-off f bs   (lookup xs i) (λ j → avk   i j))
        (sym (cascade-off f ksec (lookup xs i) (λ j → avsec i j)))

------------------------------------------------------------------------
--  After q DIPs avoiding the secret's corruption points with 2 + q ≤ 2ⁿ,
--  two distinct block vectors remain consistent, preventing determination
--  of the cascade key regardless of the number of blocks.

cascade-SAT-lb :
  (f : Vec Bool n → Bool) (ksec : Vec (Block n) (suc m)) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) (j : Fin (suc m)) → proj₁ (lookup ksec j) ≢ lookup xs i) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOnK (cascade f) ksec xs k₁
    × consistentOnK (cascade f) ksec xs k₂
cascade-SAT-lb {n} {m} {q} f ksec xs avsec bound =
  k₁ , k₂ , k≢ , c₁ , c₂
  where
    up   = unprobed-pair xs bound
    p₁   = proj₁ up
    p₂   = proj₁ (proj₂ up)
    p≢   = proj₁ (proj₂ (proj₂ up))
    avp₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    avp₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))

    k₁ : Vec (Block n) (suc m)
    k₁ = replicate (suc m) (p₁ , p₂)
    k₂ : Vec (Block n) (suc m)
    k₂ = (p₂ , p₁) ∷ replicate m (p₁ , p₂)

    --  All blocks in k₁ begin with p₁, which every probe misses.
    avk₁ : (i : Fin q) (j : Fin (suc m)) → proj₁ (lookup k₁ j) ≢ lookup xs i
    avk₁ i j e =
      avp₁ i (sym (trans (sym (cong proj₁ (lookup-replicate j (p₁ , p₂)))) e))

    --  The head of k₂ begins with unprobed p₂; its remaining blocks begin with p₁.
    avk₂ : (i : Fin q) (j : Fin (suc m)) → proj₁ (lookup k₂ j) ≢ lookup xs i
    avk₂ i zero     e = avp₂ i (sym e)
    avk₂ i (suc j') e =
      avp₁ i (sym (trans (sym (cong proj₁ (lookup-replicate j' (p₁ , p₂)))) e))

    k≢ : k₁ ≢ k₂
    k≢ e = p≢ (cong proj₁ (cong head e))

    c₁ = cascade-consistent f k₁ ksec xs avsec avk₁
    c₂ = cascade-consistent f k₂ ksec xs avsec avk₂

------------------------------------------------------------------------
--  Show the surviving keys are functionally distinct rather than merely
--  sharing a fibre. They disagree at unprobed p₂, where only k₂'s head corrupts.

private
  not-≢ : (b : Bool) → b ≢ not b
  not-≢ true  ()
  not-≢ false ()

  xor-true : (b : Bool) → (b xor true) ≡ not b
  xor-true true  = refl
  xor-true false = refl

  --  The identity HD k k = 0 makes prot 0 k k true.
  prot0-diag : (k : Vec Bool n) → prot 0 k k ≡ true
  prot0-diag k = cong (λ d → d ≡ᵇ 0) (HD-refl k)

--  For p₁ ≢ p₂, the keys constructed by cascade-SAT-lb differ at p₂,
--  establishing genuine ambiguity between functions.
cascade-differ :
  (f : Vec Bool n → Bool) (p₁ p₂ : Vec Bool n) → p₁ ≢ p₂ →
  cascade f (replicate (suc m) (p₁ , p₂)) p₂
    ≢ cascade f ((p₂ , p₁) ∷ replicate m (p₁ , p₂)) p₂
cascade-differ {n} {m} f p₁ p₂ p≢ e =
  not-≢ (f p₂) (trans (sym lhsEq) (trans e rhsEq))
  where
    av-rep : (k : ℕ) (j : Fin k) → proj₁ (lookup (replicate k (p₁ , p₂)) j) ≢ p₂
    av-rep k j eq = p≢ (trans (sym (cong proj₁ (lookup-replicate j (p₁ , p₂)))) eq)

    cbHead : antiSat p₂ p₁ p₂ ≡ true
    cbHead = cong₂ _∧_ (prot0-diag p₂)
                       (cong not (prot0-false p₂ p₁ (λ eq → p≢ (sym eq))))

    lhsEq : cascade f (replicate (suc m) (p₁ , p₂)) p₂ ≡ f p₂
    lhsEq = cascade-off f (replicate (suc m) (p₁ , p₂)) p₂ (av-rep (suc m))

    cbTail : cascadeBlocks (replicate m (p₁ , p₂)) p₂ ≡ false
    cbTail = cascadeBlocks-off (replicate m (p₁ , p₂)) p₂ (av-rep m)

    rhsEq : cascade f ((p₂ , p₁) ∷ replicate m (p₁ , p₂)) p₂ ≡ not (f p₂)
    rhsEq = trans (cong (f p₂ xor_) (cong₂ _xor_ cbHead cbTail)) (xor-true (f p₂))
