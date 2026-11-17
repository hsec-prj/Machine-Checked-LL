------------------------------------------------------------------------
--  Bit-vector Hamming distance
--  `HD xs ys` counts unequal positions in vectors of the same length.
--  SFLL-HD uses this distance to protect exactly the inputs at distance
--  `h` from key `k`; see `SFLL.HD`. The basic `HD_correct` facts proved
--  here are zero self-distance and symmetry.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module SFLL.HammingDistance where

open import Data.Nat using (ℕ; zero; suc; _+_; _≤_; z≤n; s≤s)
open import Data.Nat.Properties
  using (m+n≡0⇒m≡0; m+n≡0⇒n≡0; +-assoc; +-comm; ≤-trans; ≤-reflexive; +-mono-≤; +-commutativeSemigroup)
import Algebra.Properties.CommutativeSemigroup as CommutativeSemigroup
open import Data.Bool using (Bool; false; true; not; _xor_)
open import Data.Bool.Properties
  using (xor-same; not-distribˡ-xor; xor-assoc; xor-comm; xor-identityˡ)
open import Data.Vec using (Vec; []; _∷_; _++_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; cong; cong₂; trans; sym)

private
  variable
    n p q : ℕ

--  Convert a Boolean to its natural-number indicator, mapping `true` to 1.
b2n : Bool → ℕ
b2n false = 0
b2n true  = 1

--  Sum the per-position difference indicators: `x xor y` marks a
--  mismatch and `b2n` converts each mark to its numeric contribution.
HD : Vec Bool n → Vec Bool n → ℕ
HD []       []       = 0
HD (x ∷ xs) (y ∷ ys) = b2n (x xor y) + HD xs ys

------------------------------------------------------------------------
--  Elementary identities for HD_correct

--  Comparing a bit with itself produces the difference bit `false`.
xor-self : (x : Bool) → (x xor x) ≡ false
xor-self false = refl
xor-self true  = refl

--  A vector's distance from itself is zero.
HD-refl : (xs : Vec Bool n) → HD xs xs ≡ 0
HD-refl []       = refl
HD-refl (x ∷ xs) = cong₂ _+_ (cong b2n (xor-self x)) (HD-refl xs)

--  Swapping the two bits leaves their difference count unchanged.
b2n-xor-comm : (x y : Bool) → b2n (x xor y) ≡ b2n (y xor x)
b2n-xor-comm false false = refl
b2n-xor-comm false true  = refl
b2n-xor-comm true  false = refl
b2n-xor-comm true  true  = refl

--  Exchanging the vectors preserves Hamming distance.
HD-sym : (xs ys : Vec Bool n) → HD xs ys ≡ HD ys xs
HD-sym []       []       = refl
HD-sym (x ∷ xs) (y ∷ ys) = cong₂ _+_ (b2n-xor-comm x y) (HD-sym xs ys)

--  Zero distance characterizes vector equality, as needed when `h = 0`
--  makes protection a singleton. First, `b2n b ≡ 0` implies `b ≡ false`;
--  then a false difference bit implies that the compared bits are equal.
b2n≡0 : (b : Bool) → b2n b ≡ 0 → b ≡ false
b2n≡0 false _ = refl
b2n≡0 true  ()

xor≡false : (x y : Bool) → (x xor y) ≡ false → x ≡ y
xor≡false false false _ = refl
xor≡false false true  ()
xor≡false true  false ()
xor≡false true  true  _ = refl

HD0→≡ : (xs ys : Vec Bool n) → HD xs ys ≡ 0 → xs ≡ ys
HD0→≡ []       []       _  = refl
HD0→≡ (x ∷ xs) (y ∷ ys) eq =
  cong₂ _∷_
    (xor≡false x y (b2n≡0 (x xor y) (m+n≡0⇒m≡0 (b2n (x xor y)) eq)))
    (HD0→≡ xs ys (m+n≡0⇒n≡0 (b2n (x xor y)) eq))

------------------------------------------------------------------------
--  Parity of the distance
--  The general OCR bound uses the fact that the parities of `HD x k`
--  and `HD x k'` differ by `parity (HD k k')`, independently of `x`.
--  An odd-distance wrong key therefore gives `HD x k ≠ HD x k'` for
--  every input, since the parities differ. The protected spheres cannot intersect.

--  Encode parity modulo 2, using `true` precisely for odd values.
parity : ℕ → Bool
parity zero    = false
parity (suc n) = not (parity n)

--  The map `parity` preserves the monoid operation from `(ℕ, +)` to `(Bool, xor)`.
parity-+ : (a b : ℕ) → parity (a + b) ≡ parity a xor parity b
parity-+ zero    b = refl
parity-+ (suc a) b =
  trans (cong not (parity-+ a b)) (not-distribˡ-xor (parity a) (parity b))

parity-b2n : (c : Bool) → parity (b2n c) ≡ c
parity-b2n false = refl
parity-b2n true  = refl

--  Exchange the middle two terms in the commutative xor monoid.
xor-mid4 : (a b c d : Bool) → (a xor b) xor (c xor d) ≡ (a xor c) xor (b xor d)
xor-mid4 a b c d =
  trans (xor-assoc a b (c xor d))
        (trans (cong (a xor_)
                     (trans (sym (xor-assoc b c d))
                            (trans (cong (_xor d) (xor-comm b c)) (xor-assoc c b d))))
               (sym (xor-assoc a c (b xor d))))

--  Separate the first position in `parity ∘ HD`.
parity-HD-cons : (x₀ : Bool) (xs : Vec Bool n) (k₀ : Bool) (ks : Vec Bool n) →
                 parity (HD (x₀ ∷ xs) (k₀ ∷ ks)) ≡ (x₀ xor k₀) xor parity (HD xs ks)
parity-HD-cons x₀ xs k₀ ks =
  trans (parity-+ (b2n (x₀ xor k₀)) (HD xs ks))
        (cong (_xor parity (HD xs ks)) (parity-b2n (x₀ xor k₀)))

--  Relate the two input-to-key parities to the key-to-key parity.
HD-xor-parity : (x k k' : Vec Bool n) →
                (parity (HD x k) xor parity (HD x k')) ≡ parity (HD k k')
HD-xor-parity []        []        []         = refl
HD-xor-parity (x₀ ∷ xs) (k₀ ∷ ks) (k₀' ∷ ks') =
  trans (cong₂ _xor_ (parity-HD-cons x₀ xs k₀ ks) (parity-HD-cons x₀ xs k₀' ks'))
  (trans (xor-mid4 (x₀ xor k₀) (parity (HD xs ks)) (x₀ xor k₀') (parity (HD xs ks')))
  (trans (cong₂ _xor_
            (trans (xor-mid4 x₀ k₀ x₀ k₀')
                   (trans (cong (_xor (k₀ xor k₀')) (xor-same x₀))
                          (xor-identityˡ (k₀ xor k₀'))))
            (HD-xor-parity xs ks ks'))
         (sym (parity-HD-cons k₀ ks k₀' ks'))))

------------------------------------------------------------------------
--  Split HD across concatenated regions, for the positions where a
--  pair of keys agrees and those where it differs.

HD-++ : (xs ks : Vec Bool p) (ys ls : Vec Bool q) →
        HD (xs ++ ys) (ks ++ ls) ≡ HD xs ks + HD ys ls
HD-++ []       []       ys ls = refl
HD-++ (x ∷ xs) (k ∷ ks) ys ls =
  trans (cong (b2n (x xor k) +_) (HD-++ xs ks ys ls))
        (sym (+-assoc (b2n (x xor k)) (HD xs ks) (HD ys ls)))

------------------------------------------------------------------------
--  The triangle bound
--  The metric inequality `HD a c ≤ HD a b + HD b c` makes radius-`h`
--  spheres disjoint whenever their centres are more than `2h` apart.
--  This completes the unconditional exact OCR account: even distance
--  `2e` with `e > h` gives the disjoint count `2·C(n,h)`, because no
--  input can be at distance `h` from both keys.

--  Exchange the middle terms using the commutative monoid structure of `+`.
+-mid4 : (w x y z : ℕ) → (w + x) + (y + z) ≡ (w + y) + (x + z)
+-mid4 = CommutativeSemigroup.interchange +-commutativeSemigroup

--  Bound a one-bit difference by the sum of differences through an intermediate bit.
b2n-xor-tri : (a b c : Bool) → b2n (a xor c) ≤ b2n (a xor b) + b2n (b xor c)
b2n-xor-tri false false false = z≤n
b2n-xor-tri false false true  = s≤s z≤n
b2n-xor-tri false true  false = z≤n
b2n-xor-tri false true  true  = s≤s z≤n
b2n-xor-tri true  false false = s≤s z≤n
b2n-xor-tri true  false true  = z≤n
b2n-xor-tri true  true  false = s≤s z≤n
b2n-xor-tri true  true  true  = z≤n

--  Sum the single-bit bounds to prove the Hamming-distance triangle inequality.
HD-triangle : (xs ys zs : Vec Bool n) → HD xs zs ≤ HD xs ys + HD ys zs
HD-triangle []       []       []       = z≤n
HD-triangle (x ∷ xs) (y ∷ ys) (z ∷ zs) =
  ≤-trans (+-mono-≤ (b2n-xor-tri x y z) (HD-triangle xs ys zs))
          (≤-reflexive (+-mid4 (b2n (x xor y)) (b2n (y xor z)) (HD xs ys) (HD ys zs)))
