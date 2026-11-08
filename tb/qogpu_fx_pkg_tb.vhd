-- qogpu_fx_pkg_tb: checks the VHDL fixed-point helpers against the golden
-- vectors written by the Ada reference (sw/ada/ref, "make vectors"):
--   mul.csv      : a,b,y              (mul_q16)
--   viewport.csv : x,y,z,sx,sy,sz8,sz16 (viewport_x/y, depth_map D=8 and 16)
-- scripts/sim.tcl copies tb/vectors/ into the run directory.
-- Bit-exact: any differing field is an error (numeric contract, need 3).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.qogpu_fx_pkg.all;

entity qogpu_fx_pkg_tb is
end entity;

architecture sim of qogpu_fx_pkg_tb is
begin
  process
    file f      : text;
    variable l  : line;
    variable c  : character;
    variable a, b, y, x, yy, z, sx, sy : std_logic_vector(31 downto 0);
    variable sz8  : std_logic_vector(7 downto 0);
    variable sz16 : std_logic_vector(15 downto 0);
    variable n_mul, n_vp, errors : natural := 0;

    procedure fail(msg : string) is
    begin
      if errors < 10 then
        report msg severity error;
      end if;
      errors := errors + 1;
    end procedure;
  begin
    file_open(f, "mul.csv", read_mode);
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0 or l(l'left) = '#';
      hread(l, a); read(l, c); hread(l, b); read(l, c); hread(l, y);
      if mul_q16(signed(a), signed(b)) /= signed(y) then
        fail("mul_q16(" & to_hstring(a) & ", " & to_hstring(b) & ") = " &
             to_hstring(std_logic_vector(mul_q16(signed(a), signed(b)))) &
             ", Ada says " & to_hstring(y));
      end if;
      n_mul := n_mul + 1;
    end loop;
    file_close(f);

    file_open(f, "viewport.csv", read_mode);
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0 or l(l'left) = '#';
      hread(l, x); read(l, c); hread(l, yy); read(l, c); hread(l, z); read(l, c);
      hread(l, sx); read(l, c); hread(l, sy); read(l, c);
      hread(l, sz8); read(l, c); hread(l, sz16);
      if viewport_x(signed(x)) /= signed(sx) then
        fail("viewport_x(" & to_hstring(x) & ") differs from Ada " & to_hstring(sx));
      end if;
      if viewport_y(signed(yy)) /= signed(sy) then
        fail("viewport_y(" & to_hstring(yy) & ") differs from Ada " & to_hstring(sy));
      end if;
      if depth_map(signed(z), 8) /= unsigned(sz8) then
        fail("depth_map(" & to_hstring(z) & ", 8) differs from Ada " & to_hstring(sz8));
      end if;
      if depth_map(signed(z), 16) /= unsigned(sz16) then
        fail("depth_map(" & to_hstring(z) & ", 16) differs from Ada " & to_hstring(sz16));
      end if;
      n_vp := n_vp + 1;
    end loop;
    file_close(f);

    if errors = 0 and n_mul = 1020 and n_vp = 510 then
      report "qogpu_fx_pkg_tb: " & integer'image(n_mul) & " mul and " &
             integer'image(n_vp) & " viewport rows bit-exact with the Ada reference";
      report "qogpu_fx_pkg_tb: ALL TESTS PASSED";
    else
      report "FAIL: errors=" & integer'image(errors) & " mul rows=" &
             integer'image(n_mul) & " viewport rows=" & integer'image(n_vp)
        severity failure;
    end if;
    wait;
  end process;
end architecture;
