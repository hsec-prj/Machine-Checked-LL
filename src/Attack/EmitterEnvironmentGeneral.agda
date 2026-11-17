------------------------------------------------------------------------
-- Inhabited emitter environments for every input width, host, and key.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}
module Attack.EmitterEnvironmentGeneral where

open import Data.Bool using (Bool)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.List.Properties using (length-++)
open import Data.Nat using (ℕ; _+_; _≤_; _<_)
open import Data.Nat.Properties using (+-mono-≤; ≤-refl; m≤m+n; +-comm; +-assoc)
open import Data.Vec using (Vec; toList)
open import Data.Vec.Properties using (length-toList)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; subst; subst₂)
open import Extraction.Netlist using (upFrom; get)
open import Extraction.NetlistCorrect using (AllLt; AllLt-upFrom; get-++-+)
open import Extraction.LockedNet using (ReadsAs; reads-mid; get-at-len)
open import Attack.EmitterEnvironment
open import Attack.ObservationSeparation using (ClosedSeparation)

private
  variable
    n : ℕ

environmentAll : (Vec Bool n → Bool) → Vec Bool n → Vec Bool n → List Bool
environmentAll f k0 x = toList x ++ (toList k0 ++ (f x ∷ []))

environment-all-witness : (f : Vec Bool n → Bool) (k0 : Vec Bool n) →
  EmitterEnv f k0 (upFrom 0 n) (upFrom n n) (n + n) (n + (n + 1))
    (environmentAll f k0)
environment-all-witness {n} f k0 = record
  { env-size = size
  ; xs-fit = λ x → subst (λ l → AllLt l (upFrom 0 n)) (sym (size x))
      (AllLt-upFrom 0 n (n + (n + 1)) (m≤m+n n (n + 1)))
  ; keys-fit = λ x → subst (λ l → AllLt l (upFrom n n)) (sym (size x))
      (AllLt-upFrom n n (n + (n + 1)) (+-mono-≤ ≤-refl (m≤m+n n 1)))
  ; feed-fit = λ x → subst (λ l → n + n < l) (sym (size x))
      (subst (λ l → n + n < l)
        (trans (sym (+-comm (n + n) 1)) (+-assoc n n 1)) ≤-refl)
  ; reads-in = λ x → subst (λ l → ReadsAs (environmentAll f k0 x) (upFrom 0 l) (toList x))
      (length-toList x) (reads-mid [] (toList x) (toList k0 ++ (f x ∷ [])))
  ; reads-key = λ x → subst₂
      (λ s l → ReadsAs (environmentAll f k0 x) (upFrom s l) (toList k0))
      (length-toList x) (length-toList k0) (reads-mid (toList x) (toList k0) (f x ∷ []))
  ; feed-is-f = feed
  }
  where
    size : (x : Vec Bool n) → length (environmentAll f k0 x) ≡ n + (n + 1)
    size x rewrite length-++ (toList x) {ys = toList k0 ++ (f x ∷ [])}
                 | length-++ (toList k0) {ys = f x ∷ []}
                 | length-toList x | length-toList k0 = refl

    feed : (x : Vec Bool n) → get (environmentAll f k0 x) (n + n) ≡ f x
    feed x =
      trans (cong (get (environmentAll f k0 x))
               (sym (trans (cong (_+ length (toList k0)) (length-toList x))
                           (cong (n +_) (length-toList k0)))))
        (trans (get-++-+ (toList x) (toList k0 ++ (f x ∷ [])) (length (toList k0)))
               (get-at-len (toList k0) (f x ∷ [])))

closed-all-witness : (f : Vec Bool n → Bool) (k0 : Vec Bool n) →
  ClosedSeparation f k0 (upFrom 0 n) (upFrom n n) (n + n) (n + (n + 1))
    (environmentAll f k0)
closed-all-witness {n} f k0 =
  point-closed-separation-env f k0 (upFrom 0 n) (upFrom n n) (n + n) (n + (n + 1))
    (environmentAll f k0) (environment-all-witness f k0)
