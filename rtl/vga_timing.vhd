-- Helen Xu
-- Last edited: 11/8/2026 (pixel enable added)
-- this is the vga_timing module
-- it will make the timing signals for a 640x480 VGA screen
-- 640 visible + 16 front porch + 96 sync + 48 back porch = 800 clocks per line;
-- 480 + 10 + 2 + 33 = 525 lines; 
-- both syncs active-low; 25 MHz pixel rate.
-- The design runs on one clock (clk_i, 100 MHz on the board). pix_en_i is a
-- one-clock pulse at the pixel rate (every 4th clock at 100 MHz); the counters
-- only advance on clocks where it is high. It defaults to '1', so a 25 MHz
-- clk_i (as in the testbenches) needs no enable.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing is
  port (
    clk_i : in std_logic;
    rst_n_i : in std_logic; -- reset is active low
    pix_en_i : in std_logic := '1'; -- pixel-rate enable, see header
    x_o : out unsigned(9 downto 0); -- x vals, pixels0 to 799
    y_o : out unsigned(9 downto 0); -- y vals, pixels 0 to 524
    active_o : out std_logic; -- active high when inside the 640x480 picture
    hsync_n_o : out std_logic; -- horizontal sync, active low
    vsync_n_o : out std_logic   -- vertical sync, active low
  );
end entity;

architecture rtl of vga_timing is

  -- horizontal timing, counted in pixel ticks
  constant H_VISIBLE : natural := 640; --visible pixels
  constant H_FRONT   : natural := 16; -- front porch
  constant H_SYNC    : natural := 96; -- sync pulse
  constant H_BACK    : natural := 48; -- back porch
  constant H_TOTAL   : natural := H_VISIBLE + H_FRONT + H_SYNC + H_BACK; -- 800 total

  -- vertical timing, counted in lines
  constant V_VISIBLE : natural := 480;
  constant V_FRONT   : natural := 10;
  constant V_SYNC    : natural := 2;
  constant V_BACK    : natural := 33;
  constant V_TOTAL   : natural := V_VISIBLE + V_FRONT + V_SYNC + V_BACK; -- 525 total

  -- where the sync pulses start and end
  constant H_SYNC_START : natural := H_VISIBLE + H_FRONT;   -- 656
  constant H_SYNC_END   : natural := H_SYNC_START + H_SYNC; -- 752
  constant V_SYNC_START : natural := V_VISIBLE + V_FRONT;   -- 490
  constant V_SYNC_END   : natural := V_SYNC_START + V_SYNC; -- 492

  -- two 10 bit counters
  signal x_cnt : unsigned(9 downto 0) := (others => '0');
  signal y_cnt : unsigned(9 downto 0) := (others => '0');

begin

  -- x counts every clock, when it gets to 799 it goes back to 0 and y goes up by 1
  -- same idea as a nested for loop, y wraps at 524
  counters : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        x_cnt <= (others => '0');
        y_cnt <= (others => '0');
      elsif pix_en_i = '1' then
        if x_cnt = H_TOTAL - 1 then
          x_cnt <= (others => '0');
          if y_cnt = V_TOTAL - 1 then
            y_cnt <= (others => '0');
          else
            y_cnt <= y_cnt + 1;
          end if;
        else
          x_cnt <= x_cnt + 1;
        end if;
      end if;
    end if;
  end process counters;

  x_o <= x_cnt;
  y_o <= y_cnt;

  -- picture area is the top-left 640x480 corner of the 800x525 grid
  active_o <= '1' when (x_cnt < H_VISIBLE and y_cnt < V_VISIBLE) else '0';

  -- sync is low from LO up to (not including) HI
  hsync_n_o <= '0' when (x_cnt >= H_SYNC_START and x_cnt < H_SYNC_END) else '1';
  vsync_n_o <= '0' when (y_cnt >= V_SYNC_START and y_cnt < V_SYNC_END) else '1';

end architecture rtl;
