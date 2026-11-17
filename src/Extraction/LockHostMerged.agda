------------------------------------------------------------------------
--  Compose a whole host netlist with the certified cube-fused
--  lock. LockHost's unfused path materialises secret constants
--  for an isolated comparator. LockedNetMerged instead
--  certifies literal-by-literal fusion at h = 0, with no
--  cube wire or perturb-path constant gate, through its
--  correctness theorems and fusedPerturb-noConst.
--  lockHostBlockMerged lays out the supplied host and fuses the lock
--  over its cone output. lockHostMerged-locked proves the emitted ops
--  denote locked 0 ksec key (importConeF nl) x. Correct key ksec restores
--  that imported cone. lockHostMergedBench and lockHostFlatMergedBench
--  render the construction; fromFlat assembles well-scoped hosts at runtime.
--  The flat-input theorems concern the supplied parsed representation,
--  not the faithfulness of external .bench-to-flat preprocessing.
--  Inherited scope is denotation and perturb-path oConst
--  freedom at h = 0 only; the unchanged restore cone still
--  contains key-independent true/false rails. Reuse LockHost,
--  LockHostFlat, and LockedNet(Merged) without altering
--  their constructions. Add no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockHostMerged where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; _<_)
open import Data.Nat.Properties using (≤-refl; m≤m+n)
open import Data.Bool using (Bool)
open import Data.Fin using (Fin; zero; suc; toℕ)
open import Data.Fin.Properties using (toℕ<n)
open import Data.List using (List; []; _++_; length)
open import Data.List.Properties using (length-++; ++-identityʳ)
open import Data.Maybe using (Maybe; just; nothing)
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
  (ReadsAs; ReadsAs-runNet; reads-mid)
open import Extraction.LockedNetMerged using
  (lockedBlockMerged; lockedBlockMerged-locked)
open import Extraction.LUTNetParse using (FGate)
open import Extraction.LUTNetBuild using (NLΣ; fromFlat)

private
  variable
    n G : ℕ

------------------------------------------------------------------------
--  §1 Lay out the host, then fuse the lock into its cone
--  output. Match LockHost.lockHostBlock apart from choosing
--  the fused block and fixing h = 0.

--  Place inputs as x on wires 0..n-1 and key on n..2n-1.
--  The host reads x and supplies lookup ws zero as fWire.
lockHostBlockMerged : Netlist n (suc G) → (ksecBits : List Bool) → Builder ℕ
lockHostBlockMerged {n = n} nl ksecBits =
  netlistWires nl »= λ ws →
  lockedBlockMerged (upFrom 0 n) (upFrom n n) ksecBits (lookup ws zero)

------------------------------------------------------------------------
--  §2 Prove the whole fused netlist denotes the SFLL-HD locked host.

--  Obtain lockHost-locked's radius-zero conclusion from a
--  perturb path with no cube wire and, by fusedPerturb-noConst,
--  no constant gate.
lockHostMerged-locked :
  (nl : Netlist n (suc G)) (x key ksec : Vec Bool n) →
  let (out , _ , ops) = lockHostBlockMerged nl (toList ksec) (length (toList x ++ toList key))
  in get (runNet (toList x ++ toList key) ops) out
       ≡ locked 0 ksec key (importConeF nl) x
lockHostMerged-locked {n = n} nl x key ksec = goal
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

    --  §2.1 Read x from env's first n wires, with n ≤ length env.
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

    --  §2.2 Use layout correctness to identify bus-position zero with fWire.
    NC    = netlistWires-correct nl x env n≤env inR
    bnd   = proj₁ NC
    mono  = proj₁ (proj₂ NC)
    val   = proj₂ (proj₂ NC)

    fWire< : fWire < length env'
    fWire< = bnd zero
    fVal : get env' fWire ≡ importConeF nl x
    fVal = val zero

    --  §2.3 Keep data/key wires in range with readings x/key
    --  preserved through host operations.
    allxs-base : AllLt (length env) xs
    allxs-base = AllLt-upFrom 0 n (length env) n≤env
    allkeys-base : AllLt (length env) keys
    allkeys-base = AllLt-upFrom n n (length env) (subst (n + n ≤_) (sym len-env) ≤-refl)

    allxs   : AllLt (length env') xs
    allxs   = AllLt-mono mono xs allxs-base
    allkeys : AllLt (length env') keys
    allkeys = AllLt-mono mono keys allkeys-base

    --  Read the middle segments as x/key first in env, then in env'.
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

    --  §2.4 Apply fused-block correctness at start = length env'.
    P : ℕ → Set
    P s = get (runNet env' (proj₂ (proj₂ (lockedBlockMerged xs keys ksecL fWire s))))
              (proj₁ (lockedBlockMerged xs keys ksecL fWire s))
            ≡ locked 0 ksec key (importConeF nl) x
    LB : P (length env')
    LB = lockedBlockMerged-locked xs keys x key ksec fWire (importConeF nl) env'
           allxs allkeys fWire< xsReads keyReads fVal

    --  Align actual allocation state iH with length env'.
    iH≡ : iH ≡ length env'
    iH≡ = trans (netlistWires-cnt nl (length env)) (sym (runNet-length env hOps))
    LB-iH : P iH
    LB-iH = subst P (sym iH≡) LB

    --  Split bind's operation list into host execution followed by lock execution.
    fullOps = proj₂ (proj₂ (lockHostBlockMerged nl ksecL (length env)))
    out     = proj₁ (lockHostBlockMerged nl ksecL (length env))
    lOps    = proj₂ (proj₂ (lockedBlockMerged xs keys ksecL fWire iH))
    runEq : runNet env fullOps ≡ runNet env' lOps
    runEq = runNet-++ env hOps lOps

    goal : get (runNet env fullOps) out ≡ locked 0 ksec key (importConeF nl) x
    goal = trans (cong (λ e → get e out) runEq) LB-iH

--  For any imported nl, the correct key ksec restores
--  its cone. Keep nl abstract so lockHostBlockMerged nl …
--  remains unreduced, avoiding concrete operation-list
--  normalisation as in the memory-efficient lockHost-restores route.
lockHostMerged-restores :
  (nl : Netlist n (suc G)) (x ksec : Vec Bool n) →
  let (out , _ , ops) = lockHostBlockMerged nl (toList ksec) (length (toList x ++ toList ksec))
  in get (runNet (toList x ++ toList ksec) ops) out ≡ importConeF nl x
lockHostMerged-restores nl x ksec =
  trans (lockHostMerged-locked nl x ksec ksec) (SFLL_correct 0 ksec (importConeF nl) x)

------------------------------------------------------------------------
--  §3 Render the certified fused locked host as .bench.
--  With x/key primary inputs followed by the host's own
--  gates and fused wrapper, the shared-wire output is
--  exactly the artifact certified by lockHostMerged-locked.

lockHostMergedBench : (n : ℕ) {G : ℕ} → Netlist n (suc G) → (ksecBits : List Bool) → String
lockHostMergedBench n nl ksecBits =
  let (out , _ , ops) = lockHostBlockMerged nl ksecBits (n + n)
  in renderNet (n + n) ops out

------------------------------------------------------------------------
--  §4 Parse a flat host and emit its fused lock at runtime.
--  As in lockHostFlatBench, fromFlat's just result is
--  dependently well-scoped, and lockHostMerged-locked
--  certifies the assembled host's emitted netlist.

lockHostFlatMergedBench : (n : ℕ) → List FGate → (ksecBits : List Bool) → Maybe String
lockHostFlatMergedBench n gs ksecBits = go (fromFlat n gs)
  where
    go : Maybe (NLΣ n) → Maybe String
    go (just (suc G , nl)) = just (lockHostMergedBench n nl ksecBits)
    go (just (0     , nl)) = nothing
    go nothing             = nothing

------------------------------------------------------------------------
--  §5 State emission/restoration over parsed gs using
--  §2's universal host theorems. The parse equation links
--  conclusion nl to the runtime text, eliminating any
--  need for a compile-time Netlist literal.

lockHostFlatMerged-locked :
  (n : ℕ) (gs : List FGate) (x key ksec : Vec Bool n) (G : ℕ)
  (nl : Netlist n (suc G)) →
  fromFlat n gs ≡ just (suc G , nl) →
  let (out , _ , ops) = lockHostBlockMerged nl (toList ksec) (length (toList x ++ toList key))
  in get (runNet (toList x ++ toList key) ops) out
       ≡ locked 0 ksec key (importConeF nl) x
lockHostFlatMerged-locked n gs x key ksec G nl _ = lockHostMerged-locked nl x key ksec

lockHostFlatMerged-restores :
  (n : ℕ) (gs : List FGate) (x ksec : Vec Bool n) (G : ℕ)
  (nl : Netlist n (suc G)) →
  fromFlat n gs ≡ just (suc G , nl) →
  let (out , _ , ops) = lockHostBlockMerged nl (toList ksec) (length (toList x ++ toList ksec))
  in get (runNet (toList x ++ toList ksec) ops) out ≡ importConeF nl x
lockHostFlatMerged-restores n gs x ksec G nl _ = lockHostMerged-restores nl x ksec
