library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;

entity framebuffer_tb is
end entity;

architecture sim of framebuffer_tb is
  constant T       : time    := 10 ns;
  constant LAST    : natural := FB_PIXELS - 1;          -- (239 * 320) + 319

  signal clk     : std_logic := '0';
  signal wr_en   : std_logic := '0';
  signal wr_addr : fb_addr_t := (others => '0');
  signal wr_data : pixel_t   := (others => '0');
  signal rd_addr : fb_addr_t := (others => '0');
  signal rd_data : pixel_t;
  signal done    : boolean   := false;

 -- addr dependent patter. Differs between a and a + 2^16
 -- Any dropped addr bits show up as a mismatch in test
 function pattern(a : natural) return pixel_t is
 begin
  return std_logic_vector(to_unsigned((a mod 251) + (a / 65536) * 4, PIXEL_W));
end function; -- AI used to design pattern, necessary for catching OOB

begin
  clk <= not clk after T/2 when not done else '0';

  dut : entity work.framebuffer
    port map (clk_i => clk, wr_en_i => wr_en, wr_addr_i => wr_addr, wr_data_i => wr_data,
              rd_addr_i => rd_addr, rd_data_o => rd_data);

  stim : process
    -- all stimulus is driven 1 ns after a rising edge
    procedure write_px(a : natural; d : pixel_t) is
    begin
      wr_en <= '1'; wr_addr <= to_unsigned(a, FB_ADDR_W); wr_data <= d;
      wait until rising_edge(clk); wait for 1 ns;
      wr_en <= '0';
    end procedure;

    -- Set rd_addr, confirm rd_data has NOT changed yet (no combinational path),
    -- then confirm the new data shows up after exactly one clock edge.
    procedure read_check(a : natural; exp : pixel_t) is
      variable before : pixel_t;
    begin
      before := rd_data;
      rd_addr <= to_unsigned(a, FB_ADDR_W);
      wait for T/4;
      assert rd_data = before
        report "rd_data changed before clock edge (not registered)" severity failure;
      wait until rising_edge(clk); wait for 1 ns;
      assert rd_data = exp
        report "addr " & integer'image(a) & ": expected " &
               integer'image(to_integer(unsigned(exp))) & ", got " &
               integer'image(to_integer(unsigned(rd_data)))
        severity failure;
    end procedure;
  begin
    -- addr width is smallest that holds every pixel
    assert 2**FB_ADDR_W >= FB_PIXELS and 2**(FB_ADDR_W - 1) < FB_PIXELS
      report "FB_ADDR_W does not match FB_PIXELS" severity failure;
    -- fb_addr: every (x,y) maps to y * FB_W + x
    for y in 0 to FB_H - 1 loop
      for x in 0 to FB_W - 1 loop
        assert to_integer(fb_addr(to_unsigned(x, FB_X_W), to_unsigned(y, FB_Y_W))) = y * FB_W + x
          report "fb_addr(" & integer'image(x) & "," & integer'image(y) & ") = " &
            integer'image(to_integer(fb_addr(to_unsigned(x, FB_X_W), to_unsigned(y, FB_Y_W)))) &
            ", expected " & integer'image(y * FB_W + x)
          severity failure;
      end loop;
    end loop;
    wait for 3 * T;
    wait until rising_edge(clk); wait for 1 ns;

    -- power-up contents are zero
    read_check(0, x"00");

    -- first pixel, (x=1,y=0), start row 1, end row 0, middle, last pixel
    write_px(0, x"E0");               -- red
    write_px(1, x"1C");               -- green
    write_px(FB_W, x"03");            -- blue, (x=0,y=1)
    write_px(FB_W - 1, x"FF");        -- white, end of row 0
    write_px(FB_PIXELS / 2, x"A5");   -- middle
    write_px(LAST, x"5A");            -- last pixel (x=319,y=239)

    -- read back
    read_check(0, x"E0");
    read_check(1, x"1C");
    read_check(FB_W, x"03");
    read_check(FB_W - 1, x"FF");
    read_check(FB_PIXELS / 2, x"A5");
    read_check(LAST, x"5A");
    read_check(2, x"00");             -- untouched address still zero

    -- back-to-back reads: one new pixel per clock, pipelined
    rd_addr <= to_unsigned(0, FB_ADDR_W);
    wait until rising_edge(clk); wait for 1 ns;
    assert rd_data = x"E0" report "pipelined read 0 failed" severity failure;
    rd_addr <= to_unsigned(1, FB_ADDR_W);
    wait until rising_edge(clk); wait for 1 ns;
    assert rd_data = x"1C" report "pipelined read 1 failed" severity failure;
    rd_addr <= to_unsigned(LAST, FB_ADDR_W);
    wait until rising_edge(clk); wait for 1 ns;
    assert rd_data = x"5A" report "pipelined read LAST failed" severity failure;

    -- write and read same address in the same cycle: read-first (old data)
    wr_en <= '1'; wr_addr <= to_unsigned(LAST, FB_ADDR_W); wr_data <= x"77";
    rd_addr <= to_unsigned(LAST, FB_ADDR_W);
    wait until rising_edge(clk); wait for 1 ns;
    wr_en <= '0';
    assert rd_data = x"5A" report "read-during-write should return old data" severity failure;
    read_check(LAST, x"77");

    -- wr_en = '0' should never write
    wr_addr <= to_unsigned(2, FB_ADDR_W); wr_data <= x"EE";
    wait until rising_edge(clk); wait for 1 ns;
    read_check(2, x"00");

    -- full sweep of unique pattern @ every addr to catch aliasing
    for a in 0 to LAST loop
      wr_en <= '1'; wr_addr <= to_unsigned(a, FB_ADDR_W); wr_data <= pattern(a);
      wait until rising_edge(clk); wait for 1 ns;
    end loop;
    wr_en <= '0';
    rd_addr <= to_unsigned(0, FB_ADDR_W);
    for a in 0 to LAST loop
      wait until rising_edge(clk); wait for 1 ns;
      assert rd_data = pattern(a)
        report "sweep mismatch @ addr " & integer'image(a) severity failure;
      if a < LAST then
        rd_addr <= to_unsigned(a + 1, FB_ADDR_W);
      end if;
    end loop;

    report "framebuffer_tb: ALL TESTS PASSED" severity note;
    done <= true;
    wait;
  end process;
end architecture;
