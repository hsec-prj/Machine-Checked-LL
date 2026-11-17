------------------------------------------------------------------------
--  Express point-DIP recovery and its resistance bound in one adversary
--  type. ExactResist quantifies over QAdversary (Vec Bool n) Bool
--  (Vec Bool n) q, with gen-ExactResist/gen-SAT-lb discharging the bound.
--  PointDIPAttack instead prunes a query List via survives ksec qs k;
--  dipAttack-recovers is a pair of Boolean equations, not Recovers.
--  Construct dipQA at budget 2 ^ n with probes = allVecsV n. Enumeration
--  length appears in the type. The decoder searches candidate keys and
--  chooses the first whose predicted outputs match the complete answers.
--  Predictions use the public key-parametric actGen f gS pointGadget k;
--  the secret is not an adversary parameter, and no secret-bearing
--  delivered netlist is supplied. decode-test-is-survives identifies
--  this Boolean test with the fold, and dipQA-recovers
--  states Recovers (dipQA f gS) (actGen f gS pointGadget), precisely the
--  form negated by the lower bound. TightQ combines universal failure
--  for 2 + q ≤ 2ⁿ (lo and quantitative lo-count) with a successful hi
--  at budget 2ⁿ and proof hi-ok. disjoint proves ¬ (2 + 2ⁿ ≤ 2ⁿ);
--  lo-range identifies the excluded budgets as q ≤ 2ⁿ − 2. Thus the
--  winning budget in this record is 2ⁿ and its last excluded budget is
--  2ⁿ−2. Attack.ExactQuery separately proves the optimum at 2ⁿ−1;
--  the full-enumeration route here remains useful as a typed fold.
--  Scope: VerifiedFALL.fallPolyQA uses integer distNode answers and
--  does not inhabit this Boolean-oracle record. dipQA is non-adaptive;
--  ExactQueryAdaptive supplies the coercion and exact adaptive result.
--  Survivor uniqueness here relies on PointConc. Recovers requires one
--  fixed adversary to succeed for every secret. Only queries are counted:
--  the decoder's candidate scan has no certified time bound here.
--  Reuse survives, survives-ksec, survives-only-ksec, andMap, ∈-allVecs,
--  actGen/baseGen/pointGadget, gen-ExactResist, and gen-strong-ExactResist-∸.
--  New proofs concern allVecsV/toList-allVecsV, findFirst-unique,
--  survives-unique, and decode-test-is-survives. Add no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.TightQ where

open import Data.Nat using (ℕ; zero; suc; _+_; _∸_; _^_; _≤_; s≤s)
open import Data.Nat.Properties using (+-comm; m+n≤o⇒m≤o∸n; ≤-trans; n≮n; n≤1+n)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_; if_then_else_)
open import Data.Bool.Properties using (_≟_)
open import Data.List using (List; []; _∷_; _++_; map)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.List.Properties using (++-identityʳ)
open import Data.Product using (_×_; _,_; Σ-syntax)
open import Data.Empty using (⊥; ⊥-elim)
import Data.Vec as V
open V using (Vec)
open import Data.Vec.Properties using (toList-map; toList-++; ≡-dec)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)
open import Relation.Nullary using (¬_; yes; no)

open import SFLL.HD using (prot)
open import Util.Counting using (allVecs)
open import Locking.GenericLock using (ProtGadget; pointGadget)
open import Attack.Oracle using (QAdversary; ask; Recovers)
open import Attack.Tradeoff using (ExactResist)
open import Attack.GenericSAT
  using (actGen; baseGen; point-PointConc; gen-ExactResist)
open import Attack.StrongResist using (failCount; gen-strong-ExactResist-∸)
open import Attack.PointDIPAttack
  using (consist; survives; andMap; ∈-allVecs; survives-ksec; survives-only-ksec)

private
  variable
    n : ℕ
    A : Set

------------------------------------------------------------------------
--  §1 Enumerate all inputs in a Vec of length 2ⁿ. Util.Counting.allVecs
--  has a List length proved by a lemma, while QAdversary needs Vec _ q.
--  allVecsV carries the same enumeration at that index. The final ++ []
--  matches the reduction 2 ^ suc m = 2 ^ m + (2 ^ m + 0), making the
--  three-part length definitional without cast or subst.

allVecsV : (m : ℕ) → Vec (Vec Bool m) (2 ^ m)
allVecsV zero    = V.[] V.∷ V.[]
allVecsV (suc m) =
  V.map (false V.∷_) (allVecsV m) V.++ (V.map (true V.∷_) (allVecsV m) V.++ V.[])

--  Identify the enumeration with the fold's actual queries, establishing
--  a shared query set as well as its size.
toList-allVecsV : (m : ℕ) → V.toList (allVecsV m) ≡ allVecs m
toList-allVecsV zero = refl
toList-allVecsV (suc m) =
  trans (toList-++ (V.map (false V.∷_) (allVecsV m))
                   (V.map (true V.∷_) (allVecsV m) V.++ V.[]))
        (cong₂ _++_ lft rgt)
  where
    lft : V.toList (V.map (false V.∷_) (allVecsV m)) ≡ map (false V.∷_) (allVecs m)
    lft = trans (toList-map (false V.∷_) (allVecsV m))
                (cong (map (false V.∷_)) (toList-allVecsV m))
    rgt : V.toList (V.map (true V.∷_) (allVecsV m) V.++ V.[])
          ≡ map (true V.∷_) (allVecs m)
    rgt = trans (toList-++ (V.map (true V.∷_) (allVecsV m)) V.[])
                (trans (++-identityʳ (V.toList (V.map (true V.∷_) (allVecsV m))))
                       (trans (toList-map (true V.∷_) (allVecsV m))
                              (cong (map (true V.∷_)) (toList-allVecsV m))))

------------------------------------------------------------------------
--  §2 Give a secret-independent decoder test and identify it with the fold.
--  matchAns g qs ans checks g's predictions against ans at every query.
--  The decoder evaluates the public key-parametric family at a candidate;
--  ans contains activated-oracle responses, without a delivered secret file.

matchAns : (Vec Bool n → Bool) → List (Vec Bool n) → List Bool → Bool
matchAns g []       []       = true
matchAns g (x ∷ xs) (a ∷ as) = not (g x xor a) ∧ matchAns g xs as
matchAns g []       (_ ∷ _)  = false
matchAns g (_ ∷ _)  []       = false

--  For answers obtained by applying an oracle to these queries, the
--  test equals the pointwise-agreement conjunction andMap.
matchAns-map : (g h : Vec Bool n → Bool) (qs : List (Vec Bool n)) →
               matchAns g qs (map h qs) ≡ andMap (λ x → not (g x xor h x)) qs
matchAns-map g h []       = refl
matchAns-map g h (x ∷ xs) = cong (not (g x xor h x) ∧_) (matchAns-map g h xs)

andMap-cong : (g h : Vec Bool n → Bool) (qs : List (Vec Bool n)) →
              ((x : Vec Bool n) → g x ≡ h x) → andMap g qs ≡ andMap h qs
andMap-cong g h []       eq = refl
andMap-cong g h (x ∷ xs) eq = cong₂ _∧_ (eq x) (andMap-cong g h xs eq)

--  Cancel the common key-independent summand baseGen f gS x, reducing
--  point-family oracle comparison to point-indicator comparison.
xor-cancel₂ : (b p r : Bool) → (b xor p) xor (b xor r) ≡ p xor r
xor-cancel₂ false p     r     = refl
xor-cancel₂ true  true  true  = refl
xor-cancel₂ true  true  false = refl
xor-cancel₂ true  false true  = refl
xor-cancel₂ true  false false = refl

--  Identify oracle-answer agreement at one input with consist.
--  CorruptionTriangle.bridge-consist-iff gives this as two implications;
--  the Boolean equality here supports a decoder expressed with _∧_.
match-bit-is-consist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec x k : Vec Bool n) →
  not (actGen f gS pointGadget k x xor actGen f gS pointGadget ksec x)
    ≡ consist ksec x k
match-bit-is-consist f gS ksec x k =
  cong not (xor-cancel₂ (baseGen f gS x) (prot 0 k x) (prot 0 ksec x))

------------------------------------------------------------------------
--  §3 Search candidate keys for the first successful test.

findFirst : (A → Bool) → List A → A → A
findFirst p []       d = d
findFirst p (x ∷ xs) d = if p x then x else findFirst p xs d

--  If a occurs in the list and uniquely passes the test, return a
--  regardless of the fallback value.
findFirst-unique :
  (p : A → Bool) (xs : List A) (d a : A) →
  a ∈ xs → p a ≡ true → ((b : A) → p b ≡ true → b ≡ a) →
  findFirst p xs d ≡ a
findFirst-unique p (x ∷ xs) d a (here refl) pa uniq rewrite pa = refl
findFirst-unique p (x ∷ xs) d a (there mem) pa uniq with p x in eq
... | true  = uniq x eq
... | false = findFirst-unique p xs d a mem pa uniq

------------------------------------------------------------------------
--  §4 Convert the fold's two recovery equations into survivor uniqueness.
--  dipAttack-recovers preserves the secret and rejects every other key;
--  decidable Vec Bool n equality yields the converse needed by the search: 
--  any surviving candidate must be the secret.

true≢false : true ≡ false → ⊥
true≢false ()

survives-unique : (ksec b : Vec Bool n) →
                  survives ksec (allVecs n) b ≡ true → b ≡ ksec
survives-unique ksec b sv with ≡-dec _≟_ b ksec
... | yes b≡     = b≡
... | no  b≢ksec =
  ⊥-elim (true≢false (trans (sym sv) (survives-only-ksec ksec b b≢ksec)))

------------------------------------------------------------------------
--  §5 Construct the QAdversary with query budget 2 ^ n in its type.

qaTest : (f : Vec Bool n → Bool) (gS : ProtGadget n) →
         Vec Bool (2 ^ n) → Vec Bool n → Bool
qaTest {n} f gS ans k =
  matchAns (actGen f gS pointGadget k) (allVecs n) (V.toList ans)

dipQA : (f : Vec Bool n → Bool) (gS : ProtGadget n) →
        QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n)
dipQA {n} f gS = record
  { probes = allVecsV n
  ; decode = λ ans → findFirst (qaTest f gS ans) (allVecs n) (V.replicate n false)
  }

--  Its probes equal the fold's query list itself, beyond matching its length.
dipQA-probes-are-allVecs :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  V.toList (QAdversary.probes (dipQA f gS)) ≡ allVecs n
dipQA-probes-are-allVecs {n} f gS = toList-allVecsV n

------------------------------------------------------------------------
--  §6 Identify the decoder with the existing attack. On answers from the
--  activated oracle for ksec, testing candidate k equals survives ksec
--  (allVecs n) k. Thus dipQA presents the same pruning fold as a typed
--  adversary rather than defining an unrelated recovery procedure.

decode-test-is-survives :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (ksec k : Vec Bool n) →
  qaTest f gS (V.map (actGen f gS pointGadget ksec) (allVecsV n)) k
    ≡ survives ksec (allVecs n) k
decode-test-is-survives {n} f gS ksec k =
  trans (cong (matchAns (actGen f gS pointGadget k) (allVecs n)) ansEq)
        (trans (matchAns-map (actGen f gS pointGadget k)
                             (actGen f gS pointGadget ksec) (allVecs n))
               (andMap-cong (λ x → not (actGen f gS pointGadget k x
                                          xor actGen f gS pointGadget ksec x))
                            (λ x → consist ksec x k)
                            (allVecs n)
                            (λ x → match-bit-is-consist f gS ksec x k)))
  where
    ansEq : V.toList (V.map (actGen f gS pointGadget ksec) (allVecsV n))
            ≡ map (actGen f gS pointGadget ksec) (allVecs n)
    ansEq = trans (toList-map (actGen f gS pointGadget ksec) (allVecsV n))
                  (cong (map (actGen f gS pointGadget ksec)) (toList-allVecsV n))

------------------------------------------------------------------------
--  §7 Establish recovery in exactly the proposition negated by resistance.

dipQA-recovers :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  Recovers (dipQA f gS) (actGen f gS pointGadget)
dipQA-recovers {n} f gS ksec =
  findFirst-unique test (allVecs n) (V.replicate n false) ksec
                   (∈-allVecs ksec) hits uniq
  where
    test : Vec Bool n → Bool
    test = qaTest f gS (V.map (actGen f gS pointGadget ksec) (allVecsV n))

    hits : test ksec ≡ true
    hits = trans (decode-test-is-survives f gS ksec ksec) (survives-ksec ksec)

    uniq : (b : Vec Bool n) → test b ≡ true → b ≡ ksec
    uniq b tb =
      survives-unique ksec b (trans (sym (decode-test-is-survives f gS ksec b)) tb)

------------------------------------------------------------------------
--  §8 Package both results over QAdversary (Vec Bool n) Bool (Vec Bool n) _,
--  the actGen f gS pointGadget family, and Recovers. lo universally
--  quantifies and hi supplies an inhabitant; only their budgets differ.
--  lo-range and disjoint separate q ≤ 2ⁿ−2 from this record's q = 2ⁿ
--  winner. Attack.ExactQuery supplies the q = 2ⁿ−1 optimum.

--  Establish the shared budget arithmetic once.
budgets-disjoint : (m : ℕ) → ¬ (2 + 2 ^ m ≤ 2 ^ m)
budgets-disjoint m le = n≮n (2 ^ m) (≤-trans (s≤s (n≤1+n (2 ^ m))) le)

budget-range : (m r : ℕ) → 2 + r ≤ 2 ^ m → r ≤ 2 ^ m ∸ 2
budget-range m r le = m+n≤o⇒m≤o∸n r (subst (_≤ 2 ^ m) (+-comm 2 r) le)

record TightQ (f : Vec Bool n → Bool) (gS : ProtGadget n) : Set where
  field
    --  Lower bound: all adversaries in this type fail when the budget
    --  leaves a pair of keys unprobed.
    lo       : ∀ {r} (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
               2 + r ≤ 2 ^ n → ¬ Recovers Adv (actGen f gS pointGadget)
    --  Quantify failure on at least 2ⁿ − r − 1 of the 2ⁿ possible keys.
    lo-count : ∀ {r} (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
               2 ^ n ∸ suc r ≤ failCount (λ k → ask Adv (actGen f gS pointGadget k))
    --  Upper bound: provide an adversary of this type using exactly 2ⁿ queries.
    hi       : QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n)
    --  Prove recovery for every secret by that adversary.
    hi-ok    : Recovers hi (actGen f gS pointGadget)
    --  Exclude the winning budget from the lower-bound range, ensuring
    --  consistency and a bracket with no overlapping claims.
    disjoint : ¬ (2 + 2 ^ n ≤ 2 ^ n)
    --  Locate the final covered budget at 2ⁿ − 2.
    lo-range : ∀ {r} → 2 + r ≤ 2 ^ n → r ≤ 2 ^ n ∸ 2

point-TightQ : (f : Vec Bool n → Bool) (gS : ProtGadget n) → TightQ f gS
point-TightQ {n} f gS = record
  { lo       = gen-ExactResist f gS pointGadget point-PointConc
  ; lo-count = gen-strong-ExactResist-∸ f gS pointGadget point-PointConc
  ; hi       = dipQA f gS
  ; hi-ok    = dipQA-recovers f gS
  ; disjoint = budgets-disjoint n
  ; lo-range = λ {r} → budget-range n r
  }

--  Restate the record's content directly: universal impossibility
--  below the bound together with existence at the successful budget.
tight-Θ :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  (∀ {r} (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
     2 + r ≤ 2 ^ n → ¬ Recovers Adv (actGen f gS pointGadget))
  × (Σ[ Adv ∈ QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n) ]
       Recovers Adv (actGen f gS pointGadget))
tight-Θ f gS =
  gen-ExactResist f gS pointGadget point-PointConc ,
  dipQA f gS , dipQA-recovers f gS

------------------------------------------------------------------------
--  §9 Apply the defence to the attack itself. dipQA has exactly the
--  type quantified by gen-ExactResist, so this application type-checks
--  and requires the inequality violated by its 2ⁿ budget. The conclusion
--  of meet-consistency is arithmetic already proved in one line by
--  budgets-disjoint. Its significance is the derivation composing offence
--  and defence: both can hold because their budget ranges are disjoint.

lo-applies-to-hi :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  2 + 2 ^ n ≤ 2 ^ n → ¬ Recovers (dipQA f gS) (actGen f gS pointGadget)
lo-applies-to-hi f gS =
  gen-ExactResist f gS pointGadget point-PointConc (dipQA f gS)

meet-consistency : (f : Vec Bool n → Bool) (gS : ProtGadget n) →
                   ¬ (2 + 2 ^ n ≤ 2 ^ n)
meet-consistency f gS le = lo-applies-to-hi f gS le (dipQA-recovers f gS)

------------------------------------------------------------------------
--  §10 Check that the lower side is the existing ExactResist proposition,
--  without weakening it to accommodate the record.

lo-is-ExactResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  ExactResist (actGen f gS pointGadget)
lo-is-ExactResist f gS = TightQ.lo (point-TightQ f gS)

--  At n=4 this record excludes budgets at most 14 and supplies 16 queries;
--  Attack.ExactQuery's separate optimum is 15.
_ : 2 ^ 4 ∸ 2 ≡ 14
_ = refl

--  Check computational content at n = 1 with a trivial host and point
--  secret 1: dipQA returns 1 against the activated oracle by reduction.
--  dipQA-recovers therefore certifies an executing decoder rather than
--  a stuck expression.
private
  k₁ : Vec Bool 1
  k₁ = true V.∷ V.[]

  f₁ : Vec Bool 1 → Bool
  f₁ _ = false

  _ : ask (dipQA f₁ (pointGadget k₁))
          (actGen f₁ (pointGadget k₁) pointGadget k₁) ≡ k₁
  _ = refl
