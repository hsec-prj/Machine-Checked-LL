------------------------------------------------------------------------
--  From a host to a shared flat netlist
--  Lay out `Netlist n G` as `List Op` while preserving `busEval`.
--  The verified `Extraction.HostNet.gadgetOps` compiler places gates
--  oldest first, ensuring fan-ins are available. A `Vec ℕ` explicitly
--  stores each bus position's wire identifier; bookkeeping then uses
--  `lookup` instead of arithmetic translation and `Fin` subtraction.
--  For every position `p`, correctness states
--  `get (runNet (toList x) ops) (lookup ws p) ≡ lookup (busEval nl x) p`.
--  No postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.HostNetlist where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; _<_; z≤n; s≤s)
open import Data.Nat.Properties using (≤-trans; ≤-refl; n≤1+n)
open import Data.Bool using (Bool)
open import Data.Fin using (Fin; zero; suc; toℕ)
open import Data.Fin.Properties using (toℕ<n)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.List.Properties using (++-identityʳ)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Vec using (Vec; []; _∷_; lookup; tabulate; toList)
open import Data.Vec.Properties using (lookup∘tabulate; lookup-++ˡ; lookup-++ʳ)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst)

open import Circuit.Core using (Circuit)
open import Circuit.Semantics using (⟦_⟧)
open import Extraction.NetDepthBuilder using (CntLaw; ret-cnt; »=-cnt)
open import Extraction.Netlist using (Op; get; runNet; Builder; ret; _»=_)
open import Extraction.NetlistCorrect using (runNet-++; runNet-length; runNet-prefix; runNet-mono)
open import Extraction.HostNet using (gadgetOps; gadgetOps-cnt; gadget-correct)
open import Locking.NetlistToCircuit using
  (Gate; gate; Netlist; []; _∷_; busEval; evalG)
open Gate

private
  variable
    n G : ℕ

------------------------------------------------------------------------
--  §1 Represent inputs as wires and read the input Vec through the environment.

allInputs : (n : ℕ) → Vec ℕ n
allInputs n = tabulate toℕ

allInputs-lookup : (n : ℕ) (i : Fin n) → lookup (allInputs n) i ≡ toℕ i
allInputs-lookup n i = lookup∘tabulate toℕ i

--  At each input identifier, the environment `toList x` returns the corresponding entry of `x`.
get-toList : (x : Vec Bool n) (i : Fin n) → get (toList x) (toℕ i) ≡ lookup x i
get-toList (x ∷ xs) zero    = refl
get-toList (x ∷ xs) (suc i) = get-toList xs i

------------------------------------------------------------------------
--  §2 Lay out the host while recording bus-position wire identifiers in `Vec ℕ`.

netlistWires : Netlist n G → Builder (Vec ℕ (G + n))
netlistWires {n} [] = ret (allInputs n)
netlistWires (gt ∷ nl) =
  netlistWires nl »= λ ws →
  gadgetOps (g gt) (lookup ws (a gt)) (lookup ws (b gt)) »= λ wOut →
  ret (wOut ∷ ws)

netlistWires-cnt : (nl : Netlist n G) → CntLaw (netlistWires nl)
netlistWires-cnt {n} [] = ret-cnt (allInputs n)
netlistWires-cnt (gt ∷ nl) =
  »=-cnt (netlistWires nl)
         (λ ws → gadgetOps (g gt) (lookup ws (a gt)) (lookup ws (b gt)) »= λ wOut → ret (wOut ∷ ws))
         (netlistWires-cnt nl)
    (λ ws → »=-cnt (gadgetOps (g gt) (lookup ws (a gt)) (lookup ws (b gt)))
                   (λ wOut → ret (wOut ∷ ws))
                   (gadgetOps-cnt (g gt) (lookup ws (a gt)) (lookup ws (b gt)))
                   (λ wOut → ret-cnt (wOut ∷ ws)))

------------------------------------------------------------------------
--  §3 Prove that reading the laid-out wires agrees with bus evaluation.

netlistWires-correct : (nl : Netlist n G) (x : Vec Bool n) (env : List Bool) →
  n ≤ length env → ((i : Fin n) → get env (toℕ i) ≡ lookup x i) →
  let ws   = proj₁ (netlistWires nl (length env))
      ops  = proj₂ (proj₂ (netlistWires nl (length env)))
      env' = runNet env ops
  in ((p : Fin (G + n)) → lookup ws p < length env')
   × (length env ≤ length env')
   × ((p : Fin (G + n)) → get env' (lookup ws p) ≡ lookup (busEval nl x) p)
netlistWires-correct {n} [] x env n≤env inR =
    (λ p → subst (_< length env) (sym (allInputs-lookup n p))
                 (≤-trans (toℕ<n p) n≤env))
  , ≤-refl
  , (λ p → trans (cong (get env) (allInputs-lookup n p)) (inR p))
netlistWires-correct {n} {suc G} (gt ∷ nl) x env n≤env inR =
    boundsN , monoN , valueN
  where
    SR = netlistWires-correct nl x env n≤env inR
    ws'    = proj₁ (netlistWires nl (length env))
    opsSub = proj₂ (proj₂ (netlistWires nl (length env)))
    iSub   = proj₁ (proj₂ (netlistWires nl (length env)))
    envSub = runNet env opsSub
    bndSub = proj₁ SR ; monoSub = proj₁ (proj₂ SR) ; valSub = proj₂ (proj₂ SR)

    faninA = lookup ws' (a gt) ; faninB = lookup ws' (b gt)
    iSub≡lenSub : iSub ≡ length envSub
    iSub≡lenSub = trans (netlistWires-cnt nl (length env)) (sym (runNet-length env opsSub))

    --  Run the gadget at iSub, the actual state aligned with length envSub.
    Pg : ℕ → Set
    Pg st =
      let (out , _ , ops) = gadgetOps (g gt) faninA faninB st
          e               = runNet envSub ops
      in (out < length e) × (length envSub ≤ length e)
       × ((w : ℕ) → w < length envSub → get e w ≡ get envSub w)
       × (get e out ≡ lookup (⟦ g gt ⟧ (get envSub faninA ∷ get envSub faninB ∷ [])) zero)
    gG : Pg iSub
    gG = subst Pg (sym iSub≡lenSub)
           (gadget-correct (g gt) faninA faninB envSub (bndSub (a gt)) (bndSub (b gt)))
    gOut  = proj₁ (gadgetOps (g gt) faninA faninB iSub)
    gOps  = proj₂ (proj₂ (gadgetOps (g gt) faninA faninB iSub))
    env'  = runNet envSub gOps
    gOut< = proj₁ gG ; gMono = proj₁ (proj₂ gG)
    gPresv = proj₁ (proj₂ (proj₂ gG)) ; gVal = proj₂ (proj₂ (proj₂ gG))

    fullOps = proj₂ (proj₂ (netlistWires (gt ∷ nl) (length env)))
    runEq : runNet env fullOps ≡ env'
    runEq = trans (runNet-++ env opsSub (gOps ++ []))
                  (cong (runNet envSub) (++-identityʳ gOps))

    --  The fan-in values read in envSub agree with the corresponding sub-bus values.
    faninA≡ : get envSub faninA ≡ lookup (busEval nl x) (a gt)
    faninA≡ = valSub (a gt)
    faninB≡ : get envSub faninB ≡ lookup (busEval nl x) (b gt)
    faninB≡ = valSub (b gt)

    boundsN : (p : Fin (suc G + n)) → lookup (gOut ∷ ws') p < length (runNet env fullOps)
    boundsN zero    = subst (λ e → gOut < length e) (sym runEq) gOut<
    boundsN (suc q) = subst (λ e → lookup ws' q < length e) (sym runEq)
                            (≤-trans (bndSub q) gMono)
    monoN : length env ≤ length (runNet env fullOps)
    monoN = subst (λ e → length env ≤ length e) (sym runEq) (≤-trans monoSub gMono)
    valueN : (p : Fin (suc G + n)) →
             get (runNet env fullOps) (lookup (gOut ∷ ws') p)
               ≡ lookup (busEval (gt ∷ nl) x) p
    valueN zero =
      trans (cong (λ e → get e gOut) runEq)
      (trans gVal
      (trans (cong₂ (λ va vb → lookup (⟦ g gt ⟧ (va ∷ vb ∷ [])) zero) faninA≡ faninB≡)
             (sym (lookup-++ˡ (evalG gt (busEval nl x)) (busEval nl x) zero))))
    valueN (suc q) =
      trans (cong (λ e → get e (lookup ws' q)) runEq)
      (trans (gPresv (lookup ws' q) (bndSub q))
      (trans (valSub q)
             (sym (lookup-++ʳ (evalG gt (busEval nl x)) (busEval nl x) q))))
