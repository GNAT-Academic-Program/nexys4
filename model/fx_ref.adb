--  fx_ref.adb : Ada reference model for fx_mul (S2).
--  Usage: fx_ref <0|1>     0 = truncate, 1 = round half up (matches ROUND)
--  Writes vectors_trunc.txt / vectors_round.txt: "AAAAAAAA BBBBBBBB YYYYYYYY"
--  (hex, one case per line): 20 directed cases then 1000 random cases.
--  Shift is floor (contract rule 4); no case overflows (contract rule 7).
--  Regenerate from tb/vectors/:  gnatmake ../../model/fx_ref.adb
--                                ./fx_ref 0 && ./fx_ref 1
with Ada.Text_IO;          use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Numerics.Discrete_Random;

procedure Fx_Ref is
   subtype I64 is Long_Long_Integer;          --  64-bit in GNAT
   Frac : constant := 16;
   Two_Frac : constant I64 := 2 ** Frac;
   Two_32   : constant I64 := 2 ** 32;
   Two_31   : constant I64 := 2 ** 31;

   Round_Mode : Natural := 0;
   F : File_Type;

   function Floor_Shift (P : I64) return I64 is  --  arithmetic >> Frac
   begin
      if P >= 0 then
         return P / Two_Frac;
      else
         return -((-P + Two_Frac - 1) / Two_Frac);
      end if;
   end Floor_Shift;

   function Model (A, B : I64) return I64 is
      P : I64 := A * B;                       --  fits: |P| <= 2**62
   begin
      if Round_Mode = 1 then
         P := P + Two_Frac / 2;
      end if;
      declare
         Q : constant I64 := Floor_Shift (P);
      begin
         return ((Q + Two_31) mod Two_32) - Two_31;   --  wrap to 32 bit signed
      end;
   end Model;

   function Hex8 (V : I64) return String is
      D : constant String := "0123456789ABCDEF";
      U : I64 := V mod Two_32;
      S : String (1 .. 8);
   begin
      for I in reverse S'Range loop
         S (I) := D (Integer (U mod 16) + 1);
         U := U / 16;
      end loop;
      return S;
   end Hex8;

   procedure Emit (A, B : I64) is
   begin
      Put_Line (F, Hex8 (A) & " " & Hex8 (B) & " " & Hex8 (Model (A, B)));
   end Emit;

   function Q (X : Long_Float) return I64 is   --  real -> Q16.16
   begin
      return I64 (X * 65536.0);
   end Q;

   Max : constant I64 := Two_31 - 1;
   Min : constant I64 := -Two_31;

   subtype R32 is Integer range Integer (Min) .. Integer (Max);
   package Rnd is new Ada.Numerics.Discrete_Random (R32);
   G : Rnd.Generator;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Round_Mode := Natural'Value (Ada.Command_Line.Argument (1));
   end if;
   Create (F, Out_File, (if Round_Mode = 1 then "vectors_round.txt"
                                           else "vectors_trunc.txt"));
   --  20 directed cases: the same inputs, in the same order, as the
   --  directed rows of mul.csv in docs/spec/golden-vectors-set.md
   Emit (Q (1.0), Q (1.0));            --  1 x 1
   Emit (0, Q (1.0));                  --  zero on each side
   Emit (Q (1.0), 0);
   Emit (Q (0.5), Q (-2.0));           --  = -1.0
   Emit (Q (-0.5), Q (0.5));           --  = -0.25
   Emit (Q (-1.0), Q (-1.0));          --  = 1.0
   Emit (1, Q (1.0));                  --  +/-1 LSB x 1
   Emit (-1, Q (1.0));
   Emit (1, 16#8000#);                 --  +0.5 LSB tie: trunc 0, round 1
   Emit (-1, 16#8000#);                --  -0.5 LSB tie: trunc -1, round 0
   Emit (1, 16#7FFF#);                 --  just below the tie
   Emit (3, 16#8000#);                 --  +1.5 LSB tie
   Emit (-3, 16#8000#);                --  -1.5 LSB tie
   Emit (1, 1);                        --  LSB x LSB -> 0
   Emit (Max, Q (1.0));                --  max and min x 1
   Emit (Min, Q (1.0));
   Emit (Max, Q (0.5));                --  max x 0.5
   Emit (Q (181.0), Q (181.0));        --  near the limit
   Emit (Q (-181.0), Q (181.0));
   Emit (16#0003_243F#, -16#0002_B7E1#);  --  pi x -e

   --  1000 random cases, fixed seed (reproducible). Numeric contract
   --  rule 7 forbids overflow, so every product fits in Q16.16:
   --  odd cases use |a|, |b| < 2**23 (+/-128.0), even cases use a full
   --  32-bit a and |b| < 2**15 (+/-0.5). Either way |a * b| < 2**46.
   Rnd.Reset (G, 12345);
   for I in 1 .. 1000 loop
      declare
         A : constant I64 := I64 (Rnd.Random (G));
         B : constant I64 := I64 (Rnd.Random (G));
      begin
         if I mod 2 = 1 then
            Emit (A mod 2 ** 24 - 2 ** 23, B mod 2 ** 24 - 2 ** 23);
         else
            Emit (A, B mod 2 ** 16 - 2 ** 15);
         end if;
      end;
   end loop;
   Close (F);
end Fx_Ref;
