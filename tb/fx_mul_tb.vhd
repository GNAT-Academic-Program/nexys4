-- fx_mul_tb.vhd : VHDL-2008 self-checking testbench for fx_mul (xsim).
-- Reads vectors written by the Ada model (model/fx_ref.adb):
--   "AAAAAAAA BBBBBBBB YYYYYYYY" hex per line (20 directed + 1000 random).
-- ROUND selects the file: 1 -> vectors_round.txt, 0 -> vectors_trunc.txt
-- (scripts/sim.tcl copies tb/vectors/ into the run directory).
-- tb/fx_mul_trunc_tb.vhd runs this testbench with ROUND = 0.
-- Drives back-to-back with periodic bubbles (valid low) to exercise the
-- valid pipe. Checks y in order, and checks every cycle that out_valid
-- equals in_valid delayed by exactly LATENCY clock edges.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity fx_mul_tb is
  generic (
    ROUND     : natural range 0 to 1 := 1;
    N_EXPECT  : natural := 1020;
    TB_NAME   : string  := "fx_mul_tb"   -- name in the pass line (scripts/sim.tcl)
  );
end entity;

architecture sim of fx_mul_tb is
  constant LATENCY : natural := 3;

  function pick_vec_file return string is
  begin
    if ROUND = 1 then
      return "vectors_round.txt";
    else
      return "vectors_trunc.txt";
    end if;
  end function;
  constant VEC_FILE : string := pick_vec_file;
  type vec_t is array (0 to N_EXPECT - 1) of std_logic_vector(31 downto 0);
  signal va, vb, vy : vec_t;

  signal clk       : std_logic := '0';
  signal a, b, y   : signed(31 downto 0) := (others => '0');
  signal in_valid  : std_logic := '0';
  signal out_valid : std_logic;
  signal done      : boolean := false;
  signal errors    : natural := 0;
  signal lat_errs  : natural := 0;
  signal checked   : natural := 0;
begin
  clk <= not clk after 5 ns when not done;

  dut : entity work.fx_mul
    generic map (FRAC => 16, ROUND => ROUND)
    port map (clk => clk, a => a, b => b, in_valid => in_valid,
              y => y, out_valid => out_valid);

  -- driver
  stim : process
    file f      : text open read_mode is VEC_FILE;
    variable l  : line;
    variable ha, hb, hy : std_logic_vector(31 downto 0);
    variable n  : natural := 0;
    variable sp : character;
    variable ok : boolean;
  begin
    while not endfile(f) loop
      readline(f, l);
      hread(l, ha); read(l, sp, ok); hread(l, hb); read(l, sp, ok); hread(l, hy);
      assert n < N_EXPECT report "more vectors than N_EXPECT" severity failure;
      va(n) <= ha; vb(n) <= hb; vy(n) <= hy;
      n := n + 1;
    end loop;
    assert n = N_EXPECT
      report "vector count " & integer'image(n) & " /= " & integer'image(N_EXPECT)
      severity failure;
    wait for 1 ns;  -- let array signals update

    for i in 0 to N_EXPECT - 1 loop
      wait until falling_edge(clk);
      if i mod 7 = 6 then               -- bubble: junk data, valid low
        in_valid <= '0'; a <= x"DEADBEEF"; b <= x"12345678";
        wait until falling_edge(clk);
      end if;
      in_valid <= '1'; a <= signed(va(i)); b <= signed(vb(i));
    end loop;
    wait until falling_edge(clk);
    in_valid <= '0';
    for i in 1 to LATENCY + 2 loop
      wait until falling_edge(clk);
    end loop;
    done <= true;
    wait;
  end process;

  -- checker (in order, on falling edge)
  chk : process (clk)
    variable k : natural := 0;
  begin
    if falling_edge(clk) and out_valid = '1' then
      if k < N_EXPECT then
        if std_logic_vector(y) /= vy(k) then
          report "MISMATCH #" & integer'image(k) & " a=" & to_hstring(va(k)) &
                 " b=" & to_hstring(vb(k)) & " got=" & to_hstring(std_logic_vector(y)) &
                 " exp=" & to_hstring(vy(k)) severity error;
          errors <= errors + 1;
        end if;
        checked <= checked + 1;
      end if;
      k := k + 1;
    end if;
  end process;

  -- latency checker: model the valid pipe and compare every cycle
  lat : process (clk)
    variable pipe : std_logic_vector(LATENCY - 1 downto 0) := (others => '0');
  begin
    if rising_edge(clk) then
      pipe := pipe(LATENCY - 2 downto 0) & in_valid;
    end if;
    if falling_edge(clk) and out_valid /= pipe(LATENCY - 1) then
      report "LATENCY: out_valid=" & std_logic'image(out_valid) &
             ", expected " & std_logic'image(pipe(LATENCY - 1)) severity error;
      lat_errs <= lat_errs + 1;
    end if;
  end process;

  final : process
  begin
    wait until done;
    wait for 1 ns;
    if errors = 0 and lat_errs = 0 and checked = N_EXPECT then
      report TB_NAME & ": " & integer'image(checked) & " vectors, ROUND=" & integer'image(ROUND);
      report TB_NAME & ": ALL TESTS PASSED";
    else
      report "FAIL: errors=" & integer'image(errors) & " latency errors=" &
             integer'image(lat_errs) & " checked=" &
             integer'image(checked) & "/" & integer'image(N_EXPECT) severity failure;
    end if;
    finish;
  end process;
end architecture;
