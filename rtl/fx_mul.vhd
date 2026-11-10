-------------------------------------------------------------------------------
-- fx_mul.vhd : signed 32x32 fixed-point multiply, result in 16.16 (S2)
--
-- y = (a * b) >>> FRAC, low 32 bits of the shifted 64-bit product.
--   a, b : signed Q16.16 (FRAC = 16), two's complement
--   y    : signed Q16.16; wraps (no saturation) if the result exceeds 32 bits.
--          Numeric contract rule 7 forbids such inputs: callers must keep the
--          product in range (proved in Ada, asserted in simulation).
--
-- LATENCY: 3 clock cycles, throughput 1 result/cycle (fully pipelined).
--   in_valid at edge N  ->  y / out_valid valid after edge N+2
--   (cycle count: input regs, product reg, rounded/shifted output reg)
--   Stage 1: a_r <= a, b_r <= b             (DSP48E1 AREG/BREG)
--   Stage 2: p_r <= a_r * b_r  (64 bit)     (DSP48E1 MREG)
--   Stage 3: y   <= (p_r + RND)(FRAC+31 downto FRAC)  (PREG, rounding folds
--                                           into the DSP post-adder)
--   y is not gated by valid: it holds don't-care data while out_valid = '0'.
--   out_valid is initialised '0' (FPGA power-up value); no reset port per S2.
--
-- ROUND generic: 1 = round half up, ties toward +inf: (a*b + 2**(FRAC-1)) >> FRAC
--                    (numeric contract rule 5, the default)
--                0 = truncate (floor); kept for comparison only
--
-- Vivado maps 32x32 signed onto 4 DSP48E1 (25x18) slices. Check the
-- utilization report for DSP48E1 > 0 (make synth-fx-mul).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fx_mul is
  generic (
    FRAC  : natural range 1 to 32 := 16;
    ROUND : natural range 0 to 1  := 1
  );
  port (
    clk       : in  std_logic;
    a, b      : in  signed(31 downto 0);
    in_valid  : in  std_logic;
    y         : out signed(31 downto 0);
    out_valid : out std_logic
  );
end entity fx_mul;

architecture rtl of fx_mul is
  signal a_r, b_r : signed(31 downto 0) := (others => '0');
  signal p_r      : signed(63 downto 0) := (others => '0');
  signal y_r      : signed(31 downto 0) := (others => '0');
  signal v        : std_logic_vector(2 downto 0) := (others => '0');

  function rnd_const return signed is
  begin
    if ROUND = 1 then
      return shift_left(to_signed(1, 64), FRAC - 1);
    else
      return to_signed(0, 64);
    end if;
  end function;

  constant RND : signed(63 downto 0) := rnd_const;
begin
  process (clk)
    variable sum : signed(63 downto 0);
  begin
    if rising_edge(clk) then
      -- stage 1
      a_r <= a;
      b_r <= b;
      -- stage 2
      p_r <= a_r * b_r;
      -- stage 3
      sum := p_r + RND;
      y_r <= sum(FRAC + 31 downto FRAC);
      -- valid pipe
      v <= v(1 downto 0) & in_valid;
    end if;
  end process;

  y         <= y_r;
  out_valid <= v(2);
end architecture rtl;
