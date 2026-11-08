-- qogpu_fx_pkg: 16.16 fixed-point helpers of the numeric contract
-- (docs/spec/qogpu_numeric_contract.md, RQ-38), written to match the Ada
-- reference sw/ada/ref/src/qogpu_fixed.ads operation for operation.
--
-- Every value is a raw two's complement integer (rule 16). The functions are
-- combinational; pipelined datapaths (fx_mul.vhd) must give the same result.
-- Rule 7: no wrap and no saturation. Each function asserts its legal input
-- range in simulation (severity failure) so an overflow is a test failure.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package qogpu_fx_pkg is
  constant FRAC : natural := 16;

  subtype q16_t is signed(31 downto 0);                 -- raw 16.16
  constant Q16_ONE : integer := 2 ** FRAC;              -- 1.0

  -- Rule 4: arithmetic shift right, rounds down (floor) for negative values
  function shr_floor(p : signed; n : natural) return signed;

  -- Rule 5: (a * b + 2**15) >> 16, ties toward +inf; asserts rule 7
  function mul_q16(a, b : q16_t) return q16_t;

  -- Rule 2: (x + 1) * 160 and (1 - y) * 120, exact; x, y in -1.0 .. 1.0
  function viewport_x(x : q16_t) return q16_t;
  function viewport_y(y : q16_t) return q16_t;

  -- Rule 3: ((z + 2**16)(2**D - 1) + 2**16) >> 17; z in -1.0 .. 1.0, D <= 16
  function depth_map(z : q16_t; depth_w : positive) return unsigned;
end package;

package body qogpu_fx_pkg is

  function shr_floor(p : signed; n : natural) return signed is
  begin
    return shift_right(p, n);   -- numeric_std replicates the sign bit
  end function;

  procedure check_unit(v : q16_t; name : string) is
  begin
    assert v >= -Q16_ONE and v <= Q16_ONE
      report name & ": input outside -1.0 .. 1.0 (numeric contract)" severity failure;
  end procedure;

  function mul_q16(a, b : q16_t) return q16_t is
    variable p : signed(63 downto 0);
  begin
    p := shr_floor(a * b + to_signed(2 ** (FRAC - 1), 64), FRAC);
    assert resize(p(31 downto 0), 64) = p   -- upper 33 bits all equal the sign
      report "mul_q16: result overflows 16.16 (numeric contract rule 7)" severity failure;
    return p(31 downto 0);
  end function;

  function viewport_x(x : q16_t) return q16_t is
    variable s : signed(40 downto 0);       -- 32-bit sum times 9-bit constant
  begin
    check_unit(x, "viewport_x");
    s := resize(resize(x, 40) + Q16_ONE, 32) * to_signed(160, 9);
    return s(31 downto 0);
  end function;

  function viewport_y(y : q16_t) return q16_t is
    variable s : signed(40 downto 0);
  begin
    check_unit(y, "viewport_y");
    s := resize(to_signed(Q16_ONE, 40) - resize(y, 40), 32) * to_signed(120, 9);
    return s(31 downto 0);
  end function;

  function depth_map(z : q16_t; depth_w : positive) return unsigned is
    variable zp : signed(18 downto 0);     -- z + 1.0, 0 .. 2**17
    variable p  : signed(36 downto 0);     -- times 2**D - 1 (17 bits), plus 2**16
    variable q  : signed(36 downto 0);
  begin
    check_unit(z, "depth_map");
    assert depth_w <= 16 report "depth_map: DEPTH_W above 16" severity failure;
    zp := resize(z, 19) + Q16_ONE;
    p  := zp * to_signed(2 ** depth_w - 1, 18) + to_signed(Q16_ONE, 37);
    q := shr_floor(p, FRAC + 1);           -- 0 .. 2**D - 1, never negative
    -- slice, not resize: resize on signed would keep the sign bit
    return unsigned(q(depth_w - 1 downto 0));
  end function;

end package body;
