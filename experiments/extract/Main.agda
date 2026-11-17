------------------------------------------------------------------------
--  Native IO front-end for checked circuit computations and text emission.
--  Compile with agda --compile. Shared-wire routes use Extraction.Render
--  and the BenchISCAS character path with their checked contracts.
--  popcount emits the shared comparator; eval runs its checked evaluator.
--  IO, compilation, external preprocessing and synthesis remain trusted.
--  This --guardedness entry is outside the --safe --without-K roots.
------------------------------------------------------------------------

{-# OPTIONS --guardedness --without-K #-}

module Main where

open import Data.Nat using (ℕ; suc; _+_; _*_; _∸_; _/_; _^_; _≤?_)
open import Relation.Nullary using (yes; no)
open import SFLL.HammingDistance using (HD; parity)
open import Data.Nat.Show using (readMaybe; show)
open import Data.Maybe using (Maybe; just; nothing; fromMaybe)
open import Data.Product using (_×_; _,_)
open import Data.List using (List; []; _∷_; map; reverse; drop; foldl)
open import Data.Char using (Char)
import Data.Char as DC
open import Data.Bool using (Bool; true; false; if_then_else_; _∧_; _∨_; not)
open import Data.String using (String; _++_; toList; fromList; words; lines; _≟_)
open import Relation.Nullary.Decidable using (⌊_⌋)
import Data.Vec as V
open import IO using (IO; Main; run; putStrLn; _>>=_; readFiniteFile)
open import System.Environment using (getArgs)

open import Extraction.Render using (renderPopcount)
open import Extraction.Netlist using (netEval; Op; oConst; oNot; oAnd; oOr; oXor; get; runNet)
open import Attack.PointDIPRun using (dipReport)
open import Attack.VerifiedFALLRun using (fallReport)
open import Extraction.LUTNetParse using (parseFlat; FGate)
open import Extraction.LUTNetBuild using (importGateCount; importConeBit)
open import Extraction.LockedNet using (lockedFlatBench)
open import Extraction.LockHost using (lockHostBench)
open import Extraction.LockHostFlat using (lockHostFlatBench)
open import Extraction.LockHostMerged using (lockHostFlatMergedBench)
open import Locking.CompileC17Multi using (c17nl2)
open import Security.OCR using (OCR)
open import Util.Counting using (binom)
open import Security.ObsHosts using (mId; mParity; mThresh; mDensity; obsCount; fallCount)

------------------------------------------------------------------------
--  Use certified netEval as eval's golden oracle,
--  with all-N correctness from NetlistCorrect.netEval-correct.
--  Main eval N h <bits> evaluates popcount_eq(N,h)
--  on a zero/one string whose position i maps to
--  wᵢ, least-significant first as in INPUT(wᵢ) =
--  (x≫i)&1. Thus E1 checks the synthesized/attacked
--  text against the checked evaluator. Agreement is a local execution
--  check; it does not certify the IO/compiler or external synthesis.

charBit : Char → Bool
charBit '1' = true
charBit _   = false

bitsVec : (n : ℕ) → List Char → V.Vec Bool n
bitsVec ℕ.zero    _        = V.[]
bitsVec (ℕ.suc n) []       = false   V.∷ bitsVec n []
bitsVec (ℕ.suc n) (c ∷ cs) = charBit c V.∷ bitsVec n cs

evalReport : (N h : ℕ) → String → String
evalReport N h s = if netEval N h (bitsVec N (toList s)) then "1" else "0"

------------------------------------------------------------------------
--  emitlockflat <n> <h> <ksec> emits shared-wire .bench.
--  Inputs are x(0..n-1), keyinput(n..2n-1), and f(2n).
--  Applied keys remain INPUT wires while the secret is embedded.
--  lockedBlock-locked certifies the emitted object as locked h ksec key f x.
emitLockFlat : (n h : ℕ) → String → String
emitLockFlat n h ksec = lockedFlatBench n (V.toList (bitsVec n (toList ksec))) h

--  emitlockhost <host> <h> <ksec> uses
--  LockHost to emit a complete locked host in
--  shared-wire .bench. Here host gates compute
--  f x rather than taking f as an input.
--  Inputs are x and key buses; lockHost-locked/
--  c17flat-locked certify locked h ksec key
--  (importConeF nl) x. The supported host is c17.
emitLockHost : String → (h : ℕ) → String → String
emitLockHost "c17" h ksec = lockHostBench 5 c17nl2 (V.toList (bitsVec 5 (toList ksec))) h
emitLockHost host  _ _    =
  "# ERROR: unknown host '" ++ host ++ "' (emitlockhost hosts: c17)\n"

--  sharp reads OCR as #SAT. enum uses
--  the verified countT corrupt count over 2ⁿ inputs
--  from ModelCount.OCR-is-modelCount. closed uses
--  the proved distance-dependent formula: 2·C(n,h)
--  for odd distance, and 2·C(n,h) minus
--  2·C(n−2e,h−e)·C(2e,e) at even distance 2e≤2h
--  from EvenOCR/OCR-normal-even. Far-even e>h
--  returns the disjoint value again.
closedEven : (n h e : ℕ) → ℕ
closedEven n h e with e ≤? h
... | yes _ = 2 * binom n h ∸ 2 * (binom (n ∸ 2 * e) (h ∸ e) * binom (2 * e) e)
... | no  _ = 2 * binom n h

closedForm : (n h dist : ℕ) → ℕ
closedForm n h dist with parity dist
... | true  = 2 * binom n h
... | false = closedEven n h (dist / 2)

sharpReport : (N H : ℕ) → String → String → String
sharpReport N H ksec kapp =
  "enum=" ++ show (OCR H kV kpV) ++ " closed=" ++ show (closedForm N H (HD kV kpV))
  where kV  = bitsVec N (toList ksec)
        kpV = bitsVec N (toList kapp)

--  obs <n> prints per-host
--  name obsCount fallCount denom with denom = 2^n.
--  It runs compiled ObsHosts counting cores on
--  host slices.
--  The identity host attains obsCount = 2^n
--  by obsCount-mId-full; masking hosts reduce fallCount.
obsMain : ℕ → String
obsMain n = let d = 2 ^ n in
      row "id"  (obsCount {n} mId)            (fallCount {n} mId) d
  ++  row "par" (obsCount {n} mParity)        (fallCount {n} mParity) d
  ++  row "thr" (obsCount {n} mThresh)        (fallCount {n} mThresh) d
  ++  row "d50" (obsCount {n} (mDensity 50))  (fallCount {n} (mDensity 50)) d
  ++  rowEnd "d25" (obsCount {n} (mDensity 25)) (fallCount {n} (mDensity 25)) d
  where
    line : String → ℕ → ℕ → ℕ → String
    line nm oc fc d = nm ++ " " ++ show oc ++ " " ++ show fc ++ " " ++ show d
    row    : String → ℕ → ℕ → ℕ → String
    row nm oc fc d = line nm oc fc d ++ "\n"
    rowEnd : String → ℕ → ℕ → ℕ → String
    rowEnd = line

------------------------------------------------------------------------
--  Dispatch arguments purely from List String to output text.

usage : String
usage = "usage: Main popcount <N> <h>     (emits popcount_eq(N,h) as .bench to stdout)\n"
     ++ "       Main eval <N> <h> <bits>  (golden: verified netEval on <bits>, LSB-first, prints 0/1)\n"
     ++ "       Main dip <N> <idx>        (runs the verified point-DIP attack: 2^N queries, recovers ksec)\n"
     ++ "       Main fall <N> <idx>       (runs the verified FALL attack: N+1 queries, recovers ksec)\n"
     ++ "       Main sharp <n> <h> <ksec> <kapp>  (OCR as #SAT: the verified model count countT(corrupt) over 2^n inputs + the closed form 2*C(n,h))\n"
     ++ "       Main emitlockflat <n> <h> <ksec>          (emits the verified KEYED flat locked .bench: x|key|f inputs)\n"
     ++ "       Main emitlockhost <host> <h> <ksec>       (emits the verified locked WHOLE host .bench: x|key inputs, host computes f; host=c17)\n"
     ++ "       Main importnet <file> [bits]              (verified host import: parseFlat + fromFlat on a flat LUT-netlist; prints n/gate counts, or the cone bit on <bits>)\n"
     ++ "       Main emitlockhostflat <file> <h> <ksec>   (runtime verified extraction: parse+assemble+LOCK a flat host of unbounded size; emits the certified locked .bench)\n"
     ++ "       Main emitlockhostflatmerged <file> <ksec>  (as above but CUBE-FUSED at h=0: no secret-cube constant wires, no isolated flip node; lockHostMerged-locked)\n"
     ++ "       Main simbench <file> <bits>               (verified eval of an EMITTED .bench on one LSB-first input: runNet behind an IO-shell parser; prints 0/1)\n"
     ++ "       Main obs <n>                              (per-host observability: verified obsCount/fallCount over host slices id/par/thr/d50/d25; prints name obs fall denom)"

dispatch : List String → String
dispatch ("popcount" ∷ n ∷ h ∷ []) with readMaybe 10 n | readMaybe 10 h
... | just N | just H = renderPopcount N H
... | _      | _      = "# ERROR: N and h must be decimal naturals\n" ++ usage
dispatch ("eval" ∷ n ∷ h ∷ bits ∷ []) with readMaybe 10 n | readMaybe 10 h
... | just N | just H = evalReport N H bits
... | _      | _      = "# ERROR: N and h must be decimal naturals\n" ++ usage
dispatch ("dip" ∷ n ∷ i ∷ []) with readMaybe 10 n | readMaybe 10 i
... | just N | just I = dipReport N I
... | _      | _      = "# ERROR: N and idx must be decimal naturals\n" ++ usage
dispatch ("fall" ∷ n ∷ i ∷ []) with readMaybe 10 n | readMaybe 10 i
... | just N | just I = fallReport N I
... | _      | _      = "# ERROR: N and idx must be decimal naturals\n" ++ usage
dispatch ("obs" ∷ n ∷ []) with readMaybe 10 n
... | just N = obsMain N
... | _      = "# ERROR: n must be a decimal natural\n" ++ usage
dispatch ("sharp" ∷ n ∷ h ∷ ksec ∷ kapp ∷ []) with readMaybe 10 n | readMaybe 10 h
... | just N | just H = sharpReport N H ksec kapp
... | _      | _      = "# ERROR: n and h must be decimal naturals\n" ++ usage
dispatch ("emitlockflat" ∷ n ∷ h ∷ ksec ∷ []) with readMaybe 10 n | readMaybe 10 h
... | just N | just H = emitLockFlat N H ksec
... | _      | _      = "# ERROR: n and h must be decimal naturals\n" ++ usage
dispatch ("emitlockhost" ∷ host ∷ h ∷ ksec ∷ []) with readMaybe 10 h
... | just H = emitLockHost host H ksec
... | _      = "# ERROR: h must be a decimal natural\n" ++ usage
dispatch _ = "# ERROR: bad arguments\n" ++ usage

------------------------------------------------------------------------
--  importnet <file> [bits] reads flat LUT data
--  with header n G and G rows a b code.
--  Certified parseFlat/fromFlat parse and assemble
--  the host in Agda instead of relying on trusted
--  gen_netlist_data.py source emission. Without
--  bits, print counts; with an LSB-first bit
--  string, evaluate the imported cone to zero/one for cross-checking.

importReport : ℕ → List FGate → String
importReport n gates with importGateCount n gates
... | just G  = "imported: n=" ++ show n ++ " gates=" ++ show G
... | nothing = "import: assemble failed (scope/code)"

importEvalReport : ℕ → List FGate → String → String
importEvalReport n gates bits with importConeBit n gates (bitsVec n (toList bits))
... | just b  = if b then "1" else "0"
... | nothing = "import: assemble failed"

elimP : (Maybe (ℕ × List FGate)) → (ℕ → List FGate → String) → String
elimP nothing        _ = "import: parse failed"
elimP (just (n , g)) f = f n g

importMain : String → List String → String
importMain s (bits ∷ []) = elimP (parseFlat (toList s)) (λ n g → importEvalReport n g bits)
importMain s []          = elimP (parseFlat (toList s)) importReport
importMain s _           = "usage: Main importnet <file> [inputbits]"

------------------------------------------------------------------------
--  simbench <file> <bits> evaluates
--  an emitted renderNet .bench on one LSB-first
--  input. Surface parsing belongs to the trusted
--  IO shell, while Netlist.runNet/get provide
--  verified semantics in place of sim_bench.py's
--  evaluate(). This verifies the measurement core,
--  not orchestration; ABC cec remains an independent
--  check. Support the emitted gnd/vdd/NOT/AND/OR/XOR
--  dialect on oldest-first wK wires. Yosys-normalised
--  hosts with other syntax still use cec under the §7 dialect limit.

--  Blank gate punctuation and split words into maximal alphanumeric tokens.
isDelim : Char → Bool
isDelim c = ⌊ DC._≟_ c '(' ⌋ ∨ ⌊ DC._≟_ c ')' ⌋ ∨ ⌊ DC._≟_ c ',' ⌋ ∨ ⌊ DC._≟_ c '=' ⌋

lineTokens : String → List String
lineTokens s = words (fromList (map (λ c → if isDelim c then ' ' else c) (toList s)))

wireNum : String → ℕ                            -- Decode w12 as 12 by removing its w prefix.
wireNum s = fromMaybe 0 (readMaybe 10 (fromList (drop 1 (toList s))))

_isTok_ : String → String → Bool
a isTok b = ⌊ a ≟ b ⌋

PStateT : Set                                   -- Track input count, reversed operations, and output wire.
PStateT = ℕ × List Op × ℕ

stepLine : PStateT → String → PStateT
stepLine (n , ops , o) line with lineTokens line
... | (t0 ∷ t1 ∷ [])           = if t0 isTok "INPUT" then (suc n , ops , o)
                                  else if t0 isTok "OUTPUT" then (n , ops , wireNum t1)
                                  else if t1 isTok "gnd" then (n , oConst false ∷ ops , o)
                                  else if t1 isTok "vdd" then (n , oConst true ∷ ops , o)
                                  else (n , ops , o)
... | (_ ∷ t1 ∷ a ∷ [])        = if t1 isTok "NOT" then (n , oNot (wireNum a) ∷ ops , o)
                                  else (n , ops , o)
... | (_ ∷ t1 ∷ a ∷ b ∷ [])    = if t1 isTok "AND" then (n , oAnd (wireNum a) (wireNum b) ∷ ops , o)
                                  else if t1 isTok "OR"  then (n , oOr  (wireNum a) (wireNum b) ∷ ops , o)
                                  else if t1 isTok "XOR" then (n , oXor (wireNum a) (wireNum b) ∷ ops , o)
                                  else (n , ops , o)
... | _                        = (n , ops , o)

simbenchMain : String → String → String
simbenchMain s bits =
  let (n , opsR , o) = foldl stepLine (0 , [] , 0) (lines s)
      env = V.toList (bitsVec n (toList bits))
  in if get (runNet env (reverse opsR)) o then "1" else "0"

------------------------------------------------------------------------
--  emitlockhostflat <flatfile> <h> <ksec>
-- reads, parses, assembles, and
--  locks flat LUT input at runtime through
--  parseFlat/fromFlat/lockHostBench. Print the
--  locked .bench certified by LockHostFlat's
--  lockHostFlat-locked as locked … (importConeF nl).
--  The universal guarantee avoids a compile-time
--  Netlist literal or fixed host-size limit.

emitOrErr : Maybe String → String
emitOrErr (just t) = t
emitOrErr nothing  = "# ERROR: assemble failed (scope/code/empty host)\n"

emitLockHostFlatMain : String → String → String → String
emitLockHostFlatMain s hS ksecS with parseFlat (toList s) | readMaybe 10 hS
... | just (n , gs) | just h  = emitOrErr (lockHostFlatBench n gs (V.toList (bitsVec n (toList ksecS))) h)
... | nothing       | _       = "# ERROR: parse failed\n"
... | just _        | nothing = "# ERROR: h must be a decimal natural\n"

--  Use the same verified pipeline with
--  LockHostMerged.lockHostFlatMergedBench for
--  cube-fused emission. Its perturb path has
--  no secret-cube constants or isolated flip
--  node, and lockHostMerged-locked still gives
--  locked 0 ksec key f x. Fix h = 0 because
--  the fusion identity requires a cube predicate.
emitLockHostFlatMergedMain : String → String → String
emitLockHostFlatMergedMain s ksecS with parseFlat (toList s)
... | just (n , gs) = emitOrErr (lockHostFlatMergedBench n gs (V.toList (bitsVec n (toList ksecS))))
... | nothing       = "# ERROR: parse failed\n"

------------------------------------------------------------------------

handle : List String → IO _
handle ("importnet" ∷ f ∷ rest) = readFiniteFile f >>= λ s → putStrLn (importMain s rest)
handle ("simbench" ∷ f ∷ bits ∷ []) = readFiniteFile f >>= λ s → putStrLn (simbenchMain s bits)
handle ("emitlockhostflat" ∷ f ∷ h ∷ ksec ∷ []) =
  readFiniteFile f >>= λ s → putStrLn (emitLockHostFlatMain s h ksec)
handle ("emitlockhostflatmerged" ∷ f ∷ ksec ∷ []) =
  readFiniteFile f >>= λ s → putStrLn (emitLockHostFlatMergedMain s ksec)
handle args                     = putStrLn (dispatch args)

main : Main
main = run (getArgs >>= handle)
