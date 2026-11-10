--Helen Xu
--Last Updated: 11/8/2026
--Reads a framebuffer preloaded with a gradient and checks that 4 neighboring screen
--pixels show the same color and that blanking is black; syncs are aligned with the delayed data.
--PIX_DIV = 4 runs a 100 MHz clock with a one-in-four pixel enable, as on the board
--(tb/vga_scanout_100_tb.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_scanout_tb is
  generic (
    PIX_DIV : positive := 1;
    TB_NAME : string   := "vga_scanout_tb"   -- name in the pass line (scripts/sim.tcl)
  );
end entity;

architecture sim of vga_scanout_tb is

  constant FB_W      : natural := 320;
  constant FB_H      : natural := 240;
  constant FB_PIXELS : natural := FB_W * FB_H;

  constant H_VISIBLE : natural := 640;
  constant H_FRONT   : natural := 16;
  constant H_SYNC    : natural := 96;
  constant H_BACK    : natural := 48;
  constant H_TOTAL   : natural := 800;
  constant V_VISIBLE : natural := 480;
  constant V_FRONT   : natural := 10;
  constant V_SYNC    : natural := 2;
  constant V_BACK    : natural := 33;
  constant V_TOTAL   : natural := 525;

  type mem_t is array (0 to FB_PIXELS - 1) of std_logic_vector(7 downto 0); -- the framebuffer is 320x240, 8 bits per pixel

  -- the +1 keeps pixel 0 from being black, so blanking has to actually hide it
  function gradient(fx, fy : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned((fx + fy + 1) mod 256, 8));
  end function;

  function init_fb return mem_t is -- initialize the framebuffer with a gradient
    variable m : mem_t;
  begin
    for i in 0 to FB_PIXELS - 1 loop
      m(i) := gradient(i mod FB_W, i / FB_W);
    end loop;
    return m;
  end function;

  constant mem : mem_t := init_fb;

  signal clk      : std_logic := '0'; 
  signal rst_n    : std_logic := '0';
  signal fb_raddr : unsigned(16 downto 0);
  signal fb_rdata : std_logic_vector(7 downto 0) := (others => '0');
  signal vga_r    : std_logic_vector(2 downto 0);
  signal vga_g    : std_logic_vector(2 downto 0);
  signal vga_b    : std_logic_vector(1 downto 0);
  signal vga_hs_n : std_logic;
  signal vga_vs_n : std_logic;
  signal done     : boolean := false;
  signal pix_en   : std_logic := '1';

begin
 -- device under test instantiation
  dut : entity work.vga_scanout 
    port map (
      clk_i      => clk,
      rst_n_i    => rst_n,
      pix_en_i   => pix_en,
      fb_raddr_o => fb_raddr,
      fb_rdata_i => fb_rdata,
      vga_r_o    => vga_r,
      vga_g_o    => vga_g,
      vga_b_o    => vga_b,
      vga_hs_n_o => vga_hs_n,
      vga_vs_n_o => vga_vs_n
    );

  clk <= not clk after (20 ns / PIX_DIV) when not done;

  pix_div_gen : if PIX_DIV > 1 generate
    process (clk)
      variable n : natural range 0 to PIX_DIV - 1 := 0;
    begin
      if rising_edge(clk) then
        if n = PIX_DIV - 1 then n := 0; else n := n + 1; end if;
        if n = PIX_DIV - 1 then pix_en <= '1'; else pix_en <= '0'; end if;
      end if;
    end process;
  end generate;
  rst_n <= '1' after 200 ns;

  -- framebuffer model with 1-cycle read latency
  fb_model : process (clk)
  begin
    if rising_edge(clk) then
      assert to_integer(fb_raddr) < FB_PIXELS
        report "read address " & integer'image(to_integer(fb_raddr)) & " out of range"
        severity failure;
      fb_rdata <= mem(to_integer(fb_raddr));
    end if;
  end process;

  checker : process -- check that the output matches the gradient and that 2x2 blocks are the same color
    type line_t is array (0 to H_VISIBLE - 1) of std_logic_vector(7 downto 0);
    variable line_buf : line_t;
    variable prev_pix : std_logic_vector(7 downto 0) := (others => '0');
    variable pix      : std_logic_vector(7 downto 0);
    variable x, y     : natural;
    variable hs_low   : boolean;
    variable vs_low   : boolean;
    variable errors   : natural := 0;

    -- one screen pixel lasts PIX_DIV clocks
    procedure next_pixel is
    begin
      for k in 1 to PIX_DIV loop
        wait until falling_edge(clk);
      end loop;
    end procedure;

    procedure fail(msg : string) is -- report an error, but don't stop the simulation
    begin
      if errors < 10 then
        report msg & " at x=" & integer'image(x) & " y=" & integer'image(y) severity error;
      end if;
      errors := errors + 1;
    end procedure;
  begin
    wait until rst_n = '1';

    -- find pixel (0,0) from the sync outputs: first vsync rising edge, then the
    -- next hsync rising edge, then skip the back porch
    wait until rising_edge(vga_vs_n);
    wait until rising_edge(vga_hs_n);
    wait until falling_edge(clk);
    for i in 1 to H_BACK + (V_BACK - 1) * H_TOTAL loop
      next_pixel;
    end loop;

    for p in 0 to H_TOTAL * V_TOTAL - 1 loop
      x := p mod H_TOTAL;
      y := p / H_TOTAL;
      pix := vga_r & vga_g & vga_b;

      if x < H_VISIBLE and y < V_VISIBLE then
        if pix /= gradient(x / 2, y / 2) then
          fail("wrong pixel");
        end if;

        -- odd x matches the pixel to its left, odd y matches the row above
        if x mod 2 = 1 and pix /= prev_pix then
          fail("2x2 block mismatch (left/right)");
        end if;
        if y mod 2 = 0 then
          line_buf(x) := pix;
        elsif pix /= line_buf(x) then
          fail("2x2 block mismatch (up/down)");
        end if;
        prev_pix := pix;
      elsif pix /= "00000000" then
        fail("not black while blanked");
      end if;

      hs_low := x >= H_VISIBLE + H_FRONT and x < H_VISIBLE + H_FRONT + H_SYNC; -- hsync is low during the sync pulse
      vs_low := y >= V_VISIBLE + V_FRONT and y < V_VISIBLE + V_FRONT + V_SYNC; -- vsync is low during the sync pulse
      if (vga_hs_n = '0') /= hs_low then
        fail("hsync misaligned");
      end if;
      if (vga_vs_n = '0') /= vs_low then
        fail("vsync misaligned");
      end if;

      next_pixel;
    end loop;

    if errors = 0 then
      report TB_NAME & ": ALL TESTS PASSED";
    else
      report "FAIL: " & integer'image(errors) & " errors" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture sim;