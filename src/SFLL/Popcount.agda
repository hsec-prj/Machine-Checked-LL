------------------------------------------------------------------------
--  D1-B proves efficient popcount equality for every N. Previously, the flat
--  `popcountEqNet` in Extraction.Netlist had only small-N checks by refl, the
--  D1-A simulation proxy. Here an algorithm-level proof establishes that its
--  distribution-thermometer recursion computes the one-hot weight indicator:
--  distF-spec : lookup (distF v) k ≡ (weight v ≡ᵇ toℕ k).
--  Slot k of `distF v` therefore gives `[weight v = toℕ k]` exactly at every
--  width. The key recurrence, `distF (b ∷ v) = shift b false (distF v)`,
--  handles the boundary without separate cases: a set bit shifts the entire
--  distribution up one slot. The proof uses no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.Popcount where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; z≤n; s≤s; _≡ᵇ_)
open import Data.Nat.Properties using (≤-refl; +-mono-≤)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_)
open import Data.Bool.Properties using (∧-identityʳ; ∧-zeroʳ; ∨-identityʳ)
open import Data.Fin using (Fin; zero; suc; toℕ; inject₁; fromℕ)
open import Data.Fin.Properties using (toℕ-inject₁; toℕ-fromℕ)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Product using (Σ; _,_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; trans; sym)

open import SFLL.HammingDistance using (b2n)
open import SFLL.Netlist using (weight)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Use a Boolean mux with bmux b lo hi selecting hi when b is true, otherwise lo.

bmux : Bool → Bool → Bool → Bool
bmux b lo hi = (lo ∧ not b) ∨ (hi ∧ b)

bmux-false : (lo hi : Bool) → bmux false lo hi ≡ lo
bmux-false lo hi =
  trans (cong ((lo ∧ true) ∨_) (∧-zeroʳ hi))
        (trans (∨-identityʳ (lo ∧ true)) (∧-identityʳ lo))

bmux-true : (lo hi : Bool) → bmux true lo hi ≡ hi
bmux-true lo hi = trans (cong (_∨ (hi ∧ true)) (∧-zeroʳ lo)) (∧-identityʳ hi)

------------------------------------------------------------------------
--  Define the distribution thermometer together with its structural lookup.

shift : Bool → Bool → Vec Bool n → Vec Bool (suc n)
shift b prev []       = bmux b false prev ∷ []
shift b prev (x ∷ xs) = bmux b x prev ∷ shift b x xs

distF : Vec Bool n → Vec Bool (suc n)
distF []      = true ∷ []
distF (b ∷ v) = shift b false (distF v)

lookA : Vec Bool n → Fin (suc n) → Bool
lookA []       zero    = false
lookA (x ∷ _)  zero    = x
lookA (_ ∷ xs) (suc k) = lookA xs k

lookB : Bool → Vec Bool n → Fin (suc n) → Bool
lookB prev _        zero    = prev
lookB _    (x ∷ xs) (suc k) = lookB x xs k

shiftL : (b prev : Bool) (d : Vec Bool n) (k : Fin (suc n)) →
         lookup (shift b prev d) k ≡ bmux b (lookA d k) (lookB prev d k)
shiftL b prev []       zero    = refl
shiftL b prev (x ∷ xs) zero    = refl
shiftL b prev (x ∷ xs) (suc k) = shiftL b x xs k

------------------------------------------------------------------------
--  Prove general lookup facts by structural recursion alone.

lookA-inject : (d : Vec Bool n) (k : Fin n) → lookA d (inject₁ k) ≡ lookup d k
lookA-inject (x ∷ xs) zero    = refl
lookA-inject (x ∷ xs) (suc k) = lookA-inject xs k

lookA-last : (d : Vec Bool n) → lookA d (fromℕ n) ≡ false
lookA-last []       = refl
lookA-last (x ∷ xs) = lookA-last xs

--  At a successor index, lookB reduces to lookup in the shifted distribution.
lookB-here : (x : Bool) (xs : Vec Bool n) (k : Fin (suc n)) →
             lookB x xs k ≡ lookup (x ∷ xs) k
lookB-here x xs       zero    = refl
lookB-here x (y ∷ ys) (suc k) = lookB-here y ys k

lookB-suc : (prev : Bool) (d : Vec Bool (suc n)) (k : Fin (suc n)) →
            lookB prev d (suc k) ≡ lookup d k
lookB-suc prev (x ∷ xs) k = lookB-here x xs k

------------------------------------------------------------------------
--  Bound the weight, forcing the top-slot ≡ᵇ comparison to be false.

b2n≤1 : (b : Bool) → b2n b ≤ 1
b2n≤1 false = z≤n
b2n≤1 true  = ≤-refl

weight-bound : (v : Vec Bool n) → weight v ≤ n
weight-bound []      = z≤n
weight-bound (b ∷ v) = +-mono-≤ (b2n≤1 b) (weight-bound v)

≤⇒≡ᵇsuc-false : ∀ {m p} → m ≤ p → (m ≡ᵇ suc p) ≡ false
≤⇒≡ᵇsuc-false {zero}            _        = refl
≤⇒≡ᵇsuc-false {suc m} {suc p} (s≤s le) = ≤⇒≡ᵇsuc-false {m} {p} le

------------------------------------------------------------------------
--  Split any index in `Fin (suc m)` into an interior `inject₁ k'` or the final
--  index `fromℕ m`.

finView : (k : Fin (suc n)) →
          (Σ (Fin n) λ k′ → k ≡ inject₁ k′) ⊎ (k ≡ fromℕ n)
finView {zero}  zero    = inj₂ refl
finView {suc n} zero    = inj₁ (zero , refl)
finView {suc n} (suc k) with finView k
... | inj₁ (k′ , eq) = inj₁ (suc k′ , cong suc eq)
... | inj₂ eq        = inj₂ (cong suc eq)

------------------------------------------------------------------------
--  Establish correctness by mutual recursion over the input vector.

distF-spec  : (v : Vec Bool n) (k : Fin (suc n)) →
              lookup (distF v) k ≡ (weight v ≡ᵇ toℕ k)
lookAspec   : (v : Vec Bool n) (k : Fin (suc (suc n))) →
              lookA (distF v) k ≡ (weight v ≡ᵇ toℕ k)
lookBspec   : (v : Vec Bool n) (k : Fin (suc (suc n))) →
              lookB false (distF v) k ≡ (suc (weight v) ≡ᵇ toℕ k)

distF-spec []          zero    = refl
distF-spec (false ∷ v) k =
  trans (shiftL false false (distF v) k)
        (trans (bmux-false (lookA (distF v) k) (lookB false (distF v) k))
               (lookAspec v k))
distF-spec (true ∷ v)  k =
  trans (shiftL true false (distF v) k)
        (trans (bmux-true (lookA (distF v) k) (lookB false (distF v) k))
               (lookBspec v k))

lookAspec v k with finView k
... | inj₁ (k′ , refl) =
  trans (lookA-inject (distF v) k′)
        (trans (distF-spec v k′)
               (cong (weight v ≡ᵇ_) (sym (toℕ-inject₁ k′))))
... | inj₂ refl =
  trans (lookA-last (distF v))
        (sym (trans (cong (weight v ≡ᵇ_) (toℕ-fromℕ (suc _)))
                    (≤⇒≡ᵇsuc-false (weight-bound v))))

lookBspec v zero     = refl
lookBspec v (suc k′) = trans (lookB-suc false (distF v) k′) (distF-spec v k′)
