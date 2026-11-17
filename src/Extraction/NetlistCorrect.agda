------------------------------------------------------------------------
--  Close D1-B by proving the flat synthesized comparator
--  correct for all N. Netlist.popcountEqNet emits a
--  polynomial cumulative thermometer through Builder on
--  named-wire IR. Earlier D1-A refl checks covered only
--  small N; universal correctness removes that simulation-only
--  wiring boundary. Prove runNet extends environments,
--  establish a Hoare-style Builder invariant, and derive
--  the cumulative-thermometer invariant. Use no postulates.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.NetlistCorrect where

open import Data.Nat using (ℕ; zero; suc; _+_; _<_; _≤_; z≤n; s≤s; _≡ᵇ_; _<?_)
open import Data.Nat.Properties
  using (+-comm; +-assoc; +-suc; +-identityʳ; ≤-trans; ≤-refl;
         m≤m+n; m≤n+m; n<1+n; n≤1+n; suc-injective; ≮⇒≥)
open import Data.Unit using (⊤; tt)
open import Data.Bool using (Bool; true; false; not; _∧_; _∨_)
open import Data.Bool.Properties using (∧-identityʳ; ∧-zeroʳ; ∨-identityʳ)
open import Relation.Nullary using (yes; no)
open import SFLL.HammingDistance using (b2n)
open import SFLL.Netlist using (weight)
open import SFLL.Popcount using (weight-bound)
open import Data.Vec using (Vec; toList)
open import Data.List using (List; []; _∷_; _++_; length; replicate)
open import Data.List.Properties using (length-++; ++-assoc; ++-identityʳ; length-replicate)
open import Data.Product using (_×_; _,_; proj₁; proj₂; ∃)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; sym; trans; subst)

open import Extraction.NetDepthBuilder using
  (CntLaw; ret-cnt; fresh-cnt; »=-cnt; mkMux-cnt; mapMB-cnt-general; foldlMB-cnt-general)

open import Extraction.Netlist
  using (Op; oConst; oNot; oAnd; oOr; oXor; get; evalOp; runNet;
         Builder; ret; _»=_; fresh; mkConst; mkNot; mkAnd; mkMux;
         upTo; upFrom; tailL; zipL; nth; mapMB; foldlMB; stepTh; popBuilder;
         popcountEqNet; netEval)

------------------------------------------------------------------------
--  §1 Prove lookup facts for appended lists.

get-++-< : (xs ys : List Bool) (i : ℕ) → i < length xs →
           get (xs ++ ys) i ≡ get xs i
get-++-< []       ys i       ()
get-++-< (x ∷ xs) ys zero    _        = refl
get-++-< (x ∷ xs) ys (suc i) (s≤s lt) = get-++-< xs ys i lt

get-snoc-len : (xs : List Bool) (v : Bool) →
               get (xs ++ (v ∷ [])) (length xs) ≡ v
get-snoc-len []       v = refl
get-snoc-len (x ∷ xs) v = get-snoc-len xs v

------------------------------------------------------------------------
--  §2 Show runNet folds by extending its environment.

runNet-++ : (env : List Bool) (ops₁ ops₂ : List Op) →
            runNet env (ops₁ ++ ops₂) ≡ runNet (runNet env ops₁) ops₂
runNet-++ env []          ops₂ = refl
runNet-++ env (op ∷ ops₁) ops₂ =
  runNet-++ (env ++ (evalOp env op ∷ [])) ops₁ ops₂

runNet-length : (env : List Bool) (ops : List Op) →
                length (runNet env ops) ≡ length env + length ops
runNet-length env []         = sym (+-identityʳ (length env))
runNet-length env (op ∷ ops) =
  trans (runNet-length (env ++ (evalOp env op ∷ [])) ops)
        (trans (cong (_+ length ops) (length-++ env))
               (+-assoc (length env) 1 (length ops)))

runNet-mono : (env : List Bool) (ops : List Op) → length env ≤ length (runNet env ops)
runNet-mono env ops = subst (length env ≤_) (sym (runNet-length env ops))
                            (m≤m+n (length env) (length ops))

runNet-prefix : (env : List Bool) (ops : List Op) (i : ℕ) → i < length env →
                get (runNet env ops) i ≡ get env i
runNet-prefix env []         i lt = refl
runNet-prefix env (op ∷ ops) i lt =
  trans (runNet-prefix (env ++ (evalOp env op ∷ [])) ops i lt′)
        (get-++-< env (evalOp env op ∷ []) i lt)
  where
    lt′ : i < length (env ++ (evalOp env op ∷ []))
    lt′ = subst (i <_) (sym (length-++ env)) (≤-trans lt (m≤m+n (length env) 1))

------------------------------------------------------------------------
--  §3 Model Builder m by mv mapping env to a result and
--  appended values. From counter length env, it returns
--  that result, advances by appended length, and satisfies
--  runNet env ops ≡ env ++ appended-values. An explicit
--  i with length env ≡ i simplifies bind composition.

n+1≡sucn : (n : ℕ) → n + 1 ≡ suc n
n+1≡sucn n = +-comm n 1

Modelled : ∀ {A : Set} → Builder A → (List Bool → A × List Bool) → Set
Modelled {A} m mv =
  ∀ (env : List Bool) (i : ℕ) → length env ≡ i →
    (proj₁ (m i) ≡ proj₁ (mv env))
  × (runNet env (proj₂ (proj₂ (m i))) ≡ env ++ proj₂ (mv env))
  × (proj₁ (proj₂ (m i)) ≡ i + length (proj₂ (mv env)))

ret-Modelled : ∀ {A} (a : A) → Modelled (ret a) (λ env → a , [])
ret-Modelled a env i refl =
  refl , sym (++-identityʳ env) , sym (+-identityʳ (length env))

fresh-Modelled : (op : Op) →
  Modelled (fresh op) (λ env → length env , (evalOp env op ∷ []))
fresh-Modelled op env i refl =
  refl , refl , sym (n+1≡sucn (length env))

--  Compose bind models while threading the resulting environment.
»=-Modelled : ∀ {A B} (m : Builder A) (f : A → Builder B)
  (mv : List Bool → A × List Bool) (fv : A → List Bool → B × List Bool) →
  Modelled m mv → (∀ a → Modelled (f a) (fv a)) →
  Modelled (m »= f)
    (λ env → let av = mv env
                 bv = fv (proj₁ av) (env ++ proj₂ av)
             in proj₁ bv , (proj₂ av ++ proj₂ bv))
»=-Modelled m f mv fv Mm Mf env i refl
  with Mm env (length env) refl
... | (a≡ , run₁ , cnt₁)
  rewrite a≡
  with Mf (proj₁ (mv env)) (env ++ proj₂ (mv env))
          (proj₁ (proj₂ (m (length env))))
          (trans (length-++ env) (sym cnt₁))
... | (b≡ , run₂ , cnt₂) =
      b≡
    , trans (runNet-++ env (proj₂ (proj₂ (m (length env)))) _)
            (trans (cong (λ e → runNet e (proj₂ (proj₂ (f (proj₁ (mv env))
                                          (proj₁ (proj₂ (m (length env)))))))) run₁)
                   (trans run₂ (++-assoc env (proj₂ (mv env)) _)))
    , trans cnt₂
            (trans (cong (_+ length (proj₂ (fv (proj₁ (mv env)) (env ++ proj₂ (mv env))))) cnt₁)
                   (trans (+-assoc (length env) (length (proj₂ (mv env))) _)
                          (cong (length env +_)
                                (sym (length-++ (proj₂ (mv env)))))))

------------------------------------------------------------------------
--  §4a Supply the thermometer's Boolean/arithmetic core:
--  leb j c = [j ≤ c] is wire j's value at count c.
--  muxB s a b denotes mkMux, selecting b when s is true
--  and a otherwise.

leb : ℕ → ℕ → Bool             --  leb j c = [ j ≤ c ]
leb zero    _       = true
leb (suc _) zero    = false
leb (suc j) (suc c) = leb j c

--  Identify the mkMux expression (a ∧ ¬s) ∨ (b ∧ s)
--  with selection of b on true and a on false.
muxB : Bool → Bool → Bool → Bool
muxB s a b = (a ∧ not s) ∨ (b ∧ s)

muxB-false : (a b : Bool) → muxB false a b ≡ a
muxB-false a b =
  trans (cong ((a ∧ true) ∨_) (∧-zeroʳ b))
        (trans (∨-identityʳ (a ∧ true)) (∧-identityʳ a))

muxB-true : (a b : Bool) → muxB true a b ≡ b
muxB-true a b = trans (cong (_∨ (b ∧ true)) (∧-zeroʳ a)) (∧-identityʳ b)

--  At thermometer level suc m, a set bit shifts the tested level down one.
leb-mux : (s : Bool) (m c : ℕ) →
          muxB s (leb (suc m) c) (leb m c) ≡ leb (suc m) (c + b2n s)
leb-mux false m c = trans (muxB-false (leb (suc m) c) (leb m c))
                          (cong (leb (suc m)) (sym (+-identityʳ c)))
leb-mux true  m c = trans (muxB-true (leb (suc m) c) (leb m c))
                          (cong (leb (suc m)) (sym (n+1≡sucn c)))

--  Extract equality from adjacent thresholds:
--  [count ≥ h] ∧ ¬[count ≥ h+1] = [count = h].
out-eq : (h c : ℕ) → (leb h c ∧ not (leb (suc h) c)) ≡ (c ≡ᵇ h)
out-eq zero    zero    = refl
out-eq zero    (suc c) = refl
out-eq (suc h) zero    = refl
out-eq (suc h) (suc c) = out-eq h c

------------------------------------------------------------------------
--  §4b Read newly appended wires through their offsets.

--  At offset k beyond the old end, read appended value k.
get-++-+ : (xs ys : List Bool) (k : ℕ) →
           get (xs ++ ys) (length xs + k) ≡ get ys k
get-++-+ []       ys k = refl
get-++-+ (x ∷ xs) ys k = get-++-+ xs ys k

--  Put the offset first so concrete k reduces to
--  sucᵏ (length xs), matching suc i-style allocated identifiers.
get-++-+k : (xs ys : List Bool) (k : ℕ) →
            get (xs ++ ys) (k + length xs) ≡ get ys k
get-++-+k xs ys k =
  subst (λ n → get (xs ++ ys) n ≡ get ys k) (+-comm (length xs) k)
        (get-++-+ xs ys k)

--  Peel the first gate: if evalOp e o = v, runNet
--  on o ∷ ops reduces to runNet (e ++ [v]) ops.
step : (e : List Bool) (o : Op) (ops : List Op) (v : Bool) →
       evalOp e o ≡ v → runNet e (o ∷ ops) ≡ runNet (e ++ (v ∷ [])) ops
step e o ops v eq = cong (λ w → runNet (e ++ (w ∷ [])) ops) eq

open import Relation.Binary.PropositionalEquality using (module ≡-Reasoning)
open ≡-Reasoning

--  Describe mkMux execution exactly: append four values,
--  with the final wire holding muxB sel a-val b-val.
mkMux-run : (s a b : ℕ) (env : List Bool) →
            a < length env → b < length env → s < length env →
            runNet env (proj₂ (proj₂ (mkMux s a b (length env))))
              ≡ env ++ ( not (get env s)
                       ∷ (get env a ∧ not (get env s))
                       ∷ (get env b ∧ get env s)
                       ∷ muxB (get env s) (get env a) (get env b)
                       ∷ [] )
mkMux-run s a b env a< b< s< = begin
    runNet env (proj₂ (proj₂ (mkMux s a b (length env))))
  ≡⟨ step env (oNot s) (oAnd a (length env) ∷ oAnd b s ∷ o3 ∷ []) v0 refl ⟩
    runNet (env ++ (v0 ∷ [])) (oAnd a (length env) ∷ oAnd b s ∷ o3 ∷ [])
  ≡⟨ step (env ++ (v0 ∷ [])) (oAnd a (length env)) (oAnd b s ∷ o3 ∷ []) v1 eq1 ⟩
    runNet ((env ++ (v0 ∷ [])) ++ (v1 ∷ [])) (oAnd b s ∷ o3 ∷ [])
  ≡⟨ cong (λ e → runNet e (oAnd b s ∷ o3 ∷ [])) (++-assoc env (v0 ∷ []) (v1 ∷ [])) ⟩
    runNet (env ++ (v0 ∷ v1 ∷ [])) (oAnd b s ∷ o3 ∷ [])
  ≡⟨ step (env ++ (v0 ∷ v1 ∷ [])) (oAnd b s) (o3 ∷ []) v2 eq2 ⟩
    runNet ((env ++ (v0 ∷ v1 ∷ [])) ++ (v2 ∷ [])) (o3 ∷ [])
  ≡⟨ cong (λ e → runNet e (o3 ∷ [])) (++-assoc env (v0 ∷ v1 ∷ []) (v2 ∷ [])) ⟩
    runNet (env ++ (v0 ∷ v1 ∷ v2 ∷ [])) (o3 ∷ [])
  ≡⟨ step (env ++ (v0 ∷ v1 ∷ v2 ∷ [])) o3 [] v3 eq3 ⟩
    (env ++ (v0 ∷ v1 ∷ v2 ∷ [])) ++ (v3 ∷ [])
  ≡⟨ ++-assoc env (v0 ∷ v1 ∷ v2 ∷ []) (v3 ∷ []) ⟩
    env ++ (v0 ∷ v1 ∷ v2 ∷ v3 ∷ [])
  ∎
  where
    v0 = not (get env s)
    v1 = get env a ∧ not (get env s)
    v2 = get env b ∧ get env s
    v3 = muxB (get env s) (get env a) (get env b)
    o3 = oOr (suc (length env)) (suc (suc (length env)))
    eq1 : evalOp (env ++ (v0 ∷ [])) (oAnd a (length env)) ≡ v1
    eq1 = cong₂ _∧_ (get-++-< env (v0 ∷ []) a a<) (get-snoc-len env v0)
    eq2 : evalOp (env ++ (v0 ∷ v1 ∷ [])) (oAnd b s) ≡ v2
    eq2 = cong₂ _∧_ (get-++-< env (v0 ∷ v1 ∷ []) b b<)
                    (get-++-< env (v0 ∷ v1 ∷ []) s s<)
    eq3 : evalOp (env ++ (v0 ∷ v1 ∷ v2 ∷ [])) o3 ≡ v3
    eq3 = cong₂ _∨_ (get-++-+k env (v0 ∷ v1 ∷ v2 ∷ []) 1)
                    (get-++-+k env (v0 ∷ v1 ∷ v2 ∷ []) 2)

------------------------------------------------------------------------
--  §4c Keep every referenced wire below environment length.

AllLt : ℕ → List ℕ → Set
AllLt L []       = ⊤
AllLt L (x ∷ xs) = (x < L) × AllLt L xs

PairLt : ℕ → List (ℕ × ℕ) → Set
PairLt L []       = ⊤
PairLt L (p ∷ ps) = (proj₁ p < L) × (proj₂ p < L) × PairLt L ps

AllLt-mono : ∀ {L L'} → L ≤ L' → (xs : List ℕ) → AllLt L xs → AllLt L' xs
AllLt-mono le []       _        = tt
AllLt-mono le (x ∷ xs) (x< , r) = ≤-trans x< le , AllLt-mono le xs r

PairLt-mono : ∀ {L L'} → L ≤ L' → (ps : List (ℕ × ℕ)) → PairLt L ps → PairLt L' ps
PairLt-mono le []       _            = tt
PairLt-mono le (p ∷ ps) (a< , b< , r) =
  ≤-trans a< le , ≤-trans b< le , PairLt-mono le ps r

AllLt-tailL : ∀ {L} (xs : List ℕ) → AllLt L xs → AllLt L (tailL xs)
AllLt-tailL []       _       = tt
AllLt-tailL (x ∷ xs) (_ , r) = r

PairLt-zipL : ∀ {L} (as bs : List ℕ) → AllLt L as → AllLt L bs →
              PairLt L (zipL as bs)
PairLt-zipL []        bs       _        _        = tt
PairLt-zipL (a ∷ as)  []       _        _        = tt
PairLt-zipL (a ∷ as)  (b ∷ bs) (a< , ra) (b< , rb) =
  a< , b< , PairLt-zipL as bs ra rb

--  Select pair k, defaulting to (0,0).
nthP : List (ℕ × ℕ) → ℕ → ℕ × ℕ
nthP []       _       = 0 , 0
nthP (p ∷ _)  zero    = p
nthP (p ∷ ps) (suc k) = nthP ps k

nthP-PairLt : ∀ {L} (ps : List (ℕ × ℕ)) (k : ℕ) → PairLt L ps → k < length ps →
              (proj₁ (nthP ps k) < L) × (proj₂ (nthP ps k) < L)
nthP-PairLt (p ∷ ps) zero    (a< , b< , _) _        = a< , b<
nthP-PairLt (p ∷ ps) (suc k) (_ , _ , r)   (s≤s lt) = nthP-PairLt ps k r lt

nth-oor : (xs : List ℕ) (k d : ℕ) → length xs ≤ k → nth xs k d ≡ d
nth-oor []       k       d _        = refl
nth-oor (x ∷ xs) (suc k) d (s≤s le) = nth-oor xs k d le

------------------------------------------------------------------------
--  §4d Model one step's mapMB over MUXes. Starting at
--  length env, mapMB (mkMux bit …) ps appends 4·|ps|
--  wires and returns |ps| output identifiers without
--  shrinking env. Result rest[k] holds pair k's MUX
--  value read in the original environment, since all
--  input references are in range and remain stable.

mapMB-mux :
  (bit : ℕ) (ps : List (ℕ × ℕ)) (env : List Bool) (i : ℕ) → length env ≡ i →
  bit < length env → PairLt (length env) ps →
  let r    = mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps i
      rest = proj₁ r
      env' = runNet env (proj₂ (proj₂ r))
  in (length rest ≡ length ps)
   × (length env ≤ length env')
   × AllLt (length env') rest
   × ((k d : ℕ) → k < length ps →
        get env' (nth rest k d)
          ≡ muxB (get env bit) (get env (proj₁ (nthP ps k)))
                               (get env (proj₂ (nthP ps k))))
mapMB-mux bit []         env i refl bit< pl =
  refl , ≤-refl , tt , λ k d ()
mapMB-mux bit (p ∷ ps') env i refl bit< (p< , q< , prest) =
    cong suc L1
  , subst (λ E → length env ≤ length E) (sym env-eq) grows
  , subst (λ E → AllLt (length E) (y ∷ rs)) (sym env-eq) alllt
  , subst (λ E → (k d : ℕ) → k < suc (length ps') →
                 get E (nth (y ∷ rs) k d)
                   ≡ muxB (get env bit) (get env (proj₁ (nthP (p ∷ ps') k)))
                                        (get env (proj₂ (nthP (p ∷ ps') k))))
          (sym env-eq) values
  where
    --  Execute the head MUX block.
    ops1 = proj₂ (proj₂ (mkMux bit (proj₁ p) (proj₂ p) (length env)))
    vals = not (get env bit)
         ∷ (get env (proj₁ p) ∧ not (get env bit))
         ∷ (get env (proj₂ p) ∧ get env bit)
         ∷ muxB (get env bit) (get env (proj₁ p)) (get env (proj₂ p))
         ∷ []
    env₁ = runNet env ops1
    y    = proj₁ (mkMux bit (proj₁ p) (proj₂ p) (length env))   --  = suc³ (length env)
    i₁   = proj₁ (proj₂ (mkMux bit (proj₁ p) (proj₂ p) (length env)))  --  = suc⁴
    run1 : env₁ ≡ env ++ vals
    run1 = mkMux-run bit (proj₁ p) (proj₂ p) env p< q< bit<
    lenenv₁ : length env₁ ≡ i₁
    lenenv₁ = trans (runNet-length env ops1) (+-comm (length env) 4)
    --  Recurse on the remaining pairs at actual post-block state i₁.
    IH = mapMB-mux bit ps' env₁ i₁ lenenv₁
           (≤-trans bit< (subst (length env ≤_) (sym lenenv₁)
                                (m≤n+m (length env) 4)))
           (PairLt-mono (subst (length env ≤_) (sym lenenv₁)
                               (m≤n+m (length env) 4)) ps' prest)
    rs   = proj₁ (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps' i₁)
    opsX = proj₂ (proj₂ (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps' i₁))
    env' = runNet env₁ opsX
    env-eq : runNet env (proj₂ (proj₂ (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p))
                                              (p ∷ ps') (length env))))
               ≡ env'
    env-eq = trans (runNet-++ env ops1 (opsX ++ []))
                   (cong (runNet env₁) (++-identityʳ opsX))
    L1 = proj₁ IH
    L2 = proj₁ (proj₂ IH)
    L3 = proj₁ (proj₂ (proj₂ IH))
    L4 = proj₂ (proj₂ (proj₂ IH))

    env≤env₁ : length env ≤ length env₁
    env≤env₁ = subst (length env ≤_) (sym lenenv₁) (m≤n+m (length env) 4)

    grows : length env ≤ length env'
    grows = ≤-trans env≤env₁ L2

    y<env₁ : y < length env₁
    y<env₁ = subst (y <_) (sym lenenv₁) (n<1+n y)

    y<env' : y < length env'
    y<env' = ≤-trans y<env₁ L2

    alllt : (y < length env') × AllLt (length env') rs
    alllt = y<env' , L3

    --  Identify the value on head output wire y.
    val0 : get env' y ≡ muxB (get env bit) (get env (proj₁ p)) (get env (proj₂ p))
    val0 = trans (runNet-prefix env₁ opsX y y<env₁)
                 (trans (cong (λ e → get e y) run1)
                        (get-++-+k env vals 3))

    --  Transport an inherited-wire read from env₁ back to env.
    old : (w : ℕ) → w < length env → get env₁ w ≡ get env w
    old w w< = trans (cong (λ e → get e w) run1) (get-++-< env vals w w<)

    values : (k d : ℕ) → k < suc (length ps') →
             get env' (nth (y ∷ rs) k d)
               ≡ muxB (get env bit) (get env (proj₁ (nthP (p ∷ ps') k)))
                                    (get env (proj₂ (nthP (p ∷ ps') k)))
    values zero    d _        = val0
    values (suc k) d (s≤s lt) =
      trans (L4 k d lt)
            (trans (cong (λ z → muxB z (get env₁ (proj₁ (nthP ps' k)))
                                       (get env₁ (proj₂ (nthP ps' k))))
                         (old bit bit<))
                   (cong₂ (muxB (get env bit))
                          (old (proj₁ (nthP ps' k)) (proj₁ (nthP-PairLt ps' k prest lt)))
                          (old (proj₂ (nthP ps' k)) (proj₂ (nthP-PairLt ps' k prest lt)))))

------------------------------------------------------------------------
--  §4e Supply index/list facts and popcount counting helpers.

nth-tailL : (th : List ℕ) (m d : ℕ) → nth (tailL th) m d ≡ nth th (suc m) d
nth-tailL []       m d = refl
nth-tailL (x ∷ xs) m d = refl

nthP-zipL-1 : (as bs : List ℕ) (m d : ℕ) → m < length (zipL as bs) →
              proj₁ (nthP (zipL as bs) m) ≡ nth as m d
nthP-zipL-1 (a ∷ as) (b ∷ bs) zero    d _        = refl
nthP-zipL-1 (a ∷ as) (b ∷ bs) (suc m) d (s≤s lt) = nthP-zipL-1 as bs m d lt

nthP-zipL-2 : (as bs : List ℕ) (m d : ℕ) → m < length (zipL as bs) →
              proj₂ (nthP (zipL as bs) m) ≡ nth bs m d
nthP-zipL-2 (a ∷ as) (b ∷ bs) zero    d _        = refl
nthP-zipL-2 (a ∷ as) (b ∷ bs) (suc m) d (s≤s lt) = nthP-zipL-2 as bs m d lt

leb-big : (j c : ℕ) → c < j → leb j c ≡ false
leb-big (suc j) zero    _        = refl
leb-big (suc j) (suc c) (s≤s lt) = leb-big j c lt

zipL-length : (as bs : List ℕ) → length as ≤ length bs →
              length (zipL as bs) ≡ length as
zipL-length []       bs       _        = refl
zipL-length (a ∷ as) (b ∷ bs) (s≤s le) = cong suc (zipL-length as bs le)

length-tailL≤ : (th : List ℕ) → length (tailL th) ≤ length th
length-tailL≤ []       = z≤n
length-tailL≤ (x ∷ xs) = n≤1+n (length xs)

--  Count set bits on a wire list in an environment.
sumB : List Bool → List ℕ → ℕ
sumB env []       = 0
sumB env (b ∷ bs) = b2n (get env b) + sumB env bs

sumB-runNet : (env : List Bool) (ops : List Op) (bs : List ℕ) →
              AllLt (length env) bs → sumB (runNet env ops) bs ≡ sumB env bs
sumB-runNet env ops []       _        = refl
sumB-runNet env ops (b ∷ bs) (b< , r) =
  cong₂ _+_ (cong b2n (runNet-prefix env ops b b<)) (sumB-runNet env ops bs r)

--  Express popcount as a list fold and equate it with Vec weight.
weightL : List Bool → ℕ
weightL []       = 0
weightL (b ∷ bs) = b2n b + weightL bs

weight-toList : ∀ {n} (xs : Vec Bool n) → weightL (toList xs) ≡ weight xs
weight-toList Vec.[]       = refl
weight-toList (x Vec.∷ xs) = cong (b2n x +_) (weight-toList xs)

--  Shift window [s … s+k) down one index when reading after cons.
sumB-shift : (x : Bool) (rest : List Bool) (s k : ℕ) →
             sumB (x ∷ rest) (upFrom (suc s) k) ≡ sumB rest (upFrom s k)
sumB-shift x rest s zero    = refl
sumB-shift x rest s (suc k) =
  cong (b2n (get rest s) +_) (sumB-shift x rest (suc s) k)

--  Sum b2n over the first |ws| identifiers to obtain ws's popcount.
connector : (ws ext : List Bool) →
            sumB (ws ++ ext) (upFrom 0 (length ws)) ≡ weightL ws
connector []        ext = refl
connector (w ∷ ws') ext =
  cong (b2n w +_) (trans (sumB-shift w (ws' ++ ext) 0 (length ws'))
                         (connector ws' ext))

AllLt-upFrom : (s k L : ℕ) → s + k ≤ L → AllLt L (upFrom s k)
AllLt-upFrom s zero    L _  = tt
AllLt-upFrom s (suc k) L le =
  ≤-trans (s≤s (m≤m+n s k)) le′ , AllLt-upFrom (suc s) k L le′
  where
    le′ : suc (s + k) ≤ L
    le′ = subst (_≤ L) (+-suc s k) le

------------------------------------------------------------------------
--  §4f Derive the final counter/environment-length law
--  structurally from Modelled combinators, using only
--  allocation bookkeeping rather than modelled values.

--  Define CntLaw m to advance initial counter i by
--  exactly the number of emitted operations, one new wire per operation.
mapMB-cnt : (bit : ℕ) (ps : List (ℕ × ℕ)) →
            CntLaw (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps)
mapMB-cnt bit pairs =
  mapMB-cnt-general (λ pair → mkMux bit (proj₁ pair) (proj₂ pair))
                    (λ pair → mkMux-cnt bit (proj₁ pair) (proj₂ pair)) pairs

--  Equate the final fresh identifier with the resulting environment length.
mapMB-cnt≡len : (bit : ℕ) (ps : List (ℕ × ℕ)) (env : List Bool) →
  proj₁ (proj₂ (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps (length env)))
    ≡ length (runNet env (proj₂ (proj₂ (mapMB (λ p → mkMux bit (proj₁ p)
                                                            (proj₂ p)) ps (length env)))))
mapMB-cnt≡len bit ps env =
  trans (mapMB-cnt bit ps (length env))
        (sym (runNet-length env
               (proj₂ (proj₂ (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) ps (length env))))))

------------------------------------------------------------------------
--  §4g Preserve the cumulative thermometer through the bit fold.

length-tailL-eq : ∀ {N} (th : List ℕ) → length th ≡ suc N → length (tailL th) ≡ N
length-tailL-eq (x ∷ xs) eq = suc-injective eq

--  Folding stepTh over bs keeps every valid j ≤ N
--  wire equal to [count ≥ j], with count equal to c
--  plus the popcount of already processed bits.
fold-inv :
  (N trueW fW : ℕ) (bs th : List ℕ) (c : ℕ) (env : List Bool) (i : ℕ) →
  length env ≡ i →
  length th ≡ suc N →
  get env trueW ≡ true → trueW < length env →
  get env fW ≡ false → fW < length env →
  AllLt (length env) th →
  AllLt (length env) bs →
  (∀ j → j < suc N → get env (nth th j fW) ≡ leb j c) →
  let r    = foldlMB (stepTh trueW) th bs i
      th'  = proj₁ r
      env' = runNet env (proj₂ (proj₂ r))
  in (length env ≤ length env')
   × (length th' ≡ suc N)
   × AllLt (length env') th'
   × (get env' trueW ≡ true)
   × (get env' fW ≡ false)
   × (∀ j → j < suc N → get env' (nth th' j fW) ≡ leb j (c + sumB env bs))
fold-inv N trueW fW [] th c env i refl lenth tW≡ tW< fW≡ fW< allth allbs inv =
    ≤-refl , lenth , allth , tW≡ , fW≡
  , λ j j< → trans (inv j j<) (cong (leb j) (sym (+-identityʳ c)))
fold-inv N trueW fW (bit ∷ bs') th c env i refl lenth tW≡ tW< fW≡ fW<
         allth (bit< , bsrest) inv =
    ≤-trans M2 (subst (λ E → length env₁ ≤ length E) (sym env-eq-fold) IH1)
  , IH2
  , subst (λ E → AllLt (length E) th'goal) (sym env-eq-fold) IH3
  , subst (λ E → get E trueW ≡ true) (sym env-eq-fold) IH4
  , subst (λ E → get E fW ≡ false) (sym env-eq-fold) IH5
  , λ j j< →
      trans (subst (λ E → get E (nth th'goal j fW) ≡ leb j (c₁ + sumB env₁ bs'))
                   (sym env-eq-fold) (IH6 j j<))
            (cong (leb j) count-eq)
  where
    μ      = λ (p : ℕ × ℕ) → mkMux bit (proj₁ p) (proj₂ p)
    ps     = zipL (tailL th) th
    mapops = proj₂ (proj₂ (mapMB μ ps (length env)))
    env₁   = runNet env mapops
    rest   = proj₁ (mapMB μ ps (length env))
    th₁    = trueW ∷ rest
    c₁     = c + b2n (get env bit)
    i'     = proj₁ (proj₂ (mapMB μ ps (length env)))

    ps-len : length ps ≡ N
    ps-len = trans (zipL-length (tailL th) th (length-tailL≤ th))
                   (length-tailL-eq th lenth)

    M = mapMB-mux bit ps env (length env) refl bit<
                  (PairLt-zipL (tailL th) th (AllLt-tailL th allth) allth)
    M1 = proj₁ M
    M2 = proj₁ (proj₂ M)
    M3 = proj₁ (proj₂ (proj₂ M))
    M4 = proj₂ (proj₂ (proj₂ M))

    slen : length env₁ ≡ i'
    slen = sym (mapMB-cnt≡len bit ps env)

    lenth₁ : length th₁ ≡ suc N
    lenth₁ = cong suc (trans M1 ps-len)

    tW≡₁ : get env₁ trueW ≡ true
    tW≡₁ = trans (runNet-prefix env mapops trueW tW<) tW≡

    fW≡₁ : get env₁ fW ≡ false
    fW≡₁ = trans (runNet-prefix env mapops fW fW<) fW≡

    inv₁ : (j : ℕ) → j < suc N → get env₁ (nth th₁ j fW) ≡ leb j c₁
    inv₁ zero    _       = trans (runNet-prefix env mapops trueW tW<) tW≡
    inv₁ (suc m) (s≤s e) =
      trans (M4 m fW mlt)
            (trans (cong₂ (muxB (get env bit)) (cong (get env) e1) (cong (get env) e2))
                   (trans (cong₂ (muxB (get env bit)) (inv (suc m) (s≤s e))
                                 (inv m (≤-trans e (n≤1+n N))))
                          (leb-mux (get env bit) m c)))
      where
        mlt : m < length ps
        mlt = subst (m <_) (sym ps-len) e
        e1 : proj₁ (nthP ps m) ≡ nth th (suc m) fW
        e1 = trans (nthP-zipL-1 (tailL th) th m fW mlt) (nth-tailL th m fW)
        e2 : proj₂ (nthP ps m) ≡ nth th m fW
        e2 = nthP-zipL-2 (tailL th) th m fW mlt

    IH = fold-inv N trueW fW bs' th₁ c₁ env₁ i' slen lenth₁ tW≡₁
                  (≤-trans tW< M2) fW≡₁ (≤-trans fW< M2)
                  (≤-trans tW< M2 , M3) (AllLt-mono M2 bs' bsrest) inv₁
    IH1 = proj₁ IH
    IH2 = proj₁ (proj₂ IH)
    IH3 = proj₁ (proj₂ (proj₂ IH))
    IH4 = proj₁ (proj₂ (proj₂ (proj₂ IH)))
    IH5 = proj₁ (proj₂ (proj₂ (proj₂ (proj₂ IH))))
    IH6 = proj₂ (proj₂ (proj₂ (proj₂ (proj₂ IH))))

    th'goal = proj₁ (foldlMB (stepTh trueW) th₁ bs' i')
    o₂      = proj₂ (proj₂ (foldlMB (stepTh trueW) th₁ bs' i'))

    env-eq-fold :
      runNet env (proj₂ (proj₂ (foldlMB (stepTh trueW) th (bit ∷ bs') (length env))))
        ≡ runNet env₁ o₂
    env-eq-fold = trans (runNet-++ env (mapops ++ []) o₂)
                        (cong (λ e → runNet e o₂)
                              (cong (runNet env) (++-identityʳ mapops)))

    count-eq : c₁ + sumB env₁ bs' ≡ c + sumB env (bit ∷ bs')
    count-eq = trans (cong (c₁ +_) (sumB-runNet env mapops bs' bsrest))
                     (+-assoc c (b2n (get env bit)) (sumB env bs'))

------------------------------------------------------------------------
--  §4h Assemble the supporting results.

nth-replicate : (k x m d : ℕ) → m < k → nth (replicate k x) m d ≡ x
nth-replicate (suc k) x zero    d _        = refl
nth-replicate (suc k) x (suc m) d (s≤s lt) = nth-replicate k x m d lt

AllLt-replicate : (k x L : ℕ) → x < L → AllLt L (replicate k x)
AllLt-replicate zero    x L _   = tt
AllLt-replicate (suc k) x L x<L = x<L , AllLt-replicate k x L x<L

length-toList : ∀ {n} (xs : Vec Bool n) → length (toList xs) ≡ n
length-toList Vec.[]       = refl
length-toList (x Vec.∷ xs) = cong suc (length-toList xs)

--  Prove CntLaw for one step and the complete thermometer fold.
stepTh-cnt : (tw : ℕ) (th : List ℕ) (bit : ℕ) → CntLaw (stepTh tw th bit)
stepTh-cnt tw th bit =
  »=-cnt (mapMB (λ p → mkMux bit (proj₁ p) (proj₂ p)) (zipL (tailL th) th))
         (λ rest → ret (tw ∷ rest))
         (mapMB-cnt bit (zipL (tailL th) th))
         (λ rest → ret-cnt (tw ∷ rest))

foldlMB-cnt : (tw : ℕ) (th bs : List ℕ) → CntLaw (foldlMB (stepTh tw) th bs)
foldlMB-cnt trueWire accumulator bits =
  foldlMB-cnt-general (stepTh trueWire) (stepTh-cnt trueWire) accumulator bits

--  Read valid final levels by the invariant; out-of-range
--  levels use the false wire, matching false leb there.
read-th : (N fW : ℕ) (eF : List Bool) (thF : List ℕ) (w : ℕ) →
          length thF ≡ suc N → get eF fW ≡ false → w ≤ N →
          (∀ j → j < suc N → get eF (nth thF j fW) ≡ leb j w) →
          (j : ℕ) → get eF (nth thF j fW) ≡ leb j w
read-th N fW eF thF w lenthF fW≡ w≤N invF j with j <? suc N
... | yes j<   = invF j j<
... | no  j≮   =
  trans (cong (get eF) (nth-oor thF j fW (subst (_≤ j) (sym lenthF) (≮⇒≥ j≮))))
        (trans fW≡ (sym (leb-big j w (≤-trans (s≤s w≤N) (≮⇒≥ j≮)))))

------------------------------------------------------------------------
--  §4i Conclude that the synthesized flat netlist computes
--  [weight = h] for every N.

nth-AllLt : ∀ {L} (xs : List ℕ) (k d : ℕ) → AllLt L xs → d < L → nth xs k d < L
nth-AllLt []        k       d _         d< = d<
nth-AllLt (x ∷ xs)  zero    d (x< , _)  d< = x<
nth-AllLt (x ∷ xs)  (suc k) d (_  , r)  d< = nth-AllLt xs k d r d<

netEval-correct : (N h : ℕ) (xs : Vec Bool N) →
                  netEval N h xs ≡ (weight xs ≡ᵇ h)
netEval-correct N h xs = begin
    netEval N h xs
  ≡⟨⟩
    get (runNet ws (proj₂ (proj₂ (popBuilder N h N)))) (proj₁ (popBuilder N h N))
  ≡⟨ cong (λ l → get l (proj₁ (popBuilder N h N))) trace ⟩
    get (eN ++ (andVal ∷ [])) (proj₁ (popBuilder N h N))
  ≡⟨ cong (get (eN ++ (andVal ∷ []))) outId≡lenEN ⟩
    get (eN ++ (andVal ∷ [])) (length eN)
  ≡⟨ get-snoc-len eN andVal ⟩
    andVal
  ≡⟨ cong₂ _∧_ get-eN-nth get-eN-ng ⟩
    get eF (nth thF h (suc N)) ∧ not (get eF (nth thF (suc h) (suc N)))
  ≡⟨ cong₂ (λ a b → a ∧ not b) (rt h) (rt (suc h)) ⟩
    leb h (weight xs) ∧ not (leb (suc h) (weight xs))
  ≡⟨ out-eq h (weight xs) ⟩
    (weight xs ≡ᵇ h)
  ∎
  where
    ws  = toList xs
    Nws : length ws ≡ N
    Nws = length-toList xs
    e1  = ws ++ (true ∷ [])
    e2  = e1 ++ (false ∷ [])
    th0 = N ∷ replicate N (suc N)
    foldB   = foldlMB (stepTh N) th0 (upTo N) (suc (suc N))
    thF     = proj₁ foldB
    cF      = proj₁ (proj₂ foldB)
    foldOps = proj₂ (proj₂ foldB)
    eF      = runNet e2 foldOps

    len-e1 : length e1 ≡ suc N
    len-e1 = trans (length-++ ws {true ∷ []}) (trans (cong (_+ 1) Nws) (n+1≡sucn N))
    len-e2 : length e2 ≡ suc (suc N)
    len-e2 = trans (length-++ e1 {false ∷ []})
                   (trans (cong (_+ 1) len-e1) (n+1≡sucn (suc N)))
    lenth0 : length th0 ≡ suc N
    lenth0 = cong suc (length-replicate N)

    tW≡ : get e2 N ≡ true
    tW≡ = trans (get-++-< e1 (false ∷ []) N (subst (N <_) (sym len-e1) (n<1+n N)))
                (trans (cong (get e1) (sym Nws)) (get-snoc-len ws true))
    tW< : N < length e2
    tW< = subst (N <_) (sym len-e2) (s≤s (n≤1+n N))
    fW≡ : get e2 (suc N) ≡ false
    fW≡ = trans (cong (get e2) (sym len-e1)) (get-snoc-len e1 false)
    fW< : suc N < length e2
    fW< = subst (suc N <_) (sym len-e2) (n<1+n (suc N))

    allth0 : AllLt (length e2) th0
    allth0 = tW< , AllLt-replicate N (suc N) (length e2) fW<
    allbits : AllLt (length e2) (upTo N)
    allbits = AllLt-upFrom 0 N (length e2)
                (subst (N ≤_) (sym len-e2) (≤-trans (n≤1+n N) (n≤1+n (suc N))))

    inv0 : (j : ℕ) → j < suc N → get e2 (nth th0 j (suc N)) ≡ leb j 0
    inv0 zero    _       = tW≡
    inv0 (suc m) (s≤s e) =
      trans (cong (get e2) (nth-replicate N (suc N) m (suc N) e)) fW≡

    FI = fold-inv N N (suc N) (upTo N) th0 0 e2 (suc (suc N))
                  len-e2 lenth0 tW≡ tW< fW≡ fW< allth0 allbits inv0
    FI2    = proj₁ FI
    FI-len = proj₁ (proj₂ FI)
    FI-all = proj₁ (proj₂ (proj₂ FI))
    FI-fW  = proj₁ (proj₂ (proj₂ (proj₂ (proj₂ FI))))
    FI-inv = proj₂ (proj₂ (proj₂ (proj₂ (proj₂ FI))))

    count0 : 0 + sumB e2 (upTo N) ≡ weight xs
    count0 = trans (cong (λ e → sumB e (upFrom 0 N))
                         (++-assoc ws (true ∷ []) (false ∷ [])))
                   (trans (cong (λ k → sumB (ws ++ (true ∷ false ∷ [])) (upFrom 0 k))
                                (sym Nws))
                          (trans (connector ws (true ∷ false ∷ []))
                                 (weight-toList xs)))

    invW : (j : ℕ) → j < suc N → get eF (nth thF j (suc N)) ≡ leb j (weight xs)
    invW j j< = trans (FI-inv j j<) (cong (leb j) count0)

    rt : (j : ℕ) → get eF (nth thF j (suc N)) ≡ leb j (weight xs)
    rt = read-th N (suc N) eF thF (weight xs) FI-len FI-fW (weight-bound xs) invW

    leneF≡cF : length eF ≡ cF
    leneF≡cF = trans (runNet-length e2 foldOps)
                     (trans (cong (_+ length foldOps) len-e2)
                            (sym (foldlMB-cnt N th0 (upTo N) (suc (suc N)))))

    notVal : Bool
    notVal = not (get eF (nth thF (suc h) (suc N)))
    eN     = eF ++ (notVal ∷ [])
    andVal : Bool
    andVal = get eN (nth thF h (suc N)) ∧ get eN cF

    sucN<eF : suc N < length eF
    sucN<eF = ≤-trans fW< FI2

    lenEN : length eN ≡ suc cF
    lenEN = trans (length-++ eF {notVal ∷ []})
                  (trans (n+1≡sucn (length eF)) (cong suc leneF≡cF))
    outId≡lenEN : proj₁ (popBuilder N h N) ≡ length eN
    outId≡lenEN = sym lenEN

    trace : runNet ws (proj₂ (proj₂ (popBuilder N h N)))
              ≡ eN ++ (andVal ∷ [])
    trace = runNet-++ e2 foldOps
              (oNot (nth thF (suc h) (suc N)) ∷ oAnd (nth thF h (suc N)) cF ∷ [])

    get-eN-nth : get eN (nth thF h (suc N)) ≡ get eF (nth thF h (suc N))
    get-eN-nth = get-++-< eF (notVal ∷ []) (nth thF h (suc N))
                          (nth-AllLt thF h (suc N) FI-all sucN<eF)
    get-eN-ng : get eN cF ≡ not (get eF (nth thF (suc h) (suc N)))
    get-eN-ng = trans (cong (get eN) (sym leneF≡cF)) (get-snoc-len eF notVal)
