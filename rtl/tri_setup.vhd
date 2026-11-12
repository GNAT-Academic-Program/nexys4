-- Block D: triangle setup (RQ-92)
--
-- Bit-exact with Qogpu_Raster.Setup (sw/ada/ref/src/qogpu_raster.adb) and
-- numeric contract rules 2, 7, 8, 9, 11, 12. Checked against tb/vectors/setup.csv.
--
--   A_i   = y_i - y_{i+1}                          25 bits signed
--   B_i   = x_{i+1} - x_i                          26 bits signed
--   area2 = A_0 (x_2 - x_0) + B_0 (y_2 - y_0)      51 bits signed, exact (no rounding)
--   area2 < 0  -> negate every A_i, B_i and area2 (one winding)
--   TL_i  = A_i > 0 or (A_i = 0 and B_i > 0)       on the normalized values
--   bbox  = floor of min/max, clamped to 0..319 / 0..239; vertices never clamped
--   area2 = 0  -> rejected: dropped, unless last, then sent with empty = '1'
--
-- Serial FSM, one triangle at a time (two triangles per frame, so latency
-- does not matter):
--   IDLE -> EDGE -> MUL -> SUM -> NORM -> FLAGS -> OUTPUT -> IDLE
--                                          \-> IDLE (rejected, not last: dropped)
-- in_ready_o is high only in IDLE. out_tri_o is a register held steady while
-- out_valid_o = '1' and out_ready_i = '0' (valid/ready rule, mvp_block_diagram.md).
-- Reset is synchronous, active low.
--
-- Do NOT use fx_mul (RQ-88) here: it rounds and shifts by 16. area2 is exact.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;
use work.qogpu_fx_pkg.all;
use work.raster_pkg.all;

entity tri_setup is
  generic (DEPTH_W : positive := 8);
  port (
    clk_i      : in  std_logic;
    rst_n_i    : in  std_logic;
    -- from Block C: 16.16 screen space, x in 0..320, y in 0..240
    in_valid_i : in  std_logic;
    in_ready_o : out std_logic;
    in_v0_x_i, in_v0_y_i : in q16_t;
    in_v1_x_i, in_v1_y_i : in q16_t;
    in_v2_x_i, in_v2_y_i : in q16_t;
    in_v0_z_i, in_v1_z_i, in_v2_z_i : in unsigned(DEPTH_W - 1 downto 0);
    in_color_i : in  pixel_t;
    in_last_i  : in  std_logic;
    -- to E1
    out_valid_o : out std_logic;
    out_ready_i : in  std_logic;
    out_tri_o   : out tri_t
  );
end entity;

architecture rtl of tri_setup is
  type state_t is (IDLE, EDGE, MUL, SUM, NORM, FLAGS, OUTPUT);
  signal state : state_t := IDLE;

  signal t : tri_t := TRI_ZERO;           -- triangle being built, then the output register

  -- datapath registers between states
  signal dx20 : b_t;                      -- x_2 - x_0, 26 bits
  signal dy20 : a_t;                      -- y_2 - y_0, 25 bits
  signal p0, p1 : signed(A_W + B_W - 1 downto 0);  -- 51-bit products, let Vivado infer DSPs
  signal area_sum  : signed(AREA_W downto 0);  -- 52 bits, asserted to fit 51 (rule 7)

  constant X_MAX_RAW : integer := FB_W * Q16_ONE;
  constant Y_MAX_RAW : integer := FB_H * Q16_ONE;

  function min3(a, b, c : q16_t) return q16_t is
  begin
    return minimum(a, minimum(b, c));
  end function;

  function max3(a, b, c : q16_t) return q16_t is
  begin
    return maximum(a, maximum(b, c));
  end function;

  -- floor to a pixel index, clamped to 0..hi (rule 8)
  function floor_clamp(v : q16_t; hi : natural) return unsigned is
    variable s : q16_t;
    variable p : signed(15 downto 0);
  begin
    s := shift_right(v, FRAC);
    p := s(15 downto 0);
    if p < 0 then
      return to_unsigned(0, FB_X_W);
    elsif p > hi then
      return to_unsigned(hi, FB_X_W);
    else
      return resize(unsigned(p), FB_X_W);
    end if;
  end function;
begin
  in_ready_o  <= '1' when state = IDLE else '0';
  out_valid_o <= '1' when state = OUTPUT else '0';
  out_tri_o   <= t;

  process (clk_i)
    variable nxt : natural range 0 to 2;
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        state <= IDLE;
        t     <= TRI_ZERO;
      else
        case state is
          when IDLE =>
            if in_valid_i = '1' then
              assert in_v0_x_i >= 0 and in_v0_x_i <= X_MAX_RAW and
                     in_v1_x_i >= 0 and in_v1_x_i <= X_MAX_RAW and
                     in_v2_x_i >= 0 and in_v2_x_i <= X_MAX_RAW
                report "tri_setup: x outside 0..320 (numeric contract rule 7)" severity failure;
              assert in_v0_y_i >= 0 and in_v0_y_i <= Y_MAX_RAW and
                     in_v1_y_i >= 0 and in_v1_y_i <= Y_MAX_RAW and
                     in_v2_y_i >= 0 and in_v2_y_i <= Y_MAX_RAW
                report "tri_setup: y outside 0..240 (numeric contract rule 7)" severity failure;
              t.vx(0) <= in_v0_x_i;  t.vy(0) <= in_v0_y_i;
              t.vx(1) <= in_v1_x_i;  t.vy(1) <= in_v1_y_i;
              t.vx(2) <= in_v2_x_i;  t.vy(2) <= in_v2_y_i;
              t.z(0)  <= resize(in_v0_z_i, DEPTH_MAX_W);
              t.z(1)  <= resize(in_v1_z_i, DEPTH_MAX_W);
              t.z(2)  <= resize(in_v2_z_i, DEPTH_MAX_W);
              t.color <= in_color_i;
              t.last  <= in_last_i;
              state   <= EDGE;
            end if;

          when EDGE =>
            for i in 0 to 2 loop
              nxt := (i + 1) mod 3;
              t.a(i) <= resize(t.vy(i) - t.vy(nxt), A_W);
              t.b(i) <= resize(t.vx(nxt) - t.vx(i), B_W);
            end loop;
            dx20 <= resize(t.vx(2) - t.vx(0), B_W);
            dy20 <= resize(t.vy(2) - t.vy(0), A_W);
            t.xmin <= floor_clamp(min3(t.vx(0), t.vx(1), t.vx(2)), FB_W - 1);
            t.xmax <= floor_clamp(max3(t.vx(0), t.vx(1), t.vx(2)), FB_W - 1);
            t.ymin <= resize(floor_clamp(min3(t.vy(0), t.vy(1), t.vy(2)), FB_H - 1), FB_Y_W);
            t.ymax <= resize(floor_clamp(max3(t.vy(0), t.vy(1), t.vy(2)), FB_H - 1), FB_Y_W);
            state <= MUL;

          when MUL =>
            p0 <= t.a(0) * dx20;
            p1 <= t.b(0) * dy20;
            state <= SUM;

          when SUM =>
            area_sum <= resize(p0, area_sum'length) + resize(p1, area_sum'length);
            state <= NORM;

          when NORM =>
            assert area_sum(AREA_W) = area_sum(AREA_W - 1)
              report "tri_setup: area2 does not fit 51 bits (numeric contract rule 7)"
              severity failure;
            if area_sum < 0 then
              for i in 0 to 2 loop
                t.a(i) <= -t.a(i);
                t.b(i) <= -t.b(i);
              end loop;
              t.area2 <= resize(-area_sum, AREA_W);
            else
              t.area2 <= resize(area_sum, AREA_W);
            end if;
            state <= FLAGS;

          when FLAGS =>
            for i in 0 to 2 loop
              if t.a(i) > 0 or (t.a(i) = 0 and t.b(i) > 0) then
                t.tl(i) <= '1';
              else
                t.tl(i) <= '0';
              end if;
            end loop;
            if t.area2 = 0 then
              t.empty <= '1';
              if t.last = '0' then
                state <= IDLE;      -- rejected and not last: drop
              else
                state <= OUTPUT;
              end if;
            else
              t.empty <= '0';
              state <= OUTPUT;
            end if;

          when OUTPUT =>
            if out_ready_i = '1' then
              state <= IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
