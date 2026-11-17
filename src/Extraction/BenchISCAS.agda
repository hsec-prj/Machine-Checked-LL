------------------------------------------------------------------------
--  Verify the emitter's ISCAS .bench printer/parser round trip.
--  BenchRoundTrip certifies a separate private #n=… g=… o=… format.
--  Render.renderNet supplies INPUT(w…) and OUTPUT(w…) declarations and
--  w<id> = GATE(w…, w…) lines. renderNet-roundtrip proves
--  parseNet (renderNetL n ops outId) ≡ just (n,ops,outId).
--  renderNet is defined as fromList of that certified character list.
--  Input count, operations, and output wire survive the text layer; renderNet-sem
--  then preserves denotation. This does not prove agreement with ABC's
--  or Yosys's readers; that remains external empirical evidence. The
--  parser intentionally accepts only this printer's format: exact header
--  characters, case-sensitive keywords, exactly comma-space-w between
--  two-input operands, no optional whitespace, blank lines, trailing
--  newline, or other comments. It is a round-trip witness, not a
--  general .bench frontend. As in BenchRoundTrip, the theorem concerns
--  List Char. Under --safe the String primitives expose injectivity
--  but no toList ∘ fromList ≡ id reduction, so the String renderer
--  is defined through the certified character list. natCharsM prints
--  most-significant-first ordinary decimal without leading zeros, like
--  Data.Nat.Show.show. Its toNatDigits recursion lacks a library
--  inversion lemma, so use Data.Digit.toDigits with its bundled inverse
--  and reverse the digits. Characterwise equality of the two decimal
--  renderers is not proved here. Use --safe --without-K and no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.BenchISCAS where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Fin using (Fin) renaming (zero to fz; suc to fs)
open import Data.Bool using (Bool; true; false; if_then_else_; _≟_)
open import Data.Char using (Char; _≈ᵇ_)
open import Data.List using (List; []; _∷_; _++_; map; reverse)
open import Data.List.Properties using (reverse-involutive)
open import Data.List.Relation.Unary.All using (All; all?)
  renaming ([] to []ᴬ; _∷_ to _∷ᴬ_)
open import Data.List.Relation.Unary.All.Properties using (map⁺; ++⁺)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Product using (_×_; _,_; proj₁; proj₂; map₁)
open import Data.String using (toList)
open import Data.Unit using (⊤; tt)
open import Data.Vec using (Vec) renaming (toList to vecToList)
open import Data.Digit using (toDigits; fromDigits)
open import Relation.Nullary.Decidable using (Dec; from-yes)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; module ≡-Reasoning)

open import Extraction.Netlist using
  (Op; oConst; oNot; oAnd; oOr; oXor; get; runNet; popcountEqNet; netEval)
open import Extraction.BenchRoundTrip using
  (digitChar; charToDigit; spanDigits; span-rt; match; _>>=_; evalParsed)

------------------------------------------------------------------------
--  §1 Reverse BenchRoundTrip's least-significant-first digit codec
--  to print ordinary most-significant-first .bench indices. Prove
--  the inverse using reverse-involutive and toDigits' bundled theorem.

natCharsM : ℕ → List Char
natCharsM k = map digitChar (reverse (proj₁ (toDigits 10 k)))

readNatM : List Char → ℕ × List Char
readNatM cs = map₁ (λ ds → fromDigits (reverse ds)) (spanDigits cs)

--  State the rewriting lemmas at spanDigits/fromDigits, since
--  let (a,r) = readNatM cs eta-expands the result pair and leaves
--  no readNatM cs expression in per-line round-trip goals.
spanM : (k : ℕ) (c : Char) (rest : List Char)
      → charToDigit c ≡ nothing
      → spanDigits (natCharsM k ++ c ∷ rest)
        ≡ (reverse (proj₁ (toDigits 10 k)) , c ∷ rest)
spanM k = span-rt (reverse (proj₁ (toDigits 10 k)))

natM-inv : (k : ℕ) → fromDigits (reverse (reverse (proj₁ (toDigits 10 k)))) ≡ k
natM-inv k rewrite reverse-involutive (proj₁ (toDigits 10 k)) = proj₂ (toDigits 10 k)

--  Package spanM/natM-inv as the specification that number reading
--  inverts number printing.
readNatM-rt : (k : ℕ) (c : Char) (rest : List Char)
            → charToDigit c ≡ nothing
            → readNatM (natCharsM k ++ c ∷ rest) ≡ (k , c ∷ rest)
readNatM-rt k c rest cn = begin
    map₁ f (spanDigits (map digitChar (reverse ds) ++ c ∷ rest))
  ≡⟨ cong (map₁ f) (span-rt (reverse ds) c rest cn) ⟩
    (fromDigits (reverse (reverse ds)) , c ∷ rest)
  ≡⟨ cong (λ z → (fromDigits z , c ∷ rest)) (reverse-involutive ds) ⟩
    (fromDigits ds , c ∷ rest)
  ≡⟨ cong (_, c ∷ rest) (proj₂ (toDigits 10 k)) ⟩
    (k , c ∷ rest)
  ∎
  where
    open ≡-Reasoning
    ds = proj₁ (toDigits 10 k)
    f  = λ (es : List (Fin 10)) → fromDigits (reverse es)

------------------------------------------------------------------------
--  §2 Split characters into lines before parsing. ISCAS headers have
--  no gate/input counts for the structural recursion used by
--  BenchRoundTrip.parseNGates; recursion over the line list restores
--  a structural argument for every following parser.

isNL : Char → Bool
isNL c = c ≈ᵇ '\n'

--  Require newline-free lines so splitting can invert joining.
NoNL : List Char → Set
NoNL = All (λ c → isNL c ≡ false)

noNL? : (l : List Char) → Dec (NoNL l)
noNL? = all? (λ c → isNL c ≟ false)

consHead : Char → List (List Char) → List (List Char)
consHead c []       = (c ∷ []) ∷ []
consHead c (l ∷ ls) = (c ∷ l) ∷ ls

splitLines : List Char → List (List Char)
splitLines []       = [] ∷ []
splitLines (c ∷ cs) = if isNL c then [] ∷ splitLines cs else consHead c (splitLines cs)

--  Insert newlines only between lines, matching Render.joinNL's
--  existing layout without a final newline.
joinLines : List (List Char) → List Char
joinLines []            = []
joinLines (l ∷ [])      = l
joinLines (l ∷ l' ∷ ls) = l ++ '\n' ∷ joinLines (l' ∷ ls)

split-noNL : (l : List Char) → NoNL l → splitLines l ≡ l ∷ []
split-noNL []      _          = refl
split-noNL (c ∷ l) (p ∷ᴬ ps) rewrite p | split-noNL l ps = refl

split-cons : (l t : List Char) → NoNL l
           → splitLines (l ++ '\n' ∷ t) ≡ l ∷ splitLines t
split-cons []      t _          = refl
split-cons (c ∷ l) t (p ∷ᴬ ps) rewrite p | split-cons l t ps = refl

--  Prove splitting reverses joining for nonempty lists of newline-free lines.
splitLines-joinLines :
  (l : List Char) (ls : List (List Char)) → NoNL l → All NoNL ls →
  splitLines (joinLines (l ∷ ls)) ≡ l ∷ ls
splitLines-joinLines l []        pl _           = split-noNL l pl
splitLines-joinLines l (l' ∷ ls) pl (q ∷ᴬ qs)
  rewrite split-cons l (joinLines (l' ∷ ls)) pl
        | splitLines-joinLines l' ls q qs = refl

------------------------------------------------------------------------
--  §3 Print character sequences with toList literals, making source
--  text resemble output. primStringToList reduces on literals,
--  so those parts of the round trip hold definitionally.

headerLine : List Char
headerLine = toList "# generated by Extraction.Render (netlist .bench)"

inputLine : ℕ → List Char
inputLine j = toList "INPUT(w" ++ (natCharsM j ++ ')' ∷ [])

inputLines : ℕ → ℕ → List (List Char)
inputLines j zero    = []
inputLines j (suc k) = inputLine j ∷ inputLines (suc j) k

outputLine : ℕ → List Char
outputLine o = toList "OUTPUT(w" ++ (natCharsM o ++ ')' ∷ [])

rhsChars : Op → List Char
rhsChars (oConst true)  = toList "vdd()"
rhsChars (oConst false) = toList "gnd()"
rhsChars (oNot a)   = toList "NOT(w" ++ (natCharsM a ++ ')' ∷ [])
rhsChars (oAnd a b) =
  toList "AND(w" ++ (natCharsM a ++ (toList ", w" ++ (natCharsM b ++ ')' ∷ [])))
rhsChars (oOr a b) =
  toList "OR(w" ++ (natCharsM a ++ (toList ", w" ++ (natCharsM b ++ ')' ∷ [])))
rhsChars (oXor a b) =
  toList "XOR(w" ++ (natCharsM a ++ (toList ", w" ++ (natCharsM b ++ ')' ∷ [])))

gateLine : ℕ → Op → List Char
gateLine w op = toList "w" ++ (natCharsM w ++ (toList " = " ++ rhsChars op))

--  Number the output of zero-indexed gate k as wire w + k in the flat IR.
gateLines : ℕ → List Op → List (List Char)
gateLines w []         = []
gateLines w (op ∷ ops) = gateLine w op ∷ gateLines (suc w) ops

renderNetLines : ℕ → List Op → ℕ → List (List Char)
renderNetLines n ops outId =
  headerLine ∷ (inputLines 0 n ++ (outputLine outId ∷ gateLines n ops))

--  Provide shipped .bench characters; Render.renderNet applies fromList to them.
renderNetL : ℕ → List Op → ℕ → List Char
renderNetL n ops outId = joinLines (renderNetLines n ops outId)

------------------------------------------------------------------------
--  §4 Parse by lines, keeping all recursive calls structural.

endOf : {A : Set} → A → List Char → Maybe A
endOf a []      = just a
endOf a (_ ∷ _) = nothing

parseInputLine : List Char → Maybe ℕ
parseInputLine l =
  match (toList "INPUT(w") l >>= λ r0 →
  let (j , r1) = readNatM r0 in
  match (')' ∷ []) r1 >>= λ r2 →
  endOf j r2

parseOutputLine : List Char → Maybe ℕ
parseOutputLine l =
  match (toList "OUTPUT(w") l >>= λ r0 →
  let (o , r1) = readNatM r0 in
  match (')' ∷ []) r1 >>= λ r2 →
  endOf o r2

parse1L : (ℕ → Op) → List Char → List Char → Maybe Op
parse1L ctor tl cs =
  match tl cs >>= λ r1 →
  let (a , r2) = readNatM r1 in
  match (')' ∷ []) r2 >>= λ r3 →
  endOf (ctor a) r3

parse2L : (ℕ → ℕ → Op) → List Char → List Char → Maybe Op
parse2L ctor tl cs =
  match tl cs >>= λ r1 →
  let (a , r2) = readNatM r1 in
  match (toList ", w") r2 >>= λ r3 →
  let (b , r4) = readNatM r3 in
  match (')' ∷ []) r4 >>= λ r5 →
  endOf (ctor a b) r5

parseRHSL : List Char → Maybe Op
parseRHSL []       = nothing
parseRHSL (c ∷ cs) =
  if c ≈ᵇ 'v' then (match (toList "dd()") cs >>= endOf (oConst true))
  else if c ≈ᵇ 'g' then (match (toList "nd()") cs >>= endOf (oConst false))
  else if c ≈ᵇ 'N' then parse1L oNot (toList "OT(w") cs
  else if c ≈ᵇ 'A' then parse2L oAnd (toList "ND(w") cs
  else if c ≈ᵇ 'O' then parse2L oOr  (toList "R(w") cs
  else if c ≈ᵇ 'X' then parse2L oXor (toList "OR(w") cs
  else nothing

parseGateLine : List Char → Maybe Op
parseGateLine l =
  match (toList "w") l >>= λ r0 →
  let (w , r1) = readNatM r0 in
  match (toList " = ") r1 >>= λ r2 →
  parseRHSL r2

parseGateLines : List (List Char) → Maybe (List Op)
parseGateLines []       = just []
parseGateLines (l ∷ ls) =
  parseGateLine l >>= λ op →
  parseGateLines ls >>= λ ops →
  just (op ∷ ops)

--  Count the initial INPUT declarations because .bench carries no
--  input count. Factor through top-level inpStep so the round-trip
--  proof can rewrite its scrutinee.
inpStep : Maybe ℕ → List Char → List (List Char)
        → ℕ × List (List Char) → ℕ × List (List Char)
inpStep (just _) l ls r = map₁ suc r
inpStep nothing  l ls r = 0 , l ∷ ls

countInputs : List (List Char) → ℕ × List (List Char)
countInputs []       = 0 , []
countInputs (l ∷ ls) = inpStep (parseInputLine l) l ls (countInputs ls)

parseTail : ℕ → List (List Char) → Maybe (ℕ × List Op × ℕ)
parseTail n []       = nothing
parseTail n (o ∷ ls) =
  parseOutputLine o >>= λ outId →
  parseGateLines ls >>= λ ops →
  just (n , ops , outId)

parseNetLines : List (List Char) → Maybe (ℕ × List Op × ℕ)
parseNetLines []       = nothing
parseNetLines (h ∷ ls) =
  match headerLine h >>= λ r →
  endOf tt r >>= λ _ →
  parseTail (proj₁ (countInputs ls)) (proj₂ (countInputs ls))

--  Parse the character sequence used for the shipped ISCAS text.
parseNet : List Char → Maybe (ℕ × List Op × ℕ)
parseNet cs = parseNetLines (splitLines cs)

------------------------------------------------------------------------
--  §5 Prove line-level round trips, definitionally after digit inversion.

parseInputLine-rt : (j : ℕ) → parseInputLine (inputLine j) ≡ just j
parseInputLine-rt j rewrite spanM j ')' [] refl | natM-inv j = refl

parseOutputLine-rt : (o : ℕ) → parseOutputLine (outputLine o) ≡ just o
parseOutputLine-rt o rewrite spanM o ')' [] refl | natM-inv o = refl

parseRHSL-rt : (op : Op) → parseRHSL (rhsChars op) ≡ just op
parseRHSL-rt (oConst true)  = refl
parseRHSL-rt (oConst false) = refl
parseRHSL-rt (oNot a) rewrite spanM a ')' [] refl | natM-inv a = refl
parseRHSL-rt (oAnd a b)
  rewrite spanM a ',' (' ' ∷ 'w' ∷ (natCharsM b ++ ')' ∷ [])) refl
        | spanM b ')' [] refl | natM-inv a | natM-inv b = refl
parseRHSL-rt (oOr a b)
  rewrite spanM a ',' (' ' ∷ 'w' ∷ (natCharsM b ++ ')' ∷ [])) refl
        | spanM b ')' [] refl | natM-inv a | natM-inv b = refl
parseRHSL-rt (oXor a b)
  rewrite spanM a ',' (' ' ∷ 'w' ∷ (natCharsM b ++ ')' ∷ [])) refl
        | spanM b ')' [] refl | natM-inv a | natM-inv b = refl

--  Parse and discard the left-hand wire identifier; its role is
--  to delimit the remaining line.
parseGateLine-rt : (w : ℕ) (op : Op) → parseGateLine (gateLine w op) ≡ just op
parseGateLine-rt w op
  rewrite spanM w ' ' ('=' ∷ ' ' ∷ rhsChars op) refl
        | parseRHSL-rt op = refl

parseGateLines-rt : (w : ℕ) (ops : List Op) → parseGateLines (gateLines w ops) ≡ just ops
parseGateLines-rt w []         = refl
parseGateLines-rt w (op ∷ ops)
  rewrite parseGateLine-rt w op | parseGateLines-rt (suc w) ops = refl

--  Stop the initial INPUT run exactly at OUTPUT: its first character
--  O fails the I match definitionally, where the printer ends the run.
countInputs-stop : (o : ℕ) (ls : List (List Char))
                 → countInputs (outputLine o ∷ ls) ≡ (0 , outputLine o ∷ ls)
countInputs-stop o ls = refl

countInputs-rt : (n j : ℕ) (rest : List (List Char))
               → countInputs rest ≡ (0 , rest)
               → countInputs (inputLines j n ++ rest) ≡ (n , rest)
countInputs-rt zero    j rest hyp = hyp
countInputs-rt (suc n) j rest hyp
  rewrite parseInputLine-rt j | countInputs-rt n (suc j) rest hyp = refl

------------------------------------------------------------------------
--  §6 Prove rendered lines contain no newline, satisfying §2's premise.

digitNoNL : (d : Fin 10) → isNL (digitChar d) ≡ false
digitNoNL fz                                              = refl
digitNoNL (fs fz)                                         = refl
digitNoNL (fs (fs fz))                                    = refl
digitNoNL (fs (fs (fs fz)))                               = refl
digitNoNL (fs (fs (fs (fs fz))))                          = refl
digitNoNL (fs (fs (fs (fs (fs fz)))))                     = refl
digitNoNL (fs (fs (fs (fs (fs (fs fz))))))                = refl
digitNoNL (fs (fs (fs (fs (fs (fs (fs fz)))))))           = refl
digitNoNL (fs (fs (fs (fs (fs (fs (fs (fs fz))))))))      = refl
digitNoNL (fs (fs (fs (fs (fs (fs (fs (fs (fs fz))))))))) = refl

private
  allDigits : (ds : List (Fin 10)) → All (λ d → isNL (digitChar d) ≡ false) ds
  allDigits []       = []ᴬ
  allDigits (d ∷ ds) = digitNoNL d ∷ᴬ allDigits ds

natCharsM-NoNL : (k : ℕ) → NoNL (natCharsM k)
natCharsM-NoNL k = map⁺ (allDigits (reverse (proj₁ (toDigits 10 k))))

private
  closeNoNL : NoNL (')' ∷ [])
  closeNoNL = refl ∷ᴬ []ᴬ

noNL-header : NoNL headerLine
noNL-header = from-yes (noNL? headerLine)

noNL-input : (j : ℕ) → NoNL (inputLine j)
noNL-input j =
  ++⁺ (from-yes (noNL? (toList "INPUT(w"))) (++⁺ (natCharsM-NoNL j) closeNoNL)

noNL-inputs : (j n : ℕ) → All NoNL (inputLines j n)
noNL-inputs j zero    = []ᴬ
noNL-inputs j (suc n) = noNL-input j ∷ᴬ noNL-inputs (suc j) n

noNL-output : (o : ℕ) → NoNL (outputLine o)
noNL-output o =
  ++⁺ (from-yes (noNL? (toList "OUTPUT(w"))) (++⁺ (natCharsM-NoNL o) closeNoNL)

noNL-rhs : (op : Op) → NoNL (rhsChars op)
noNL-rhs (oConst true)  = from-yes (noNL? (toList "vdd()"))
noNL-rhs (oConst false) = from-yes (noNL? (toList "gnd()"))
noNL-rhs (oNot a) =
  ++⁺ (from-yes (noNL? (toList "NOT(w"))) (++⁺ (natCharsM-NoNL a) closeNoNL)
noNL-rhs (oAnd a b) =
  ++⁺ (from-yes (noNL? (toList "AND(w")))
      (++⁺ (natCharsM-NoNL a)
           (++⁺ (from-yes (noNL? (toList ", w")))
                (++⁺ (natCharsM-NoNL b) closeNoNL)))
noNL-rhs (oOr a b) =
  ++⁺ (from-yes (noNL? (toList "OR(w")))
      (++⁺ (natCharsM-NoNL a)
           (++⁺ (from-yes (noNL? (toList ", w")))
                (++⁺ (natCharsM-NoNL b) closeNoNL)))
noNL-rhs (oXor a b) =
  ++⁺ (from-yes (noNL? (toList "XOR(w")))
      (++⁺ (natCharsM-NoNL a)
           (++⁺ (from-yes (noNL? (toList ", w")))
                (++⁺ (natCharsM-NoNL b) closeNoNL)))

noNL-gate : (w : ℕ) (op : Op) → NoNL (gateLine w op)
noNL-gate w op =
  ++⁺ (from-yes (noNL? (toList "w")))
      (++⁺ (natCharsM-NoNL w)
           (++⁺ (from-yes (noNL? (toList " = "))) (noNL-rhs op)))

noNL-gates : (w : ℕ) (ops : List Op) → All NoNL (gateLines w ops)
noNL-gates w []         = []ᴬ
noNL-gates w (op ∷ ops) = noNL-gate w op ∷ᴬ noNL-gates (suc w) ops

noNL-body : (n : ℕ) (ops : List Op) (outId : ℕ)
          → All NoNL (inputLines 0 n ++ (outputLine outId ∷ gateLines n ops))
noNL-body n ops outId =
  ++⁺ (noNL-inputs 0 n) (noNL-output outId ∷ᴬ noNL-gates n ops)

------------------------------------------------------------------------
--  §7 Establish the round trip for the delivered ISCAS syntax.

--  Recover the exact rendered line list by splitting the emitted text.
splitLines-renderNetL : (n : ℕ) (ops : List Op) (outId : ℕ)
                      → splitLines (renderNetL n ops outId) ≡ renderNetLines n ops outId
splitLines-renderNetL n ops outId =
  splitLines-joinLines headerLine _ noNL-header (noNL-body n ops outId)

--  Show .bench printing followed by parsing preserves input count,
--  gate list, and output wire identically.
renderNet-roundtrip : (n : ℕ) (ops : List Op) (outId : ℕ)
                    → parseNet (renderNetL n ops outId) ≡ just (n , ops , outId)
renderNet-roundtrip n ops outId
  rewrite splitLines-renderNetL n ops outId
        | countInputs-rt n 0 (outputLine outId ∷ gateLines n ops)
                        (countInputs-stop outId (gateLines n ops))
        | parseOutputLine-rt outId
        | parseGateLines-rt n ops = refl

------------------------------------------------------------------------
--  §8 Derive denotation preservation through the delivered text.

--  At every input environment, evaluate the parsed emitted netlist
--  to the same value as the original netlist.
renderNet-sem : (n : ℕ) (ops : List Op) (outId : ℕ) (env : List Bool)
              → evalParsed (parseNet (renderNetL n ops outId)) env
                ≡ get (runNet env ops) outId
renderNet-sem n ops outId env rewrite renderNet-roundtrip n ops outId = refl

--  Specialise to the synthesizable comparator: parsing and evaluating
--  its shipped .bench text computes netEval, identified by
--  NetlistCorrect.netEval-correct with weight ≡ᵇ h. This is the
--  shipped-format counterpart of BenchRoundTrip.netlist-text-correct.
netlist-bench-correct :
  (N h : ℕ) →
  let (ops , outId) = popcountEqNet N h in
  (xs : Vec Bool N) →
  evalParsed (parseNet (renderNetL N ops outId)) (vecToList xs) ≡ netEval N h xs
netlist-bench-correct N h xs =
  renderNet-sem N (proj₁ (popcountEqNet N h)) (proj₂ (popcountEqNet N h)) (vecToList xs)

------------------------------------------------------------------------
--  §9 Use small normalising examples to fix the printer's actual
--  output and show the parser is not a constantly-just function.
--  They are independent of the preceding theorems.

--  Spell out small emitted-byte examples. Data.Nat.Show.show would
--  produce these same decimal characters on the displayed instances.
render-sample :
  renderNetL 2 (oAnd 0 1 ∷ oNot 2 ∷ []) 3
    ≡ toList "# generated by Extraction.Render (netlist .bench)\nINPUT(w0)\nINPUT(w1)\nOUTPUT(w3)\nw2 = AND(w0, w1)\nw3 = NOT(w2)"
render-sample = refl

--  Check that multi-digit identifiers use most-significant-first order.
render-sample-2digit :
  renderNetL 0 [] 12 ≡ toList "# generated by Extraction.Render (netlist .bench)\nOUTPUT(w12)"
render-sample-2digit = refl

--  Demonstrate partial parsing by rejecting text outside this printer's format.
parse-rejects-foreign : parseNet (toList "INPUT(w0)\nOUTPUT(w1)\nw1 = NOT(w0)") ≡ nothing
parse-rejects-foreign = refl

parse-rejects-truncated :
  parseNet (toList "# generated by Extraction.Render (netlist .bench)\nINPUT(w0)") ≡ nothing
parse-rejects-truncated = refl

--  Also exhibit successful parsing, excluding a constantly-nothing parser.
parse-sample :
  parseNet (toList "# generated by Extraction.Render (netlist .bench)\nINPUT(w0)\nINPUT(w1)\nOUTPUT(w3)\nw2 = AND(w0, w1)\nw3 = NOT(w2)")
    ≡ just (2 , oAnd 0 1 ∷ oNot 2 ∷ [] , 3)
parse-sample = refl
