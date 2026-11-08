-- Framebuffer clear engine: fills all FB_PIXELS (320x240) with one color.
-- Framebuffer write port (fb_we_o, fb_waddr_o, fb_wdata_o) as named in
-- docs/architecture/mvp_block_diagram.md; it drives framebuffer.vhd's write port.
--
--   IDLE --start--> RUN (fb_we_o=1, fb_waddr_o counts 0..FB_PIXELS-1, one write per clock)
--   RUN  --last address written--> FINISH (done=1 for exactly one clock) --> IDLE
--
-- * start is only accepted in IDLE; it is ignored while busy or in FINISH.
-- * color is latched when start is accepted, so it may change during the run.
-- * Reset is synchronous, active low.
-- * The depth-buffer port and stall handling (memory_interface.md) arrive with RQ-96.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;

entity clear_engine is
  port (
    clk_i      : in  std_logic;
    rst_n_i    : in  std_logic;
    start_i    : in  std_logic;
    color_i    : in  pixel_t;
    busy_o     : out std_logic;
    done_o     : out std_logic;
    fb_we_o    : out std_logic;
    fb_waddr_o : out fb_addr_t;
    fb_wdata_o : out pixel_t
  );
end entity;

architecture rtl of clear_engine is
  type state_t is (IDLE, RUN, FINISH);
  signal state   : state_t := IDLE;
  signal cnt     : fb_addr_t := (others => '0');
  signal color_r : pixel_t := (others => '0');
  constant LAST_ADDR : fb_addr_t := to_unsigned(FB_PIXELS - 1, FB_ADDR_W);
begin
  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        state <= IDLE;
        cnt   <= (others => '0');
      else
        case state is
          when IDLE =>
            if start_i = '1' then
              color_r <= color_i;
              cnt     <= (others => '0');
              state   <= RUN;
            end if;
          when RUN =>
            if cnt = LAST_ADDR then
              state <= FINISH;
            else
              cnt <= cnt + 1;
            end if;
          when FINISH =>
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  busy_o     <= '1' when state = RUN    else '0';
  fb_we_o    <= '1' when state = RUN    else '0';
  done_o     <= '1' when state = FINISH else '0';
  fb_waddr_o <= cnt;
  fb_wdata_o <= color_r;
end architecture;
