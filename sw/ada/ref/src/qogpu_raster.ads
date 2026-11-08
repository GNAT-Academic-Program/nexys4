--  Qogpu_Raster: triangle setup, edge functions, coverage and depth
--  interpolation of the numeric contract (rules 8 to 14), on raw integers.
--
--  Units: screen x, y are Q16 (16.16). Edge coefficients A, B are Q16
--  differences (25 and 26 bits). Edge values E and area2 are products of two
--  Q16 values, so they are 18.32 raw values in 51 bits (rule 9).

with Qogpu_Fixed; use Qogpu_Fixed;

package Qogpu_Raster with SPARK_Mode is

   FB_W : constant := 320;
   FB_H : constant := 240;

   subtype Px_X is Natural range 0 .. FB_W - 1;
   subtype Px_Y is Natural range 0 .. FB_H - 1;
   subtype Depth8 is Natural range 0 .. 255;   --  interpolation is defined for D = 8

   type Vertex is record
      X, Y : Q16;       --  screen space, 0.0 .. 320.0 and 0.0 .. 240.0
      Z    : Depth8;    --  mapped depth
   end record;

   type Index is mod 3;
   type Triangle is array (Index) of Vertex;
   type Coef is array (Index) of Wide;
   type Flags is array (Index) of Boolean;

   type Setup_T is record
      V      : Triangle;
      A, B   : Coef;      --  after winding normalization (rule 12)
      Area2  : Wide;      --  twice the signed area, >= 0 after normalization
      TL     : Flags;     --  top-left flag per edge (rule 11)
      Xmin, Xmax : Px_X;  --  bounding box, clamped (rule 8)
      Ymin, Ymax : Px_Y;
      Reject : Boolean;   --  area2 = 0 (rule 12)
   end record;

   function Setup (V : Triangle) return Setup_T
     with Pre => (for all I in Index =>
                    V (I).X in 0 .. FB_W * One and V (I).Y in 0 .. FB_H * One);

   --  E_i at the centre of pixel (Px, Py); 0 for a rejected triangle.
   function Edge (S : Setup_T; I : Index; Px : Px_X; Py : Px_Y) return Wide;

   --  Rule 11: covered if every E_i > 0, or E_i = 0 on a top-left edge.
   function Covered (S : Setup_T; Px : Px_X; Py : Px_Y) return Boolean;

   --  Rule 10: z = (2 num + area2) div (2 area2), num = E0 z2 + E1 z0 + E2 z1.
   function Interp_Z (S : Setup_T; Px : Px_X; Py : Px_Y) return Depth8
     with Pre => Covered (S, Px, Py);

   --  Rule 13: a fragment passes only when it is strictly nearer.
   function Depth_Pass (Z, Stored : Natural) return Boolean is (Z < Stored);

end Qogpu_Raster;
