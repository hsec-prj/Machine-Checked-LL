------------------------------------------------------------------------
--  Compose verified host layout with a complete lock block. HostNetlist's
--  netlistWires lays Netlist n G into shared operations and tracks bus
--  wire identifiers in Vec ℕ, with correctness
--  get env' (lookup ws p) ≡ lookup (busEval nl x) p. LockedNet's
--  lockedBlock emits SFLL-HD from data wires, key wires, secret constants,
--  and fWire, proving locked h ksec key f x. Start with
--  env=toList x ++ toList key, using data indices 0..n-1 and key indices
--  n..2n-1. Lay out the host, select bus position zero for importConeF nl x,
--  then feed it to the lock. lockHost-locked proves that the complete flat
--  netlist denotes locked h ksec key (importConeF nl) x. The host's own
--  gates now compute f x, yielding the certified shared-wire artifact
--  consumed by synthesis/SAT tools. No postulates are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockHost where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; _<_)
open import Data.Nat.Properties using (≤-refl; m≤m+n)
open import Data.Bool using (Bool)
open import Data.Fin using (Fin; zero; suc; toℕ)
open import Data.Fin.Properties using (toℕ<n)
open import Data.List using (List; []; _++_; length)
open import Data.List.Properties using (length-++; ++-identityʳ)
open import Data.Product using (_,_; proj₁; proj₂)
open import Data.Vec using (Vec; toList; lookup)
open import Data.String using (String)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; sym; trans; subst; subst₂)

open import SFLL.HD using (locked; SFLL_correct)
open import Locking.NetlistToCircuit using (Netlist; importConeF)
open import Extraction.Netlist using
  (Op; get; runNet; Builder; _»=_; upFrom)
open import Extraction.Render using (renderNet)
open import Extraction.NetlistCorrect using
  (get-++-<; runNet-++; runNet-length; AllLt; AllLt-mono; AllLt-upFrom; length-toList)
open import Extraction.HostNetlist using
  (netlistWires; netlistWires-cnt; netlistWires-correct; get-toList)
open import Extraction.LockedNet using
  (lockedBlock; lockedBlock-locked; ReadsAs; ReadsAs-runNet; reads-mid)

private
  variable
    n G : ℕ

------------------------------------------------------------------------
--  Section 1: build the host layout followed by protection of its cone output.

--  Read x on wires 0..n-1 and key on n..2n-1. Host output lookup ws zero
--  becomes the lock's fWire.
lockHostBlock : Netlist n (suc G) → (ksecBits : List Bool) (h : ℕ) → Builder ℕ
lockHostBlock {n = n} nl ksecBits h =
  netlistWires nl »= λ ws →
  lockedBlock (upFrom 0 n) (upFrom n n) ksecBits h (lookup ws zero)

------------------------------------------------------------------------
--  Section 2: prove complete emitted-netlist semantics for the locked host.

lockHost-locked :
  (nl : Netlist n (suc G)) (x key ksec : Vec Bool n) (h : ℕ) →
  let (out , _ , ops) = lockHostBlock nl (toList ksec) h (length (toList x ++ toList key))
  in get (runNet (toList x ++ toList key) ops) out
       ≡ locked h ksec key (importConeF nl) x
lockHost-locked {n = n} nl x key ksec h = goal
  where
    env   = toList x ++ toList key
    ksecL = toList ksec
    xs    = upFrom 0 n
    keys  = upFrom n n

    --  Allocate the host-layout components after env.
    ws    = proj₁ (netlistWires nl (length env))
    iH    = proj₁ (proj₂ (netlistWires nl (length env)))
    hOps  = proj₂ (proj₂ (netlistWires nl (length env)))
    env'  = runNet env hOps
    fWire = lookup ws zero

    --  Part 2.1: env's first n wires read x, and n ≤ length env.
    len-env : length env ≡ n + n
    len-env = trans (length-++ (toList x))
                    (trans (cong (_+ length (toList key)) (length-toList x))
                           (cong (n +_) (length-toList key)))

    n≤env : n ≤ length env
    n≤env = subst (n ≤_) (sym len-env) (m≤m+n n n)

    inR : (i : Fin n) → get env (toℕ i) ≡ lookup x i
    inR i = trans (get-++-< (toList x) (toList key) (toℕ i)
                     (subst (toℕ i <_) (sym (length-toList x)) (toℕ<n i)))
                  (get-toList x i)

    --  Part 2.2: host layout places the cone output at bus-position-zero fWire.
    NC    = netlistWires-correct nl x env n≤env inR
    bnd   = proj₁ NC
    mono  = proj₁ (proj₂ NC)
    val   = proj₂ (proj₂ NC)

    fWire< : fWire < length env'
    fWire< = bnd zero
    fVal : get env' fWire ≡ importConeF nl x
    fVal = val zero

    --  Part 2.3: data and key wires remain in range and preserve x/key after host operations.
    allxs-base : AllLt (length env) xs
    allxs-base = AllLt-upFrom 0 n (length env) n≤env
    allkeys-base : AllLt (length env) keys
    allkeys-base = AllLt-upFrom n n (length env) (subst (n + n ≤_) (sym len-env) ≤-refl)

    allxs   : AllLt (length env') xs
    allxs   = AllLt-mono mono xs allxs-base
    allkeys : AllLt (length env') keys
    allkeys = AllLt-mono mono keys allkeys-base

    --  Read the middle segments as x/key in env and transport those readings to env'.
    xsReads-base : ReadsAs env xs (toList x)
    xsReads-base = subst (λ k → ReadsAs env (upFrom 0 k) (toList x))
                         (length-toList x)
                         (reads-mid [] (toList x) (toList key))

    keyReads-base : ReadsAs env keys (toList key)
    keyReads-base =
      subst (λ e → ReadsAs e keys (toList key))
            (cong (toList x ++_) (++-identityʳ (toList key)))
            (subst₂ (λ s ln → ReadsAs (toList x ++ toList key ++ [])
                                       (upFrom s ln) (toList key))
                    (length-toList x) (length-toList key)
                    (reads-mid (toList x) (toList key) []))

    xsReads  : ReadsAs env' xs (toList x)
    xsReads  = ReadsAs-runNet env hOps xs (toList x) allxs-base xsReads-base
    keyReads : ReadsAs env' keys (toList key)
    keyReads = ReadsAs-runNet env hOps keys (toList key) allkeys-base keyReads-base

    --  Part 2.4: apply the lock-block certificate at start=length env'.
    P : ℕ → Set
    P s = get (runNet env' (proj₂ (proj₂ (lockedBlock xs keys ksecL h fWire s))))
              (proj₁ (lockedBlock xs keys ksecL h fWire s))
            ≡ locked h ksec key (importConeF nl) x
    LB : P (length env')
    LB = lockedBlock-locked xs keys x key ksec h fWire (importConeF nl) env'
           allxs allkeys fWire< xsReads keyReads fVal

    --  Align actual allocation iH with length env'.
    iH≡ : iH ≡ length env'
    iH≡ = trans (netlistWires-cnt nl (length env)) (sym (runNet-length env hOps))
    LB-iH : P iH
    LB-iH = subst P (sym iH≡) LB

    --  Split the bind's operation list to run host operations before lock operations.
    fullOps = proj₂ (proj₂ (lockHostBlock nl ksecL h (length env)))
    out     = proj₁ (lockHostBlock nl ksecL h (length env))
    lOps    = proj₂ (proj₂ (lockedBlock xs keys ksecL h fWire iH))
    runEq : runNet env fullOps ≡ runNet env' lOps
    runEq = runNet-++ env hOps lOps

    goal : get (runNet env fullOps) out ≡ locked h ksec key (importConeF nl) x
    goal = trans (cong (λ e → get e out) runEq) LB-iH

--  At key=ksec, restore any imported cone. Prove the corollary generically
--  in abstract nl so lockHostBlock nl remains unreduced. Applying it to
--  c432nl's 132 gates then uses little memory; applying trans directly to
--  a concrete netlist forces operation-list normalisation and can overflow
--  memory. This generic lift allows restoration results at scale.
lockHost-restores :
  (nl : Netlist n (suc G)) (x ksec : Vec Bool n) (h : ℕ) →
  let (out , _ , ops) = lockHostBlock nl (toList ksec) h (length (toList x ++ toList ksec))
  in get (runNet (toList x ++ toList ksec) ops) out ≡ importConeF nl x
lockHost-restores nl x ksec h =
  trans (lockHost-locked nl x ksec ksec h) (SFLL_correct h ksec (importConeF nl) x)

------------------------------------------------------------------------
--  Section 3: expose the verified host-lock block as .bench. Primary wires
--  carry x followed by key, host gates compute the cone, and the lock wraps
--  it, producing exactly the shared-wire artifact of lockHost-locked.

lockHostBench : (n : ℕ) {G : ℕ} → Netlist n (suc G) → (ksecBits : List Bool) (h : ℕ) → String
lockHostBench n nl ksecBits h =
  let (out , _ , ops) = lockHostBlock nl ksecBits h (n + n)
  in renderNet (n + n) ops out

------------------------------------------------------------------------
--  Add the depth companion: the same functionally certified emission adds
--  only O(n) critical-path depth beyond an arbitrary host, rather than its
--  O(n²) lock gate count. netDepth measures the structural longest path
--  reported by ABC print_stats.

open import Data.Nat using (_*_)
open import Data.Nat.Properties using (≤-trans; ≤-reflexive; m≤m+n)
open import Data.List.Relation.Unary.All using (All) renaming (map to all-map)
open import Extraction.NetDepth using (maxL; runLevels; runLevels-++)
open import Extraction.NetDepthComp using (runLevels-len)
open import Extraction.NetDepthFold using (run-len-state)
open import Extraction.NetDepthPop using (lockedBlock-bound)

private
  lenUpFrom : (k j : ℕ) → length (upFrom j k) ≡ k
  lenUpFrom zero    j = refl
  lenUpFrom (suc k) j = cong suc (lenUpFrom k (suc j))

--  Bound lockHostBlock depth by host depth + 6n + 9. Retain this result
--  although NetDepthExact.lockHostBlock-adds-2-tight supersedes it with +2
--  under a hypothesis 4n+5 levels weaker, and rederives it as
--  lockHostBlock-bound-from-tight.
lockHostBlock-bound :
  (nl : Netlist n (suc G)) (ksec : List Bool) (h : ℕ) (lv : List ℕ) →
  All (_< length lv) (upFrom 0 n) → All (_< length lv) (upFrom n n) →
  maxL (runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv)))))
    ≤ maxL (runLevels lv (proj₂ (proj₂ (netlistWires nl (length lv))))) + 6 * n + 9
lockHostBlock-bound {n} {G} nl ksec h lv xsv keysv =
  ≤-trans (≤-reflexive (cong maxL split))
          (≤-trans lb≤ (≤-reflexive (cong (λ z → maxL eH + 6 * z + 9) (lenUpFrom n 0))))
  where
    hOps  = proj₂ (proj₂ (netlistWires nl (length lv)))
    eH    = runLevels lv hOps
    wid   = proj₁ (proj₂ (netlistWires nl (length lv)))
    ws    = proj₁ (netlistWires nl (length lv))
    fWire = lookup ws zero
    lbO   = proj₂ (proj₂ (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire wid))

    split : runLevels lv (proj₂ (proj₂ (lockHostBlock nl ksec h (length lv)))) ≡ runLevels eH lbO
    split = runLevels-++ lv hOps lbO

    lv≤H : length lv ≤ length eH
    lv≤H = ≤-trans (m≤m+n (length lv) (length hOps)) (≤-reflexive (sym (runLevels-len lv hOps)))
    wid≡ : wid ≡ length eH
    wid≡ = run-len-state (netlistWires nl) (netlistWires-cnt nl) lv

    lb≤ : maxL (runLevels eH lbO) ≤ maxL eH + 6 * length (upFrom 0 n) + 9
    lb≤ = ≤-trans (≤-reflexive (cong (λ s → maxL (runLevels eH (proj₂ (proj₂ (lockedBlock (upFrom 0 n) (upFrom n n) ksec h fWire s))))) wid≡))
                  (lockedBlock-bound eH (upFrom 0 n) (upFrom n n) ksec h fWire
                     (all-map (λ px → ≤-trans px lv≤H) xsv) (all-map (λ px → ≤-trans px lv≤H) keysv))
