-- Helen Xu
-- Last edited: 10/27/2026
-- this is the test bench for the vga_timing module
-- it will count 800 clocks per line, 525 lines per frame, and checks sync pulse widths (96 and 2)
-- PIX_DIV = 1 runs a 25 MHz clock with the pixel enable tied high. PIX_DIV = 4
-- runs a 100 MHz clock with a one-in-four pixel enable, as on the board; the
-- checker then samples once per pixel and every count is the same.
-- tb/vga_timing_100_tb.vhd runs this testbench with PIX_DIV = 4.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing_tb is
  generic (
    PIX_DIV : positive := 1;
    TB_NAME : string   := "vga_timing_tb"   -- name in the pass line (scripts/sim.tcl)
  );
end entity vga_timing_tb;

architecture sim of vga_timing_tb is

  constant CLK_PERIOD : time    := 40 ns / PIX_DIV; -- 25 MHz pixel rate
  constant FRAMES     : natural := 3;     

  signal clk_i : std_logic := '0';
  signal rst_n_i : std_logic := '0';
  signal x_o, y_o : unsigned(9 downto 0);
  signal active_o, hsync_n_o, vsync_n_o : std_logic;
  signal pix_en : std_logic := '1';
  signal done : boolean := false;

begin

  -- clock runs until checker is done then sim ends
  clk_i <= not clk_i after CLK_PERIOD / 2 when not done else clk_i;

  dut : entity work.vga_timing
    port map (
      clk_i => clk_i, rst_n_i => rst_n_i, pix_en_i => pix_en, x_o => x_o, y_o => y_o,
      active_o => active_o, hsync_n_o => hsync_n_o, vsync_n_o => vsync_n_o);

  -- pixel enable: high one clock in every PIX_DIV
  pix_div_gen : if PIX_DIV > 1 generate
    process (clk_i)
      variable n : natural range 0 to PIX_DIV - 1 := 0;
    begin
      if rising_edge(clk_i) then
        if n = PIX_DIV - 1 then n := 0; else n := n + 1; end if;
        if n = PIX_DIV - 1 then pix_en <= '1'; else pix_en <= '0'; end if;
      end if;
    end process;
  end generate;

  -- reset
  process
  begin
    rst_n_i <= '0';
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk_i);
    rst_n_i <= '1';
    wait;
  end process;

  checker : process
    variable since_hfall : natural := 0; --clock since last falling edge
    variable since_vfall : natural := 0;
    variable h_low : natural := 0; --how long it has been low 
    variable v_low : natural := 0;
    variable active_count : natural := 0; --pixels in the frame
    variable vsync_count : natural := 0; --pulses so far
    variable prev_h : std_logic := '1'; --vals from prev clock
    variable prev_v : std_logic := '1';
    variable prev_x : natural := 0;
    variable prev_y : natural := 0;
    variable seen_hfall : boolean := false;
    variable seen_vfall : boolean := false;
    variable started    : boolean := false;
  begin
    wait until rst_n_i = '1';
    wait until rising_edge(clk_i) and pix_en = '1';

    -- first clock out of reset, top-left of the frame
    assert x_o = 0 and y_o = 0
      report "counters should be 0,0 right after reset" severity failure;

    while vsync_count < FRAMES loop

      --check x and y count properly and wrap
      if started then 
        if x_o = 0 then
          assert prev_x = 799 report "x didn't wrap from 799" severity failure;
          if y_o = 0 then
            assert prev_y = 524 report "y didn't wrap from 524" severity failure;
          else
            assert to_integer(y_o) = prev_y + 1
              report "y didn't go up when x wrapped" severity failure;
          end if;
        else
          assert to_integer(x_o) = prev_x + 1 report "x skipped a count" severity failure;
          assert to_integer(y_o) = prev_y     report "y moved in the middle of a line" severity failure;
        end if;
      end if;
      started := true;

      -- active inside 640x480
      if x_o < 640 and y_o < 480 then
        assert active_o = '1' report "active should be 1 in the picture" severity failure;
        active_count := active_count + 1;
      else
        assert active_o = '0' report "active should be 0 in the blanking area" severity failure;
      end if;

      -- check hsync
      if hsync_n_o = '0' then
        h_low := h_low + 1;
      end if;

      if prev_h = '1' and hsync_n_o = '0' then          -- falling edge
        assert to_integer(x_o) = 656
          report "hsync fell at x=" & integer'image(to_integer(x_o)) severity failure;
        if seen_hfall then
          assert since_hfall = 800
            report "line was " & integer'image(since_hfall) & " clocks, wanted 800"
            severity failure;
        end if;
        seen_hfall := true;
        since_hfall := 0;
      end if;

      if prev_h = '0' and hsync_n_o = '1' then          -- rising edge
        assert h_low = 96
          report "hsync was low for " & integer'image(h_low) & " clocks, wanted 96"
          severity failure;
        h_low := 0;
      end if;

      -- check vsync
      if vsync_n_o = '0' then
        v_low := v_low + 1;
      end if;

      if prev_v = '1' and vsync_n_o = '0' then          -- falling edge
        assert to_integer(y_o) = 490 and to_integer(x_o) = 0
          report "vsync fell at the wrong spot" severity failure;
        if seen_vfall then
          assert since_vfall = 525 * 800
            report "frame was " & integer'image(since_vfall) & " clocks, wanted 420000"
            severity failure;
          assert active_count = 640 * 480
            report "got " & integer'image(active_count) & " active clocks, wanted 307200"
            severity failure;
        end if;
        seen_vfall := true;
        since_vfall := 0;
        active_count := 0;
        vsync_count := vsync_count + 1;
      end if;

      if prev_v = '0' and vsync_n_o = '1' then          -- rising edge
        assert v_low = 2 * 800
          report "vsync was low for " & integer'image(v_low) & " clocks, wanted 1600"
          severity failure;
        v_low := 0;
      end if;

      -- details for next clock
      prev_h := hsync_n_o;
      prev_v := vsync_n_o;
      prev_x := to_integer(x_o);
      prev_y := to_integer(y_o);
      since_hfall := since_hfall + 1;
      since_vfall := since_vfall + 1;

      wait until rising_edge(clk_i) and pix_en = '1';
    end loop;

    report TB_NAME & ": ALL TESTS PASSED" severity note;
    done <= true;
    wait;
  end process checker;

end architecture sim;