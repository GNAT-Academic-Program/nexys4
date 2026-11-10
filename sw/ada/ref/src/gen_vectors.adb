--  gen_vectors: writes the golden vector files of docs/spec/golden-vectors-set.md
--  (RQ-38) from the Ada reference arithmetic (Qogpu_Fixed, Qogpu_Raster).
--
--  Usage: gen_vectors [output_dir]        (default: current directory)
--  Writes mul.csv, viewport.csv, setup.csv, depth_test.csv (committed in
--  tb/vectors/) and edge.csv (every pixel of each directed triangle's
--  bounding box plus a one-pixel margin) and interp.csv (its covered pixels).
--  Those two are several MB, so "make vectors" regenerates them; they are
--  not committed.
--
--  Format (golden-vectors-set.md): first line "# col,col,...", then hex
--  fields, comma separated, two's complement padded to whole hex digits.
--  Random rows use fixed seeds, so every run writes identical files.

with Ada.Command_Line;
with Ada.Numerics.Discrete_Random;
with Ada.Text_IO;   use Ada.Text_IO;
with Qogpu_Fixed;   use Qogpu_Fixed;
with Qogpu_Raster;  use Qogpu_Raster;

procedure Gen_Vectors is

   Dir : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1) & "/" else "");

   --  V as N hex digits, two's complement
   function Hex (V : Wide; N : Positive) return String is
      D : constant String := "0123456789ABCDEF";
      U : Wide := V mod 16 ** N;
      S : String (1 .. N);
   begin
      for I in reverse S'Range loop
         S (I) := D (Integer (U mod 16) + 1);
         U := U / 16;
      end loop;
      return S;
   end Hex;

   function H8  (V : Q16) return String is (Hex (Wide (V), 8));
   function H2  (V : Natural) return String is (Hex (Wide (V), 2));
   function H4  (V : Natural) return String is (Hex (Wide (V), 4));
   function H7  (V : Wide) return String is (Hex (V, 7));     --  A (25b), B (26b)
   function H13 (V : Wide) return String is (Hex (V, 13));    --  E, area2 (51b)
   function B01 (V : Boolean) return String is (if V then "1" else "0");

   package Rnd is new Ada.Numerics.Discrete_Random (Q16);
   G : Rnd.Generator;

   function Rand_Unit return Unit is
     (Unit (Wide (Rnd.Random (G)) mod (2 * One + 1) - One));

   F : File_Type;

   ---------------------------------------------------------------- mul.csv
   procedure Mul_Row (A, B : Q16) is
   begin
      Put_Line (F, H8 (A) & "," & H8 (B) & "," & H8 (Mul (A, B)));
   end Mul_Row;

   procedure Gen_Mul is
   begin
      Create (F, Out_File, Dir & "mul.csv");
      Put_Line (F, "# a,b,y");
      --  20 directed rows, in the order of golden-vectors-set.md
      Mul_Row (One, One);
      Mul_Row (0, One);
      Mul_Row (One, 0);
      Mul_Row (One / 2, -2 * One);
      Mul_Row (-One / 2, One / 2);
      Mul_Row (-One, -One);
      Mul_Row (1, One);
      Mul_Row (-1, One);
      Mul_Row (1, 16#8000#);
      Mul_Row (-1, 16#8000#);
      Mul_Row (1, 16#7FFF#);
      Mul_Row (3, 16#8000#);
      Mul_Row (-3, 16#8000#);
      Mul_Row (1, 1);
      Mul_Row (Q16'Last, One);
      Mul_Row (Q16'First, One);
      Mul_Row (Q16'Last, One / 2);
      Mul_Row (181 * One, 181 * One);
      Mul_Row (-181 * One, 181 * One);
      Mul_Row (16#0003_243F#, -16#0002_B7E1#);          --  pi x -e
      --  1000 random rows; every product fits (rule 7): alternately both
      --  operands within +/-128.0, or any a times |b| < 0.5
      Rnd.Reset (G, 12345);
      for I in 1 .. 1000 loop
         declare
            A : constant Wide := Wide (Rnd.Random (G));
            B : constant Wide := Wide (Rnd.Random (G));
         begin
            if I mod 2 = 1 then
               Mul_Row (Q16 (A mod 2 ** 24 - 2 ** 23), Q16 (B mod 2 ** 24 - 2 ** 23));
            else
               Mul_Row (Q16 (A), Q16 (B mod 2 ** 16 - 2 ** 15));
            end if;
         end;
      end loop;
      Close (F);
   end Gen_Mul;

   ----------------------------------------------------------- viewport.csv
   procedure Vp_Row (X, Y, Z : Unit) is
   begin
      Put_Line (F, H8 (X) & "," & H8 (Y) & "," & H8 (Z) & ","
                & H8 (Viewport_X (X)) & "," & H8 (Viewport_Y (Y)) & ","
                & H2 (Depth_Map (Z, 8)) & "," & H4 (Depth_Map (Z, 16)));
   end Vp_Row;

   procedure Gen_Viewport is
   begin
      Create (F, Out_File, Dir & "viewport.csv");
      Put_Line (F, "# x,y,z,sx,sy,sz8,sz16");
      Vp_Row (-One, -One, -One);                   --  corners and centre
      Vp_Row (0, 0, 0);
      Vp_Row (One, One, One);
      Vp_Row (-One, One, 0);
      Vp_Row (One, -One, 0);
      Vp_Row (One / 4, One / 4, One / 4);          --  quarter and half points
      Vp_Row (-One / 2, One / 2, -One / 2);
      Vp_Row (One / 2, -One / 2, One / 2);
      Vp_Row (1, -1, 1);                           --  1 LSB
      Vp_Row (-16#FFBE#, 16#FFBE#, 16#FFBE#);      --  -0.999 / 0.999
      Rnd.Reset (G, 2026);
      for I in 1 .. 500 loop
         declare
            X : constant Unit := Rand_Unit;
            Y : constant Unit := Rand_Unit;
            Z : constant Unit := Rand_Unit;
         begin
            Vp_Row (X, Y, Z);
         end;
      end loop;
      Close (F);
   end Gen_Viewport;

   --------------------------------------------- setup.csv, edge.csv, interp.csv
   type Tri_List is array (Positive range <>) of Triangle;

   function Vx (X, Y : Q16; Z : Depth8) return Vertex is ((X, Y, Z));

   --  The eight directed triangles of golden-vectors-set.md, in screen space
   Directed : constant Tri_List :=
     [1 => [Vx (16#0028_0000#, 16#001E_0000#, 16#0A#),
            Vx (16#00C8_0000#, 16#001E_0000#, 16#C8#),
            Vx (16#0028_0000#, 16#00B4_0000#, 16#64#)],
      2 => [Vx (16#0028_0000#, 16#001E_0000#, 16#0A#),
            Vx (16#0028_0000#, 16#00B4_0000#, 16#64#),
            Vx (16#00C8_0000#, 16#001E_0000#, 16#C8#)],
      3 => [Vx (16#000A_4000#, 16#0014_8000#, 16#05#),
            Vx (16#012C_C000#, 16#0016_0000#, 16#FA#),
            Vx (16#000A_4000#, 16#0015_0000#, 16#80#)],
      4 => [Vx (16#0014_8000#, 16#0064_8000#, 16#32#),
            Vx (16#0078_8000#, 16#0096_8000#, 16#5A#),
            Vx (16#0064_4000#, 16#0028_C000#, 16#1E#)],
      5 => [Vx (16#0078_8000#, 16#0096_8000#, 16#5A#),
            Vx (16#0014_8000#, 16#0064_8000#, 16#32#),
            Vx (16#003C_C000#, 16#00C8_4000#, 16#B4#)],
      6 => [Vx (16#000A_8000#, 16#000A_8000#, 16#07#),
            Vx (16#005A_8000#, 16#000A_8000#, 16#FA#),
            Vx (16#000A_8000#, 16#0046_8000#, 16#21#)],
      7 => [Vx (16#0014_0000#, 16#0014_0000#, 16#00#),
            Vx (16#0064_0000#, 16#0064_0000#, 16#00#),
            Vx (16#003C_0000#, 16#003C_0000#, 16#00#)],
      8 => [Vx (16#0000_0000#, 16#0000_0000#, 16#00#),
            Vx (16#0140_0000#, 16#00F0_0000#, 16#FF#),
            Vx (16#0000_0000#, 16#00F0_0000#, 16#80#)]];

   procedure Setup_Row (N : Positive; T : Triangle) is
      S : constant Setup_T := Setup (T);
      TL_Bits : constant Natural :=
        (if S.TL (0) then 1 else 0) + (if S.TL (1) then 2 else 0)
        + (if S.TL (2) then 4 else 0);
      Line : constant String := N'Image;
   begin
      Put (F, Line (Line'First + 1 .. Line'Last));
      for I in Index loop
         Put (F, "," & H8 (T (I).X) & "," & H8 (T (I).Y) & "," & H2 (T (I).Z));
      end loop;
      for I in Index loop
         Put (F, "," & H7 (S.A (I)) & "," & H7 (S.B (I)));
      end loop;
      Put_Line (F, "," & H13 (S.Area2) & "," & Hex (Wide (TL_Bits), 1)
                & "," & Hex (Wide (S.Xmin), 3) & "," & Hex (Wide (S.Xmax), 3)
                & "," & H2 (S.Ymin) & "," & H2 (S.Ymax) & "," & B01 (S.Reject));
   end Setup_Row;

   procedure Gen_Setup is
   begin
      Create (F, Out_File, Dir & "setup.csv");
      Put_Line (F, "# tri,x0,y0,z0,x1,y1,z1,x2,y2,z2,A0,B0,A1,B1,A2,B2,"
                & "area2,TL,xmin,xmax,ymin,ymax,reject");
      for N in Directed'Range loop
         Setup_Row (N, Directed (N));
      end loop;
      --  200 random triangles from a real scene: vertices in -1..1 mapped
      --  through viewport_xy and depth_map (D = 8)
      Rnd.Reset (G, 4242);
      for N in 1 .. 200 loop
         declare
            T : Triangle;
         begin
            for I in Index loop
               declare
                  X : constant Unit := Rand_Unit;
                  Y : constant Unit := Rand_Unit;
                  Z : constant Unit := Rand_Unit;
               begin
                  T (I) := (Viewport_X (X), Viewport_Y (Y), Depth_Map (Z, 8));
               end;
            end loop;
            Setup_Row (Directed'Last + N, T);
         end;
      end loop;
      Close (F);
   end Gen_Setup;

   procedure Gen_Edge_Interp is
      E_File, Z_File : File_Type;
      function Img (N : Natural) return String is
         S : constant String := N'Image;
      begin
         return S (S'First + 1 .. S'Last);
      end Img;
   begin
      Create (E_File, Out_File, Dir & "edge.csv");
      Create (Z_File, Out_File, Dir & "interp.csv");
      Put_Line (E_File, "# tri,px,py,E0,E1,E2,covered");
      Put_Line (Z_File, "# tri,px,py,z");
      for N in Directed'Range loop
         declare
            S : constant Setup_T := Setup (Directed (N));
         begin
            --  the bounding box plus a one-pixel margin (clamped to the
            --  screen), so pixels just outside the box are checked too
            for Py in Natural'Max (S.Ymin, 1) - 1 .. Natural'Min (S.Ymax + 1, FB_H - 1) loop
               for Px in Natural'Max (S.Xmin, 1) - 1 .. Natural'Min (S.Xmax + 1, FB_W - 1) loop
                  declare
                     C   : constant Boolean := Covered (S, Px, Py);
                     Pos : constant String :=
                       Img (N) & "," & Hex (Wide (Px), 3) & "," & H2 (Py);
                  begin
                     Put_Line (E_File, Pos & "," & H13 (Edge (S, 0, Px, Py))
                               & "," & H13 (Edge (S, 1, Px, Py))
                               & "," & H13 (Edge (S, 2, Px, Py)) & "," & B01 (C));
                     if C then
                        Put_Line (Z_File, Pos & "," & H2 (Interp_Z (S, Px, Py)));
                     end if;
                  end;
               end loop;
            end loop;
         end;
      end loop;
      Close (E_File);
      Close (Z_File);
   end Gen_Edge_Interp;

   ------------------------------------------------------- depth_test.csv
   procedure Gen_Depth_Test is
      type Pair is array (1 .. 2) of Natural;
      Rows : constant array (1 .. 7) of Pair :=
        [[16#0B#, 16#FF#], [16#0B#, 16#0B#], [16#0B#, 16#0A#], [16#0A#, 16#0B#],
         [16#FF#, 16#FF#], [16#00#, 16#00#], [16#00#, 16#01#]];
   begin
      Create (F, Out_File, Dir & "depth_test.csv");
      Put_Line (F, "# z,stored,pass");
      for R of Rows loop
         Put_Line (F, H2 (R (1)) & "," & H2 (R (2)) & "," & B01 (Depth_Pass (R (1), R (2))));
      end loop;
      Close (F);
   end Gen_Depth_Test;

begin
   Gen_Mul;
   Gen_Viewport;
   Gen_Setup;
   Gen_Edge_Interp;
   Gen_Depth_Test;
   Put_Line ("gen_vectors: wrote mul, viewport, setup, edge, interp, depth_test");
end Gen_Vectors;
