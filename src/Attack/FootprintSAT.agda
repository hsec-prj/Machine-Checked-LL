------------------------------------------------------------------------
--  Generalise SAT lower bounds through footprints over arbitrary key spaces,
--  including complementary AND-type Anti-SAT pairs. This resolves the
--  2026-06-22 RED concern about a non-vacuous GenericSAT extension.
--  gen-SAT-lb assumes G : Vec Bool n → ProtGadget n with corruption
--  concentrated at its single key. The AND-type Anti-SAT instance uses pairs
--  (k₁,k₂) mapping many-to-one to corruption points, making a naive bound
--  over 2^(2n) keys vacuous, the AND-tree-of-points trap. Abstract a footprint
--  fp : K → Vec Bool n where an oracle may differ from a key-independent
--  base. A DIP avoiding fp ksec eliminates only footprints it hits. Run
--  SARLockQueryBound.unprobed-pair on the 2ⁿ input points rather than K.
--  footprint-SAT-lb leaves keys with two distinct footprints consistent
--  after q DIPs with 2+q ≤ 2ⁿ, leaving the footprint and locked function
--  undetermined. point-footprint-lb uses K=Vec Bool n and fp=id to recover
--  the point/SARLock bound. antiSat-footprint-lb uses a pair and fp=proj₁
--  to give exponential cost for its function-determining k₁. antiSat-fibre
--  additionally shows that equal first components with k₂,k₂' ≠ k₁ are
--  observationally identical, rendering the second component information-
--  theoretically unrecoverable, as in graph/Attack/CycSATComposeFibre.
--  Recovery is therefore exponential in the determining component and
--  limited to its observational class. No postulates are used.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.FootprintSAT where

open import Data.Nat using (ℕ; suc; _+_; _^_; _≤_)
open import Data.Bool using (Bool; true; false; _xor_; _∧_; not)
open import Data.Bool.Properties using (xor-identityʳ)
open import Data.Fin using (Fin)
open import Data.Vec using (Vec; lookup)
open import Data.Product using (_×_; _,_; ∃; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; _≢_)

open import SFLL.HD using (prot)
open import Security.AntiSat using (antiSat; antiSat≡prot0; prot0-false)
open import Attack.SARLockQueryBound using (unprobed-pair)
open import Locking.GenericLock using (ProtGadget; pointGadget)
open import Attack.GenericSAT using (actGen; baseGen; gen-offdiag; point-PointConc)

private
  variable
    n q : ℕ

------------------------------------------------------------------------
--  Define consistency over probes for arbitrary K, extending consistentOn's
--  fixed Vec Bool n key type.

consistentOnK : {K : Set} (eval : K → Vec Bool n → Bool)
                (ksec : K) (xs : Vec (Vec Bool n) q) (k : K) → Set
consistentOnK {q = q} eval ksec xs k =
  (i : Fin q) → eval k (lookup xs i) ≡ eval ksec (lookup xs i)

------------------------------------------------------------------------
--  A candidate with an unprobed footprint agrees with the secret wherever
--  both oracles reduce to base, preserving consistency on the probe set.

fp-consistent :
  {K : Set} (act : K → Vec Bool n → Bool) (base : Vec Bool n → Bool)
  (fp : K → Vec Bool n)
  (off : (k : K) (x : Vec Bool n) → x ≢ fp k → base x ≡ act k x)
  (ksec : K) (xs : Vec (Vec Bool n) q) (k : K) →
  ((i : Fin q) → lookup xs i ≢ fp ksec) →
  ((i : Fin q) → lookup xs i ≢ fp k) →
  consistentOnK act ksec xs k
fp-consistent act base fp off ksec xs k avs avk i =
  trans (sym (off k    (lookup xs i) (avk i)))
        (     off ksec (lookup xs i) (avs i))

------------------------------------------------------------------------
--  Prove the arbitrary-key-space footprint bound using unprobed-pair on
--  the 2ⁿ input-point space.

footprint-SAT-lb :
  {K : Set} (act : K → Vec Bool n → Bool) (base : Vec Bool n → Bool)
  (fp : K → Vec Bool n)
  (off : (k : K) (x : Vec Bool n) → x ≢ fp k → base x ≡ act k x)
  (mkKey : (p p' : Vec Bool n) → p ≢ p' → K)
  (mkfp : (p p' : Vec Bool n) (ne : p ≢ p') → fp (mkKey p p' ne) ≡ p)
  (ksec : K) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ fp ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (fp k₁ ≢ fp k₂)
    × consistentOnK act ksec xs k₁
    × consistentOnK act ksec xs k₂
footprint-SAT-lb {q = q} act base fp off mkKey mkfp ksec xs avs bound =
  k₁ , k₂ , fpne , c₁ , c₂
  where
    up   = unprobed-pair xs bound
    p₁   = proj₁ up
    p₂   = proj₁ (proj₂ up)
    p≢   = proj₁ (proj₂ (proj₂ up))
    avp₁ = proj₁ (proj₂ (proj₂ (proj₂ up)))
    avp₂ = proj₂ (proj₂ (proj₂ (proj₂ up)))
    p≢′  : p₂ ≢ p₁
    p≢′  = λ e → p≢ (sym e)
    k₁   = mkKey p₁ p₂ p≢
    k₂   = mkKey p₂ p₁ p≢′
    fp1  : fp k₁ ≡ p₁
    fp1  = mkfp p₁ p₂ p≢
    fp2  : fp k₂ ≡ p₂
    fp2  = mkfp p₂ p₁ p≢′
    fpne : fp k₁ ≢ fp k₂
    fpne e = p≢ (trans (sym fp1) (trans e fp2))
    avk₁ : (i : Fin q) → lookup xs i ≢ fp k₁
    avk₁ i e = avp₁ i (trans e fp1)
    avk₂ : (i : Fin q) → lookup xs i ≢ fp k₂
    avk₂ i e = avp₂ i (trans e fp2)
    c₁ = fp-consistent act base fp off ksec xs k₁ avs avk₁
    c₂ = fp-consistent act base fp off ksec xs k₂ avs avk₂

------------------------------------------------------------------------
--  Instantiate fp=id so each point/SARLock key is its own footprint,
--  recovering the generic point bound.

point-footprint-lb :
  (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (ksec : Vec Bool n) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (k₁ ≢ k₂)
    × consistentOnK (actGen f gS pointGadget) ksec xs k₁
    × consistentOnK (actGen f gS pointGadget) ksec xs k₂
point-footprint-lb f gS ksec xs avs bound =
  footprint-SAT-lb (actGen f gS pointGadget) (baseGen f gS) (λ k → k)
    (gen-offdiag f gS pointGadget point-PointConc)
    (λ p _ _ → p) (λ _ _ _ → refl)
    ksec xs avs bound

------------------------------------------------------------------------
--  Instantiate the complementary AND-type Anti-SAT block with key pair
--  (k₁,k₂) and first-component footprint k₁.

--  Define the activated oracle as host XOR Anti-SAT block.
actAS : (f : Vec Bool n → Bool) → (Vec Bool n × Vec Bool n) → Vec Bool n → Bool
actAS f (k₁ , k₂) x = f x xor antiSat k₁ k₂ x

--  Away from k₁, prot 0 k₁ x is false and the oracle reduces to its host.
antiSat-off : (k₁ k₂ x : Vec Bool n) → x ≢ k₁ → antiSat k₁ k₂ x ≡ false
antiSat-off k₁ k₂ x x≢k₁ =
  cong (_∧ not (prot 0 k₂ x)) (prot0-false x k₁ x≢k₁)

actAS-off : (f : Vec Bool n → Bool) (k : Vec Bool n × Vec Bool n) (x : Vec Bool n) →
            x ≢ proj₁ k → f x ≡ actAS f k x
actAS-off f (k₁ , k₂) x x≢k₁ =
  sym (trans (cong (f x xor_) (antiSat-off k₁ k₂ x x≢k₁)) (xor-identityʳ (f x)))

--  After q DIPs avoiding the secret's k₁ with 2+q ≤ 2ⁿ, retain two distinct
--  first components. Determining the locked function's k₁ therefore needs
--  an exponential query budget.
antiSat-footprint-lb :
  (f : Vec Bool n → Bool)
  (ksec : Vec Bool n × Vec Bool n) (xs : Vec (Vec Bool n) q) →
  ((i : Fin q) → lookup xs i ≢ proj₁ ksec) →
  2 + q ≤ 2 ^ n →
  ∃ λ k₁ → ∃ λ k₂ →
    (proj₁ k₁ ≢ proj₁ k₂)
    × consistentOnK (actAS f) ksec xs k₁
    × consistentOnK (actAS f) ksec xs k₂
antiSat-footprint-lb f ksec xs avs bound =
  footprint-SAT-lb (actAS f) f proj₁ (actAS-off f)
    (λ p p' _ → (p , p')) (λ _ _ _ → refl)
    ksec xs avs bound

------------------------------------------------------------------------
--  By antiSat≡prot0, keys sharing k₁ with unequal components have identical
--  observations. The second component cannot be recovered information-
--  theoretically, giving the genuine pair-key fibre as in the graph-track
--  CycSATComposeFibre result.

antiSat-fibre :
  (f : Vec Bool n → Bool) (k₁ k₂ k₂' : Vec Bool n) →
  k₁ ≢ k₂ → k₁ ≢ k₂' → (x : Vec Bool n) →
  actAS f (k₁ , k₂) x ≡ actAS f (k₁ , k₂') x
antiSat-fibre f k₁ k₂ k₂' ne ne' x =
  cong (f x xor_)
       (trans (antiSat≡prot0 k₁ k₂ ne x) (sym (antiSat≡prot0 k₁ k₂' ne' x)))
