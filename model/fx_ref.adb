--  fx_ref.adb : Ada reference model for fx_mul (S2).
--  Usage: fx_ref <0|1>     0 = truncate, 1 = round half up (matches ROUND)
--  Writes vectors_trunc.txt / vectors_round.txt: "AAAAAAAA BBBBBBBB YYYYYYYY"
--  (hex, one case per line): 20 directed cases then 1000 random cases.
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
   --  20 directed cases
   Emit (Q (1.0), Q (1.0));            --  1.0*1.0 = 0x00010000
   Emit (Q (0.5), Q (-2.0));           --  = -1.0
   Emit (Q (-0.5), Q (0.5));           --  = -0.25
   Emit (0, 0);
   Emit (0, Q (123.456));
   Emit (Q (-7.25), 0);
   Emit (Q (1.0), Max);
   Emit (Q (1.0), Min);
   Emit (Q (-1.0), Min);               --  wraps
   Emit (Min, Min);                    --  2**62 product
   Emit (Max, Max);
   Emit (Max, Min);
   Emit (Q (2.5), Q (4.0));
   Emit (Q (-2.5), Q (-4.0));
   Emit (Q (100.0), Q (-100.0));
   Emit (1, 1);                        --  smallest LSBs -> 0
   Emit (1, 16#8000#);                 --  rounding boundary (+): trunc 0, round 1
   Emit (-1, 16#8000#);                --  rounding boundary (-): trunc -1, round 0
   Emit (-1, 16#7FFF#);                --  just below half
   Emit (16#0001_8000#, Q (3.0));      --  1.5*3.0 = 4.5

   --  1000 random cases, fixed seed (reproducible)
   Rnd.Reset (G, 12345);
   for I in 1 .. 1000 loop
      Emit (I64 (Rnd.Random (G)), I64 (Rnd.Random (G)));
   end loop;
   Close (F);
end Fx_Ref;
