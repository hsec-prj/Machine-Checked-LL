------------------------------------------------------------------------
--  The point family's exact uniform non-adaptive recovery budget is 2ⁿ−1.
--  dipQA⁻ has that QAdversary budget and recovers every key by
--  dipQA⁻-recovers. For minimality, gen-ExactResist universally excludes
--  budgets with 2+r ≤ 2ⁿ. budget-range⁻ rewrites r ≤ 2ⁿ−2 into that
--  condition, giving below-all for every smaller budget. below-max-fails
--  specialises to the greatest losing budget; adjacent identifies it as
--  the predecessor of 2ⁿ−1. No padding or budget-monotonicity theorem is
--  needed. TightQ separately retains the full-enumeration 2ⁿ-query route.
--  The oracle is baseGen f gS x xor prot 0 ksec x, differing from the
--  key-free base only at ksec. A wrong candidate k differs from it at
--  exactly two distinct inputs, k and ksec, through consist-kill and
--  consist-kill-sym. Pins requires the query list to meet each such pair.
--  Omitting at most one input still does so; omit one to obtain 2ⁿ−1
--  queries. survives-ksec-any preserves the secret under any query list
--  using consist-self, so the resulting unique survivor is returned by
--  first-match decoding. Define omitted=head and probesMinus=tail of
--  allVecsV; probes-cons reconstructs the full enumeration, avoiding
--  a removal function and additional membership bookkeeping.
--  Scope is the point family: point-PointConc supplies concentration for
--  uniqueness and the lower bound, with no claim for other gadget families.
--  This module uses non-adaptive QAdversary values. ExactQueryAdaptive
--  coerces this optimum to Adaptive and proves matching adaptive bounds.
--  The index counts oracle queries only. Decoding scans all 2ⁿ candidates
--  against 2ⁿ−1 answers, with no bound on that computation or time.
--  Recovers requires exact success for every secret, excluding removal,
--  bypass, approximation, structural netlist readers, and attacks allowed
--  to fail on some keys. At n=0, zero queries return the unique vector;
--  the 1≤n premise restricts below-all, below-max, and no-gap to the
--  nondegenerate lower-bound case. A fixed probe vector and decoder are
--  deterministic: no key distribution or adversary randomness is covered.
--  ProbQueryBound's uniform-key probability statement is separate. Here
--  actGen f gS pointGadget ksec returns one Bool. ExactQueryMulti proves
--  the same optimum for one protected output with key-independent companion
--  outputs, a hard instance at every positive width, not every vector lock.
--  The supplied f and gS describe the public key-parametric family used for
--  offline candidate evaluation. They do not grant a secret-bearing
--  delivered netlist for selecting probes. Only activated-oracle queries
--  count; the upper bound assumes these public parameters are available.
--  Reuse survives, andMap and its true/false lemmas, consist and its
--  self/kill lemmas, prot0-self, prot0-false, ∈-allVecs, actGen,
--  pointGadget, and gen-ExactResist. TightQ supplies allVecsV,
--  toList-allVecsV, matchAns, matchAns-map, andMap-cong,
--  match-bit-is-consist, findFirst, and findFirst-unique. No postulates
--  or holes are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.ExactQuery where

open import Data.Nat using (ℕ; suc; _+_; _∸_; _^_; _≤_; s≤s)
open import Data.Nat.Properties
  using (≤-trans; ≤-reflexive; +-monoʳ-≤; ^-monoʳ-≤; m+[n∸m]≡n; m^n>0)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_)
open import Data.Bool.Properties using (_≟_)
open import Data.List using (List; []; _∷_)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Empty using (⊥-elim)
import Data.Vec as V
open V using (Vec)
open import Data.Vec.Properties using (toList-map; ≡-dec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst; ≢-sym)
open import Relation.Nullary using (¬_; yes; no)

open import SFLL.HD using (prot)
open import Util.Counting using (allVecs)
open import Locking.GenericLock using (ProtGadget; pointGadget)
open import Attack.Oracle using (QAdversary; ask; Recovers)
open import Attack.GenericSAT using (actGen; point-PointConc; gen-ExactResist)
open import Security.AntiSat using (prot0-false)
open import Attack.PointDIPAttack
  using (consist; survives; andMap; andMap-true; andMap-false;
         consist-self; consist-kill; prot0-self; ∈-allVecs)
open import Attack.TightQ
  using (allVecsV; toList-allVecsV; matchAns; matchAns-map; andMap-cong;
         match-bit-is-consist; findFirst; findFirst-unique)

private
  variable
    n : ℕ
    A : Set

------------------------------------------------------------------------
--  Section 1: characterise sufficient query lists. Pins means each pair
--  of distinct inputs has at least one member queried, enough to eliminate
--  every wrong key while allowing one input to be omitted.

Pins : List (Vec Bool n) → Set
Pins {n} qs = (a b : Vec Bool n) → a ≢ b → (a ∈ qs) ⊎ (b ∈ qs)

--  The secret survives any list by consist-self, without completeness
--  or membership assumptions; dropping probes preserves this positive half.
survives-ksec-any : (ksec : Vec Bool n) (qs : List (Vec Bool n)) →
                    survives ksec qs ksec ≡ true
survives-ksec-any ksec qs =
  andMap-true (λ x → consist ksec x ksec) qs (consist-self ksec)

--  Mirror consist-kill at x=ksec, where the secret indicator is true and
--  the wrong candidate's false. Together they give the two inputs met by Pins.
consist-kill-sym : (ksec k : Vec Bool n) → k ≢ ksec →
                   consist ksec ksec k ≡ false
consist-kill-sym ksec k k≢ksec =
  cong not (cong₂ _xor_ (prot0-false ksec k (≢-sym k≢ksec)) (prot0-self ksec))

--  Prove that a pinning list eliminates every wrong candidate.
survives-kill-pins : (qs : List (Vec Bool n)) → Pins qs →
                     (ksec k : Vec Bool n) → k ≢ ksec →
                     survives ksec qs k ≡ false
survives-kill-pins qs pins ksec k k≢ksec with pins k ksec k≢ksec
... | inj₁ k∈qs    = andMap-false (λ x → consist ksec x k) qs k
                                  k∈qs (consist-kill ksec k k≢ksec)
... | inj₂ ksec∈qs = andMap-false (λ x → consist ksec x k) qs ksec
                                  ksec∈qs (consist-kill-sym ksec k k≢ksec)

------------------------------------------------------------------------
--  Section 2: take head as omitted and tail as probesMinus from allVecsV,
--  reindexed once by 2^≡suc. Dropping the first input gives typed length
--  2ⁿ−1 without defining removal.

--  Use stdlib m^n>0 with base 2 for positivity, and m+[n∸m]≡n at m=1
--  for x ≡ suc (x ∸ 1), since 1+y reduces to suc y.
2^≡suc : (m : ℕ) → 2 ^ m ≡ suc (2 ^ m ∸ 1)
2^≡suc m = sym (m+[n∸m]≡n (m^n>0 2 m))

allVecsSuc : (m : ℕ) → Vec (Vec Bool m) (suc (2 ^ m ∸ 1))
allVecsSuc m = subst (Vec (Vec Bool m)) (2^≡suc m) (allVecsV m)

--  Name the sole input absent from the optimal probe vector.
omitted : (m : ℕ) → Vec Bool m
omitted m = V.head (allVecsSuc m)

--  Retain all remaining inputs at budget 2ⁿ−1.
probesMinus : (m : ℕ) → Vec (Vec Bool m) (2 ^ m ∸ 1)
probesMinus m = V.tail (allVecsSuc m)

--  Use ordinary J, valid with --without-K.
toList-subst : {a b : ℕ} (eq : a ≡ b) (xs : Vec A a) →
               V.toList (subst (Vec A) eq xs) ≡ V.toList xs
toList-subst refl xs = refl

head∷tail : {m : ℕ} (xs : Vec A (suc m)) → V.head xs V.∷ V.tail xs ≡ xs
head∷tail (x V.∷ xs) = refl

--  Prepending the omitted input reconstructs the entire fold-attack
--  enumeration, so exactly one input has been removed.
probes-cons : (m : ℕ) →
              omitted m ∷ V.toList (probesMinus m) ≡ allVecs m
probes-cons m =
  trans (cong V.toList (head∷tail (allVecsSuc m)))
        (trans (toList-subst (2^≡suc m) (allVecsV m)) (toList-allVecsV m))

--  Every input different from omitted still occurs among the probes.
mem-tail : (m : ℕ) (v : Vec Bool m) → v ≢ omitted m →
           v ∈ V.toList (probesMinus m)
mem-tail m v v≢om with subst (v ∈_) (sym (probes-cons m)) (∈-allVecs v)
... | here  v≡om = ⊥-elim (v≢om v≡om)
... | there mem  = mem

--  Prove Pins because two distinct inputs cannot both be the omitted one.
probesMinus-Pins : (m : ℕ) → Pins (V.toList (probesMinus m))
probesMinus-Pins m a b a≢b with ≡-dec _≟_ a (omitted m)
... | no  a≢om = inj₁ (mem-tail m a a≢om)
... | yes a≡om = inj₂ (mem-tail m b (λ b≡om → a≢b (trans a≡om (sym b≡om))))

------------------------------------------------------------------------
--  Section 3: generalise TightQ.decode-test-is-survives from allVecsV to
--  arbitrary probe vectors using the same three-step proof. Leave the
--  existing specialised theorem intact and use the general one for reduced probes.

decode-test-gen :
  {q : ℕ} (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (ps : Vec (Vec Bool n) q) (ksec k : Vec Bool n) →
  matchAns (actGen f gS pointGadget k) (V.toList ps)
           (V.toList (V.map (actGen f gS pointGadget ksec) ps))
    ≡ survives ksec (V.toList ps) k
decode-test-gen f gS ps ksec k =
  trans (cong (matchAns (actGen f gS pointGadget k) (V.toList ps))
              (toList-map (actGen f gS pointGadget ksec) ps))
        (trans (matchAns-map (actGen f gS pointGadget k)
                             (actGen f gS pointGadget ksec) (V.toList ps))
               (andMap-cong (λ x → not (actGen f gS pointGadget k x
                                          xor actGen f gS pointGadget ksec x))
                            (λ x → consist ksec x k)
                            (V.toList ps)
                            (λ x → match-bit-is-consist f gS ksec x k)))

qaTest⁻ : (f : Vec Bool n → Bool) (gS : ProtGadget n) →
          Vec Bool (2 ^ n ∸ 1) → Vec Bool n → Bool
qaTest⁻ {n} f gS ans k =
  matchAns (actGen f gS pointGadget k) (V.toList (probesMinus n)) (V.toList ans)

--  Define the optimal adversary with budget 2ⁿ−1 in its type. Its decoder
--  still scans all 2ⁿ keys, work outside the oracle-query count.
dipQA⁻ : (f : Vec Bool n → Bool) (gS : ProtGadget n) →
         QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n ∸ 1)
dipQA⁻ {n} f gS = record
  { probes = probesMinus n
  ; decode = λ ans → findFirst (qaTest⁻ f gS ans) (allVecs n) (omitted n)
  }

--  Prove uniqueness on the reduced list using survives-kill-pins instead
--  of survives-only-ksec; TightQ's full-enumeration uniqueness does not apply.
survives-unique⁻ : (ksec b : Vec Bool n) →
                   survives ksec (V.toList (probesMinus n)) b ≡ true →
                   b ≡ ksec
survives-unique⁻ {n} ksec b sv with ≡-dec _≟_ b ksec
... | yes b≡     = b≡
... | no  b≢ksec with trans (sym sv)
                            (survives-kill-pins (V.toList (probesMinus n))
                                                (probesMinus-Pins n)
                                                ksec b b≢ksec)
...                 | ()

--  Establish recovery at 2ⁿ−1 in the precise form negated by the lower bound.
dipQA⁻-recovers :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  Recovers (dipQA⁻ f gS) (actGen f gS pointGadget)
dipQA⁻-recovers {n} f gS ksec =
  findFirst-unique test (allVecs n) (omitted n) ksec
                   (∈-allVecs ksec) hits uniq
  where
    test : Vec Bool n → Bool
    test = qaTest⁻ f gS (V.map (actGen f gS pointGadget ksec) (probesMinus n))

    test-is-survives : (k : Vec Bool n) →
                       test k ≡ survives ksec (V.toList (probesMinus n)) k
    test-is-survives = decode-test-gen f gS (probesMinus n) ksec

    hits : test ksec ≡ true
    hits = trans (test-is-survives ksec)
                 (survives-ksec-any ksec (V.toList (probesMinus n)))

    uniq : (b : Vec Bool n) → test b ≡ true → b ≡ ksec
    uniq b tb = survives-unique⁻ ksec b (trans (sym (test-is-survives b)) tb)

------------------------------------------------------------------------
--  Section 4: show the immediately smaller budget already fails.

--  Apply stdlib exponent monotonicity at base 2 and exponent 1, giving 2.
2≤2^ : (m : ℕ) → 1 ≤ m → 2 ≤ 2 ^ m
2≤2^ m 1≤m = ^-monoʳ-≤ 2 1≤m

budget-max : (m : ℕ) → 1 ≤ m → 2 + (2 ^ m ∸ 2) ≤ 2 ^ m
budget-max m 1≤m = ≤-reflexive (m+[n∸m]≡n (2≤2^ m 1≤m))

--  Prove the converse budget-range arithmetic equating r ≤ 2ⁿ−2 with
--  2+r ≤ 2ⁿ. This connects universal gen-ExactResist to below-all without
--  padding adversaries to larger budgets.
budget-range⁻ : (m r : ℕ) → 1 ≤ m → r ≤ 2 ^ m ∸ 2 → 2 + r ≤ 2 ^ m
budget-range⁻ m r 1≤m r≤max = ≤-trans (+-monoʳ-≤ 2 r≤max) (budget-max m 1≤m)

--  Read the existing lower bound at its largest covered budget.
below-max-fails :
  1 ≤ n → (f : Vec Bool n → Bool) (gS : ProtGadget n)
  (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n ∸ 2)) →
  ¬ Recovers Adv (actGen f gS pointGadget)
below-max-fails {n} 1≤n f gS Adv =
  gen-ExactResist f gS pointGadget point-PointConc Adv (budget-max n 1≤n)

x∸1≡suc[x∸2] : (x : ℕ) → 2 ≤ x → x ∸ 1 ≡ suc (x ∸ 2)
x∸1≡suc[x∸2] (suc (suc t)) (s≤s (s≤s _)) = refl

--  Identify the winning and greatest losing budgets as adjacent integers.
adjacent : (m : ℕ) → 1 ≤ m → 2 ^ m ∸ 1 ≡ suc (2 ^ m ∸ 2)
adjacent m 1≤m = x∸1≡suc[x∸2] (2 ^ m) (2≤2^ m 1≤m)

------------------------------------------------------------------------
--  Section 5: package exact complexity over one adversary type. below is
--  ExactResist; opt and opt-ok give the winning adversary.
--  below-all supplies minimality by universally reindexing below through
--  budget-range⁻. below-max is only its top-budget instance and no-gap
--  only arithmetic. The latter identifies the covered range with all
--  r < 2ⁿ−1 through 2ⁿ−1=suc(2ⁿ−2). No budget-monotonicity principle is
--  proved or used: universal failure below plus the winner establishes
--  the least sufficient budget.

record ExactQuery {n : ℕ} (f : Vec Bool n → Bool) (gS : ProtGadget n) : Set where
  field
    --  Upper bound: supply a concrete adversary at 2ⁿ−1 queries.
    opt        : QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n ∸ 1)
    --  Prove that it recovers every secret.
    opt-ok     : Recovers opt (actGen f gS pointGadget)
    --  Retain the main track's lower bound unchanged.
    below      : ∀ {r} (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
                 2 + r ≤ 2 ^ n → ¬ Recovers Adv (actGen f gS pointGadget)
    --  Express minimality as failure of every budget strictly below 2ⁿ−1.
    below-all  : 1 ≤ n → ∀ {r} (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
                 r ≤ 2 ^ n ∸ 2 → ¬ Recovers Adv (actGen f gS pointGadget)
    --  Specialise failure to one query below the winning budget.
    below-max  : 1 ≤ n → (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n ∸ 2)) →
                 ¬ Recovers Adv (actGen f gS pointGadget)
    --  Prove this is the immediate predecessor, leaving no uncovered budget.
    no-gap     : 1 ≤ n → 2 ^ n ∸ 1 ≡ suc (2 ^ n ∸ 2)

point-ExactQuery : (f : Vec Bool n → Bool) (gS : ProtGadget n) → ExactQuery f gS
point-ExactQuery {n} f gS = record
  { opt       = dipQA⁻ f gS
  ; opt-ok    = dipQA⁻-recovers f gS
  ; below     = lower
  ; below-all = λ 1≤n {r} Adv r≤max → lower Adv (budget-range⁻ n r 1≤n r≤max)
  ; below-max = λ 1≤n Adv → below-max-fails 1≤n f gS Adv
  ; no-gap    = λ 1≤n → adjacent n 1≤n
  }
  where
    --  Use one lower bound, already universal in budgets, for all three lower
    --  fields; budget-range⁻ arithmetic suffices without padding.
    lower : ∀ {r} (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
            2 + r ≤ 2 ^ n → ¬ Recovers Adv (actGen f gS pointGadget)
    lower = gen-ExactResist f gS pointGadget point-PointConc

------------------------------------------------------------------------
--  Section 6: check concrete boundary instances.

--  At n=4, the optimal budget is 15; TightQ separately records the
--  lower-bound endpoint 14 and its full-enumeration 16-query attack.
_ : 2 ^ 4 ∸ 1 ≡ 15
_ = refl

_ : 2 ^ 4 ∸ 2 ≡ 14
_ = refl

--  Demonstrate computation at n=1: with trivial host and secret 1, dipQA⁻
--  asks one query, 2¹−1=1, and returns 1 by reduction.
private
  k₁ : Vec Bool 1
  k₁ = true V.∷ V.[]

  f₁ : Vec Bool 1 → Bool
  f₁ _ = false

  _ : ask (dipQA⁻ f₁ (pointGadget k₁))
          (actGen f₁ (pointGadget k₁) pointGadget k₁) ≡ k₁
  _ = refl
