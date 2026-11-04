--Helen Xu
--Last Updated: 11/3/2026
--vga scanout module: read framebuffer with 2x2 doubling, output RGB332 pins
--outline
-- module vga_scanout (
--   input  logic clk, rst_n,
--   output logic [16:0] fb_raddr, input logic [7:0] fb_rdata,
--   output logic [2:0] vga_r, vga_g, output logic [1:0] vga_b,
--   output logic vga_hs_n, vga_vs_n
-- );
--   // instantiate vga_timing; compute fb_raddr from x[9:1], y[9:1]; blank outside active
--   // RGB332: r = pix[7:5], g = pix[4:2], b = pix[1:0]
-- endmodule

-- VGA scan-out: reads the 320x240 framebuffer and shows it on 640x480
-- with 2x2 pixel doubling. Output is RGB332.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_scanout is
  port (
    clk_i      : in  std_logic;
    rst_n_i    : in  std_logic;
    fb_raddr_o : out unsigned(16 downto 0);
    fb_rdata_i : in  std_logic_vector(7 downto 0);
    vga_r_o    : out std_logic_vector(2 downto 0); --3 bits red
    vga_g_o    : out std_logic_vector(2 downto 0); --3 bits green
    vga_b_o    : out std_logic_vector(1 downto 0); --2 bits blue
    vga_hs_n_o : out std_logic;
    vga_vs_n_o : out std_logic
  );
end entity;

architecture rtl of vga_scanout is

  signal x, y     : unsigned(9 downto 0);
  signal active   : std_logic;
  signal hs_n     : std_logic;
  signal vs_n     : std_logic;
  signal row_base : unsigned(16 downto 0);
  signal active_d : std_logic;

begin
 -- device under test instantiation
  timing : entity work.vga_timing
    port map (
      clk_i     => clk_i,
      rst_n_i   => rst_n_i,
      x_o       => x,
      y_o       => y,
      active_o  => active,
      hsync_n_o => hs_n,
      vsync_n_o => vs_n
    );

  -- screen pixel (x, y) reads framebuffer pixel (x/2, y/2)
  row_base <= resize(resize(y(9 downto 1), 17) * 320, 17);

  -- outside the picture this would go past the end of the framebuffer, so use 0
  fb_raddr_o <= row_base + resize(x(9 downto 1), 17) when active = '1' else (others => '0');

  -- fb_rdata_i comes one cycle after the address, so delay active and the syncs too
  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        active_d   <= '0';
        vga_hs_n_o <= '1';
        vga_vs_n_o <= '1';
      else
        active_d   <= active;
        vga_hs_n_o <= hs_n;
        vga_vs_n_o <= vs_n;
      end if;
    end if;
  end process;

  vga_r_o <= fb_rdata_i(7 downto 5) when active_d = '1' else "000"; -- red 
  vga_g_o <= fb_rdata_i(4 downto 2) when active_d = '1' else "000"; -- green 
  vga_b_o <= fb_rdata_i(1 downto 0) when active_d = '1' else "00";   -- blue 

end architecture rtl;