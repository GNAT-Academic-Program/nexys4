--Helen Xu
--Last Updated: 11/8/2026
-- VGA scan-out: reads the 320x240 framebuffer and shows it on 640x480
-- with 2x2 pixel doubling. Output is RGB332.
--
-- Pipeline (clk_i cycles):
--   0: vga_timing gives (x, y); fb_raddr_o is computed from them
--   1: fb_rdata_i arrives (framebuffer has 1-cycle read latency);
--      active and the syncs are delayed one cycle to match
--   2: RGB and syncs leave from registers, so every VGA pin is driven
--      straight from a flip-flop
-- pix_en_i is the pixel-rate enable passed to vga_timing (see there).
-- The board's 4-4-4 VGA pins are mapped from RGB332 at the top level.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;

entity vga_scanout is
  port (
    clk_i      : in  std_logic;
    rst_n_i    : in  std_logic;
    pix_en_i   : in  std_logic := '1';
    fb_raddr_o : out fb_addr_t;
    fb_rdata_i : in  pixel_t;
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
  signal row_base : fb_addr_t;
  signal active_d : std_logic;
  signal hs_n_d   : std_logic;
  signal vs_n_d   : std_logic;

begin
  timing : entity work.vga_timing
    port map (
      clk_i     => clk_i,
      rst_n_i   => rst_n_i,
      pix_en_i  => pix_en_i,
      x_o       => x,
      y_o       => y,
      active_o  => active,
      hsync_n_o => hs_n,
      vsync_n_o => vs_n
    );

  -- screen pixel (x, y) reads framebuffer pixel (x/2, y/2)
  row_base <= resize(resize(y(9 downto 1), FB_ADDR_W) * FB_W, FB_ADDR_W);

  -- outside the picture this would go past the end of the framebuffer, so use 0
  fb_raddr_o <= row_base + resize(x(9 downto 1), FB_ADDR_W) when active = '1'
                else (others => '0');

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        active_d   <= '0';
        hs_n_d     <= '1';
        vs_n_d     <= '1';
        vga_r_o    <= (others => '0');
        vga_g_o    <= (others => '0');
        vga_b_o    <= (others => '0');
        vga_hs_n_o <= '1';
        vga_vs_n_o <= '1';
      else
        -- stage 1: line up with fb_rdata_i
        active_d <= active;
        hs_n_d   <= hs_n;
        vs_n_d   <= vs_n;
        -- stage 2: registered outputs, black while blanked
        if active_d = '1' then
          vga_r_o <= fb_rdata_i(7 downto 5);
          vga_g_o <= fb_rdata_i(4 downto 2);
          vga_b_o <= fb_rdata_i(1 downto 0);
        else
          vga_r_o <= (others => '0');
          vga_g_o <= (others => '0');
          vga_b_o <= (others => '0');
        end if;
        vga_hs_n_o <= hs_n_d;
        vga_vs_n_o <= vs_n_d;
      end if;
    end if;
  end process;

end architecture rtl;
