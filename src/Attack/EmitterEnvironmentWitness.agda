------------------------------------------------------------------------
-- Non-vacuity regression: all five-bit inputs and arbitrary host f/key k0.
-- The feed stores f x, not a constant value shared by all inputs.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}
module Attack.EmitterEnvironmentWitness where

open import Data.Bool using (Bool; false; true)
open import Data.List using (List; []; _∷_)
open import Data.Nat using (ℕ; s≤s; z≤n)
open import Data.Product using (_,_)
open import Data.Unit using (tt)
open import Data.Vec using (Vec; head)
import Data.Vec as V
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Extraction.LockedNet using ([]ᴿ; _∷ᴿ_)
open import Attack.EmitterEnvironment
open import Attack.ObservationSeparation using (ClosedSeparation)
open import Locking.CompileC17Multi using (F2)

xs keys : List ℕ
xs = 0 ∷ 1 ∷ 2 ∷ 3 ∷ 4 ∷ []
keys = 5 ∷ 6 ∷ 7 ∷ 8 ∷ 9 ∷ []

environment : (Vec Bool 5 → Bool) → Vec Bool 5 → Vec Bool 5 → List Bool
environment f (k1 V.∷ k2 V.∷ k3 V.∷ k4 V.∷ k5 V.∷ V.[])
              x@(a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) =
  a ∷ b ∷ c ∷ d ∷ e ∷ k1 ∷ k2 ∷ k3 ∷ k4 ∷ k5 ∷ f x ∷ []

environment-witness : (f : Vec Bool 5 → Bool) (k0 : Vec Bool 5) →
  EmitterEnv f k0 xs keys 10 11 (environment f k0)
environment-witness f (k1 V.∷ k2 V.∷ k3 V.∷ k4 V.∷ k5 V.∷ V.[]) = record
  { env-size = λ { (a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) → refl }
  ; xs-fit = λ { (a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) →
      s≤s z≤n , s≤s (s≤s z≤n) , s≤s (s≤s (s≤s z≤n)) ,
      s≤s (s≤s (s≤s (s≤s z≤n))) , s≤s (s≤s (s≤s (s≤s (s≤s z≤n)))) , tt }
  ; keys-fit = λ { (a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) →
      s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))) ,
      s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n)))))) ,
      s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))))) ,
      s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n)))))))) ,
      s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))))))) , tt }
  ; feed-fit = λ { (a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) →
      s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n)))))))))) }
  ; reads-in = λ { (a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) →
      refl ∷ᴿ (refl ∷ᴿ (refl ∷ᴿ (refl ∷ᴿ (refl ∷ᴿ []ᴿ)))) }
  ; reads-key = λ { (a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) →
      refl ∷ᴿ (refl ∷ᴿ (refl ∷ᴿ (refl ∷ᴿ (refl ∷ᴿ []ᴿ)))) }
  ; feed-is-f = λ { (a V.∷ b V.∷ c V.∷ d V.∷ e V.∷ V.[]) → refl }
  }

closed-witness : (f : Vec Bool 5 → Bool) (k0 : Vec Bool 5) →
  ClosedSeparation f k0 xs keys 10 11 (environment f k0)
closed-witness f k0 =
  point-closed-separation-env f k0 xs keys 10 11 (environment f k0)
    (environment-witness f k0)

-- Actual c17 N22 output, five inputs; the block consumes a host feed.
c17-host : Vec Bool 5 → Bool
c17-host x = head (F2 x)

zero-key : Vec Bool 5
zero-key = false V.∷ false V.∷ false V.∷ false V.∷ false V.∷ V.[]

c17-closed : ClosedSeparation c17-host zero-key xs keys 10 11
               (environment c17-host zero-key)
c17-closed = closed-witness c17-host zero-key

-- These different host values rule out an accidentally constant fixture.
c17-zero : c17-host zero-key ≡ false
c17-zero = refl
c17-one : c17-host
  (true V.∷ false V.∷ true V.∷ false V.∷ false V.∷ V.[]) ≡ true
c17-one = refl
