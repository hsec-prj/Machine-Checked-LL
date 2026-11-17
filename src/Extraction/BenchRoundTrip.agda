------------------------------------------------------------------------
--  Verify a printer/parser round trip for the private flat-netlist format.
--  renderL and parseL operate on List Op with the theorem roundtrip:
--  parseL (renderL n ops outId) ≡ just (n, ops, outId).
--  The semantic consequence netlist-text-correct gives evaluation after
--  printing and parsing equal to netEval, certifying text semantics.
--  The theorem concerns faithful List Char content. Under --safe,
--  Agda.Builtin.String.Properties provides primStringToList and
--  primStringFromList injectivity but no toList ∘ fromList ≡ id reduction,
--  so String is represented by injective fromList of the proved character
--  sequence. Print wire indices least-significant-digit first using
--  Data.Digit.toDigits, which bundles fromDigits ∘ toDigits ≡ id. Digit
--  Digit orientation is internal to this codec; BenchISCAS uses ordinary order.
--  The development is --safe --without-K with no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.BenchRoundTrip where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Fin using (Fin; #_) renaming (zero to fz; suc to fs)
open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Char using (Char; _≈ᵇ_)
open import Data.List using (List; []; _∷_; _++_; map; length)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Product using (_×_; _,_; proj₁; proj₂; map₁)
open import Data.Vec using (Vec; lookup) renaming (_∷_ to _∷ᵛ_; [] to []ᵛ)
open import Data.Vec using (toList)
open import Data.Digit using (toDigits; fromDigits)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; trans; module ≡-Reasoning)

open import Extraction.Netlist using
  (Op; oConst; oNot; oAnd; oOr; oXor; get; runNet; popcountEqNet; netEval)

------------------------------------------------------------------------
--  Section 1: define the decimal codec, the only part requiring number reasoning.

digitTable : Vec Char 10
digitTable =
  '0' ∷ᵛ '1' ∷ᵛ '2' ∷ᵛ '3' ∷ᵛ '4' ∷ᵛ '5' ∷ᵛ '6' ∷ᵛ '7' ∷ᵛ '8' ∷ᵛ '9' ∷ᵛ []ᵛ

digitChar : Fin 10 → Char
digitChar = lookup digitTable

--  Choose canonical digits so their round-trip cases are ten refl proofs.
d0 d1 d2 d3 d4 d5 d6 d7 d8 d9 : Fin 10
d0 = # 0
d1 = # 1
d2 = # 2
d3 = # 3
d4 = # 4
d5 = # 5
d6 = # 6
d7 = # 7
d8 = # 8
d9 = # 9

charToDigit : Char → Maybe (Fin 10)
charToDigit c =
  if c ≈ᵇ '0' then just d0 else
  if c ≈ᵇ '1' then just d1 else
  if c ≈ᵇ '2' then just d2 else
  if c ≈ᵇ '3' then just d3 else
  if c ≈ᵇ '4' then just d4 else
  if c ≈ᵇ '5' then just d5 else
  if c ≈ᵇ '6' then just d6 else
  if c ≈ᵇ '7' then just d7 else
  if c ≈ᵇ '8' then just d8 else
  if c ≈ᵇ '9' then just d9 else nothing

--  Prove char-to-digit inverts digit-to-char in ten concrete reducing cases.
cd-dc : (d : Fin 10) → charToDigit (digitChar d) ≡ just d
cd-dc fz                                              = refl
cd-dc (fs fz)                                         = refl
cd-dc (fs (fs fz))                                    = refl
cd-dc (fs (fs (fs fz)))                               = refl
cd-dc (fs (fs (fs (fs fz))))                          = refl
cd-dc (fs (fs (fs (fs (fs fz)))))                     = refl
cd-dc (fs (fs (fs (fs (fs (fs fz))))))                = refl
cd-dc (fs (fs (fs (fs (fs (fs (fs fz)))))))           = refl
cd-dc (fs (fs (fs (fs (fs (fs (fs (fs fz))))))))      = refl
cd-dc (fs (fs (fs (fs (fs (fs (fs (fs (fs fz))))))))) = refl

------------------------------------------------------------------------
--  Section 2: encode naturals as decimal character lists and prove inversion.

natToDigits : ℕ → List Char
natToDigits n = map digitChar (proj₁ (toDigits 10 n))

--  Read the longest leading sequence of decimal digits, least significant first.
spanDigits : List Char → List (Fin 10) × List Char
spanDigits []       = [] , []
spanDigits (c ∷ cs) with charToDigit c
... | just d  = map₁ (d ∷_) (spanDigits cs)
... | nothing = [] , c ∷ cs

readNat : List Char → ℕ × List Char
readNat cs = map₁ fromDigits (spanDigits cs)

--  A non-digit c terminates a digit sequence unambiguously.
span-rt : (ds : List (Fin 10)) (c : Char) (rest : List Char)
        → charToDigit c ≡ nothing
        → spanDigits (map digitChar ds ++ c ∷ rest) ≡ (ds , c ∷ rest)
span-rt []       c rest cn rewrite cn = refl
span-rt (d ∷ ds) c rest cn rewrite cd-dc d | span-rt ds c rest cn = refl

readNat-rt : (n : ℕ) (c : Char) (rest : List Char)
           → charToDigit c ≡ nothing
           → readNat (natToDigits n ++ c ∷ rest) ≡ (n , c ∷ rest)
readNat-rt n c rest cn = begin
    map₁ fromDigits (spanDigits (map digitChar (proj₁ (toDigits 10 n)) ++ c ∷ rest))
  ≡⟨ cong (map₁ fromDigits) (span-rt (proj₁ (toDigits 10 n)) c rest cn) ⟩
    (fromDigits (proj₁ (toDigits 10 n)) , c ∷ rest)
  ≡⟨ cong (_, c ∷ rest) (proj₂ (toDigits 10 n)) ⟩
    (n , c ∷ rest)
  ∎
  where open ≡-Reasoning

------------------------------------------------------------------------
--  Section 3: match concrete keyword lists, which reduce definitionally
--  without a separate lemma.

match : List Char → List Char → Maybe (List Char)
match []       cs       = just cs
match (l ∷ ls) []       = nothing
match (l ∷ ls) (c ∷ cs) = if l ≈ᵇ c then match ls cs else nothing

infixl 1 _>>=_
_>>=_ : ∀ {A B : Set} → Maybe A → (A → Maybe B) → Maybe B
just a  >>= f = f a
nothing >>= f = nothing

------------------------------------------------------------------------
--  Section 4: print and parse gate right-hand sides in .bench-style syntax.
--  Use continuation/difference-list rendering, prepending to the actual tail,
--  so numbers immediately meet their suffix and round-trip proofs avoid
--  reassociating appended lists.

rRHS : Op → List Char → List Char
rRHS (oConst true)  t = 'v' ∷ 'd' ∷ 'd' ∷ '(' ∷ ')' ∷ t
rRHS (oConst false) t = 'g' ∷ 'n' ∷ 'd' ∷ '(' ∷ ')' ∷ t
rRHS (oNot a)   t = 'N' ∷ 'O' ∷ 'T' ∷ '(' ∷ 'w' ∷ natToDigits a ++ ')' ∷ t
rRHS (oAnd a b) t =
  'A' ∷ 'N' ∷ 'D' ∷ '(' ∷ 'w' ∷ natToDigits a ++ ',' ∷ ' ' ∷ 'w' ∷ natToDigits b ++ ')' ∷ t
rRHS (oOr a b) t =
  'O' ∷ 'R' ∷ '(' ∷ 'w' ∷ natToDigits a ++ ',' ∷ ' ' ∷ 'w' ∷ natToDigits b ++ ')' ∷ t
rRHS (oXor a b) t =
  'X' ∷ 'O' ∷ 'R' ∷ '(' ∷ 'w' ∷ natToDigits a ++ ',' ∷ ' ' ∷ 'w' ∷ natToDigits b ++ ')' ∷ t

--  Parse unary NOT after the keyword has consumed characters through w.
parse1 : (ℕ → Op) → List Char → List Char → Maybe (Op × List Char)
parse1 ctor tl cs =
  match tl cs >>= λ r1 →
  let (a , r2) = readNat r1 in
  match (')' ∷ []) r2 >>= λ r3 →
  just (ctor a , r3)

--  Parse a two-input AND, OR, or XOR gate.
parse2 : (ℕ → ℕ → Op) → List Char → List Char → Maybe (Op × List Char)
parse2 ctor tl cs =
  match tl cs >>= λ r1 →
  let (a , r2) = readNat r1 in
  match (',' ∷ ' ' ∷ 'w' ∷ []) r2 >>= λ r3 →
  let (b , r4) = readNat r3 in
  match (')' ∷ []) r4 >>= λ r5 →
  just (ctor a b , r5)

parseRHS : List Char → Maybe (Op × List Char)
parseRHS []       = nothing
parseRHS (c ∷ cs) =
  if c ≈ᵇ 'v' then (match ('d' ∷ 'd' ∷ '(' ∷ ')' ∷ []) cs >>= λ r → just (oConst true  , r))
  else if c ≈ᵇ 'g' then (match ('n' ∷ 'd' ∷ '(' ∷ ')' ∷ []) cs >>= λ r → just (oConst false , r))
  else if c ≈ᵇ 'N' then parse1 oNot ('O' ∷ 'T' ∷ '(' ∷ 'w' ∷ []) cs
  else if c ≈ᵇ 'A' then parse2 oAnd ('N' ∷ 'D' ∷ '(' ∷ 'w' ∷ []) cs
  else if c ≈ᵇ 'O' then parse2 oOr  ('R' ∷ '(' ∷ 'w' ∷ []) cs
  else if c ≈ᵇ 'X' then parse2 oXor ('O' ∷ 'R' ∷ '(' ∷ 'w' ∷ []) cs
  else nothing

parseRHS-rt : (op : Op) (t : List Char)
            → parseRHS (rRHS op t) ≡ just (op , t)
parseRHS-rt (oConst true)  t = refl
parseRHS-rt (oConst false) t = refl
parseRHS-rt (oNot a) t
  rewrite span-rt (proj₁ (toDigits 10 a)) ')' t refl
        | proj₂ (toDigits 10 a) = refl
parseRHS-rt (oAnd a b) t
  rewrite span-rt (proj₁ (toDigits 10 a)) ',' (' ' ∷ 'w' ∷ natToDigits b ++ ')' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 b)) ')' t refl
        | proj₂ (toDigits 10 a) | proj₂ (toDigits 10 b) = refl
parseRHS-rt (oOr a b) t
  rewrite span-rt (proj₁ (toDigits 10 a)) ',' (' ' ∷ 'w' ∷ natToDigits b ++ ')' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 b)) ')' t refl
        | proj₂ (toDigits 10 a) | proj₂ (toDigits 10 b) = refl
parseRHS-rt (oXor a b) t
  rewrite span-rt (proj₁ (toDigits 10 a)) ',' (' ' ∷ 'w' ∷ natToDigits b ++ ')' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 b)) ')' t refl
        | proj₂ (toDigits 10 a) | proj₂ (toDigits 10 b) = refl

------------------------------------------------------------------------
--  Section 5: combine the w<id> = left side with the gate right side and
--  process lists of gate lines.

rGateLine : ℕ → Op → List Char → List Char
rGateLine w op t =
  'w' ∷ natToDigits w ++ ' ' ∷ '=' ∷ ' ' ∷ rRHS op ('\n' ∷ t)

rGateLines : ℕ → List Op → List Char → List Char
rGateLines w []         t = t
rGateLines w (op ∷ ops) t = rGateLine w op (rGateLines (suc w) ops t)

parseGateLine : List Char → Maybe (Op × List Char)
parseGateLine cs =
  match ('w' ∷ []) cs >>= λ r0 →
  let (w , r1) = readNat r0 in
  match (' ' ∷ '=' ∷ ' ' ∷ []) r1 >>= λ r2 →
  parseRHS r2 >>= λ p →
  match ('\n' ∷ []) (proj₂ p) >>= λ r4 →
  just (proj₁ p , r4)

parseGateLine-rt : (w : ℕ) (op : Op) (t : List Char)
                 → parseGateLine (rGateLine w op t) ≡ just (op , t)
--  Parse but discard the left-side wire identifier; its proj₂ value is unused.
parseGateLine-rt w op t
  rewrite span-rt (proj₁ (toDigits 10 w)) ' ' ('=' ∷ ' ' ∷ rRHS op ('\n' ∷ t)) refl
        | parseRHS-rt op ('\n' ∷ t) = refl

--  Read exactly g gates by structural recursion on the header's gate count,
--  keeping parsing total and terminating.
parseNGates : ℕ → List Char → Maybe (List Op × List Char)
parseNGates zero    cs = just ([] , cs)
parseNGates (suc g) cs =
  parseGateLine cs >>= λ p →
  parseNGates g (proj₂ p) >>= λ q →
  just (proj₁ p ∷ proj₁ q , proj₂ q)

parseNGates-rt : (w : ℕ) (ops : List Op) (t : List Char)
               → parseNGates (length ops) (rGateLines w ops t) ≡ just (ops , t)
parseNGates-rt w []         t = refl
parseNGates-rt w (op ∷ ops) t
  rewrite parseGateLine-rt w op (rGateLines (suc w) ops t)
        | parseNGates-rt (suc w) ops t = refl

------------------------------------------------------------------------
--  Section 6: assemble the complete netlist with its "#n=<n> o=<outId>\n" header.

--  Also store g in the header to provide parseNGates its structural
--  recursion count.
rHeader : ℕ → ℕ → ℕ → List Char → List Char
rHeader n g outId t =
  '#' ∷ 'n' ∷ '=' ∷ natToDigits n ++
  ' ' ∷ 'g' ∷ '=' ∷ natToDigits g ++
  ' ' ∷ 'o' ∷ '=' ∷ natToDigits outId ++ '\n' ∷ t

parseHeader : List Char → Maybe (ℕ × ℕ × ℕ × List Char)
parseHeader cs =
  match ('#' ∷ 'n' ∷ '=' ∷ []) cs >>= λ r0 →
  let (n , r1) = readNat r0 in
  match (' ' ∷ 'g' ∷ '=' ∷ []) r1 >>= λ r2 →
  let (g , r3) = readNat r2 in
  match (' ' ∷ 'o' ∷ '=' ∷ []) r3 >>= λ r4 →
  let (outId , r5) = readNat r4 in
  match ('\n' ∷ []) r5 >>= λ r6 →
  just (n , g , outId , r6)

parseHeader-rt : (n g outId : ℕ) (t : List Char)
               → parseHeader (rHeader n g outId t) ≡ just (n , g , outId , t)
parseHeader-rt n g outId t
  rewrite span-rt (proj₁ (toDigits 10 n)) ' ' ('g' ∷ '=' ∷ natToDigits g ++ ' ' ∷ 'o' ∷ '=' ∷ natToDigits outId ++ '\n' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 g)) ' ' ('o' ∷ '=' ∷ natToDigits outId ++ '\n' ∷ t) refl
        | span-rt (proj₁ (toDigits 10 outId)) '\n' t refl
        | proj₂ (toDigits 10 n) | proj₂ (toDigits 10 g) | proj₂ (toDigits 10 outId) = refl

------------------------------------------------------------------------
--  Section 7: combine the verified printer, parser, and round-trip proof.

renderL : ℕ → List Op → ℕ → List Char
renderL n ops outId = rHeader n (length ops) outId (rGateLines n ops [])

parseL : List Char → Maybe (ℕ × List Op × ℕ)
parseL cs =
  parseHeader cs >>= λ h →
  parseNGates (proj₁ (proj₂ h)) (proj₂ (proj₂ (proj₂ h))) >>= λ q →
  just (proj₁ h , proj₁ q , proj₁ (proj₂ (proj₂ h)))

--  Prove structural inversion: parsing recovers exactly the printed netlist.
roundtrip : (n : ℕ) (ops : List Op) (outId : ℕ)
          → parseL (renderL n ops outId) ≡ just (n , ops , outId)
roundtrip n ops outId
  rewrite parseHeader-rt n (length ops) outId (rGateLines n ops [])
        | parseNGates-rt n ops [] = refl

------------------------------------------------------------------------
--  Section 8: derive semantic correctness of the printed text.

evalParsed : Maybe (ℕ × List Op × ℕ) → List Bool → Bool
evalParsed (just (_ , ops , outId)) env = get (runNet env ops) outId
evalParsed nothing                  env = false

--  For every environment, evaluating parsed printed text gives the
--  original netlist denotation.
roundtrip-sem : (n : ℕ) (ops : List Op) (outId : ℕ) (env : List Bool)
              → evalParsed (parseL (renderL n ops outId)) env
                ≡ get (runNet env ops) outId
roundtrip-sem n ops outId env rewrite roundtrip n ops outId = refl

--  Specialise to the comparator built by Extraction.Netlist: parse
--  and evaluate the printed text to netEval, whose weight ≡ᵇ h specification
--  is proved by NetlistCorrect.netEval-correct.
netlist-text-correct :
  (N h : ℕ) →
  let (ops , outId) = popcountEqNet N h in
  (xs : Vec (Bool) N) →
  evalParsed (parseL (renderL N ops outId)) (toList xs) ≡ netEval N h xs
netlist-text-correct N h xs = roundtrip-sem N (proj₁ (popcountEqNet N h)) (proj₂ (popcountEqNet N h)) (toList xs)
