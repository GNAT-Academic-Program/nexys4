-- Testbench for clear_engine, wired to the real framebuffer so the final
-- memory contents are checked as well as the write stream.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;

entity clear_engine_tb is
end entity;

architecture sim of clear_engine_tb is
  constant T     : time    := 10 ns;
  constant NPIX  : natural := FB_PIXELS;

  signal clk, rst_n : std_logic := '0';
  signal start      : std_logic := '0';
  signal color_in   : pixel_t := (others => '0');
  signal busy, done : std_logic;
  signal we         : std_logic;
  signal waddr      : fb_addr_t;
  signal wdata      : pixel_t;
  signal raddr      : fb_addr_t := (others => '0');
  signal rdata      : pixel_t;

  -- expectations / monitor results
  signal exp_color   : std_logic_vector(7 downto 0) := (others => '0');
  signal done_count  : natural := 0;
  signal write_total : natural := 0;
  signal finished    : boolean := false;
begin
  clk <= not clk after T/2 when not finished else '0';

  eng : entity work.clear_engine
    port map (clk_i => clk, rst_n_i => rst_n, start_i => start, color_i => color_in,
              busy_o => busy, done_o => done, fb_we_o => we, fb_waddr_o => waddr,
              fb_wdata_o => wdata);

  fb : entity work.framebuffer
    port map (clk_i => clk, wr_en_i => we, wr_addr_i => waddr, wr_data_i => wdata,
              rd_addr_i => raddr, rd_data_o => rdata);

  -- Monitor: samples every clock edge and checks the write stream.
  monitor : process (clk)
    variable n         : natural := 0;
    variable done_prev : std_logic := '0';
  begin
    if rising_edge(clk) and rst_n = '1' then
      if we = '1' then
        assert busy = '1' report "we high while busy low" severity failure;
        assert n < NPIX report "more than 76800 writes in one clear" severity failure;
        assert waddr = to_unsigned(n, FB_ADDR_W)
          report "bad address: expected " & integer'image(n) &
                 ", got " & integer'image(to_integer(waddr)) severity failure;
        assert wdata = exp_color
          report "bad color at address " & integer'image(n) severity failure;
        n := n + 1;
        write_total <= write_total + 1;
      else
        assert busy = '0' or n = 0 report "busy high but no write" severity failure;
      end if;
      if done = '1' then
        assert n = NPIX
          report "done after " & integer'image(n) & " writes, expected 76800" severity failure;
        assert busy = '0' and we = '0' report "busy/we high during done" severity failure;
        assert done_prev = '0' report "done lasted more than one cycle" severity failure;
        done_count <= done_count + 1;
        n := 0;
      end if;
      done_prev := done;
    end if;
  end process;

  stim : process
    procedure pulse_start is
    begin
      start <= '1';
      wait until rising_edge(clk); wait for 1 ns;
      start <= '0';
    end procedure;

    procedure wait_done is
    begin
      wait until done = '1' for 2 ms;
      assert done = '1' report "timeout waiting for done" severity failure;
      wait until rising_edge(clk); wait for 1 ns;   -- done pulse has ended
    end procedure;

    -- read every pixel back (pipelined, 1-cycle latency) and compare
    procedure verify_all(c : std_logic_vector(7 downto 0)) is
    begin
      for i in 0 to NPIX loop
        if i < NPIX then
          raddr <= to_unsigned(i, FB_ADDR_W);
        end if;
        wait until rising_edge(clk); wait for 1 ns;
        if i > 0 then
          assert rdata = c
            report "framebuffer mismatch at address " & integer'image(i - 1)
            severity failure;
        end if;
      end loop;
    end procedure;
  begin
    -- reset
    rst_n <= '0';
    wait for 3 * T;
    wait until rising_edge(clk); wait for 1 ns;
    rst_n <= '1';
    wait until rising_edge(clk); wait for 1 ns;

    -- idle: nothing happens without start
    assert busy = '0' and we = '0' and done = '0'
      report "engine not idle after reset" severity failure;
    for i in 1 to 20 loop
      wait until rising_edge(clk); wait for 1 ns;
    end loop;
    assert write_total = 0 report "writes without start" severity failure;

    -- clear #1: color E0
    color_in <= x"E0"; exp_color <= x"E0";
    pulse_start;
    assert busy = '1' and we = '1' report "busy/we not high after start" severity failure;
    wait_done;
    for i in 1 to 10 loop
      wait until rising_edge(clk); wait for 1 ns;
    end loop;
    assert done_count = 1 report "done did not pulse exactly once (clear 1)" severity failure;
    assert write_total = NPIX report "wrong write count (clear 1)" severity failure;
    assert busy = '0' and we = '0' report "engine not idle after clear 1" severity failure;
    verify_all(x"E0");

    -- clear #2: color 1C; start pulse and color change mid-run must be ignored
    color_in <= x"1C"; exp_color <= x"1C";
    pulse_start;
    for i in 1 to 100 loop
      wait until rising_edge(clk); wait for 1 ns;
    end loop;
    color_in <= x"FF";
    pulse_start;                       -- ignored: engine is busy
    assert busy = '1' report "busy dropped on extra start" severity failure;
    wait_done;
    for i in 1 to 10 loop
      wait until rising_edge(clk); wait for 1 ns;
    end loop;
    assert done_count = 2 report "done did not pulse exactly once (clear 2)" severity failure;
    assert write_total = 2 * NPIX report "wrong write count (clear 2)" severity failure;
    verify_all(x"1C");

    report "clear_engine_tb: ALL TESTS PASSED" severity note;
    finished <= true;
    wait;
  end process;
end architecture;
