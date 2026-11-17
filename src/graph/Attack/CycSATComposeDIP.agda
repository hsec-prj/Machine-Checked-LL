------------------------------------------------------------------------
--  Verify adaptive DIP finding for the injective
--  point residual (graph branch B). CycSATComposeGen
--  uses exhaustive scanV over 2^m keys and all inputs;
--  branch A characterises noninjective limits. Here
--  dipScan queries and prunes one distinguishing
--  input at a time. Fuel recursion branches on
--  findDIP at the recursive call site, allowing
--  definitional reduction without funext or a generic
--  dipLoop fixpoint argument under --safe. findDIP
--  selects a surviving candidate corrupted at its
--  own input: consistC ksec x x is false exactly
--  for x ≢ ksec. prune-count-< strictly decreases
--  candidate count. If no DIP remains, no-DIP→singleton
--  leaves only the secret, and dipScan-noDIP proves
--  2^m fuel sufficient. dipScan-recovers and
--  oscillation-elimination stage one give
--  cycSATComposeDIP-recovers ≡ allFalse k ++ ksec,
--  with at most 2^m residual queries. Transliterate
--  countT, conjunction bounds, pruning, and strict
--  count decrease from main-track Counting,
--  SARLockQueryBound, and DIPAttackSpike locally,
--  since graph cannot import ../src. Reuse
--  consistC/consistC-self/eqVec, scanV/scanV-char,
--  and cycSATAttack. Use no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATComposeDIP where

open import Data.Nat using (ℕ; zero; suc; _+_; _∸_; _<_; _≤_; s≤s; z≤n; _^_)
open import Data.Nat.Properties
  using (+-mono-≤; +-mono-≤-<; ≤-trans; ≤-reflexive; m≤n+m; +-assoc; +-comm)
open import Data.Bool using (Bool; true; false; not; _∧_; _xor_; if_then_else_)
open import Data.Bool.Properties using (not-involutive; xor-identityʳ; ∧-zeroʳ; ∧-identityʳ)
open import Data.Vec using (Vec; []; _∷_; _++_)
open import Data.List using (List; []; _∷_; length; map) renaming (_++_ to _++ᴸ_)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Maybe.Properties using (just-injective)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Empty using (⊥; ⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)

open import Graph.Core using (Gate)
open import Graph.Acyclic using (ANetlist)
open import Locking.CyclicMulti using (allFalse)
open import Graph.Util using (allVecsK; ∈-allVecsK; length-allVecsK)
open import Attack.CycSATCompose
  using (eqVec; eqVec-refl; eqVec-sound; eqVec-complete; ∧true→; false≢true;
         consistC; consistC-self)
open import Attack.CycSATComposeGen using (scanV; scanV-char)
open import Attack.CycSATAttack using (cycSATAttack; cycSATAttack-recovers)

private
  variable
    A B : Set
    W k m : ℕ

------------------------------------------------------------------------
--  Transliterate the needed Counting, SARLockQueryBound,
--  and DIPAttackSpike counting core into the graph track.

countT : (A → Bool) → List A → ℕ
countT p []       = 0
countT p (x ∷ xs) = (if p x then 1 else 0) + countT p xs

countT-all-true : (xs : List A) → countT (λ _ → true) xs ≡ length xs
countT-all-true []       = refl
countT-all-true (x ∷ xs) = cong suc (countT-all-true xs)

prune : (kept cand : A → Bool) → A → Bool
prune kept cand a = kept a ∧ cand a

bit-∧-≤ʳ : (a b : Bool) → (if a ∧ b then 1 else 0) ≤ (if b then 1 else 0)
bit-∧-≤ʳ false b = z≤n
bit-∧-≤ʳ true  b = ≤-reflexive refl

countT-∧-≤ʳ : (p r : A → Bool) (xs : List A) →
              countT (λ x → p x ∧ r x) xs ≤ countT r xs
countT-∧-≤ʳ p r []       = z≤n
countT-∧-≤ʳ p r (x ∷ xs) = +-mono-≤ (bit-∧-≤ʳ (p x) (r x)) (countT-∧-≤ʳ p r xs)

--  Prove an effective prune removing a survivor strictly
--  reduces count, refining countT-∧-≤ʳ.
prune-count-< : (kept cand : A → Bool) (w : A) (xs : List A) →
                w ∈ xs → cand w ≡ true → kept w ≡ false →
                countT (prune kept cand) xs < countT cand xs
prune-count-< kept cand w (.w ∷ xs) (here refl) cw kw
  rewrite kw | cw = s≤s (countT-∧-≤ʳ kept cand xs)
prune-count-< kept cand w (x ∷ xs) (there mem) cw kw =
  +-mono-≤-< (bit-∧-≤ʳ (kept x) (cand x)) (prune-count-< kept cand w xs mem cw kw)

--  Supply small arithmetic and Boolean helpers.
≤0→≡0 : {n : ℕ} → n ≤ 0 → n ≡ 0
≤0→≡0 z≤n = refl

sucinj : {a b : ℕ} → suc a ≤ suc b → a ≤ b
sucinj (s≤s p) = p

suc≢0 : {n : ℕ} → suc n ≡ 0 → ⊥
suc≢0 ()

just≢nothing : {x : Vec Bool m} → just x ≡ nothing → ⊥
just≢nothing ()

not-true→false : (c : Bool) → not c ≡ true → c ≡ false
not-true→false false _ = refl
not-true→false true  ()

not-false→true : (c : Bool) → not c ≡ false → c ≡ true
not-false→true true  _ = refl
not-false→true false ()

notnot→true : (b : Bool) → not (not b) ≡ true → b ≡ true
notnot→true true  _ = refl
notnot→true false ()

--  For point locks, identify consistC ksec x x with
--  the secret indicator, true exactly when x = ksec.
consistCxx→eq : (ksec x : Vec Bool m) → consistC ksec x x ≡ true → x ≡ ksec
consistCxx→eq ksec x h = sym (eqVec-complete ksec x (notnot→true (eqVec ksec x) h'))
  where
    h' : not (not (eqVec ksec x)) ≡ true
    h' = subst (λ z → not (z xor eqVec ksec x) ≡ true) (eqVec-refl x) h

------------------------------------------------------------------------
--  Scan surviving keys for one corrupted by the
--  secret oracle at its own input and return that DIP.

findDIP : Vec Bool m → (Vec Bool m → Bool) → List (Vec Bool m) → Maybe (Vec Bool m)
findDIP ksec cand []       = nothing
findDIP ksec cand (x ∷ xs) =
  if (cand x ∧ not (consistC ksec x x)) then just x else findDIP ksec cand xs

--  A returned x satisfies cand x = true and
--  consistC ksec x x = false, the strict-pruning premises.
findDIP-just→ : (ksec : Vec Bool m) (cand : Vec Bool m → Bool)
                (xs : List (Vec Bool m)) (x : Vec Bool m) →
                findDIP ksec cand xs ≡ just x →
                (cand x ≡ true) × (consistC ksec x x ≡ false)
findDIP-just→ ksec cand (y ∷ xs) x h with cand y ∧ not (consistC ksec y y) in e
... | true  =
  let (cy , ny) = ∧true→ (cand y) (not (consistC ksec y y)) e
      y≡x       = just-injective h
  in subst (λ z → cand z ≡ true) y≡x cy
   , subst (λ z → consistC ksec z z ≡ false) y≡x (not-true→false (consistC ksec y y) ny)
... | false = findDIP-just→ ksec cand xs x h

--  If findDIP returns nothing, every survivor agrees
--  at its own input and therefore equals the secret.
findDIP-nothing→ : (ksec : Vec Bool m) (cand : Vec Bool m → Bool)
                   (xs : List (Vec Bool m)) →
                   findDIP ksec cand xs ≡ nothing →
                   (k : Vec Bool m) → k ∈ xs → cand k ≡ true →
                   consistC ksec k k ≡ true
findDIP-nothing→ ksec cand (y ∷ xs) h k (here refl) ck
  with cand y ∧ not (consistC ksec y y) in e
... | true  = ⊥-elim (just≢nothing h)
... | false =
  not-false→true (consistC ksec y y)
    (subst (λ z → (z ∧ not (consistC ksec y y)) ≡ false) ck e)
findDIP-nothing→ ksec cand (y ∷ xs) h k (there mem) ck
  with cand y ∧ not (consistC ksec y y) in e
... | true  = ⊥-elim (just≢nothing h)
... | false = findDIP-nothing→ ksec cand xs h k mem ck

count0→findDIP-nothing : (ksec : Vec Bool m) (cand : Vec Bool m → Bool)
                         (xs : List (Vec Bool m)) →
                         countT cand xs ≡ 0 → findDIP ksec cand xs ≡ nothing
count0→findDIP-nothing ksec cand []       _  = refl
count0→findDIP-nothing ksec cand (y ∷ xs) c0 with cand y
... | true  = ⊥-elim (suc≢0 c0)
... | false = count0→findDIP-nothing ksec cand xs c0

------------------------------------------------------------------------
--  Recurse on fuel and branch on findDIP at the recursive site.

dipScan : Vec Bool m → (Vec Bool m → Bool) → ℕ → Vec Bool m → Bool
dipScan ksec cand zero    = cand
dipScan ksec cand (suc f) with findDIP ksec cand (allVecsK _)
... | nothing = cand
... | just x  = dipScan ksec (prune (λ kc → consistC ksec x kc) cand) f

--  Preserve the secret at every step using consistC-self.
dipScan-ksec : (ksec : Vec Bool m) (cand : Vec Bool m → Bool) (f : ℕ) →
               dipScan ksec cand f ksec ≡ cand ksec
dipScan-ksec ksec cand zero    = refl
dipScan-ksec ksec cand (suc f) with findDIP ksec cand (allVecsK _)
... | nothing = refl
... | just x  =
  trans (dipScan-ksec ksec (prune (λ kc → consistC ksec x kc) cand) f)
        (cong (_∧ cand ksec) (consistC-self ksec x))

--  With fuel at least candidate count, reach the no-DIP fixed point.
dipScan-noDIP : (ksec : Vec Bool m) (cand : Vec Bool m → Bool) (f : ℕ) →
                countT cand (allVecsK m) ≤ f →
                findDIP ksec (dipScan ksec cand f) (allVecsK m) ≡ nothing
dipScan-noDIP {m = m} ksec cand zero    le =
  count0→findDIP-nothing ksec cand (allVecsK m) (≤0→≡0 le)
dipScan-noDIP {m = m} ksec cand (suc f) le
  with findDIP ksec cand (allVecsK m) in e
... | nothing = e
... | just x  =
  dipScan-noDIP ksec (prune (λ kc → consistC ksec x kc) cand) f le'
  where
    pre : (cand x ≡ true) × (consistC ksec x x ≡ false)
    pre = findDIP-just→ ksec cand (allVecsK m) x e
    le' : countT (prune (λ kc → consistC ksec x kc) cand) (allVecsK m) ≤ f
    le' = sucinj (≤-trans
            (prune-count-< (λ kc → consistC ksec x kc) cand x (allVecsK m)
                           (∈-allVecsK x) (proj₁ pre) (proj₂ pre))
            le)

------------------------------------------------------------------------
--  At fuel 2^m, prove the secret survives and every
--  survivor equals it, establishing adaptive recovery.

no-DIP→singleton : (ksec : Vec Bool m) (cand : Vec Bool m → Bool) →
                   findDIP ksec cand (allVecsK m) ≡ nothing →
                   (k : Vec Bool m) → cand k ≡ true → k ≡ ksec
no-DIP→singleton {m = m} ksec cand nd k ck =
  consistCxx→eq ksec k
    (findDIP-nothing→ ksec cand (allVecsK m) nd k (∈-allVecsK k) ck)

dipScan-recovers : (ksec : Vec Bool m) →
  ((k : Vec Bool m) → dipScan ksec (λ _ → true) (2 ^ m) k ≡ true → k ≡ ksec)
  × (dipScan ksec (λ _ → true) (2 ^ m) ksec ≡ true)
dipScan-recovers {m = m} ksec =
    (λ k ck → no-DIP→singleton ksec (dipScan ksec (λ _ → true) (2 ^ m)) noDIP k ck)
  , dipScan-ksec ksec (λ _ → true) (2 ^ m)
  where
    noDIP : findDIP ksec (dipScan ksec (λ _ → true) (2 ^ m)) (allVecsK m) ≡ nothing
    noDIP = dipScan-noDIP ksec (λ _ → true) (2 ^ m)
              (≤-reflexive (trans (countT-all-true (allVecsK m)) (length-allVecsK m)))

------------------------------------------------------------------------
--  Compose with feedback oscillation elimination
--  to recover the complete key allFalse k ++ ksec.

cycSATComposeDIP : (outs : Vec (Gate W) k) (base : ANetlist W) (ksec : Vec Bool m) →
                   Vec Bool (k + m)
cycSATComposeDIP {m = m} outs base ksec =
  cycSATAttack outs base ++ scanV (dipScan ksec (λ _ → true) (2 ^ m)) (allVecsK m)

cycSATComposeDIP-recovers :
  (outs : Vec (Gate W) k) (base : ANetlist W) (ksec : Vec Bool m) →
  cycSATComposeDIP outs base ksec ≡ allFalse k ++ ksec
cycSATComposeDIP-recovers {m = m} outs base ksec =
  cong₂ _++_ (cycSATAttack-recovers outs base)
    (scanV-char (dipScan ksec (λ _ → true) (2 ^ m)) ksec (allVecsK m)
       (proj₁ (dipScan-recovers ksec)) (proj₂ (dipScan-recovers ksec)) (∈-allVecsK ksec))

--  Bound adaptive steps by fuel 2^m, the same
--  coarse worst-case ceiling as exhaustive folding.
cycSATComposeDIP-fuel : (m : ℕ) → length (allVecsK m) ≡ 2 ^ m
cycSATComposeDIP-fuel = length-allVecsK

------------------------------------------------------------------------
--  Frontier #3: distinguish effective just/pruning
--  queries from fuel-bounded loop length. Each such
--  step strictly reduces candidates while preserving
--  the secret, giving at most 2ᵐ − 1, one per
--  wrong key in the worst case; multi-removal would use fewer.

--  Count the pruning queries actually issued by the loop.
dipScanCount : Vec Bool m → (Vec Bool m → Bool) → ℕ → ℕ
dipScanCount ksec cand zero    = 0
dipScanCount ksec cand (suc f) with findDIP ksec cand (allVecsK _)
... | nothing = 0
... | just x  = suc (dipScanCount ksec (prune (λ kc → consistC ksec x kc) cand) f)

--  Use an enumerated surviving member to force a positive candidate count.
countT-pos-∈ : (p : A → Bool) (xs : List A) (w : A) →
               w ∈ xs → p w ≡ true → 1 ≤ countT p xs
countT-pos-∈ p (x ∷ xs) w (here refl) pw rewrite pw = s≤s z≤n
countT-pos-∈ p (x ∷ xs) w (there mem) pw =
  ≤-trans (countT-pos-∈ p xs w mem pw) (m≤n+m (countT p xs) _)

suc-pred : (c : ℕ) → 1 ≤ c → suc (c ∸ 1) ≡ c
suc-pred (suc c) _ = refl

<⇒≤∸1 : {a b : ℕ} → a < b → a ≤ b ∸ 1
<⇒≤∸1 {a} {suc b} (s≤s a≤b) = a≤b

--  Bound effective queries by candidate count minus
--  one: pruning decreases the count and the secret keeps it positive.
dipScanCount-≤ : (ksec : Vec Bool m) (cand : Vec Bool m → Bool) (f : ℕ) →
                 cand ksec ≡ true → countT cand (allVecsK m) ≤ f →
                 dipScanCount ksec cand f ≤ countT cand (allVecsK m) ∸ 1
dipScanCount-≤ ksec cand zero    _    _  = z≤n
dipScanCount-≤ {m = m} ksec cand (suc f) csec le
  with findDIP ksec cand (allVecsK m) in e
... | nothing = z≤n
... | just x  =
  ≤-trans (s≤s ih)
          (≤-trans (≤-reflexive (suc-pred (countT cand' (allVecsK m)) pos'))
                   (<⇒≤∸1 dec))
  where
    cand' : Vec Bool m → Bool
    cand' = prune (λ kc → consistC ksec x kc) cand
    pre : (cand x ≡ true) × (consistC ksec x x ≡ false)
    pre = findDIP-just→ ksec cand (allVecsK m) x e
    dec : countT cand' (allVecsK m) < countT cand (allVecsK m)
    dec = prune-count-< (λ kc → consistC ksec x kc) cand x (allVecsK m)
            (∈-allVecsK x) (proj₁ pre) (proj₂ pre)
    csec' : cand' ksec ≡ true
    csec' = cong₂ _∧_ (consistC-self ksec x) csec
    pos' : 1 ≤ countT cand' (allVecsK m)
    pos' = countT-pos-∈ cand' (allVecsK m) ksec (∈-allVecsK ksec) csec'
    ih : dipScanCount ksec cand' f ≤ countT cand' (allVecsK m) ∸ 1
    ih = dipScanCount-≤ ksec cand' f csec' (sucinj (≤-trans dec le))

--  Give at most 2ᵐ − 1 effective DIPs, strictly
--  below the exhaustive fold's 2ᵐ.
dipScanCount-bound : (ksec : Vec Bool m) →
                     dipScanCount ksec (λ _ → true) (2 ^ m) ≤ 2 ^ m ∸ 1
dipScanCount-bound {m = m} ksec =
  ≤-trans (dipScanCount-≤ ksec (λ _ → true) (2 ^ m) refl (≤-reflexive cnt))
          (≤-reflexive (cong (_∸ 1) cnt))
  where
    cnt : countT (λ _ → true) (allVecsK m) ≡ 2 ^ m
    cnt = trans (countT-all-true (allVecsK m)) (length-allVecsK m)

------------------------------------------------------------------------
--  Frontier #2: sharpen the point instance to exact
--  2ᵐ − 1 effective queries. Each just step removes
--  only its DIP x: off the secret, consistC ksec
--  x kc = not (eqVec kc x). countEq-one proves
--  exactly one enumerated vector equals x, so every
--  step removes one and only the secret remains.

--  Add graph-local counting facts mirroring Util.Counting.
countT-++ : (p : A → Bool) (xs ys : List A) →
            countT p (xs ++ᴸ ys) ≡ countT p xs + countT p ys
countT-++ p []       ys = refl
countT-++ p (a ∷ xs) ys =
  trans (cong ((if p a then 1 else 0) +_) (countT-++ p xs ys))
        (sym (+-assoc (if p a then 1 else 0) (countT p xs) (countT p ys)))

countT-map : (p : B → Bool) (f : A → B) (xs : List A) →
             countT p (map f xs) ≡ countT (λ a → p (f a)) xs
countT-map p f []       = refl
countT-map p f (a ∷ xs) = cong ((if p (f a) then 1 else 0) +_) (countT-map p f xs)

countT-const-false : (xs : List A) → countT (λ _ → false) xs ≡ 0
countT-const-false []       = refl
countT-const-false (a ∷ xs) = countT-const-false xs

countT-cong : {p q : A → Bool} → (∀ a → p a ≡ q a) → (xs : List A) →
              countT p xs ≡ countT q xs
countT-cong h []       = refl
countT-cong {p = p} {q} h (a ∷ xs) =
  cong₂ _+_ (cong (λ b → if b then 1 else 0) (h a)) (countT-cong h xs)

--  Split allVecsK (suc m) counting by the leading bit.
split-count-K : (P : Vec Bool (suc m) → Bool) →
  countT P (allVecsK (suc m))
  ≡ countT (λ a → P (false ∷ a)) (allVecsK m) + countT (λ a → P (true ∷ a)) (allVecsK m)
split-count-K {m = m} P =
  trans (countT-++ P (map (false ∷_) (allVecsK m)) (map (true ∷_) (allVecsK m)))
        (cong₂ _+_ (countT-map P (false ∷_) (allVecsK m))
                   (countT-map P (true ∷_) (allVecsK m)))

--  Prove exactly one enumerated vector matches x.
countEq-one : (x : Vec Bool m) → countT (λ a → eqVec a x) (allVecsK m) ≡ 1
countEq-one {zero}  []           = refl
countEq-one {suc m} (false ∷ x') =
  trans (split-count-K (λ a → eqVec a (false ∷ x')))
        (cong₂ _+_ (countEq-one x') (countT-const-false (allVecsK m)))
countEq-one {suc m} (true ∷ x') =
  trans (split-count-K (λ a → eqVec a (true ∷ x')))
        (cong₂ _+_ (countT-const-false (allVecsK m)) (countEq-one x'))

--  Partition a predicate's count into retained and removed parts.
mid4 : (a b c d : ℕ) → (a + b) + (c + d) ≡ (a + c) + (b + d)
mid4 a b c d =
  trans (+-assoc a b (c + d))
        (trans (cong (a +_) (trans (sym (+-assoc b c d))
                                   (trans (cong (_+ d) (+-comm b c)) (+-assoc c b d))))
               (sym (+-assoc a c (b + d))))

bit-split : (kp cd : Bool) →
            (if cd then 1 else 0)
            ≡ (if kp ∧ cd then 1 else 0) + (if cd ∧ not kp then 1 else 0)
bit-split true  true  = refl
bit-split true  false = refl
bit-split false true  = refl
bit-split false false = refl

countT-split : (kp cd : A → Bool) (xs : List A) →
               countT cd xs
               ≡ countT (λ a → kp a ∧ cd a) xs + countT (λ a → cd a ∧ not (kp a)) xs
countT-split kp cd []       = refl
countT-split kp cd (a ∷ xs) =
  trans (cong₂ _+_ (bit-split (kp a) (cd a)) (countT-split kp cd xs))
        (mid4 (if kp a ∧ cd a then 1 else 0) (if cd a ∧ not (kp a) then 1 else 0)
              (countT (λ a → kp a ∧ cd a) xs) (countT (λ a → cd a ∧ not (kp a)) xs))

--  Reduce off-diagonal consistency to a negated point indicator.
not-consistC-eq : (ksec x : Vec Bool m) → eqVec ksec x ≡ false →
                  (a : Vec Bool m) → consistC ksec x a ≡ not (eqVec a x)
not-consistC-eq ksec x ef a rewrite ef = cong not (xor-identityʳ (eqVec a x))

dipx-eqVec-false : (ksec x : Vec Bool m) → consistC ksec x x ≡ false → eqVec ksec x ≡ false
dipx-eqVec-false ksec x h = trans (sym reduce) h
  where
    reduce : consistC ksec x x ≡ eqVec ksec x
    reduce rewrite eqVec-refl x = not-involutive (eqVec ksec x)

--  Prove each effective step decreases count by exactly one.
prune-count-suc : (ksec x : Vec Bool m) (cand : Vec Bool m → Bool) →
                  cand x ≡ true → eqVec ksec x ≡ false →
                  countT cand (allVecsK m)
                  ≡ suc (countT (prune (λ kc → consistC ksec x kc) cand) (allVecsK m))
prune-count-suc {m = m} ksec x cand cx ef =
  trans (countT-split (λ a → consistC ksec x a) cand (allVecsK m))
        (trans (cong₂ _+_ refl second) (+-comm _ 1))
  where
    second : countT (λ a → cand a ∧ not (consistC ksec x a)) (allVecsK m) ≡ 1
    second = trans (countT-cong reduce (allVecsK m)) (countEq-one x)
      where
        eat : (a : Vec Bool m) → cand a ∧ eqVec a x ≡ eqVec a x
        eat a with eqVec a x in e
        ... | false = ∧-zeroʳ (cand a)
        ... | true  = trans (∧-identityʳ (cand a))
                            (trans (cong cand (eqVec-complete a x e)) cx)
        reduce : (a : Vec Bool m) → (cand a ∧ not (consistC ksec x a)) ≡ eqVec a x
        reduce a = trans (cong (cand a ∧_)
                               (trans (cong not (not-consistC-eq ksec x ef a))
                                      (not-involutive (eqVec a x))))
                         (eat a)

--  A secret-only survivor predicate has count one.
count-singleton : (ksec : Vec Bool m) (cand : Vec Bool m → Bool) →
                  ((k : Vec Bool m) → cand k ≡ true → k ≡ ksec) → cand ksec ≡ true →
                  countT cand (allVecsK m) ≡ 1
count-singleton {m = m} ksec cand uniq csec =
  trans (countT-cong cand≡eq (allVecsK m)) (countEq-one ksec)
  where
    cand≡eq : (a : Vec Bool m) → cand a ≡ eqVec a ksec
    cand≡eq a with cand a in e
    ... | true  = sym (eqVec-sound a ksec (uniq a e))
    ... | false = sym ev
      where
        ev : eqVec a ksec ≡ false
        ev with eqVec a ksec in e2
        ... | false = refl
        ... | true  = ⊥-elim (false≢true
                        (trans (sym e) (trans (cong cand (eqVec-complete a ksec e2)) csec)))

--  Obtain exactly candidate count minus one effective queries.
dipScanCount-exact-gen :
  (ksec : Vec Bool m) (cand : Vec Bool m → Bool) (f : ℕ) →
  cand ksec ≡ true → countT cand (allVecsK m) ≤ f →
  dipScanCount ksec cand f ≡ countT cand (allVecsK m) ∸ 1
dipScanCount-exact-gen ksec cand zero    csec le rewrite ≤0→≡0 le = refl
dipScanCount-exact-gen {m = m} ksec cand (suc f) csec le
  with findDIP ksec cand (allVecsK m) in e
... | nothing =
  sym (cong (_∸ 1) (count-singleton ksec cand (no-DIP→singleton ksec cand e) csec))
... | just x  =
  trans (cong suc ih)
        (trans (suc-pred (countT cand' (allVecsK m)) pos')
               (sym (cong (_∸ 1) pcs)))
  where
    cand' : Vec Bool m → Bool
    cand' = prune (λ kc → consistC ksec x kc) cand
    pre : (cand x ≡ true) × (consistC ksec x x ≡ false)
    pre = findDIP-just→ ksec cand (allVecsK m) x e
    pcs : countT cand (allVecsK m) ≡ suc (countT cand' (allVecsK m))
    pcs = prune-count-suc ksec x cand (proj₁ pre) (dipx-eqVec-false ksec x (proj₂ pre))
    csec' : cand' ksec ≡ true
    csec' = cong₂ _∧_ (consistC-self ksec x) csec
    pos' : 1 ≤ countT cand' (allVecsK m)
    pos' = countT-pos-∈ cand' (allVecsK m) ksec (∈-allVecsK ksec) csec'
    cand'-le : countT cand' (allVecsK m) ≤ f
    cand'-le = sucinj (subst (_≤ suc f) pcs le)
    ih : dipScanCount ksec cand' f ≡ countT cand' (allVecsK m) ∸ 1
    ih = dipScanCount-exact-gen ksec cand' f csec' cand'-le

dipScanCount-exact : (ksec : Vec Bool m) →
                     dipScanCount ksec (λ _ → true) (2 ^ m) ≡ 2 ^ m ∸ 1
dipScanCount-exact {m = m} ksec =
  trans (dipScanCount-exact-gen ksec (λ _ → true) (2 ^ m) refl (≤-reflexive cnt))
        (cong (_∸ 1) cnt)
  where
    cnt : countT (λ _ → true) (allVecsK m) ≡ 2 ^ m
    cnt = trans (countT-all-true (allVecsK m)) (length-allVecsK m)
