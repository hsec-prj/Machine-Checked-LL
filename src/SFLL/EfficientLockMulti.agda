------------------------------------------------------------------------
--  Verify SFLL-HD locking on multi-output hosts. EfficientLock handles
--  Circuit n 1; importMulti supplies a Circuit n k on a shared bus.
--  Lock a designated
--  j : Fin k while preserving k-1 outputs, with
--  correctness proved inside Agda instead of reconnecting
--  outputs externally. Host-independent δ = prot ksec
--  xor prot kapp yields updateAt (F x) j
--  (λ v → (v xor prot ksec x) xor prot kapp x).
--  Reuse tripleAll and two polynomial prot-circuit-eff
--  comparators. The new combine layer routes output j
--  and the protection bits into xor3, then projects
--  the locked bit at j and original wires elsewhere.
--  Polynomial popcount keeps the verified circuit
--  synthesizable. Introduce no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.EfficientLockMulti where

open import Data.Nat using (ℕ; zero; suc; _+_)
open import Data.Fin using (Fin; toℕ; _↑ˡ_; _↑ʳ_) renaming (zero to fz; suc to fs)
open import Data.Fin.Properties using (_≟_)
open import Data.Bool using (Bool; true; false; _xor_; _∧_)
open import Data.Bool.Properties using (xor-identityʳ)
open import Data.Vec using (Vec; []; _∷_; _++_; map; lookup; tabulate; allFin; updateAt)
open import Data.Vec.Properties using
  (lookup∘updateAt; lookup∘updateAt′; lookup-++ˡ; lookup-++ʳ;
   map-lookup-allFin; tabulate∘lookup; lookup∘tabulate; tabulate-cong; map-++)
open import Relation.Nullary using (Dec; yes; no)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import Circuit.Core using (Circuit; Id; Xor2; Seq; Par; Plug)
open import Circuit.Semantics using (⟦_⟧)
open import Circuit.Util.Vec using (take-++; drop-++)
open import SFLL.HD using (prot; locked)
open import SFLL.Netlist using (xor3; xor3-spec; tripleAll; tripleAll-spec; dupAll; dupAll-spec)
open import SFLL.EfficientLock using (prot-circuit-eff; prot-circuit-eff-correct)
open import Locking.NetlistToCircuit using (tab-map)

private
  variable
    n k : ℕ

------------------------------------------------------------------------
--  Specify locking at output j of F while passing other outputs through.

lockedVec : (j : Fin k) (h : ℕ) (ksec kapp : Vec Bool n)
            (F : Vec Bool n → Vec Bool k) → Vec Bool n → Vec Bool k
lockedVec j h ksec kapp F x =
  updateAt (F x) j (λ v → (v xor prot h ksec x) xor prot h kapp x)

--  Identify slot j as the locked SFLL-HD cone and
--  all other slots as unchanged host outputs.
lockedVec-prot : (j : Fin k) (h : ℕ) (ksec kapp : Vec Bool n)
                 (F : Vec Bool n → Vec Bool k) (x : Vec Bool n) →
                 lookup (lockedVec j h ksec kapp F x) j
                 ≡ locked h ksec kapp (λ y → lookup (F y) j) x
lockedVec-prot j h ksec kapp F x = lookup∘updateAt j (F x)

lockedVec-pass : (j : Fin k) (h : ℕ) (ksec kapp : Vec Bool n)
                 (F : Vec Bool n → Vec Bool k) (x : Vec Bool n)
                 {i : Fin k} → i ≢ j →
                 lookup (lockedVec j h ksec kapp F x) i ≡ lookup (F x) i
lockedVec-pass j h ksec kapp F x {i} i≢j = lookup∘updateAt′ i j i≢j (F x)

------------------------------------------------------------------------
--  Build combine j : Circuit (k+2) k on B =
--  F x ++ [psec,papp]. g0route produces Bⱼ,psec,papp,B
--  at width 3+(k+2); Par xor3 Id reduces the front
--  three to lockedbit,B at width suc(k+2); g1route
--  projects the updated k-output vector.

g0route : (j : Fin k) → Vec (Fin (k + 2)) (3 + (k + 2))
g0route {k} j = (j ↑ˡ 2) ∷ (k ↑ʳ fz) ∷ (k ↑ʳ fs fz) ∷ allFin (k + 2)

--  Pass an explicit p ≟ j decision to projection
--  so correctness does not depend on with-abstraction reducing.
g1aux : (p j : Fin k) → Dec (p ≡ j) → Fin (suc (k + 2))
g1aux p j (yes _) = fz
g1aux p j (no  _) = fs (p ↑ˡ 2)

g1route : (j : Fin k) → Fin k → Fin (suc (k + 2))
g1route j p = g1aux p j (p ≟ j)

combine : (j : Fin k) → Circuit (k + 2) k
combine {k} j =
  Seq (Plug (lookup (g0route j)))
      (Seq (Par {n₁ = 3} xor3 (Id {k + 2}))
           (Plug (g1route j)))

------------------------------------------------------------------------
--  Verify the output-combination layer.

combine-correct : (j : Fin k) (bus : Vec Bool k) (ps pp : Bool) →
  ⟦ combine j ⟧ (bus ++ (ps ∷ pp ∷ []))
  ≡ updateAt bus j (λ v → (v xor ps) xor pp)
combine-correct {k} j bus ps pp =
  trans (cong (λ z → ⟦ Plug (g1route j) ⟧ (⟦ Par {n₁ = 3} xor3 (Id {k + 2}) ⟧ z)) g0step)
        (trans (cong ⟦ Plug (g1route j) ⟧ parstep) g1step)
  where
    B : Vec Bool (k + 2)
    B = bus ++ (ps ∷ pp ∷ [])
    lb : Bool
    lb = (lookup bus j xor ps) xor pp

    --  Stage one: copy Bⱼ,psec,papp to the front and retain B.
    g0step : ⟦ Plug (lookup (g0route j)) ⟧ B ≡ lookup bus j ∷ ps ∷ pp ∷ B
    g0step =
      trans (tab-map (lookup B) (g0route j))
            (cong₂ _∷_ (lookup-++ˡ bus (ps ∷ pp ∷ []) j)
              (cong₂ _∷_ (lookup-++ʳ bus (ps ∷ pp ∷ []) fz)
                (cong₂ _∷_ (lookup-++ʳ bus (ps ∷ pp ∷ []) (fs fz))
                  (map-lookup-allFin B))))

    --  Stage two: combine the front three with xor3 and preserve B.
    parstep : ⟦ Par {n₁ = 3} xor3 (Id {k + 2}) ⟧ (lookup bus j ∷ ps ∷ pp ∷ B)
              ≡ lb ∷ B
    parstep = cong₂ _++_
      (trans (cong ⟦ xor3 ⟧ (take-++ (lookup bus j ∷ ps ∷ pp ∷ []) B))
             (xor3-spec (lookup bus j) ps pp))
      (drop-++ (lookup bus j ∷ ps ∷ pp ∷ []) B)

    --  Stage three: select lockedbit for j and original bus i elsewhere.
    perPoint : (p : Fin k) →
               lookup (lb ∷ B) (g1route j p)
               ≡ lookup (updateAt bus j (λ v → (v xor ps) xor pp)) p
    perPoint p = go p (p ≟ j)
      where
        go : (p : Fin k) (d : Dec (p ≡ j)) →
             lookup (lb ∷ B) (g1aux p j d)
             ≡ lookup (updateAt bus j (λ v → (v xor ps) xor pp)) p
        go p (yes e) = sym (trans (cong (lookup (updateAt bus j (λ v → (v xor ps) xor pp))) e)
                                  (lookup∘updateAt j bus))
        go p (no ¬e) = trans (lookup-++ˡ bus (ps ∷ pp ∷ []) p)
                             (sym (lookup∘updateAt′ p j ¬e bus))

    g1step : ⟦ Plug (g1route j) ⟧ (lb ∷ B)
             ≡ updateAt bus j (λ v → (v xor ps) xor pp)
    g1step = trans (tabulate-cong perPoint)
                   (tabulate∘lookup (updateAt bus j (λ v → (v xor ps) xor pp)))

------------------------------------------------------------------------
--  Compose the single-output efficient front end with
--  combine j to produce the multi-output lock.

locked-multi : (CF : Circuit n k) (j : Fin k) (hF : Fin (suc n))
               (ksec kapp : Vec Bool n) → Circuit n k
locked-multi {n} CF j hF ksec kapp =
  Seq (tripleAll n)
      (Seq (Par {n₁ = n} CF
              (Par {n₁ = n} (prot-circuit-eff hF ksec) (prot-circuit-eff hF kapp)))
           (combine j))

--  For arbitrary output width k, prove slot j denotes
--  the locked cone and every other output passes through.
locked-multi-correct :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (j : Fin k) (hF : Fin (suc n)) (ksec kapp x : Vec Bool n) →
  ⟦ locked-multi CF j hF ksec kapp ⟧ x ≡ lockedVec j (toℕ hF) ksec kapp F x
locked-multi-correct {n} CF F cf-ok j hF ksec kapp x =
  trans (cong (λ w → ⟦ combine j ⟧ (⟦ mid ⟧ w)) (tripleAll-spec n x))
        (trans (cong ⟦ combine j ⟧ stepM)
               (combine-correct j (F x) (prot (toℕ hF) ksec x) (prot (toℕ hF) kapp x)))
  where
    mid = Par {n₁ = n} CF
            (Par {n₁ = n} (prot-circuit-eff hF ksec) (prot-circuit-eff hF kapp))
    stepM : ⟦ mid ⟧ (x ++ (x ++ x))
              ≡ F x ++ (prot (toℕ hF) ksec x ∷ prot (toℕ hF) kapp x ∷ [])
    stepM = cong₂ _++_
      (trans (cong ⟦ CF ⟧ (take-++ x (x ++ x))) (cf-ok x))
      (trans (cong ⟦ Par {n₁ = n} (prot-circuit-eff hF ksec)
                          (prot-circuit-eff hF kapp) ⟧
                   (drop-++ x (x ++ x)))
             (cong₂ _++_
               (trans (cong ⟦ prot-circuit-eff hF ksec ⟧ (take-++ x x))
                      (prot-circuit-eff-correct hF ksec x))
               (trans (cong ⟦ prot-circuit-eff hF kapp ⟧ (drop-++ x x))
                      (prot-circuit-eff-correct hF kapp x))))

------------------------------------------------------------------------
--  Extend to every P-selected output with a shared key
--  cube, implementing MultiOCR.lockedSet. Compute δ once
--  and broadcast it: protected outputs use Xor2 on
--  [v,δ], while unprotected ones project v. The
--  certified construction thus supports arbitrary chosen sets.

private
  --  Keep the structural map-over-tabulate lemma local.
  map-tab : ∀ {A B : Set} {m} (f : A → B) (g : Fin m → A) →
            map f (tabulate g) ≡ tabulate (λ i → f (g i))
  map-tab {m = zero}  f g = refl
  map-tab {m = suc m} f g = cong (f (g fz) ∷_) (map-tab f (λ i → g (fs i)))

--  On [v,δ], XOR for protected outputs and return v otherwise.
hgad : Bool → Circuit 2 1
hgad true  = Xor2
hgad false = Plug (λ _ → fz)

hgad-correct : (b v d : Bool) → ⟦ hgad b ⟧ (v ∷ d ∷ []) ≡ (v xor (b ∧ d)) ∷ []
hgad-correct true  v d = refl
hgad-correct false v d = cong (_∷ []) (sym (xor-identityʳ v))

--  Broadcast head δ through the bus using the step
--  δ,v₀,rest ↦ v₀,δ,(δ,rest), applying each output's gadget.
bcRoute : (k : ℕ) → Vec (Fin (suc (suc k))) (suc (suc (suc k)))
bcRoute k = fs fz ∷ fz ∷ fz ∷ tabulate (λ j → fs (fs j))

bcastXor : (k : ℕ) (P : Fin k → Bool) → Circuit (suc k) k
bcastXor zero    P = Plug (λ ())
bcastXor (suc k) P =
  Seq (Plug (lookup (bcRoute k)))
      (Par {n₁ = 2} (hgad (P fz)) (bcastXor k (λ i → P (fs i))))

bcastXor-correct :
  (k : ℕ) (P : Fin k → Bool) (d : Bool) (v : Vec Bool k) →
  ⟦ bcastXor k P ⟧ (d ∷ v) ≡ tabulate (λ i → lookup v i xor (P i ∧ d))
bcastXor-correct zero    P d []         = refl
bcastXor-correct (suc k) P d (v₀ ∷ rest) =
  trans (cong ⟦ Par {n₁ = 2} (hgad (P fz)) (bcastXor k (λ i → P (fs i))) ⟧ routeEq)
        parEq
  where
    routeEq : ⟦ Plug (lookup (bcRoute k)) ⟧ (d ∷ v₀ ∷ rest) ≡ v₀ ∷ d ∷ d ∷ rest
    routeEq =
      trans (tab-map (lookup (d ∷ v₀ ∷ rest)) (bcRoute k))
            (cong (λ z → v₀ ∷ d ∷ d ∷ z)
                  (trans (map-tab (lookup (d ∷ v₀ ∷ rest)) (λ j → fs (fs j)))
                         (tabulate∘lookup rest)))
    parEq : ⟦ Par {n₁ = 2} (hgad (P fz)) (bcastXor k (λ i → P (fs i))) ⟧
              (v₀ ∷ d ∷ d ∷ rest)
            ≡ tabulate (λ i → lookup (v₀ ∷ rest) i xor (P i ∧ d))
    parEq = cong₂ _++_
      (trans (cong ⟦ hgad (P fz) ⟧ (take-++ (v₀ ∷ d ∷ []) (d ∷ rest)))
             (hgad-correct (P fz) v₀ d))
      (trans (cong ⟦ bcastXor k (λ i → P (fs i)) ⟧ (drop-++ (v₀ ∷ d ∷ []) (d ∷ rest)))
             (bcastXor-correct k (λ i → P (fs i)) d rest))

--  Combine protection bits into δ, then broadcast
--  its XOR across the protected output positions.
dsRoute : (k : ℕ) → Vec (Fin (k + 2)) (2 + k)
dsRoute k = (k ↑ʳ fz) ∷ (k ↑ʳ fs fz) ∷ tabulate (λ i → i ↑ˡ 2)

combineSet : (P : Fin k → Bool) → Circuit (k + 2) k
combineSet {k} P =
  Seq (Seq (Plug (lookup (dsRoute k))) (Par {n₁ = 2} Xor2 (Id {k})))
      (bcastXor k P)

combineSet-correct :
  (P : Fin k → Bool) (bus : Vec Bool k) (ps pp : Bool) →
  ⟦ combineSet P ⟧ (bus ++ (ps ∷ pp ∷ []))
  ≡ tabulate (λ i → lookup bus i xor (P i ∧ (ps xor pp)))
combineSet-correct {k} P bus ps pp =
  trans (cong (λ z → ⟦ bcastXor k P ⟧ (⟦ Par {n₁ = 2} Xor2 (Id {k}) ⟧ z)) dsStep)
        (trans (cong ⟦ bcastXor k P ⟧ parStep)
               (bcastXor-correct k P (ps xor pp) bus))
  where
    B : Vec Bool (k + 2)
    B = bus ++ (ps ∷ pp ∷ [])
    dsStep : ⟦ Plug (lookup (dsRoute k)) ⟧ B ≡ ps ∷ pp ∷ bus
    dsStep =
      trans (tab-map (lookup B) (dsRoute k))
            (cong₂ _∷_ (lookup-++ʳ bus (ps ∷ pp ∷ []) fz)
              (cong₂ _∷_ (lookup-++ʳ bus (ps ∷ pp ∷ []) (fs fz))
                (trans (map-tab (lookup B) (λ i → i ↑ˡ 2))
                       (trans (tabulate-cong (λ i → lookup-++ˡ bus (ps ∷ pp ∷ []) i))
                              (tabulate∘lookup bus)))))
    parStep : ⟦ Par {n₁ = 2} Xor2 (Id {k}) ⟧ (ps ∷ pp ∷ bus) ≡ (ps xor pp) ∷ bus
    parStep = cong₂ _++_ (cong ⟦ Xor2 ⟧ (take-++ (ps ∷ pp ∷ []) bus))
                         (cong ⟦ Id {k} ⟧ (drop-++ (ps ∷ pp ∷ []) bus))

--  Use the locked-multi front end with combineSet
--  broadcasting in place of designated-output combine.
locked-multi-set : (CF : Circuit n k) (P : Fin k → Bool) (hF : Fin (suc n))
                   (ksec kapp : Vec Bool n) → Circuit n k
locked-multi-set {n} CF P hF ksec kapp =
  Seq (tripleAll n)
      (Seq (Par {n₁ = n} CF
              (Par {n₁ = n} (prot-circuit-eff hF ksec) (prot-circuit-eff hF kapp)))
           (combineSet P))

--  Prove the circuit denotes lockedSet: selected
--  outputs flip by shared δ and others remain unchanged.
locked-multi-set-correct :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (P : Fin k → Bool) (hF : Fin (suc n)) (ksec kapp x : Vec Bool n) →
  ⟦ locked-multi-set CF P hF ksec kapp ⟧ x
  ≡ tabulate (λ i → lookup (F x) i
                    xor (P i ∧ (prot (toℕ hF) ksec x xor prot (toℕ hF) kapp x)))
locked-multi-set-correct {n} CF F cf-ok P hF ksec kapp x =
  trans (cong (λ w → ⟦ combineSet P ⟧ (⟦ mid ⟧ w)) (tripleAll-spec n x))
        (trans (cong ⟦ combineSet P ⟧ stepM)
               (combineSet-correct P (F x) (prot (toℕ hF) ksec x) (prot (toℕ hF) kapp x)))
  where
    mid = Par {n₁ = n} CF
            (Par {n₁ = n} (prot-circuit-eff hF ksec) (prot-circuit-eff hF kapp))
    stepM : ⟦ mid ⟧ (x ++ (x ++ x))
              ≡ F x ++ (prot (toℕ hF) ksec x ∷ prot (toℕ hF) kapp x ∷ [])
    stepM = cong₂ _++_
      (trans (cong ⟦ CF ⟧ (take-++ x (x ++ x))) (cf-ok x))
      (trans (cong ⟦ Par {n₁ = n} (prot-circuit-eff hF ksec)
                          (prot-circuit-eff hF kapp) ⟧
                   (drop-++ x (x ++ x)))
             (cong₂ _++_
               (trans (cong ⟦ prot-circuit-eff hF ksec ⟧ (take-++ x x))
                      (prot-circuit-eff-correct hF ksec x))
               (trans (cong ⟦ prot-circuit-eff hF kapp ⟧ (drop-++ x x))
                      (prot-circuit-eff-correct hF kapp x))))

------------------------------------------------------------------------
--  Implement MultiOCR.lockedSetK with separate output
--  keys. Unlike combineSet's shared broadcast, compute
--  one δᵢ per output. corrCirc uses two polynomial
--  comparators and Xor2 for one perturbation; corrVec
--  places k cones side by side; combineK folds δᵢ
--  into output i exactly when P i. All are certified
--  inside Agda. This supplies the circuit needed to
--  apply the existing mocr-setK-char/bound specification
--  results to the actual netlist through
--  mocr-locked-multi-setK-bound.

--  Compute one output's prot ksec x xor prot kapp x
--  perturbation on a single wire.
corrCirc : (h : Fin (suc n)) (ksec kapp : Vec Bool n) → Circuit n 1
corrCirc {n} h ksec kapp =
  Seq (dupAll n)
      (Seq (Par {n₁ = n} (prot-circuit-eff h ksec) (prot-circuit-eff h kapp)) Xor2)

corrCirc-correct : (h : Fin (suc n)) (ksec kapp x : Vec Bool n) →
  ⟦ corrCirc h ksec kapp ⟧ x
  ≡ (prot (toℕ h) ksec x xor prot (toℕ h) kapp x) ∷ []
corrCirc-correct {n} h ksec kapp x =
  trans (cong (λ w → ⟦ Seq (Par {n₁ = n} (prot-circuit-eff h ksec)
                                          (prot-circuit-eff h kapp)) Xor2 ⟧ w)
              (dupAll-spec n x))
        (cong ⟦ Xor2 ⟧ parstep)
  where
    parstep : ⟦ Par {n₁ = n} (prot-circuit-eff h ksec) (prot-circuit-eff h kapp) ⟧ (x ++ x)
              ≡ prot (toℕ h) ksec x ∷ prot (toℕ h) kapp x ∷ []
    parstep = cong₂ _++_
      (trans (cong ⟦ prot-circuit-eff h ksec ⟧ (take-++ x x))
             (prot-circuit-eff-correct h ksec x))
      (trans (cong ⟦ prot-circuit-eff h kapp ⟧ (drop-++ x x))
             (prot-circuit-eff-correct h kapp x))

--  Place k independent perturbation cones alongside
--  one another, using each output's own keys.
corrVec : (hsf : Fin k → Fin (suc n)) (ksecs kapps : Fin k → Vec Bool n)
          → Circuit n k
corrVec {k = zero}        hsf ksecs kapps = Plug (λ ())
corrVec {k = suc k} {n = n} hsf ksecs kapps =
  Seq (dupAll n)
      (Par {n₁ = n} (corrCirc (hsf fz) (ksecs fz) (kapps fz))
                    (corrVec (λ i → hsf (fs i)) (λ i → ksecs (fs i)) (λ i → kapps (fs i))))

corrVec-correct : (hsf : Fin k → Fin (suc n)) (ksecs kapps : Fin k → Vec Bool n)
                  (x : Vec Bool n) →
  ⟦ corrVec hsf ksecs kapps ⟧ x
  ≡ tabulate (λ i → prot (toℕ (hsf i)) (ksecs i) x xor prot (toℕ (hsf i)) (kapps i) x)
corrVec-correct {k = zero}        hsf ksecs kapps x = refl
corrVec-correct {k = suc k} {n = n} hsf ksecs kapps x =
  trans (cong (λ w → ⟦ Par {n₁ = n} (corrCirc (hsf fz) (ksecs fz) (kapps fz))
                            (corrVec (λ i → hsf (fs i)) (λ i → ksecs (fs i))
                                     (λ i → kapps (fs i))) ⟧ w)
              (dupAll-spec n x))
        (cong₂ _++_
          (trans (cong ⟦ corrCirc (hsf fz) (ksecs fz) (kapps fz) ⟧ (take-++ x x))
                 (corrCirc-correct (hsf fz) (ksecs fz) (kapps fz) x))
          (trans (cong ⟦ corrVec (λ i → hsf (fs i)) (λ i → ksecs (fs i))
                              (λ i → kapps (fs i)) ⟧ (drop-++ x x))
                 (corrVec-correct (λ i → hsf (fs i)) (λ i → ksecs (fs i))
                                  (λ i → kapps (fs i)) x)))

--  Interleave the head bus bit and its δ:
--  (b₀,bus′) ++ (d₀,δ′) becomes b₀,d₀,(bus′ ++ δ′),
--  ready for the two-input gadget.
zipRoute : (k : ℕ) → Vec (Fin (suc k + suc k)) (suc (suc (k + k)))
zipRoute k = (fz ↑ˡ suc k) ∷ (suc k ↑ʳ fz)
           ∷ (tabulate (λ i → (fs i) ↑ˡ suc k) ++ tabulate (λ j → suc k ↑ʳ (fs j)))

--  Combine bus ++ δvec pairwise so output i is
--  bus i xor (P i ∧ δvec i), without broadcasting.
combineK : (P : Fin k → Bool) → Circuit (k + k) k
combineK {k = zero}  P = Plug (λ ())
combineK {k = suc k} P =
  Seq (Plug (lookup (zipRoute k)))
      (Par {n₁ = 2} (hgad (P fz)) (combineK (λ i → P (fs i))))

combineK-correct : (P : Fin k → Bool) (bus δvec : Vec Bool k) →
  ⟦ combineK P ⟧ (bus ++ δvec)
  ≡ tabulate (λ i → lookup bus i xor (P i ∧ lookup δvec i))
combineK-correct {k = zero}  P [] [] = refl
combineK-correct {k = suc k} P (b₀ ∷ bus′) (d₀ ∷ δ′) =
  trans (cong ⟦ Par {n₁ = 2} (hgad (P fz)) (combineK (λ i → P (fs i))) ⟧ routeEq)
        parEq
  where
    bus  : Vec Bool (suc k)
    bus  = b₀ ∷ bus′
    δvec : Vec Bool (suc k)
    δvec = d₀ ∷ δ′
    inp  : Vec Bool (suc k + suc k)
    inp  = bus ++ δvec
    routeEq : ⟦ Plug (lookup (zipRoute k)) ⟧ inp ≡ b₀ ∷ d₀ ∷ (bus′ ++ δ′)
    routeEq =
      trans (tab-map (lookup inp) (zipRoute k))
            (cong₂ _∷_ (lookup-++ˡ bus δvec fz)
              (cong₂ _∷_ (lookup-++ʳ bus δvec fz)
                (trans (map-++ (lookup inp) (tabulate (λ i → (fs i) ↑ˡ suc k))
                                            (tabulate (λ j → suc k ↑ʳ (fs j))))
                       (cong₂ _++_
                         (trans (map-tab (lookup inp) (λ i → (fs i) ↑ˡ suc k))
                                (trans (tabulate-cong (λ i → lookup-++ˡ bus δvec (fs i)))
                                       (tabulate∘lookup bus′)))
                         (trans (map-tab (lookup inp) (λ j → suc k ↑ʳ (fs j)))
                                (trans (tabulate-cong (λ j → lookup-++ʳ bus δvec (fs j)))
                                       (tabulate∘lookup δ′)))))))
    parEq : ⟦ Par {n₁ = 2} (hgad (P fz)) (combineK (λ i → P (fs i))) ⟧
              (b₀ ∷ d₀ ∷ (bus′ ++ δ′))
            ≡ tabulate (λ i → lookup bus i xor (P i ∧ lookup δvec i))
    parEq = cong₂ _++_
      (trans (cong ⟦ hgad (P fz) ⟧ (take-++ (b₀ ∷ d₀ ∷ []) (bus′ ++ δ′)))
             (hgad-correct (P fz) b₀ d₀))
      (trans (cong ⟦ combineK (λ i → P (fs i)) ⟧ (drop-++ (b₀ ∷ d₀ ∷ []) (bus′ ++ δ′)))
             (combineK-correct (λ i → P (fs i)) bus′ δ′))

------------------------------------------------------------------------
--  Fan out x, run the host beside k independent
--  δ cones, and combine their outputs with combineK.

locked-multi-setK : (CF : Circuit n k) (P : Fin k → Bool)
                    (hsf : Fin k → Fin (suc n)) (ksecs kapps : Fin k → Vec Bool n)
                    → Circuit n k
locked-multi-setK {n} CF P hsf ksecs kapps =
  Seq (dupAll n)
      (Seq (Par {n₁ = n} CF (corrVec hsf ksecs kapps))
           (combineK P))

--  Prove the circuit denotes lockedSetK at hs = toℕ ∘ hsf.
--  Each selected i flips by its own prot ksecsᵢ ⊕
--  prot kappsᵢ, preserving unselected outputs, for
--  every output width and per-output key assignment.
locked-multi-setK-correct :
  (CF : Circuit n k) (F : Vec Bool n → Vec Bool k)
  (cf-ok : (x : Vec Bool n) → ⟦ CF ⟧ x ≡ F x)
  (P : Fin k → Bool) (hsf : Fin k → Fin (suc n))
  (ksecs kapps : Fin k → Vec Bool n) (x : Vec Bool n) →
  ⟦ locked-multi-setK CF P hsf ksecs kapps ⟧ x
  ≡ tabulate (λ i → lookup (F x) i
        xor (P i ∧ (prot (toℕ (hsf i)) (ksecs i) x xor prot (toℕ (hsf i)) (kapps i) x)))
locked-multi-setK-correct {n} {k} CF F cf-ok P hsf ksecs kapps x =
  trans (cong (λ w → ⟦ Seq (Par {n₁ = n} CF (corrVec hsf ksecs kapps)) (combineK P) ⟧ w)
              (dupAll-spec n x))
        (trans (cong ⟦ combineK P ⟧ midStep)
               (trans (combineK-correct P (F x) δv) final))
  where
    δv : Vec Bool k
    δv = tabulate (λ i → prot (toℕ (hsf i)) (ksecs i) x xor prot (toℕ (hsf i)) (kapps i) x)
    midStep : ⟦ Par {n₁ = n} CF (corrVec hsf ksecs kapps) ⟧ (x ++ x) ≡ F x ++ δv
    midStep = cong₂ _++_
      (trans (cong ⟦ CF ⟧ (take-++ x x)) (cf-ok x))
      (trans (cong ⟦ corrVec hsf ksecs kapps ⟧ (drop-++ x x))
             (corrVec-correct hsf ksecs kapps x))
    final : tabulate (λ i → lookup (F x) i xor (P i ∧ lookup δv i))
            ≡ tabulate (λ i → lookup (F x) i
                  xor (P i ∧ (prot (toℕ (hsf i)) (ksecs i) x xor prot (toℕ (hsf i)) (kapps i) x)))
    final = tabulate-cong (λ i →
              cong (λ d → lookup (F x) i xor (P i ∧ d))
                   (lookup∘tabulate
                     (λ j → prot (toℕ (hsf j)) (ksecs j) x xor prot (toℕ (hsf j)) (kapps j) x) i))
