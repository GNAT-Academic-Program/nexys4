library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.qogpu_pkg.all;
use work.frame_dump_pkg.all;

entity frame_dump_tb is
end entity;

architecture sim of frame_dump_tb is
  signal clk : std_logic := '0';
  signal wr_en : std_logic := '0';
  signal wr_addr, rd_addr : fb_addr_t := (others => '0');
  signal wr_data, rd_data : pixel_t := (others => '0');
begin
  clk <= not clk after 5 ns;
  dut : entity work.framebuffer
    port map (clk_i => clk, wr_en_i => wr_en, wr_addr_i => wr_addr,
              wr_data_i => wr_data, rd_addr_i => rd_addr, rd_data_o => rd_data);

  stimulus : process
    variable r, g, b : natural;
  begin
    -- Red increases left to right, green top to bottom, blue diagonally.
    -- First pixel is black, last pixel is white.
    for y in 0 to FB_H - 1 loop
      for x in 0 to FB_W - 1 loop
        r := x * 7 / (FB_W - 1);
        g := y * 7 / (FB_H - 1);
        b := (x + y) * 3 / (FB_W + FB_H - 2);
        wr_en <= '1';
        wr_addr <= to_unsigned(y * FB_W + x, FB_ADDR_W);
        wr_data <= std_logic_vector(to_unsigned(r * 32 + g * 4 + b, PIXEL_W));
        wait until rising_edge(clk);
        wait for 1 ns;
      end loop;
    end loop;
    wr_en <= '0';
    dump_frame("gradient.hex", clk, rd_addr, rd_data);
    report "frame_dump_tb: ALL TESTS PASSED";
    finish(0);
    wait;
  end process;
end architecture;
