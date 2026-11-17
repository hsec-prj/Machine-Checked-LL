------------------------------------------------------------------------
--  Recover planted keys by scanning stability decisions on the graph track.
--  scanDecP accepts P and its decider without a secret parameter;
--  oracleScan-recovers uses a unique-survivor premise over the 2ᵏ keys.
--  decSATModelK supplies static decisions for a base-reading feedback
--  layer on an acyclic base. CyclicKey's decoder conditions identify the
--  unique key opening all loops; xorEnc instantiates them with key-line
--  polarities, yielding cycSATAttackXor ksec outs base ≡ ksec.
--  The attacker receives those polarities and stability decisions.
--  The arbitrary-topology obstruction/uniqueness lemmas do not extend
--  this executable decider to arbitrary feedback topologies.
--  The allFalse case follows through cycSATAttack-as-instance.
--  cycSATComposeK-recovers combines this survivor with a residual
--  unique-survivor predicate and returns the concatenated keys. This
--  composition is of predicates, with the full candidate scan retained.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.CycSATAttackKey where

open import Data.Nat using (ℕ; _+_; _^_)
open import Data.Bool using (Bool; true; false; _∧_)
open import Data.Vec using (Vec; []; _∷_; _++_)
open import Data.Fin using (zero)
open import Data.List using (List; []; _∷_; length)
open import Data.Product using (_×_; _,_)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Data.Empty using (⊥-elim)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; subst)
open import Relation.Nullary using (Dec; yes; no; ¬_)
open import Relation.Nullary.Decidable using (⌊_⌋)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)

open import Graph.Core using (Gate; wire; cst)
open import Graph.Acyclic using (ANetlist)
open import Graph.Acyclic using () renaming ([] to a[]; _∷_ to _a∷_)
open import Graph.Util using (allVecsK; ∈-allVecsK; length-allVecsK)
open import Locking.CyclicMulti using (allFalse)
open import Locking.CyclicTopo using (baseLayer; SATModelT)
open import Locking.CyclicKey
  using (KeyEnc; SATModelK; model→correct-K; xorEnc; xorEnc-self; xorEnc-only;
         xorEnc-allFalseˡ)
open import Attack.CycSATAttack
  using (decSATModelT; correctModel; scanDec; cycSATAttack)
open import Attack.CycSATCompose using (false≢true)
open import Attack.CycSATComposeGen using (scanV; composeP; composeGen-recovers)

private
  variable
    W k m : ℕ

------------------------------------------------------------------------
--  §1 Make key scanning oracle-only: abstract P leaves
--  the scan access only to d, without a secret parameter.

scanDecP : {n : ℕ} {P : Vec Bool n → Set} (d : (x : Vec Bool n) → Dec (P x)) →
           List (Vec Bool n) → Vec Bool n
scanDecP {n} d []       = allFalse n
scanDecP     d (x ∷ xs) with d x
... | yes _ = x
... | no  _ = scanDecP d xs

--  Prove step identities also needed for oracle comparison.
scanDecP-yes : {n : ℕ} {P : Vec Bool n → Set} (d : (x : Vec Bool n) → Dec (P x))
               (x : Vec Bool n) (xs : List (Vec Bool n)) →
               P x → scanDecP d (x ∷ xs) ≡ x
scanDecP-yes d x xs p with d x
... | yes _  = refl
... | no  ¬p = ⊥-elim (¬p p)

scanDecP-no : {n : ℕ} {P : Vec Bool n → Set} (d : (x : Vec Bool n) → Dec (P x))
              (x : Vec Bool n) (xs : List (Vec Bool n)) →
              ¬ P x → scanDecP d (x ∷ xs) ≡ scanDecP d xs
scanDecP-no d x xs ¬p with d x
... | yes p = ⊥-elim (¬p p)
... | no  _ = refl

--  Return the unique survivor in any ordering of the scanned list.
scanDecP-char :
  {n : ℕ} {P : Vec Bool n → Set} (d : (x : Vec Bool n) → Dec (P x))
  (x* : Vec Bool n) (xs : List (Vec Bool n)) →
  ((y : Vec Bool n) → P y → y ≡ x*) → P x* → x* ∈ xs →
  scanDecP d xs ≡ x*
scanDecP-char d x* (x ∷ xs) uniq px* (here refl) = scanDecP-yes d x* xs px*
scanDecP-char d x* (x ∷ xs) uniq px* (there mem) with d x
... | yes p = uniq x p
... | no  _ = scanDecP-char d x* xs uniq px* mem

--  Invert an abstract singleton-survivor oracle by a
--  2ᵏ scan. ksec occurs in the theorem's premises,
--  while the scan stays parametric in P.
oracleScan-recovers :
  {n : ℕ} {P : Vec Bool n → Set} (d : (x : Vec Bool n) → Dec (P x))
  (ksec : Vec Bool n) →
  P ksec → ((y : Vec Bool n) → P y → y ≡ ksec) →
  scanDecP d (allVecsK n) ≡ ksec
oracleScan-recovers {n = n} d ksec self uniq =
  scanDecP-char d ksec (allVecsK n) uniq self (∈-allVecsK ksec)

--  Produce identical scans from pointwise Boolean-equivalent oracles.
private
  dec-agree : {P Q : Set} (p : Dec P) (q : Dec Q) →
              ⌊ p ⌋ ≡ ⌊ q ⌋ → (P × Q) ⊎ ((¬ P) × (¬ Q))
  dec-agree (yes a) (yes b) _  = inj₁ (a , b)
  dec-agree (no ¬a) (no ¬b) _  = inj₂ (¬a , ¬b)
  dec-agree (yes _) (no  _) ()
  dec-agree (no  _) (yes _) ()

scanDecP-cong :
  {n : ℕ} {P Q : Vec Bool n → Set}
  (d₁ : (x : Vec Bool n) → Dec (P x)) (d₂ : (x : Vec Bool n) → Dec (Q x))
  (xs : List (Vec Bool n)) →
  ((x : Vec Bool n) → ⌊ d₁ x ⌋ ≡ ⌊ d₂ x ⌋) →
  scanDecP d₁ xs ≡ scanDecP d₂ xs
scanDecP-cong d₁ d₂ []       h = refl
scanDecP-cong d₁ d₂ (x ∷ xs) h with dec-agree (d₁ x) (d₂ x) (h x)
... | inj₁ (p , q)   = trans (scanDecP-yes d₁ x xs p) (sym (scanDecP-yes d₂ x xs q))
... | inj₂ (¬p , ¬q) =
  trans (scanDecP-no d₁ x xs ¬p)
        (trans (scanDecP-cong d₁ d₂ xs h) (sym (scanDecP-no d₂ x xs ¬q)))

--  Identify the constant-key scan with this scan on the undecoded oracle.
scanDec-is-scanDecP :
  (outs : Vec (Gate W) k) (base : ANetlist W) (xs : List (Vec Bool k)) →
  scanDec outs base xs ≡ scanDecP (decSATModelT outs base) xs
scanDec-is-scanDecP outs base []       = refl
scanDec-is-scanDecP outs base (x ∷ xs) with decSATModelT outs base x
... | yes _ = refl
... | no  _ = scanDec-is-scanDecP outs base xs

------------------------------------------------------------------------
--  §2 Decide keyed oscillation from the netlist with
--  decSATModelT on decoded selectors, without simulation.

decSATModelK : (enc : KeyEnc k) (outs : Vec (Gate W) k) (base : ANetlist W)
               (ks : Vec Bool k) →
               Dec (SATModelK enc ks (baseLayer outs) base)
decSATModelK enc outs base ks = decSATModelT outs base (enc ks)

--  Admit a model at the planted key because enc ksec ≡ allFalse k opens all loops.
correctModelK : (enc : KeyEnc k) (ksec : Vec Bool k)
                (outs : Vec (Gate W) k) (base : ANetlist W) →
                enc ksec ≡ allFalse k →
                SATModelK enc ksec (baseLayer outs) base
correctModelK enc ksec outs base esec =
  subst (λ z → SATModelT z (baseLayer outs) base) (sym esec) (correctModel outs base)

------------------------------------------------------------------------
--  §3 Define the keyed attack and prove its recovery guarantee.

cycSATAttackK : (enc : KeyEnc k) (outs : Vec (Gate W) k) (base : ANetlist W) →
                Vec Bool k
cycSATAttackK {k = k} enc outs base = scanDecP (decSATModelK enc outs base) (allVecsK k)

--  Return the planted key for any supported key decoder.
cycSATAttackK-recovers :
  (enc : KeyEnc k) (ksec : Vec Bool k)
  (outs : Vec (Gate W) k) (base : ANetlist W) →
  enc ksec ≡ allFalse k →
  ((ts : Vec Bool k) → enc ts ≡ allFalse k → ts ≡ ksec) →
  cycSATAttackK enc outs base ≡ ksec
cycSATAttackK-recovers enc ksec outs base esec only =
  oracleScan-recovers (decSATModelK enc outs base) ksec
    (correctModelK enc ksec outs base esec)
    (λ y m → model→correct-K enc ksec y (baseLayer outs) base only m)

--  Retain inspection of all 2ᵏ candidate keys.
cycSATAttackK-queries : (k : ℕ) → length (allVecsK k) ≡ 2 ^ k
cycSATAttackK-queries = length-allVecsK

------------------------------------------------------------------------
--  §4 Instantiate polarity locking so that the scan returns each
--  universally quantified planted key.

cycSATAttackXor : (ksec : Vec Bool k) (outs : Vec (Gate W) k) (base : ANetlist W) →
                  Vec Bool k
cycSATAttackXor ksec outs base = cycSATAttackK (xorEnc ksec) outs base

cycSATAttackXor-recovers :
  (ksec : Vec Bool k) (outs : Vec (Gate W) k) (base : ANetlist W) →
  cycSATAttackXor ksec outs base ≡ ksec
cycSATAttackXor-recovers ksec outs base =
  cycSATAttackK-recovers (xorEnc ksec) ksec outs base
    (xorEnc-self ksec) (xorEnc-only ksec)

------------------------------------------------------------------------
--  §5 Recover the original theorem at ksec = allFalse k.

--  All-false polarity makes decoding identity; Boolean
--  oracle agreement then identifies the two attack functions.
cycSATAttack-as-instance :
  (outs : Vec (Gate W) k) (base : ANetlist W) →
  cycSATAttack outs base ≡ cycSATAttackXor (allFalse k) outs base
cycSATAttack-as-instance {k = k} outs base =
  trans (scanDec-is-scanDecP outs base (allVecsK k))
        (scanDecP-cong (decSATModelT outs base)
                       (decSATModelK (xorEnc (allFalse k)) outs base)
                       (allVecsK k)
                       (λ x → cong (λ z → ⌊ decSATModelT outs base z ⌋)
                                   (sym (xorEnc-allFalseˡ x))))

--  Derive CycSATAttack's recovery statement from the
--  keyed theorem while preserving its original proof.
cycSATAttack-recovers-derived :
  (outs : Vec (Gate W) k) (base : ANetlist W) →
  cycSATAttack outs base ≡ allFalse k
cycSATAttack-recovers-derived {k = k} outs base =
  trans (cycSATAttack-as-instance outs base)
        (cycSATAttackXor-recovers (allFalse k) outs base)

------------------------------------------------------------------------
--  §6 Compose keyed oscillation with any uniquely
--  recoverable residual scheme. Stage one now has
--  survivor ksec rather than fixed allFalse k.

stageOscK : (enc : KeyEnc k) (outs : Vec (Gate W) k) (base : ANetlist W) →
            Vec Bool k → Bool
stageOscK enc outs base hs = ⌊ decSATModelK enc outs base hs ⌋

stageOscK-self :
  (enc : KeyEnc k) (ksec : Vec Bool k)
  (outs : Vec (Gate W) k) (base : ANetlist W) →
  enc ksec ≡ allFalse k → stageOscK enc outs base ksec ≡ true
stageOscK-self enc ksec outs base esec with decSATModelK enc outs base ksec
... | yes _  = refl
... | no  ¬m = ⊥-elim (¬m (correctModelK enc ksec outs base esec))

stageOscK-uniq :
  (enc : KeyEnc k) (ksec : Vec Bool k)
  (outs : Vec (Gate W) k) (base : ANetlist W) →
  ((ts : Vec Bool k) → enc ts ≡ allFalse k → ts ≡ ksec) →
  (hs : Vec Bool k) → stageOscK enc outs base hs ≡ true → hs ≡ ksec
stageOscK-uniq enc ksec outs base only hs eq with decSATModelK enc outs base hs
... | yes mdl = model→correct-K enc ksec hs (baseLayer outs) base only mdl
... | no  _   = ⊥-elim (false≢true eq)

cycSATComposeK :
  (enc : KeyEnc k) (outs : Vec (Gate W) k) (base : ANetlist W)
  (s2 : Vec Bool m → Bool) → Vec Bool (k + m)
cycSATComposeK {k = k} {m = m} enc outs base s2 =
  scanV (composeP (stageOscK enc outs base) s2) (allVecsK (k + m))

--  Parameterise both halves of the recovered key bus.
cycSATComposeK-recovers :
  (enc : KeyEnc k) (ksec : Vec Bool k)
  (outs : Vec (Gate W) k) (base : ANetlist W)
  (s2 : Vec Bool m → Bool) (ksec₂ : Vec Bool m) →
  enc ksec ≡ allFalse k →
  ((ts : Vec Bool k) → enc ts ≡ allFalse k → ts ≡ ksec) →
  s2 ksec₂ ≡ true → ((t : Vec Bool m) → s2 t ≡ true → t ≡ ksec₂) →
  cycSATComposeK enc outs base s2 ≡ ksec ++ ksec₂
cycSATComposeK-recovers enc ksec outs base s2 ksec₂ esec only s2self s2uniq =
  composeGen-recovers (stageOscK enc outs base) s2 ksec ksec₂
    (stageOscK-self enc ksec outs base esec)
    (stageOscK-uniq enc ksec outs base only)
    s2self s2uniq

cycSATComposeXor-recovers :
  (ksec : Vec Bool k) (outs : Vec (Gate W) k) (base : ANetlist W)
  (s2 : Vec Bool m → Bool) (ksec₂ : Vec Bool m) →
  s2 ksec₂ ≡ true → ((t : Vec Bool m) → s2 t ≡ true → t ≡ ksec₂) →
  cycSATComposeK (xorEnc ksec) outs base s2 ≡ ksec ++ ksec₂
cycSATComposeXor-recovers ksec outs base s2 ksec₂ =
  cycSATComposeK-recovers (xorEnc ksec) ksec outs base s2 ksec₂
    (xorEnc-self ksec) (xorEnc-only ksec)

------------------------------------------------------------------------
--  §7 Compute recovery by refl for two distinct
--  secrets over one base, showing the returned key
--  varies and is not a disguised constant.

private
  base1 : ANetlist 1
  base1 = cst true a∷ a[]

  outs2 : Vec (Gate 1) 2
  outs2 = wire zero ∷ wire zero ∷ []

  _ : cycSATAttackXor (true ∷ false ∷ []) outs2 base1 ≡ true ∷ false ∷ []
  _ = refl

  _ : cycSATAttackXor (false ∷ true ∷ []) outs2 base1 ≡ false ∷ true ∷ []
  _ = refl

  _ : cycSATAttackXor (true ∷ true ∷ []) outs2 base1 ≡ true ∷ true ∷ []
  _ = refl
