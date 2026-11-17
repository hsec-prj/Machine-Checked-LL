------------------------------------------------------------------------
--  Verify runtime extraction for hosts supplied as flat gate data.
--  LUTNetBuild.fromFlat assembles a dependently well-scoped Netlist from
--  (a,b,code) data; lockHost-locked quantifies over that supplied Netlist.
--  The runtime path uses no per-host compile-time Netlist literal or
--  fixed host-size bound. flatConeBit-correct
--  uses the parse equation to connect runtime evaluation with
--  the assembled importConeF. §3a's flatLockedBit-correct/restores
--  mention only gs: at x ++ key, its emitted netlist computes
--  the SFLL-HD lock of flatConeFun, and the correct key
--  agrees with the CLI cone evaluator. They need no parse
--  premise, since failure gives nothing on both sides.
--  §3b re-derives the unchanged Netlist-subject
--  lockHostFlat-locked/restores forms; there ok transports
--  from gs to nl, making the parse equation active in the
--  derivation even though gs is absent from the conclusion.
--  Agda certifies the supplied flat input and constructed operations.
--  Faithfulness of external .bench-to-flat preprocessing remains outside
--  the proof; importnet parity checks only its executed input samples.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockHostFlat where

open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Bool using (Bool; true)
open import Data.List using (List; []; _∷_; _++_; length)
open import Data.Maybe using (Maybe; just; nothing; is-just) renaming (map to mapMaybe)
open import Data.Maybe.Properties using (just-injective)
open import Data.Product using (Σ-syntax; _,_; proj₁; proj₂)
open import Data.Vec using (Vec; toList)
open import Data.String using (String)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

open import SFLL.HD using (locked)
open import Locking.NetlistToCircuit using (Netlist; importConeF)
open import Extraction.Netlist using (get; runNet)
open import Extraction.LUTNetParse using (FGate)
open import Extraction.LUTNetBuild using (NLΣ; fromFlat)
open import Extraction.LockHost using
  (lockHostBlock; lockHostBench; lockHost-locked; lockHost-restores)

------------------------------------------------------------------------
--  §1 Factor the CLI cone evaluator through Maybe so a parse
--  equation rewrites it definitionally.

--  Return the assembled importConeF function, or nothing on
--  parse failure or an empty host. Downstream statements
--  can then avoid referring to an assembled Netlist.
coneFunM : ∀ {n} → Maybe (NLΣ n) → Maybe (Vec Bool n → Bool)
coneFunM (just (suc G , nl)) = just (importConeF nl)
coneFunM (just (0     , nl)) = nothing
coneFunM nothing             = nothing

--  Return the assembled certified cone, with nothing for
--  failed parsing or an empty host.
coneBitM : ∀ {n} → Maybe (NLΣ n) → Vec Bool n → Maybe Bool
coneBitM m x = mapMaybe (λ f → f x) (coneFunM m)

--  Evaluate the gs-parsed host's cone at runtime through Main.
flatConeBit : (n : ℕ) → List FGate → Vec Bool n → Maybe Bool
flatConeBit n gs x = coneBitM (fromFlat n gs) x

--  Use fromFlat n gs ≡ just (suc G,nl) to reduce coneBitM
--  definitionally and equate the runtime evaluator with
--  importConeF. The parse equation participates in the proof.
flatConeBit-correct :
  (n : ℕ) (gs : List FGate) (x : Vec Bool n) (G : ℕ) (nl : Netlist n (suc G)) →
  fromFlat n gs ≡ just (suc G , nl) →
  flatConeBit n gs x ≡ just (importConeF nl x)
flatConeBit-correct n gs x G nl ok = cong (λ m → coneBitM m x) ok

--  Express the assembled host's cone as a function of gs alone.
flatConeFun : (n : ℕ) → List FGate → Maybe (Vec Bool n → Bool)
flatConeFun n gs = coneFunM (fromFlat n gs)

------------------------------------------------------------------------
--  §2 Provide the CLI rendering entry for a parsed host's locked netlist.

--  Factor through top-level benchM, enabling downstream case
--  splits on parsing and links from emitted String to
--  certified characters that a where-local helper would obstruct.
benchM : (n : ℕ) → Maybe (NLΣ n) → (ksecBits : List Bool) (h : ℕ) → Maybe String
benchM n (just (suc G , nl)) ksecBits h = just (lockHostBench n nl ksecBits h)
benchM n (just (0     , nl)) ksecBits h = nothing
benchM n nothing             ksecBits h = nothing

--  Emit the verified lock of the gs-parsed host, or nothing.
lockHostFlatBench : (n : ℕ) → List FGate → (ksecBits : List Bool) (h : ℕ) → Maybe String
lockHostFlatBench n gs ksecBits h = benchM n (fromFlat n gs) ksecBits h

------------------------------------------------------------------------
--  §3 State emission and restoration over gs. In §3a,
--  text-only statements hold without parse premises, including
--  nothing ≡ nothing on failure. Re-derive §3b's Netlist-subject
--  lockHostFlat-locked from them, using the parse equation
--  to connect its otherwise text-independent conclusion to gs.

--  Evaluate the runtime locked output by constructing the
--  gs host's lock and reading its output wire in env.
lockedBitM : ∀ {n} → Maybe (NLΣ n) → (ksecBits : List Bool) (h : ℕ) → List Bool → Maybe Bool
lockedBitM (just (suc G , nl)) ksecBits h env =
  just (get (runNet env (proj₂ (proj₂ (lockHostBlock nl ksecBits h (length env)))))
            (proj₁ (lockHostBlock nl ksecBits h (length env))))
lockedBitM (just (0     , nl)) ksecBits h env = nothing
lockedBitM nothing             ksecBits h env = nothing

flatLockedBit : (n : ℕ) → List FGate → (ksecBits : List Bool) (h : ℕ) → List Bool → Maybe Bool
flatLockedBit n gs ksecBits h env = lockedBitM (fromFlat n gs) ksecBits h env

lockedBitM-correct :
  ∀ {n} (m : Maybe (NLΣ n)) (x key ksec : Vec Bool n) (h : ℕ) →
  lockedBitM m (toList ksec) h (toList x ++ toList key)
    ≡ mapMaybe (λ f → locked h ksec key f x) (coneFunM m)
lockedBitM-correct (just (suc G , nl)) x key ksec h =
  cong just (lockHost-locked nl x key ksec h)
lockedBitM-correct (just (0 , nl)) x key ksec h = refl
lockedBitM-correct nothing          x key ksec h = refl

--  For text gs, prove its emitted netlist at x ++ key
--  computes the SFLL-HD lock of the denoted host cone.
--  The statement has neither a Netlist subject nor a parse hypothesis.
flatLockedBit-correct :
  (n : ℕ) (gs : List FGate) (x key ksec : Vec Bool n) (h : ℕ) →
  flatLockedBit n gs (toList ksec) h (toList x ++ toList key)
    ≡ mapMaybe (λ f → locked h ksec key f x) (flatConeFun n gs)
flatLockedBit-correct n gs x key ksec h = lockedBitM-correct (fromFlat n gs) x key ksec h

lockedBitM-restores :
  ∀ {n} (m : Maybe (NLΣ n)) (x ksec : Vec Bool n) (h : ℕ) →
  lockedBitM m (toList ksec) h (toList x ++ toList ksec) ≡ coneBitM m x
lockedBitM-restores (just (suc G , nl)) x ksec h =
  cong just (lockHost-restores nl x ksec h)
lockedBitM-restores (just (0 , nl)) x ksec h = refl
lockedBitM-restores nothing         x ksec h = refl

--  At the correct key, equate emitted-netlist evaluation
--  with the CLI's gs cone evaluator, keeping both sides text-indexed.
flatLockedBit-restores :
  (n : ℕ) (gs : List FGate) (x ksec : Vec Bool n) (h : ℕ) →
  flatLockedBit n gs (toList ksec) h (toList x ++ toList ksec) ≡ flatConeBit n gs x
flatLockedBit-restores n gs x ksec h = lockedBitM-restores (fromFlat n gs) x ksec h

--  Witness successful parsing with two gates on two inputs,
--  LUT codes eight (AND) and six (XOR), and in-range fan-ins.
--  This rules out universally trivial nothing equalities
--  and satisfies §3b's parse premise.
flatExample : List FGate
flatExample = (0 , 1 , 8) ∷ (0 , 2 , 6) ∷ []

flatExample-imports : is-just (flatConeFun 2 flatExample) ≡ true
flatExample-imports = refl

flatExample-locks :
  (ksecBits : List Bool) (h : ℕ) (env : List Bool) →
  is-just (flatLockedBit 2 flatExample ksecBits h env) ≡ true
flatExample-locks ksecBits h env = refl

------------------------------------------------------------------------
--  §3b Derive Netlist-indexed corollaries from §3a.

--  For the nl assembled from gs, prove the emitted netlist
--  denotes its SFLL-HD locked cone. Universal host correctness
--  underlies the result; the parse equation ties nl to the
--  runtime artifact without a compile-time Netlist literal.
lockHostFlat-locked :
  (n : ℕ) (gs : List FGate) (x key ksec : Vec Bool n) (h G : ℕ)
  (nl : Netlist n (suc G)) →
  fromFlat n gs ≡ just (suc G , nl) →
  let (out , _ , ops) = lockHostBlock nl (toList ksec) h (length (toList x ++ toList key))
  in get (runNet (toList x ++ toList key) ops) out
       ≡ locked h ksec key (importConeF nl) x
lockHostFlat-locked n gs x key ksec h G nl ok =
  just-injective
    (trans (sym (cong (λ m → lockedBitM m (toList ksec) h (toList x ++ toList key)) ok))
    (trans (flatLockedBit-correct n gs x key ksec h)
           (cong (λ m → mapMaybe (λ f → locked h ksec key f x) (coneFunM m)) ok)))

--  Restore the parsed host's cone with the correct key in the emitted netlist.
lockHostFlat-restores :
  (n : ℕ) (gs : List FGate) (x ksec : Vec Bool n) (h G : ℕ)
  (nl : Netlist n (suc G)) →
  fromFlat n gs ≡ just (suc G , nl) →
  let (out , _ , ops) = lockHostBlock nl (toList ksec) h (length (toList x ++ toList ksec))
  in get (runNet (toList x ++ toList ksec) ops) out ≡ importConeF nl x
lockHostFlat-restores n gs x ksec h G nl ok =
  just-injective
    (trans (sym (cong (λ m → lockedBitM m (toList ksec) h (toList x ++ toList ksec)) ok))
    (trans (flatLockedBit-restores n gs x ksec h)
           (cong (λ m → coneBitM m x) ok)))
