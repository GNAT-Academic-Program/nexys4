package body Qogpu_Raster with SPARK_Mode is

   function Floor_Px (V : Q16) return Integer is (Integer (Shr (Wide (V), Frac)));

   function Clamp (V, Hi : Integer) return Natural is
     (if V < 0 then 0 elsif V > Hi then Hi else V);

   function Setup (V : Triangle) return Setup_T is
      S : Setup_T;
      Neg : Boolean;
   begin
      S.V := V;
      for I in Index loop
         S.A (I) := Wide (V (I).Y) - Wide (V (I + 1).Y);
         S.B (I) := Wide (V (I + 1).X) - Wide (V (I).X);
      end loop;

      --  area2 = E_0 at v2
      S.Area2 := S.A (0) * (Wide (V (2).X) - Wide (V (0).X))
               + S.B (0) * (Wide (V (2).Y) - Wide (V (0).Y));
      S.Reject := S.Area2 = 0;

      --  Rule 12: a negative area flips every coefficient to one winding
      Neg := S.Area2 < 0;
      if Neg then
         S.Area2 := -S.Area2;
         for I in Index loop
            S.A (I) := -S.A (I);
            S.B (I) := -S.B (I);
         end loop;
      end if;

      for I in Index loop
         S.TL (I) := S.A (I) > 0 or else (S.A (I) = 0 and then S.B (I) > 0);
      end loop;

      --  Rule 8: bounding box from the floor of the extremes, clamped
      declare
         Xlo : constant Q16 := Q16'Min (V (0).X, Q16'Min (V (1).X, V (2).X));
         Xhi : constant Q16 := Q16'Max (V (0).X, Q16'Max (V (1).X, V (2).X));
         Ylo : constant Q16 := Q16'Min (V (0).Y, Q16'Min (V (1).Y, V (2).Y));
         Yhi : constant Q16 := Q16'Max (V (0).Y, Q16'Max (V (1).Y, V (2).Y));
      begin
         S.Xmin := Clamp (Floor_Px (Xlo), FB_W - 1);
         S.Xmax := Clamp (Floor_Px (Xhi), FB_W - 1);
         S.Ymin := Clamp (Floor_Px (Ylo), FB_H - 1);
         S.Ymax := Clamp (Floor_Px (Yhi), FB_H - 1);
      end;
      return S;
   end Setup;

   function Edge (S : Setup_T; I : Index; Px : Px_X; Py : Px_Y) return Wide is
      --  Rule 2: sample at the pixel centre, (px + 0.5, py + 0.5)
      Xs : constant Wide := Wide (Px) * One + One / 2;
      Ys : constant Wide := Wide (Py) * One + One / 2;
   begin
      if S.Reject then
         return 0;
      end if;
      return S.A (I) * (Xs - Wide (S.V (I).X)) + S.B (I) * (Ys - Wide (S.V (I).Y));
   end Edge;

   function Covered (S : Setup_T; Px : Px_X; Py : Px_Y) return Boolean is
   begin
      if S.Reject then
         return False;
      end if;
      for I in Index loop
         declare
            E : constant Wide := Edge (S, I, Px, Py);
         begin
            if not (E > 0 or else (E = 0 and then S.TL (I))) then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Covered;

   function Interp_Z (S : Setup_T; Px : Px_X; Py : Px_Y) return Depth8 is
      Num : constant Wide :=
        Edge (S, 0, Px, Py) * Wide (S.V (2).Z)
        + Edge (S, 1, Px, Py) * Wide (S.V (0).Z)
        + Edge (S, 2, Px, Py) * Wide (S.V (1).Z);
   begin
      --  Both operands are positive, so "/" is the floor the contract asks for
      return Depth8 ((2 * Num + S.Area2) / (2 * S.Area2));
   end Interp_Z;

end Qogpu_Raster;
