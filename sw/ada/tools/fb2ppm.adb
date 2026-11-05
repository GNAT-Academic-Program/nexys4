with Ada.Command_Line;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;

procedure FB2PPM is
   use Ada.Command_Line;
   use Ada.Streams;
   package Binary_IO renames Ada.Streams.Stream_IO;

   Pixel_Count : constant := 320 * 240;
   Header : constant String := "P6" & ASCII.LF & "320 240" & ASCII.LF
                               & "255" & ASCII.LF;
   type RGB is record
      R, G, B : Natural range 0 .. 255;
   end record;

   function RGB332_To_RGB (P : Natural) return RGB is
      Colour : RGB;
   begin
      Colour.R := ((P / 32) mod 8) * 255 / 7;
      Colour.G := ((P / 4) mod 8) * 255 / 7;
      Colour.B := (P mod 4) * 85;
      return Colour;
   end RGB332_To_RGB;

   function Hex_Digit (C : Character) return Natural is
   begin
      case C is
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
         when 'A' .. 'F' => return Character'Pos (C) - Character'Pos ('A') + 10;
         when 'a' .. 'f' => return Character'Pos (C) - Character'Pos ('a') + 10;
         when others => raise Constraint_Error with "invalid hex digit";
      end case;
   end Hex_Digit;

   Input : Ada.Text_IO.File_Type;
   Output : Binary_IO.File_Type;
   Image : Stream_Element_Array (1 .. Header'Length + 3 * Pixel_Count);
   Next_Byte : Stream_Element_Offset := Header'Length + 1;
begin
   -- Explicit checks run even when compiler assertions are disabled.
   if RGB332_To_RGB (16#00#) /= RGB'(0, 0, 0)
     or else RGB332_To_RGB (16#FF#) /= RGB'(255, 255, 255)
     or else RGB332_To_RGB (16#E0#) /= RGB'(255, 0, 0)
     or else RGB332_To_RGB (16#1C#) /= RGB'(0, 255, 0)
     or else RGB332_To_RGB (16#03#) /= RGB'(0, 0, 255)
   then
      raise Program_Error with "RGB332 conversion check failed";
   end if;

   if Argument_Count = 1 and then Argument (1) = "--check" then
      Ada.Text_IO.Put_Line ("PASS: RGB332 black, white, red, green, blue");
      return;
   elsif Argument_Count /= 2 then
      Ada.Text_IO.Put_Line ("Usage: fb2ppm input.hex output.ppm");
      Ada.Text_IO.Put_Line ("       fb2ppm --check");
      Set_Exit_Status (Failure);
      return;
   end if;

   for I in Header'Range loop
      Image (Stream_Element_Offset (I)) := Stream_Element (Character'Pos (Header (I)));
   end loop;

   -- Provisional input: exactly 76,800 lines, each containing two hex digits.
   -- Read and validate everything before creating the output file.
   Ada.Text_IO.Open (Input, Ada.Text_IO.In_File, Argument (1));
   for Pixel in 1 .. Pixel_Count loop
      if Ada.Text_IO.End_Of_File (Input) then
         raise Constraint_Error with "expected 76800 pixels; input ended early";
      end if;
      declare
         Line : constant String := Ada.Text_IO.Get_Line (Input);
         Pixel_Value : Natural;
         Colour : RGB;
      begin
         if Line'Length /= 2 then
            raise Constraint_Error with "expected exactly two hex digits per line";
         end if;

         Pixel_Value := 16 * Hex_Digit (Line (Line'First))
                        + Hex_Digit (Line (Line'First + 1));
         Colour := RGB332_To_RGB (Pixel_Value);

         Image (Next_Byte) := Stream_Element (Colour.R);
         Image (Next_Byte + 1) := Stream_Element (Colour.G);
         Image (Next_Byte + 2) := Stream_Element (Colour.B);
         Next_Byte := Next_Byte + 3;
      end;
   end loop;
   if not Ada.Text_IO.End_Of_File (Input) then
      raise Constraint_Error with "extra data after 76800 pixels";
   end if;
   Ada.Text_IO.Close (Input);

   Binary_IO.Create (Output, Binary_IO.Out_File, Argument (2));
   Binary_IO.Write (Output, Image);
   Binary_IO.Close (Output);
   Ada.Text_IO.Put_Line ("Wrote 320x240 P6 image: " & Argument (2));
exception
   when others =>
      if Ada.Text_IO.Is_Open (Input) then
         Ada.Text_IO.Close (Input);
      end if;
      if Binary_IO.Is_Open (Output) then
         Binary_IO.Close (Output);
      end if;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "fb2ppm failed.");
      Set_Exit_Status (Failure);
end FB2PPM;
