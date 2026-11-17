------------------------------------------------------------------------
-- An inhabited whole-host deep-output premise. This synthetic chain is
-- a regression witness, not an ISCAS benchmark or a mapped timing result.
------------------------------------------------------------------------
{-# OPTIONS --safe --without-K #-}
module Extraction.HostDepthWitness where
open import Data.Nat using (ℕ; zero; suc; _+_; _<_; _≤_; z≤n; s≤s)
open import Data.Nat.Properties using (≤-refl)
open import Data.Bool using (true)
open import Data.List using (List; []; _∷_)
open import Data.Product using (proj₁; proj₂)
open import Data.Vec using (lookup)
import Data.Fin as F
open import Circuit.Core using (Seq; Plug; Not1)
open import Locking.NetlistToCircuit using (Netlist; gate; []; _∷_)
open import Extraction.HostNetlist using (netlistWires)
open import Extraction.LockHost using (lockHostBlock)
open import Extraction.NetDepthHost using (lockHostBlock-adds-2)
open import Extraction.NetDepth using (runLevels; maxL; getL)

first : (G : ℕ) → F.Fin (G + 1)
first zero = F.zero
first (suc G) = F.zero

chain : (G : ℕ) → Netlist 1 G
chain zero = []
chain (suc G) = gate (first G) (first G) (Seq (Plug (λ _ → F.zero)) Not1) ∷ chain G

levels : List ℕ
levels = 0 ∷ 0 ∷ []

inputs-zero : (i : ℕ) → i < 2 → getL levels i ≤ 0
inputs-zero zero p = z≤n
inputs-zero (suc zero) p = z≤n
inputs-zero (suc (suc i)) (s≤s (s≤s ()))

chain-dominates : 15 ≤ getL (runLevels levels (proj₂ (proj₂ (netlistWires (chain 15) 2))))
  (lookup (proj₁ (netlistWires (chain 15) 2)) F.zero)
chain-dominates = ≤-refl

chain-adds-2 :
  maxL (runLevels levels (proj₂ (proj₂ (lockHostBlock (chain 15) (true ∷ []) 0 2))))
  ≤ maxL (runLevels levels (proj₂ (proj₂ (netlistWires (chain 15) 2)))) + 2
chain-adds-2 = lockHostBlock-adds-2 (chain 15) (true ∷ []) 0 levels 0
  ≤-refl inputs-zero chain-dominates
