------------------------------------------------------------------------
-- Input-indexed environment assumptions for a fixed emitted lock block.
-- The original fixed-env universal premises were not instantiable for
-- nonempty inputs. Values now vary with x; env-size fixes the layout.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}
module Attack.EmitterEnvironment where

open import Data.Bool using (Bool)
open import Data.List using (List; length)
open import Data.Nat using (ℕ; _<_)
open import Data.Product using (proj₁; proj₂)
open import Data.Vec using (Vec; toList)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Extraction.LockedNet using (lockedBlock; ReadsAs)
open import Extraction.NetlistCorrect using (AllLt)
open import Extraction.Netlist using (runNet; get)
open import Attack.ObservationSeparation
  using (plantAct; ClosedSeparation; emit-denotes-plant; point-closed-separation)
private
  variable
    n : ℕ

record EmitterEnv
         (f : Vec Bool n → Bool) (k0 : Vec Bool n)
         (xs keys : List ℕ) (fWire start : ℕ)
         (env : Vec Bool n → List Bool) : Set where
  field
    env-size  : (x : Vec Bool n) → length (env x) ≡ start
    xs-fit    : (x : Vec Bool n) → AllLt (length (env x)) xs
    keys-fit  : (x : Vec Bool n) → AllLt (length (env x)) keys
    feed-fit  : (x : Vec Bool n) → fWire < length (env x)
    reads-in  : (x : Vec Bool n) → ReadsAs (env x) xs (toList x)
    reads-key : (x : Vec Bool n) → ReadsAs (env x) keys (toList k0)
    feed-is-f : (x : Vec Bool n) → get (env x) fWire ≡ f x
open EmitterEnv public

emit-denotes-plant-env :
  (f : Vec Bool n → Bool) (k0 : Vec Bool n) (xs keys : List ℕ)
  (fWire start : ℕ) (env : Vec Bool n → List Bool) →
  EmitterEnv f k0 xs keys fWire start env →
  (x s : Vec Bool n) →
  get (runNet (env x)
        (proj₂ (proj₂ (lockedBlock xs keys (toList s) 0 fWire (length (env x))))))
      (proj₁ (lockedBlock xs keys (toList s) 0 fWire (length (env x))))
  ≡ plantAct f k0 s x
emit-denotes-plant-env f k0 xs keys fWire start env E x s =
  emit-denotes-plant xs keys x k0 s fWire f (env x)
    (xs-fit E x) (keys-fit E x) (feed-fit E x)
    (reads-in E x) (reads-key E x) (feed-is-f E x)

point-closed-separation-env :
  (f : Vec Bool n → Bool) (k0 : Vec Bool n) (xs keys : List ℕ)
  (fWire start : ℕ) (env : Vec Bool n → List Bool) →
  EmitterEnv f k0 xs keys fWire start env →
  ClosedSeparation f k0 xs keys fWire start env
point-closed-separation-env f k0 xs keys fWire start env E =
  point-closed-separation f k0 xs keys fWire start env
    (env-size E) (xs-fit E) (keys-fit E) (feed-fit E)
    (reads-in E) (reads-key E) (feed-is-f E)

env-agrees :
  {f : Vec Bool n → Bool} {k0 : Vec Bool n} {xs keys : List ℕ}
  {fWire start : ℕ} {env : Vec Bool n → List Bool}
  (E : EmitterEnv f k0 xs keys fWire start env) (x s : Vec Bool n) →
  emit-denotes-plant-env f k0 xs keys fWire start env E x s
  ≡ emit-denotes-plant xs keys x k0 s fWire f (env x)
      (xs-fit E x) (keys-fit E x) (feed-fit E x)
      (reads-in E x) (reads-key E x) (feed-is-f E x)
env-agrees E x s = refl
