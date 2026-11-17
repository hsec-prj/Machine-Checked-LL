------------------------------------------------------------------------
--  Strengthen point concentration with non-degeneracy. GenericSAT's
--  PointConc G = (k x) → x ≢ k → pred (G k) x ≡ false requires vanishing
--  off the key but not firing at it. An everywhere-false family therefore
--  satisfies PointConc and gen-ExactResist while its locked function equals
--  the key-free base for every key. null-PointConc, null-ExactResist, and
--  null-lock-vacuous exhibit this distinction. PointConcND combines
--  PointConc with NonDeg; conc projects the weaker premise. The stronger
--  premise gives additional facts:
--  nd-oracle-injective distinguishes keys through their oracles;
--  nd-ocr-exactly-2 attains point-ocr-≤2 at every distinct pair, unlike
--  null-ocr-0; NonVacuousResist combines resistance with these properties,
--  and null-¬NonVacuous rejects the degenerate family. Real point gadgets
--  satisfy NonDeg by prot0-self, and flex singletons by the same fact under
--  OR false. This strengthens what the premise excludes, not the
--  resistance conclusion itself. No converse from corruption two to point
--  concentration is claimed. Exact corruption concerns gadget-predicate
--  symmetric difference, not circuit cost. There are no postulates or holes.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.NonDegenerate where

open import Data.Nat using (ℕ; suc; _+_; _≤_)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; _xor_)
open import Data.Bool.Properties using (xor-identityʳ)
open import Data.Vec using (Vec; []; _∷_; replicate)
open import Data.List using (List; [])
open import Data.Empty using (⊥; ⊥-elim)
open import Data.Product using (_×_; _,_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; _≢_)
open import Relation.Nullary using (¬_)

open import SFLL.HD using (prot)
open import Util.BoolVec using (eqVec; eqVec-false→≢; eqVec-sound)
open import Util.Counting
  using (countT; allVecs; countT-cong; countT-≡0; countT-xor-disjoint)
open import Attack.SARLockQueryBound using (count-eq)

open import Attack.PointDIPAttack using (prot0-self)
open import Attack.Tradeoff using (ExactResist)
open import Attack.GenericSAT
  using (actGen; baseGen; PointConc; gen-ExactResist;
         point-PointConc; flexSingleton; flex-PointConc)
open import Locking.GenericLock
  using (ProtGadget; pointGadget; flexGadget; ocrGen-of)
open ProtGadget using (pred)

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  Combine the on-key condition with point concentration.

--  Require an applied-key predicate to hold at its own key.
NonDeg : (Vec Bool n → ProtGadget n) → Set
NonDeg {n} G = (k : Vec Bool n) → pred (G k) k ≡ true

--  Combine off-key falsehood with on-key truth in PointConcND.
record PointConcND {n : ℕ} (G : Vec Bool n → ProtGadget n) : Set where
  field
    conc  : PointConc G
    fires : NonDeg G
open PointConcND public

------------------------------------------------------------------------
--  Use prot0-self for pointGadget and the same predicate OR empty-set false
--  for flexSingleton to establish the real instances.

point-PointConcND : PointConcND {n} pointGadget
point-PointConcND = record { conc = point-PointConc ; fires = prot0-self }

flex-PointConcND : PointConcND {n} flexSingleton
flex-PointConcND = record
  { conc  = flex-PointConc
  ; fires = λ k → cong (_∨ false) (prot0-self k)
  }

------------------------------------------------------------------------
--  Exhibit the degenerate family by choosing flexGadget [] at every key.
--  Its always-false predicate satisfies PointConc and all derived resistance
--  results while protecting nothing.

nullFamily : Vec Bool n → ProtGadget n
nullFamily _ = flexGadget []

--  Prove concentration without even using the x ≢ k premise.
null-PointConc : PointConc {n} nullFamily
null-PointConc k x _ = refl

--  Apply the unchanged existing resistance theorem to this family.
null-ExactResist : (f : Vec Bool n → Bool) (gS : ProtGadget n) →
                   ExactResist (actGen f gS nullFamily)
null-ExactResist f gS = gen-ExactResist f gS nullFamily null-PointConc

--  Nevertheless its locked function ignores the key and equals the base
--  on every input, formally expressing the absence of effective locking.
null-lock-vacuous :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (k x : Vec Bool n) →
  actGen f gS nullFamily k x ≡ baseGen f gS x
null-lock-vacuous f gS k x = xor-identityʳ (baseGen f gS x)

--  Its zero corruption shows that a small corruption bound alone can be
--  satisfied by doing nothing and cannot certify a useful lock.
null-ocr-0 : (k₁ k₂ : Vec Bool n) →
             ocrGen-of (nullFamily k₁) (nullFamily {n} k₂) ≡ 0
null-ocr-0 {n} k₁ k₂ = countT-≡0 _ (λ _ → refl) (allVecs n)

--  Show NonDeg excludes precisely this behaviour.
null-¬NonDeg : ¬ NonDeg {n} nullFamily
null-¬NonDeg {n} ndg with ndg (replicate n false)
... | ()

------------------------------------------------------------------------
--  Under PointConcND, identify each predicate with its key's point
--  indicator. Subsequent quantitative results use this identity and existing
--  counting lemmas, with no new allVecs induction.

nd-pred-is-point :
  (G : Vec Bool n → ProtGadget n) → PointConcND G →
  (k x : Vec Bool n) → pred (G k) x ≡ eqVec k x
nd-pred-is-point G nd k x with eqVec k x in eqp
... | true  = trans (cong (pred (G k)) (sym (eqVec-sound k x eqp)))
                    (fires nd k)
... | false = conc nd k x (λ x≡k → eqVec-false→≢ k x eqp (sym x≡k))

--  Count exactly one protected input, the key itself.
nd-pred-count :
  (G : Vec Bool n → ProtGadget n) → PointConcND G →
  (k : Vec Bool n) → countT (pred (G k)) (allVecs n) ≡ 1
nd-pred-count {n} G nd k =
  trans (countT-cong (nd-pred-is-point G nd k) (allVecs n)) (count-eq k)

--  Distinct-key point indicators have disjoint support.
eqVec-disjoint : (a b y : Vec Bool n) → a ≢ b → (eqVec a y ∧ eqVec b y) ≡ false
eqVec-disjoint a b y ne with eqVec a y in e₁ | eqVec b y in e₂
... | false | _     = refl
... | true  | false = refl
... | true  | true  =
  ⊥-elim (ne (trans (eqVec-sound a y e₁) (sym (eqVec-sound b y e₂))))

nd-disjoint :
  (G : Vec Bool n → ProtGadget n) → PointConcND G →
  (k₁ k₂ : Vec Bool n) → k₁ ≢ k₂ →
  (x : Vec Bool n) → (pred (G k₁) x ∧ pred (G k₂) x) ≡ false
nd-disjoint G nd k₁ k₂ ne x =
  trans (cong₂ _∧_ (nd-pred-is-point G nd k₁ x) (nd-pred-is-point G nd k₂ x))
        (eqVec-disjoint k₁ k₂ x ne)

--  Attain the generic ≤2 bound at every distinct key pair: two disjoint
--  singletons have symmetric difference two. This equality, contrasted
--  with null-ocr-0, records what non-degeneracy adds.
nd-ocr-exactly-2 :
  (G : Vec Bool n → ProtGadget n) → PointConcND G →
  (k₁ k₂ : Vec Bool n) → k₁ ≢ k₂ → ocrGen-of (G k₁) (G k₂) ≡ 2
nd-ocr-exactly-2 {n} G nd k₁ k₂ ne =
  trans (countT-xor-disjoint (pred (G k₁)) (pred (G k₂))
                             (nd-disjoint G nd k₁ k₂ ne) (allVecs n))
        (cong₂ _+_ (nd-pred-count G nd k₁) (nd-pred-count G nd k₂))

------------------------------------------------------------------------
--  At the first key's input, its predicate fires while a distinct key's
--  vanishes. Thus their locked oracles differ, making keys observable,
--  unlike the degenerate family.

xor-trueʳ : (b : Bool) → b xor true ≡ not b
xor-trueʳ true  = refl
xor-trueʳ false = refl

not-≢ : (b : Bool) → not b ≢ b
not-≢ true  ()
not-≢ false ()

nd-differs-at-key :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConcND G → (k₁ k₂ : Vec Bool n) → k₁ ≢ k₂ →
  actGen f gS G k₁ k₁ ≢ actGen f gS G k₂ k₁
nd-differs-at-key f gS G nd k₁ k₂ ne eq =
  not-≢ (baseGen f gS k₁) (trans (sym atSelf) (trans eq atOther))
  where
    atSelf : actGen f gS G k₁ k₁ ≡ not (baseGen f gS k₁)
    atSelf = trans (cong (baseGen f gS k₁ xor_) (fires nd k₁))
                   (xor-trueʳ (baseGen f gS k₁))
    atOther : actGen f gS G k₂ k₁ ≡ baseGen f gS k₁
    atOther = trans (cong (baseGen f gS k₁ xor_) (conc nd k₂ k₁ ne))
                    (xor-identityʳ (baseGen f gS k₁))

--  Contrapositively, equality of induced locked functions determines key equality.
nd-oracle-injective :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConcND G → (k₁ k₂ : Vec Bool n) →
  ((x : Vec Bool n) → actGen f gS G k₁ x ≡ actGen f gS G k₂ x) → k₁ ≡ k₂
nd-oracle-injective f gS G nd k₁ k₂ agree with eqVec k₁ k₂ in e
... | true  = eqVec-sound k₁ k₂ e
... | false =
  ⊥-elim (nd-differs-at-key f gS G nd k₁ k₂ (eqVec-false→≢ k₁ k₂ e) (agree k₁))

------------------------------------------------------------------------
--  Require resistance together with non-vacuity in one record, excluding
--  locks whose resistance merely reflects a key-independent function.

record NonVacuousResist (f : Vec Bool n → Bool) (gS : ProtGadget n)
                        (G : Vec Bool n → ProtGadget n) : Set where
  field
    --  Retain the original resistance conclusion.
    resist   : ExactResist (actGen f gS G)
    --  Require different keys to induce different locked functions.
    injects  : (k₁ k₂ : Vec Bool n) →
               ((x : Vec Bool n) → actGen f gS G k₁ x ≡ actGen f gS G k₂ x) →
               k₁ ≡ k₂
    --  Record exact corruption two rather than an upper bound alone.
    corrupts : (k₁ k₂ : Vec Bool n) → k₁ ≢ k₂ → ocrGen-of (G k₁) (G k₂) ≡ 2
open NonVacuousResist public

mkNonVacuousResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) (G : Vec Bool n → ProtGadget n) →
  PointConcND G → NonVacuousResist f gS G
mkNonVacuousResist f gS G nd = record
  { resist   = gen-ExactResist f gS G (conc nd)
  ; injects  = nd-oracle-injective f gS G nd
  ; corrupts = nd-ocr-exactly-2 G nd
  }

point-NonVacuousResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  NonVacuousResist f gS pointGadget
point-NonVacuousResist f gS = mkNonVacuousResist f gS pointGadget point-PointConcND

flex-NonVacuousResist :
  (f : Vec Bool n → Bool) (gS : ProtGadget n) →
  NonVacuousResist f gS flexSingleton
flex-NonVacuousResist f gS = mkNonVacuousResist f gS flexSingleton flex-PointConcND

------------------------------------------------------------------------
--  Refute NonVacuousResist for the null family despite null-ExactResist.
--  Its injects field would equate visibly different keys because both
--  induce the same constant function. The stronger property therefore
--  excludes cases admitted by PointConc alone.

private
  ∷-false≢true : {m : ℕ} (v : Vec Bool m) → (false ∷ v) ≢ (true ∷ v)
  ∷-false≢true v ()

null-¬NonVacuous :
  {m : ℕ} (f : Vec Bool (suc m) → Bool) (gS : ProtGadget (suc m)) →
  ¬ NonVacuousResist f gS nullFamily
null-¬NonVacuous {m} f gS nv =
  ∷-false≢true (replicate m false) (injects nv k₀ k₁ same)
  where
    k₀ k₁ : Vec Bool (suc m)
    k₀ = false ∷ replicate m false
    k₁ = true  ∷ replicate m false

    same : (x : Vec Bool (suc m)) →
           actGen f gS nullFamily k₀ x ≡ actGen f gS nullFamily k₁ x
    same x = trans (null-lock-vacuous f gS k₀ x)
                   (sym (null-lock-vacuous f gS k₁ x))
