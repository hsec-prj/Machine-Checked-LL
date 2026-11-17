------------------------------------------------------------------------
--  Establish exact total-recovery complexity 2ⁿ−1 at every positive output
--  width for the one-protected-output family. ExactQuery supplies the
--  single-output winner dipQA⁻ and failure at every smaller budget.
--  Here the same budget holds for
--  actGenV aux f gS G k x = actGen f gS G k x ∷ aux x.
--  The m companion outputs aux : Vec Bool n → Vec Bool m are arbitrary
--  input functions, not necessarily constants or zero padding, but cannot
--  depend on k. This models one protected output in a genuine wider host.
--  The adversary knows aux and its chosen x, so it can compute every
--  companion bit itself. OraclePostProcess.reflectQA moves
--  φ x b=b ∷ aux x into decoding without changing probes or q. A wide
--  winner would become a single-bit winner, excluded by gen-ExactResist
--  in genV-ExactResist. Conversely reflect dipQA⁻ through φ x y=head y
--  to obtain dipQAV and dipQAV-recovers, ignoring aux at budget 2ⁿ−1.
--  No bound contains m; ExactQueryV reproduces the single-output result
--  at suc m. belowV-all derives minimality from already-universal belowV
--  using budget-range⁻, excluding all r ≤ 2ⁿ−2. It does not infer
--  minimality from one failed budget; no padding or budget-monotonicity
--  principle is proved or used.
--  Scope is worst-case existence: each width 1+m has this hard family,
--  not every lock of that width. Key-dependent companion outputs can leak
--  the secret in one query; leak-recovers and leak-refutes-general prove
--  the necessity of independence, contradicting the generalised lower
--  bound for n≥2 by budget1-usable. PointConc and pointGadget restrict
--  the result to point families. Only deterministic non-adaptive
--  QAdversary values are covered; OraclePostProcess does not transfer
--  Adaptive results. The type counts queries only, not the decoder's
--  2ⁿ-candidate scan or per-probe post-processing. Recovers demands the
--  right key for every secret, excluding removal, bypass, approximation,
--  netlist-reading adversaries, and allowed failures. Section 4 counts
--  worst-case failed keys, not probability; no key or coin distribution
--  appears. Public f, gS, and aux permit offline candidate evaluation;
--  no secret-bearing delivered netlist is supplied for probe selection.
--  Only activated-oracle queries count.
--  At n=0 the sole key needs zero queries; 1≤n excludes it from
--  belowV-all. All key dependence in actGenV is at output zero, so this
--  does not address locks with key dependence spread among outputs. For
--  that Distinguishing regime, multiDIP-recovers gives an upper bound 2ⁿ
--  but no lower bound here; withAux's single-bit reflection requires
--  key-independent companions. Output width is suc m≥1 throughout.
--  At width zero all answers are the empty vector, and for n≥1 no budget
--  can recover the key, so there is no corresponding upper-bound case.
--  No postulates or holes are introduced.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.ExactQueryMulti where

open import Data.Nat using (ℕ; suc; zero; _+_; _∸_; _^_; _≤_; z≤n; s≤s)
open import Data.Nat.Properties using (≤-refl; ≤-trans; ^-monoʳ-≤; m≤n+o⇒m∸n≤o)
open import Data.Bool using (Bool; true; false; not)
import Data.Vec as V
open V using (Vec; []; _∷_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; subst)
open import Relation.Nullary using (¬_)

open import Util.BoolVec using (eqVec)
open import Util.Counting using (allVecs; countT-cong)
open import Locking.GenericLock using (ProtGadget; pointGadget)
open import Attack.Oracle using (QAdversary; ask; Recovers)
open import Attack.GenericSAT using (actGen; PointConc; point-PointConc; gen-ExactResist)

open import Attack.StrongResist using (failCount; gen-strong-ExactResist)
open import Attack.ExactQuery
  using (dipQA⁻; dipQA⁻-recovers; budget-range⁻; adjacent)
open import Attack.OraclePostProcess
  using (reflectQA; reflect-ask; reflect-Recovers)

------------------------------------------------------------------------
--  Section 1: define the vector instance and its two related post-processings.

--  Parameterise the hard family by arbitrary key-independent aux outputs
--  accompanying one protected bit.
actGenV : {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
          (f : Vec Bool n → Bool) (gS : ProtGadget n)
          (G : Vec Bool n → ProtGadget n) →
          Vec Bool n → Vec Bool n → Vec Bool (suc m)
actGenV aux f gS G k x = actGen f gS G k x ∷ aux x

--  Build a wide answer from a narrow bit using aux x. This input dependence
--  is why OraclePostProcess indexes φ by x.
withAux : {n m : ℕ} (aux : Vec Bool n → Vec Bool m) →
          Vec Bool n → Bool → Vec Bool (suc m)
withAux aux x b = b ∷ aux x

--  Project back to the first bit, without using the input.
firstOut : {n m : ℕ} → Vec Bool n → Vec Bool (suc m) → Bool
firstOut _ y = V.head y

------------------------------------------------------------------------
--  Section 2: reflect any q-query wide adversary to prove the lower bound.
--  The condition 2+q ≤ 2ⁿ contains no m, because companion outputs are
--  freely computable from x.

genV-ExactResist :
  {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G →
  ∀ {q} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) q) →
  2 + q ≤ 2 ^ n → ¬ Recovers Adv (actGenV aux f gS G)
genV-ExactResist aux f gS G pc Adv bound rec =
  gen-ExactResist f gS G pc (reflectQA (withAux aux) Adv) bound
    (reflect-Recovers (withAux aux) (actGen f gS G) Adv rec)

------------------------------------------------------------------------
--  Section 3: reflect the optimal dipQA⁻ along firstOut, preserving its
--  2ⁿ−1 probes and ignoring companion bits. Name the standalone adversary
--  dipQAV following dipQA⁻: optV belongs to the ExactQueryV field in the
--  same module scope and cannot also name this function. aux is deliberately
--  unused in the body, serving only to fix implicit m and align signatures
--  with dipQAV-recovers and actGenV, which do use it. Removing it would
--  shift width inference to the expected type and obscure alignment with
--  the lower-bound instance.

dipQAV : {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
         (f : Vec Bool n → Bool) (gS : ProtGadget n) →
         QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) (2 ^ n ∸ 1)
dipQAV aux f gS = reflectQA firstOut (dipQA⁻ f gS)

--  firstOut applied to actGenV reduces definitionally to actGen by
--  head-of-cons, so dipQA⁻'s own recovery theorem applies without a bridge.
dipQAV-recovers : {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
                  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
                  Recovers (dipQAV aux f gS) (actGenV aux f gS pointGadget)
dipQAV-recovers aux f gS =
  reflect-Recovers firstOut (actGenV aux f gS pointGadget) (dipQA⁻ f gS)
                   (dipQA⁻-recovers f gS)

------------------------------------------------------------------------
--  Section 4: lift gen-strong-ExactResist's count of at least 2ⁿ−q−1
--  incorrectly decoded keys. reflect-ask equates decoders pointwise,
--  preserving the count literally by congruence.

--  Use countT-cong for failure counts. failsAt applies not ∘ eqVec to
--  the decoded key, so pointwise decoder equality needs only one cong.
failCount-cong : {n : ℕ} (g h : Vec Bool n → Vec Bool n) →
                 ((k : Vec Bool n) → g k ≡ h k) → failCount g ≡ failCount h
failCount-cong {n} g h eq =
  countT-cong (λ k → cong (λ v → not (eqVec v k)) (eq k)) (allVecs n)

--  At width 1+m, state the missed-key bound additively as in
--  gen-strong-ExactResist.
genV-strong-ExactResist :
  {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G →
  ∀ {q} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) q) →
  2 ^ n ≤ suc q + failCount (λ k → ask Adv (actGenV aux f gS G k))
genV-strong-ExactResist {n} aux f gS G pc {q} Adv =
  subst (λ t → 2 ^ n ≤ suc q + t) transfer
        (gen-strong-ExactResist f gS G pc (reflectQA (withAux aux) Adv))
  where
    transfer : failCount (λ k → ask (reflectQA (withAux aux) Adv)
                                    (actGen f gS G k))
                 ≡ failCount (λ k → ask Adv (actGenV aux f gS G k))
    transfer = failCount-cong _ _
                 (λ k → reflect-ask (withAux aux) (actGen f gS G k) Adv)

--  Also give the weaker subtractive reading quoted in prose. Once
--  2ⁿ ≤ suc q, in particular q≥2ⁿ, truncation reduces its left side to
--  zero and yields only 0≤_. The additive form instead retains suc q
--  on the right without truncation and is the primary statement.
genV-strong-ExactResist-∸ :
  {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConc G →
  ∀ {q} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) q) →
  2 ^ n ∸ suc q ≤ failCount (λ k → ask Adv (actGenV aux f gS G k))
genV-strong-ExactResist-∸ {n} aux f gS G pc {q} Adv =
  m≤n+o⇒m∸n≤o (2 ^ n) (suc q)
              (genV-strong-ExactResist aux f gS G pc Adv)

------------------------------------------------------------------------
--  Section 5: make key independence essential by replacing aux with the
--  secret itself in actLeak. One query recovers for any host, gadget,
--  and probe. For n≥2, budget1-usable places one query within the forbidden
--  range. leak-refutes-general explicitly negates the unrestricted bound,
--  showing hardness belongs to the instance rather than output width.

actLeak : {n : ℕ} (f : Vec Bool n → Bool) (gS : ProtGadget n)
          (G : Vec Bool n → ProtGadget n) →
          Vec Bool n → Vec Bool n → Vec Bool (suc n)
actLeak f gS G k x = actGen f gS G k x ∷ k

leakQA : {n : ℕ} → Vec Bool n →
         QAdversary (Vec Bool n) (Vec Bool (suc n)) (Vec Bool n) 1
leakQA x₀ = record
  { probes = x₀ ∷ []
  ; decode = λ ans → V.tail (V.head ans)
  }

leak-recovers : {n : ℕ} (f : Vec Bool n → Bool) (gS : ProtGadget n)
                (G : Vec Bool n → ProtGadget n) (x₀ : Vec Bool n) →
                Recovers (leakQA x₀) (actLeak f gS G)
leak-recovers f gS G x₀ k = refl

--  For n≥2, show budget one is within the lower bound's covered range.
budget1-usable : (n : ℕ) → 2 ≤ n → 2 + 1 ≤ 2 ^ n
budget1-usable n 2≤n =
  ≤-trans (s≤s (s≤s (s≤s z≤n))) (^-monoʳ-≤ 2 2≤n)

--  Refute the lower bound without key-independent aux inside the type
--  checker, rather than juxtaposing incompatible statements. Use the
--  trivial host, point gadget at zeros, leaking actLeak companions, and
--  leakQA with one query. budget1-usable makes this a contradiction for
--  2≤n. That premise matters: for n≤1, 2+1 ≤ 2^1 fails, so this witness
--  lies outside the bound and gives no contradiction there. This follows
--  the explicit-refutation style of NonDegenerate.null-¬NonVacuous.
leak-refutes-general :
  (n : ℕ) → 2 ≤ n →
  ¬ (∀ (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
       PointConc G →
       ∀ {q} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc n)) (Vec Bool n) q) →
       2 + q ≤ 2 ^ n → ¬ Recovers Adv (actLeak f gS G))
leak-refutes-general n 2≤n claim =
  claim f₀ (pointGadget k₀) pointGadget point-PointConc
        (leakQA k₀) (budget1-usable n 2≤n)
        (leak-recovers f₀ (pointGadget k₀) pointGadget k₀)
  where
    k₀ : Vec Bool n
    k₀ = V.replicate n false

    f₀ : Vec Bool n → Bool
    f₀ _ = false

------------------------------------------------------------------------
--  Section 6: package six fields at width suc m corresponding to
--  ExactQuery: optV/optV-ok, belowV, belowV-all, below-maxV, and no-gapV.
--  Replace Bool by Vec Bool (suc m) in the four answer-type-dependent
--  fields; retain the same 2ⁿ−1 budget and r≤2ⁿ−2 range. no-gapV is
--  literally adjacent arithmetic, independent of m. belowV-all derives
--  minimality from universal belowV through budget-range⁻, without
--  padding; below-maxV merely specialises its top endpoint. no-gapV
--  identifies that range with every r<2ⁿ−1 through predecessor equality.
--  Together the winner and universal failure below establish the least
--  sufficient budget, leaving no intervening query count.

record ExactQueryV {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
                   (f : Vec Bool n → Bool) (gS : ProtGadget n) : Set where
  field
    --  Upper bound: provide a concrete 2ⁿ−1-query adversary at width suc m.
    optV       : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) (2 ^ n ∸ 1)
    --  Certify recovery for every secret.
    optV-ok    : Recovers optV (actGenV aux f gS pointGadget)
    --  Exclude budgets leaving room for two unprobed keys.
    belowV     : ∀ {r} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) r) →
                 2 + r ≤ 2 ^ n → ¬ Recovers Adv (actGenV aux f gS pointGadget)
    --  Express minimality as failure at every budget below 2ⁿ−1.
    belowV-all : 1 ≤ n → ∀ {r} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) r) →
                 r ≤ 2 ^ n ∸ 2 → ¬ Recovers Adv (actGenV aux f gS pointGadget)
    --  Specialise failure to the greatest covered budget, one query fewer.
    below-maxV : 1 ≤ n → (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) (2 ^ n ∸ 2)) →
                 ¬ Recovers Adv (actGenV aux f gS pointGadget)
    --  Identify that predecessor with the range r≤2ⁿ−2 iff r<2ⁿ−1. This
    --  arithmetic is m-independent and the same as ExactQuery.no-gap.
    no-gapV    : 1 ≤ n → 2 ^ n ∸ 1 ≡ suc (2 ^ n ∸ 2)

point-ExactQueryV : {n m : ℕ} (aux : Vec Bool n → Vec Bool m)
                    (f : Vec Bool n → Bool) (gS : ProtGadget n) →
                    ExactQueryV aux f gS
point-ExactQueryV {n} {m} aux f gS = record
  { optV       = dipQAV aux f gS
  ; optV-ok    = dipQAV-recovers aux f gS
  ; belowV     = lower
  ; belowV-all = lowerAll
  ; below-maxV = λ 1≤n Adv → lowerAll 1≤n Adv ≤-refl
  ; no-gapV    = λ 1≤n → adjacent n 1≤n
  }
  where
    lower : ∀ {r} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) r) →
            2 + r ≤ 2 ^ n → ¬ Recovers Adv (actGenV aux f gS pointGadget)
    lower = genV-ExactResist aux f gS pointGadget point-PointConc

    --  Since lower already quantifies over r, budget-range⁻ excludes the
    --  whole range at once. Obtain below-maxV at r=2ⁿ−2 using ≤-refl.
    lowerAll : 1 ≤ n → ∀ {r} (Adv : QAdversary (Vec Bool n) (Vec Bool (suc m)) (Vec Bool n) r) →
               r ≤ 2 ^ n ∸ 2 → ¬ Recovers Adv (actGenV aux f gS pointGadget)
    lowerAll 1≤n {r} Adv r≤max = lower Adv (budget-range⁻ n r 1≤n r≤max)

------------------------------------------------------------------------
--  Section 7: verify concrete instances.

--  Check the single-output budget remains unchanged for every m.
_ : 2 ^ 4 ∸ 1 ≡ 15
_ = refl

_ : 2 ^ 4 ∸ 2 ≡ 14
_ = refl

--  Demonstrate computation at n=1,m=1 with a trivial host, nonconstant
--  companion, and secret 1: dipQAV queries a two-bit oracle once and
--  reduces to 1.
private
  k₁ : Vec Bool 1
  k₁ = true ∷ []

  f₁ : Vec Bool 1 → Bool
  f₁ _ = false

  --  Choose the input bit itself as the nonconstant companion.
  aux₁ : Vec Bool 1 → Vec Bool 1
  aux₁ x = x

  _ : ask (dipQAV aux₁ f₁ (pointGadget k₁))
          (actGenV aux₁ f₁ (pointGadget k₁) pointGadget k₁) ≡ k₁
  _ = refl

  --  At this size, also demonstrate one-query recovery from section 5's leaking oracle.
  _ : ask (leakQA k₁) (actLeak f₁ (pointGadget k₁) pointGadget k₁) ≡ k₁
  _ = refl
