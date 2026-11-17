------------------------------------------------------------------------
--  Certify locked hosts at the shipped .bench interface. LockHostText lifts
--  lockHost-locked through BenchRoundTrip.renderL, a private counted format
--  unused by .bench consumers. Actual delivery through LockHost.lockHostBench
--  uses Render.renderNet's ISCAS INPUT(w…)/OUTPUT(w…) syntax. BenchISCAS
--  certifies those characters, and renderNet is their fromList. Therefore
--  lockHost-bench-correct establishes
--  evalParsed (parseNet (lockHostBenchL n nl ksec h)) (x ++ key)
--  ≡ locked h ksec key (importConeF nl) x. lockHostBench-chars identifies
--  the shipped String definitionally with fromList of lockHostBenchL.
--  Reading these actual characters with the checked parser and evaluating
--  recovers the locked host. Section 2 covers runtime host text as well:
--  flatBench-correct relates emitted .bench for gs to the locked cone of
--  the host denoted by gs, without a Netlist or parse premise in the
--  equation. Scope is the round trip through this printer and parser.
--  Compatibility with ABC/Yosys readers remains external empirical
--  evidence; this parser intentionally accepts only its printer's format.
--  Theorems use List Char because --safe cannot inspect String directly.
--  Shipping uses injective fromList of the certified characters. This
--  --safe --without-K development has no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LockHostBench where

open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Bool using (Bool; true)
open import Data.Char using (Char)
open import Data.List using (List; _++_; length)
open import Data.List.Properties using (length-++)
open import Data.Maybe using (Maybe; just; nothing; is-just) renaming (map to mapMaybe)
open import Data.Product using (_,_; proj₁; proj₂)
open import Data.String using (String; fromList)
open import Data.Vec using (Vec; toList)
open import Data.Vec.Properties using (length-toList)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

open import SFLL.HD using (locked; SFLL_correct)
open import Locking.NetlistToCircuit using (Netlist; importConeF)
open import Extraction.Netlist using (Op)
open import Extraction.BenchRoundTrip using (evalParsed)
open import Extraction.BenchISCAS using (renderNetL; parseNet; renderNet-sem)
open import Extraction.LockHost using (lockHostBlock; lockHostBench; lockHost-locked)
open import Extraction.LUTNetParse using (FGate)
open import Extraction.LUTNetBuild using (NLΣ; fromFlat)
open import Extraction.LockHostFlat using
  (coneFunM; coneBitM; benchM; lockHostFlatBench; flatConeFun; flatExample)

private
  variable
    n G : ℕ

------------------------------------------------------------------------
--  Section 1: certify shipped characters for compile-time host netlists.

--  Expose the character sequence shipped by lockHostBench through renderNet's fromList.
lockHostBenchL : (n : ℕ) → Netlist n (suc G) → (ksecBits : List Bool) (h : ℕ) → List Char
lockHostBenchL n nl ksecBits h =
  let (out , _ , ops) = lockHostBlock nl ksecBits h (n + n)
  in renderNetL (n + n) ops out

lockHostBench-chars :
  (n : ℕ) (nl : Netlist n (suc G)) (ksecBits : List Bool) (h : ℕ) →
  lockHostBench n nl ksecBits h ≡ fromList (lockHostBenchL n nl ksecBits h)
lockHostBench-chars n nl ksecBits h = refl

--  x ++ key has precisely the emitter's n+n primary inputs, identifying
--  the length-env-indexed generic block with the shipped instance.
private
  env-len : (x key : Vec Bool n) → length (toList x ++ toList key) ≡ n + n
  env-len x key =
    trans (length-++ (toList x)) (cong₂ _+_ (length-toList x) (length-toList key))

  benchL-at : (nl : Netlist n (suc G)) (ksecBits : List Bool) (h : ℕ)
              (env : List Bool) → length env ≡ n + n →
              renderNetL (length env)
                         (proj₂ (proj₂ (lockHostBlock nl ksecBits h (length env))))
                         (proj₁ (lockHostBlock nl ksecBits h (length env)))
                ≡ lockHostBenchL _ nl ksecBits h
  benchL-at nl ksecBits h env eq rewrite eq = refl

--  Parse the shipped ISCAS characters with the checked parser and evaluate
--  on x ++ key to obtain the locked SFLL-HD host. This transports
--  lockHost-text-correct from private renderL to the delivered format.
lockHost-bench-correct :
  (nl : Netlist n (suc G)) (x key ksec : Vec Bool n) (h : ℕ) →
  evalParsed (parseNet (lockHostBenchL _ nl (toList ksec) h)) (toList x ++ toList key)
    ≡ locked h ksec key (importConeF nl) x
lockHost-bench-correct nl x key ksec h =
  trans (cong (λ cs → evalParsed (parseNet cs) env)
              (sym (benchL-at nl (toList ksec) h env (env-len x key))))
        (trans (renderNet-sem (length env) ops out env)
               (lockHost-locked nl x key ksec h))
  where
    env = toList x ++ toList key
    out = proj₁ (lockHostBlock nl (toList ksec) h (length env))
    ops = proj₂ (proj₂ (lockHostBlock nl (toList ksec) h (length env)))

--  At key=ksec, the shipped text again denotes the host's original cone.
lockHost-bench-restores :
  (nl : Netlist n (suc G)) (x ksec : Vec Bool n) (h : ℕ) →
  evalParsed (parseNet (lockHostBenchL _ nl (toList ksec) h)) (toList x ++ toList ksec)
    ≡ importConeF nl x
lockHost-bench-restores nl x ksec h =
  trans (lockHost-bench-correct nl x ksec ksec h)
        (SFLL_correct h ksec (importConeF nl) x)

------------------------------------------------------------------------
--  Section 2: accept the host itself through the runtime text interface.

--  Expose lockHostFlatBench's emitted characters for the host parsed from gs.
benchLM : (n : ℕ) → Maybe (NLΣ n) → (ksecBits : List Bool) (h : ℕ) → Maybe (List Char)
benchLM n (just (suc G , nl)) ksecBits h = just (lockHostBenchL n nl ksecBits h)
benchLM n (just (zero  , nl)) ksecBits h = nothing
benchLM n nothing             ksecBits h = nothing

flatLockedBenchL : (n : ℕ) → List FGate → (ksecBits : List Bool) (h : ℕ) → Maybe (List Char)
flatLockedBenchL n gs ksecBits h = benchLM n (fromFlat n gs) ksecBits h

--  Identify the delivered String as fromList of those characters.
flatLockedBench-chars :
  (n : ℕ) (gs : List FGate) (ksecBits : List Bool) (h : ℕ) →
  lockHostFlatBench n gs ksecBits h ≡ mapMaybe fromList (flatLockedBenchL n gs ksecBits h)
flatLockedBench-chars n gs ksecBits h = go (fromFlat n gs)
  where
    go : (m : Maybe (NLΣ n)) → benchM n m ksecBits h ≡ mapMaybe fromList (benchLM n m ksecBits h)
    go (just (suc G , nl)) = refl
    go (just (zero  , nl)) = refl
    go nothing             = refl

private
  benchLM-correct :
    (n : ℕ) (m : Maybe (NLΣ n)) (x key ksec : Vec Bool n) (h : ℕ) →
    mapMaybe (λ cs → evalParsed (parseNet cs) (toList x ++ toList key))
             (benchLM n m (toList ksec) h)
      ≡ mapMaybe (λ f → locked h ksec key f x) (coneFunM m)
  benchLM-correct n (just (suc G , nl)) x key ksec h =
    cong just (lockHost-bench-correct nl x key ksec h)
  benchLM-correct n (just (zero , nl)) x key ksec h = refl
  benchLM-correct n nothing            x key ksec h = refl

  benchLM-restores :
    (n : ℕ) (m : Maybe (NLΣ n)) (x ksec : Vec Bool n) (h : ℕ) →
    mapMaybe (λ cs → evalParsed (parseNet cs) (toList x ++ toList ksec))
             (benchLM n m (toList ksec) h)
      ≡ coneBitM m x
  benchLM-restores n (just (suc G , nl)) x ksec h =
    cong just (lockHost-bench-restores nl x ksec h)
  benchLM-restores n (just (zero , nl)) x ksec h = refl
  benchLM-restores n nothing            x ksec h = refl

--  State the complete text-to-text equation without Netlist or parsing
--  premises. Parsing and evaluating the .bench emitted from flat gs at
--  x ++ key gives the SFLL-HD lock of its denoted host cone. If gs fails
--  to describe a nonempty host, both sides return nothing, making the
--  statement total.
flatBench-correct :
  (n : ℕ) (gs : List FGate) (x key ksec : Vec Bool n) (h : ℕ) →
  mapMaybe (λ cs → evalParsed (parseNet cs) (toList x ++ toList key))
           (flatLockedBenchL n gs (toList ksec) h)
    ≡ mapMaybe (λ f → locked h ksec key f x) (flatConeFun n gs)
flatBench-correct n gs x key ksec h = benchLM-correct n (fromFlat n gs) x key ksec h

--  With the correct key, emitted text agrees with the CLI's cone evaluator
--  on the same gs.
flatBench-restores :
  (n : ℕ) (gs : List FGate) (x ksec : Vec Bool n) (h : ℕ) →
  mapMaybe (λ cs → evalParsed (parseNet cs) (toList x ++ toList ksec))
           (flatLockedBenchL n gs (toList ksec) h)
    ≡ mapMaybe (λ f → f x) (flatConeFun n gs)
flatBench-restores n gs x ksec h = benchLM-restores n (fromFlat n gs) x ksec h

--  Demonstrate non-vacuity on LockHostFlat.flatExample: emission succeeds,
--  so the equations go beyond nothing ≡ nothing.
flatExample-emits :
  (ksecBits : List Bool) (h : ℕ) → is-just (flatLockedBenchL 2 flatExample ksecBits h) ≡ true
flatExample-emits ksecBits h = refl
