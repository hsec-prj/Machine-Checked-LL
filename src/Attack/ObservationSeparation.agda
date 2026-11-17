------------------------------------------------------------------------
--  Compare functional and structural observations of one planted secret.
--  ExactQuery varies an applied key with a fixed secret-side gadget;
--  lockedBlock-constVals concerns the cube stored in the emitted block.
--  slot-swap transports query bounds to that secret side by using XOR
--  associativity and commutativity to exchange
--  two predicates in (f x xor pred g1 x) xor pred g2 x. With public fixed
--  applied key k0, plantAct f k0 s is therefore pointwise the ExactQuery
--  family indexed by s, with no approximation. Its bounds carry over.
--  For that same s, emitted constants contain s followed by four rails;
--  keeping their first n entries recovers s without behavioural queries.
--  The costs use distinct units: zero counts oracle queries, while
--  reading the operation list still takes O(|ops|) scanning work.
--  The structural decoder is oracle-free, not cost-free.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Attack.ObservationSeparation where

open import Data.Bool using (Bool; true; false; _xor_)
open import Data.Bool.Properties using (xor-assoc; xor-comm)
open import Data.List using (List; []; _∷_; _++_; take; length)
open import Data.List.Properties using (length-++)
open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; _<_; s≤s; z≤n; _∸_; _^_)
open import Data.Product using (proj₁; proj₂)
open import Data.Vec using (Vec; toList; map; lookup)
open import Data.Vec.Properties using (length-toList; map-cong)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong)
open import Relation.Nullary using (¬_)

open import Locking.GenericLock
  using (ProtGadget; pointGadget; locked-fun-gen)
open ProtGadget using (pred)
open import Attack.Oracle using (QAdversary; ask; Recovers)
open import Attack.GenericSAT using (actGen)
open import Attack.QueryLowerBound using (ask-cong)
open import Attack.ExactQuery using (ExactQuery; point-ExactQuery)
open import Extraction.Netlist using (Op)
open import Extraction.LockedNet using (lockedBlock; lockedBlock-locked; ReadsAs)
open import Extraction.NetlistCorrect using (AllLt)
open import Extraction.Netlist using (runNet; get)
open import Extraction.LockedNetMerged using (constVals; lockedBlock-constVals)
open ExactQuery public using ()

private
  variable
    n : ℕ

------------------------------------------------------------------------
--  §1 Put the hidden value on the lock's secret side.

--  Use XOR associativity and commutativity to exchange the predicates
--  in (f x xor pred g1 x) xor pred g2 x. This exact three-line identity
--  is the basis of the transport in §1.
slot-swap :
  (f : Vec Bool n → Bool) (g₁ g₂ : ProtGadget n) (x : Vec Bool n) →
  locked-fun-gen f g₁ g₂ x ≡ locked-fun-gen f g₂ g₁ x
slot-swap f g₁ g₂ x =
  trans (xor-assoc (f x) (pred g₁ x) (pred g₂ x))
    (trans (cong (f x xor_) (xor-comm (pred g₁ x) (pred g₂ x)))
           (sym (xor-assoc (f x) (pred g₂ x) (pred g₁ x))))

--  Fix k0 as public and use s as the planted secret; actGen instead
--  places its hidden index in the applied-key slot.
plantAct : (f : Vec Bool n → Bool) (k0 : Vec Bool n) →
           Vec Bool n → Vec Bool n → Bool
plantAct f k0 s x = locked-fun-gen f (pointGadget s) (pointGadget k0) x

--  Invoke slot-swap once to move the hidden value between slots
--  while preserving every output.
plantAct-swap :
  (f : Vec Bool n → Bool) (k0 s : Vec Bool n) (x : Vec Bool n) →
  plantAct f k0 s x ≡ actGen f (pointGadget k0) pointGadget s x
plantAct-swap f k0 s x = slot-swap f (pointGadget s) (pointGadget k0) x

------------------------------------------------------------------------
--  §2 Preserve recovery when replacing an oracle by a pointwise equal one.

--  ask consults only its probes, so pointwise agreement suffices. Prove
--  both directions: transport the upper bound from actGen to plantAct
--  and the lower bound in the reverse direction.
ask-ext :
  {X Y K : Set} {q : ℕ} (A : QAdversary X Y K q) (O₁ O₂ : X → Y) →
  ((x : X) → O₁ x ≡ O₂ x) → ask A O₁ ≡ ask A O₂
ask-ext A O₁ O₂ agree =
  ask-cong A (map-cong agree (QAdversary.probes A))

Recovers-ext :
  {X Y K : Set} {q : ℕ} (A : QAdversary X Y K q) (act₁ act₂ : K → X → Y) →
  ((k : K) (x : X) → act₁ k x ≡ act₂ k x) →
  Recovers A act₁ → Recovers A act₂
Recovers-ext A act₁ act₂ agree rec k =
  trans (ask-ext A (act₂ k) (act₁ k) (λ x → sym (agree k x))) (rec k)

------------------------------------------------------------------------
--  §3 State the behavioural result for the planted secret.

--  Transport ExactQuery through §1–§2: uniform exact recovery of the
--  planted secret has optimum 2ⁿ−1 queries. The adversary is fixed before
--  the secret and observes only chosen-input Boolean responses.
record BehavioralExact (f : Vec Bool n → Bool) (k0 : Vec Bool n) : Set where
  field
    opt       : QAdversary (Vec Bool n) Bool (Vec Bool n) (2 ^ n ∸ 1)
    opt-ok    : Recovers opt (plantAct f k0)
    below-all : 1 ≤ n → ∀ {r} (Adv : QAdversary (Vec Bool n) Bool (Vec Bool n) r) →
                r ≤ 2 ^ n ∸ 2 → ¬ Recovers Adv (plantAct f k0)
open BehavioralExact public

point-BehavioralExact :
  (f : Vec Bool n → Bool) (k0 : Vec Bool n) → BehavioralExact f k0
point-BehavioralExact {n} f k0 = record
  { opt       = ExactQuery.opt eq
  ; opt-ok    = Recovers-ext (ExactQuery.opt eq) _ (plantAct f k0)
                  (λ s x → sym (plantAct-swap f k0 s x))
                  (ExactQuery.opt-ok eq)
  ; below-all = λ 1≤n Adv r≤max rec →
                  ExactQuery.below-all eq 1≤n Adv r≤max
                    (Recovers-ext Adv (plantAct f k0) _
                       (λ s x → plantAct-swap f k0 s x) rec)
  }
  where
    eq : ExactQuery f (pointGadget k0)
    eq = point-ExactQuery f (pointGadget k0)

------------------------------------------------------------------------
--  §4 Read the same secret through the emitted structure.

--  Retain a prefix of known length from a concatenated list.
take-prefix : {A : Set} (xs ys : List A) → take (length xs) (xs ++ ys) ≡ xs
take-prefix []       ys = refl
take-prefix (x ∷ xs) ys = cong (x ∷_) (take-prefix xs ys)

--  Give an executable decoder: extract the emitted operation list's
--  constant payloads and retain the first m. Recovery uses neither an
--  oracle nor simulation and does not merely appeal to injectivity.
decodeConst : ℕ → List Op → List Bool
decodeConst m ops = take m (constVals ops)

--  Recover the embedded cube for all host wiring, key lists, radii,
--  feed wires, and start identifiers. lockedBlock-constVals yields
--  ksecBits ++ [true,false,true,false]; taking length ksecBits entries
--  removes exactly the four rails.
decodeConst-correct :
  (xs keys : List ℕ) (ksecBits : List Bool) (h fWire start : ℕ) →
  decodeConst (length ksecBits)
    (proj₂ (proj₂ (lockedBlock xs keys ksecBits h fWire start)))
  ≡ ksecBits
decodeConst-correct xs keys ksecBits h fWire start =
  trans (cong (take (length ksecBits))
              (lockedBlock-constVals xs keys ksecBits h fWire start))
        (take-prefix ksecBits (true ∷ false ∷ true ∷ false ∷ []))

--  Emit the secret from §3. Injectivity of toList means recovering
--  toList s identifies s itself.
decodeConst-recovers :
  (xs keys : List ℕ) (s : Vec Bool n) (h fWire start : ℕ) →
  decodeConst n (proj₂ (proj₂ (lockedBlock xs keys (toList s) h fWire start)))
  ≡ toList s
decodeConst-recovers xs keys s h fWire start =
  trans (cong (λ m → decodeConst m
                       (proj₂ (proj₂ (lockedBlock xs keys (toList s) h fWire start))))
              (sym (length-toList s)))
        (decodeConst-correct xs keys (toList s) h fWire start)

------------------------------------------------------------------------
--  §5 Separate observations of one planted secret: uniform deterministic
--  non-adaptive exact recovery from behaviour has optimum 2ⁿ−1 queries;
--  decoding this emitted representation uses none.

record ObservationSeparation
         (f : Vec Bool n → Bool) (k0 : Vec Bool n)
         (xs keys : List ℕ) (h fWire start : ℕ) : Set where
  field
    --  Behavioural side: give the exact budget and rule out every smaller one.
    behavioural : BehavioralExact f k0
    --  Structural side: decode the secret from emitted operations without
    --  oracle queries, while still paying for the scan. §7's emit-denotes-plant
    --  connects both sides to the same lock, beyond merely sharing s. It is
    --  stated separately because its environment premises are absent here.
    structural  : (s : Vec Bool n) →
                  decodeConst n
                    (proj₂ (proj₂ (lockedBlock xs keys (toList s) h fWire start)))
                  ≡ toList s
open ObservationSeparation public

point-observation-separation :
  (f : Vec Bool n → Bool) (k0 : Vec Bool n)
  (xs keys : List ℕ) (h fWire start : ℕ) →
  ObservationSeparation f k0 xs keys h fWire start
point-observation-separation f k0 xs keys h fWire start = record
  { behavioural = point-BehavioralExact f k0
  ; structural  = λ s → decodeConst-recovers xs keys s h fWire start
  }

------------------------------------------------------------------------
--  §6 Limit the conclusion. LockedNetMerged removes cube dependence
--  from constVals, but records that inverter polarity still retains the
--  secret; this does not establish fused-emitter security. The decoder
--  reads a lock block's operation list. Extraction.DecodeText composes
--  it with the certified printer/parser; Extraction.HostDisclosure handles
--  the whole host under its explicit constant-free-prefix premise.
--  The behavioural oracle answers only chosen-input outputs; it does
--  not model the stronger SAT attacker holding both a golden chip and
--  a locked netlist, so the behavioural bound is not a SAT-attack bound.

------------------------------------------------------------------------
--  §7 Connect the semantic lock and emitted operations. A shared s alone
--  would leave two unrelated facts. At radius zero, lockedBlock-locked
--  executes the block in a well-formed environment to obtain locked h
--  ksec key f x, namely (f x xor prot 0 s x) xor prot 0 k0 x. The point
--  predicate is prot 0, so this equals plantAct f k0 s x. Require the
--  emitter's existing premises: in-range data/key lists and feed wire,
--  feed value f x, and data/key readings x and k0. These are its own
--  environment conditions, not additional separation assumptions.

emit-denotes-plant :
  (xs keys : List ℕ) (x k0 s : Vec Bool n) (fWire : ℕ)
  (f : Vec Bool n → Bool) (env : List Bool) →
  AllLt (length env) xs → AllLt (length env) keys → fWire < length env →
  ReadsAs env xs (toList x) → ReadsAs env keys (toList k0) →
  get env fWire ≡ f x →
  get (runNet env (proj₂ (proj₂ (lockedBlock xs keys (toList s) 0 fWire (length env)))))
      (proj₁ (lockedBlock xs keys (toList s) 0 fWire (length env)))
  ≡ plantAct f k0 s x
emit-denotes-plant xs keys x k0 s fWire f env axs aks fw< rx rk fEq =
  lockedBlock-locked xs keys x k0 s 0 fWire f env axs aks fw< rx rk fEq

------------------------------------------------------------------------
--  §8 Use an input-indexed environment with a fixed allocation boundary.
--  A fixed environment cannot read every input. Equal lengths keep the
--  emitted operations independent of x while wire values vary with x.

record ClosedSeparation
         (f : Vec Bool n → Bool) (k0 : Vec Bool n)
         (xs keys : List ℕ) (fWire start : ℕ)
         (env : Vec Bool n → List Bool) : Set where
  field
    behavioural : BehavioralExact f k0
    structural  : (s : Vec Bool n) →
                  decodeConst n
                    (proj₂ (proj₂ (lockedBlock xs keys (toList s) 0 fWire start)))
                  ≡ toList s
    denotes     : (x s : Vec Bool n) →
                  get (runNet (env x)
                        (proj₂ (proj₂ (lockedBlock xs keys (toList s) 0 fWire start))))
                      (proj₁ (lockedBlock xs keys (toList s) 0 fWire start))
                  ≡ plantAct f k0 s x
open ClosedSeparation public

point-closed-separation :
  (f : Vec Bool n → Bool) (k0 : Vec Bool n)
  (xs keys : List ℕ) (fWire start : ℕ) (env : Vec Bool n → List Bool) →
  ((x : Vec Bool n) → length (env x) ≡ start) →
  ((x : Vec Bool n) → AllLt (length (env x)) xs) →
  ((x : Vec Bool n) → AllLt (length (env x)) keys) →
  ((x : Vec Bool n) → fWire < length (env x)) →
  ((x : Vec Bool n) → ReadsAs (env x) xs (toList x)) →
  ((x : Vec Bool n) → ReadsAs (env x) keys (toList k0)) →
  ((x : Vec Bool n) → get (env x) fWire ≡ f x) →
  ClosedSeparation f k0 xs keys fWire start env
point-closed-separation f k0 xs keys fWire start env size axs aks fw< rx rk fEq = record
  { behavioural = point-BehavioralExact f k0
  ; structural  = λ s → decodeConst-recovers xs keys s 0 fWire start
  ; denotes     = bridge
  }
  where
    bridge : (x s : Vec Bool _) →
      get (runNet (env x)
            (proj₂ (proj₂ (lockedBlock xs keys (toList s) 0 fWire start))))
          (proj₁ (lockedBlock xs keys (toList s) 0 fWire start))
      ≡ plantAct f k0 s x
    bridge x s rewrite sym (size x) =
      emit-denotes-plant xs keys x k0 s fWire f (env x)
        (axs x) (aks x) (fw< x) (rx x) (rk x) (fEq x)
