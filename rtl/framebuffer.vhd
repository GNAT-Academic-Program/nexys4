-- 320x240 RGB332 framebuffer, simple dual-port, single clock.
-- Address = y * 320 + x  (valid range 0 .. 76799)
-- Write port: raster/CPU side. Read port: VGA side, 1-cycle read latency.
-- Same-address read/write in one cycle returns the OLD data (read-first).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;

entity framebuffer is
  port (
    clk_i   : in  std_logic;
    wr_en_i    : in  std_logic;
    wr_addr_i : in fb_addr_t;
    wr_data_i : in  pixel_t;   -- raster/CPU side
    rd_addr_i : in fb_addr_t;
    rd_data_o : out pixel_t    -- VGA side, 1-cycle read latency
  );
end entity;

architecture rtl of framebuffer is
  type mem_t is array (0 to FB_PIXELS - 1) of pixel_t;
  signal mem : mem_t := (others => (others => '0'));  -- black at power-up
  attribute ram_style : string;
  attribute ram_style of mem : signal is "block";
begin
  process (clk_i)
  begin
    if rising_edge(clk_i) then
      -- synthesis translate_off
      assert wr_en_i /= '1' or to_integer(wr_addr_i) < FB_PIXELS
        report "framebuffer: write addr " & integer'image(to_integer(wr_addr_i)) &
          " out of range (max " & integer'image(FB_PIXELS - 1) & ")"
        severity failure;
      assert to_integer(rd_addr_i) < FB_PIXELS
        report "framebuffer: read addr " & integer'image(to_integer(rd_addr_i)) &
          " out of range (max " & integer'image(FB_PIXELS - 1) & ")"
        severity failure;
      -- synthesis translate_on
      if wr_en_i = '1' then
        mem(to_integer(wr_addr_i)) <= wr_data_i;
      end if;
      rd_data_o <= mem(to_integer(rd_addr_i)); -- reg read -> BRAM
    end if;
  end process;
end architecture;
