--  Qogpu_Fixed: 16.16 fixed-point arithmetic of the numeric contract
--  (docs/spec/qogpu_numeric_contract.md, RQ-38).
--
--  Rule 16 (hybrid representation): every value is held as its raw two's
--  complement integer, so each operation is written exactly as the VHDL
--  computes it (rtl/qogpu_fx_pkg.vhd). Q16 is a 16.16 raw value; Wide is the
--  64-bit intermediate the contract allows before a shift.
--
--  Rule 7 (overflow): no wrap and no saturation. The preconditions state the
--  legal inputs, so GNATprove can show every call is free of overflow.

package Qogpu_Fixed with SPARK_Mode is

   Frac : constant := 16;
   One  : constant := 2 ** Frac;           --  1.0 as a raw Q16 value

   type Q16  is range -2 ** 31 .. 2 ** 31 - 1 with Size => 32;
   type Wide is range -2 ** 63 .. 2 ** 63 - 1 with Size => 64;

   subtype Unit is Q16 range -One .. One;  --  normalized coordinate, -1.0 .. 1.0

   --  Rule 4: arithmetic shift right that rounds down, written in the mod
   --  form so it is exact for negative P: (P - (P mod 2**N)) / 2**N.
   function Shr (P : Wide; N : Natural) return Wide is
     ((P - P mod 2 ** N) / 2 ** N)
     with Pre => N in 1 .. 61;

   --  Rule 5: (a * b + 2**15) >> 16, ties toward +inf.
   function Mul_Unchecked (A, B : Q16) return Wide is
     (Shr (Wide (A) * Wide (B) + 2 ** (Frac - 1), Frac));

   function Mul (A, B : Q16) return Q16 is (Q16 (Mul_Unchecked (A, B)))
     with Pre => Mul_Unchecked (A, B) in Wide (Q16'First) .. Wide (Q16'Last);

   --  Rule 2: screen x = (x + 1) * 160 in 0.0 .. 320.0, exact.
   function Viewport_X (X : Unit) return Q16 is (Q16 ((Wide (X) + One) * 160));

   --  Rule 2: screen y = (1 - y) * 120 in 0.0 .. 240.0 (y points down), exact.
   function Viewport_Y (Y : Unit) return Q16 is (Q16 ((One - Wide (Y)) * 120));

   --  Rule 3: depth = ((z + 2**16)(2**D - 1) + 2**16) >> 17, half up, no clamp.
   subtype Depth_Width is Positive range 1 .. 16;

   function Depth_Map (Z : Unit; D : Depth_Width) return Natural is
     (Natural (Shr ((Wide (Z) + One) * (2 ** D - 1) + One, Frac + 1)));

end Qogpu_Fixed;
