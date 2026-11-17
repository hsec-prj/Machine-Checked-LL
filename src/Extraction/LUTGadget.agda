------------------------------------------------------------------------
--  Verify gadgets for two-input LUTs (D6, input side).
--  experiments/gen_netlist_data.py parses a real host's .bench file, extracts
--  an output cone, and uses the hand-written Python GAD table to map each
--  four-bit LUT truth table to a Circuit 2 1 gadget. Its semantic claim that
--  a table denotes a given circuit has been trusted. Here lutCircuit moves
--  that claim into Agda: Fin 14 → Circuit 2 1 covers the 14 non-constant
--  two-input Boolean functions. Code k corresponds to truth table k+1; bit i
--  gives the result for (a,b), with i = a + 2·b. Constant tables 0 and 15 are
--  excluded from this enumeration. These gadgets emit no constant nodes;
--  this does not exclude semantically constant circuits in the DSL.
--  Python's GAD likewise covers only 0x1..0xe. The independent
--  Boolean specification lutFun and proof lutCircuit-correct establish each
--  gadget's meaning. An importer can consequently emit truth-table codes
--  and use verified decoding instead of the trusted GAD table. No postulates
--  are required.
------------------------------------------------------------------------

{-# OPTIONS --safe --without-K #-}

module Extraction.LUTGadget where

open import Data.Fin using (Fin; zero; suc)
open import Data.Bool using (Bool; not; _∧_; _∨_; _xor_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import Circuit.Core using (Circuit; Id; Not1; And2; Or2; Xor2; Seq; Par; Plug)
open import Circuit.Semantics using (⟦_⟧)

------------------------------------------------------------------------
--  Section 1: define projections and gadgets for all non-constant truth tables.

projA projB : Circuit 2 1
projA = Plug (λ _ → zero)         --  a
projB = Plug (λ _ → suc zero)     --  b

lutCircuit : Fin 14 → Circuit 2 1
lutCircuit zero                                              = Seq Or2 Not1                  --  0001 nor
lutCircuit (suc zero)                                        = Seq (Par (Id {1}) Not1) And2  --  0010 a∧¬b
lutCircuit (suc (suc zero))                                  = Seq projB Not1                --  0011 ¬b
lutCircuit (suc (suc (suc zero)))                            = Seq (Par Not1 (Id {1})) And2  --  0100 ¬a∧b
lutCircuit (suc (suc (suc (suc zero))))                      = Seq projA Not1                --  0101 ¬a
lutCircuit (suc (suc (suc (suc (suc zero)))))                = Xor2                          --  0110 a⊕b
lutCircuit (suc (suc (suc (suc (suc (suc zero))))))          = Seq And2 Not1                 --  0111 nand
lutCircuit (suc (suc (suc (suc (suc (suc (suc zero)))))))    = And2                          --  1000 a∧b
lutCircuit (suc (suc (suc (suc (suc (suc (suc (suc zero))))))) )
                                                             = Seq Xor2 Not1                 --  1001 xnor
lutCircuit (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))) )
                                                             = projA                         --  1010 a
lutCircuit (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero))))))))) )
                                                             = Seq (Par (Id {1}) Not1) Or2   --  1011 a∨¬b
lutCircuit (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))))) )
                                                             = projB                         --  1100 b
lutCircuit (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero))))))))))) )
                                                             = Seq (Par Not1 (Id {1})) Or2   --  1101 ¬a∨b
lutCircuit (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))))))) )
                                                             = Or2                           --  1110 a∨b

------------------------------------------------------------------------
--  Section 2: specify each truth-table function independently in Boolean form.

lutFun : Fin 14 → Bool → Bool → Bool
lutFun zero                                                  a b = not (a ∨ b)
lutFun (suc zero)                                            a b = a ∧ not b
lutFun (suc (suc zero))                                      a b = not b
lutFun (suc (suc (suc zero)))                                a b = not a ∧ b
lutFun (suc (suc (suc (suc zero))))                          a b = not a
lutFun (suc (suc (suc (suc (suc zero)))))                    a b = a xor b
lutFun (suc (suc (suc (suc (suc (suc zero))))))              a b = not (a ∧ b)
lutFun (suc (suc (suc (suc (suc (suc (suc zero)))))))        a b = a ∧ b
lutFun (suc (suc (suc (suc (suc (suc (suc (suc zero))))))) ) a b = not (a xor b)
lutFun (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))) ) a b = a
lutFun (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero))))))))) ) a b = a ∨ not b
lutFun (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))))) ) a b = b
lutFun (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero))))))))))) ) a b = not a ∨ b
lutFun (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))))))) ) a b = a ∨ b

------------------------------------------------------------------------
--  Section 3: prove each gadget implements its Boolean specification. Both
--  sides reduce to the same expression for symbolic a and b, making every case refl.

lutCircuit-correct : (V : Fin 14) (a b : Bool) →
  lookup (⟦ lutCircuit V ⟧ (a ∷ b ∷ [])) zero ≡ lutFun V a b
lutCircuit-correct zero                                                  a b = refl
lutCircuit-correct (suc zero)                                            a b = refl
lutCircuit-correct (suc (suc zero))                                      a b = refl
lutCircuit-correct (suc (suc (suc zero)))                                a b = refl
lutCircuit-correct (suc (suc (suc (suc zero))))                          a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc zero)))))                    a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc zero))))))              a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc (suc zero)))))))        a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc (suc (suc zero))))))) ) a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))) ) a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero))))))))) ) a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))))) ) a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero))))))))))) ) a b = refl
lutCircuit-correct (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc (suc zero)))))))))))) ) a b = refl
