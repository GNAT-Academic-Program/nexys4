-- tri_setup_tb: Block D (RQ-92) against the Ada golden vectors in setup.csv
-- (sw/ada/ref, "make vectors"; scripts/sim.tcl copies tb/vectors/ into the run dir).
--
-- Phase 1: all 208 rows bit-exact. Every row is sent with in_last_i = '1' so
--          rejected rows (tri 7) still come out, with empty = '1'.
--          Every third row is held back with out_ready_i low for 5 cycles.
-- Phase 2: protocol. Rejected non-last triangle is dropped; reset
--          mid-triangle recovers.
--
-- Row: tri,x0,y0,z0,x1,y1,z1,x2,y2,z2,A0,B0,A1,B1,A2,B2,area2,TL,xmin,xmax,ymin,ymax,reject
-- Hex widths: x/y 8, z 2, A/B 7 (28 bits, sign-extended), area2 13 (52 bits),
-- TL 1, xmin/xmax 3, ymin/ymax 2. Compare A/B/area2 after a SIGNED resize up
-- to the hex width, never by slicing the file value down.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.qogpu_pkg.all;
use work.qogpu_fx_pkg.all;
use work.raster_pkg.all;

entity tri_setup_tb is
end entity;

architecture sim of tri_setup_tb is
  constant CLK_PERIOD : time := 10 ns;      -- 100 MHz
  constant N_ROWS     : natural := 208;     -- 8 directed + 200 random

  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal done  : boolean := false;

  signal in_valid, in_ready, in_last : std_logic := '0';
  signal vx0, vy0, vx1, vy1, vx2, vy2 : q16_t := (others => '0');
  signal z0, z1, z2 : unsigned(7 downto 0) := (others => '0');
  signal color : pixel_t := (others => '0');
  signal out_valid, out_ready : std_logic := '0';
  signal tri : tri_t;
begin
  clk <= not clk after CLK_PERIOD / 2 when not done;

  dut : entity work.tri_setup
    generic map (DEPTH_W => 8)
    port map (
      clk_i => clk, rst_n_i => rst_n,
      in_valid_i => in_valid, in_ready_o => in_ready,
      in_v0_x_i => vx0, in_v0_y_i => vy0,
      in_v1_x_i => vx1, in_v1_y_i => vy1,
      in_v2_x_i => vx2, in_v2_y_i => vy2,
      in_v0_z_i => z0, in_v1_z_i => z1, in_v2_z_i => z2,
      in_color_i => color, in_last_i => in_last,
      out_valid_o => out_valid, out_ready_i => out_ready,
      out_tri_o => tri
    );

  -- While valid and not ready, the payload must not change on the next edge
  stable_check : process (clk)
    variable prev : tri_t;
    variable held : boolean := false;
  begin
    if rising_edge(clk) then
      if held then
        assert tri = prev
          report "tri_setup_tb: out_tri_o changed while out_valid = '1' and out_ready = '0'"
          severity failure;
      end if;
      held := out_valid = '1' and out_ready = '0';
      prev := tri;
    end if;
  end process;

  stim : process
    file f     : text;
    variable l : line;
    variable c : character;
    variable n_tri : integer;
    variable x0f, y0f, x1f, y1f, x2f, y2f : std_logic_vector(31 downto 0);
    variable z0f, z1f, z2f : std_logic_vector(7 downto 0);
    variable a0f, b0f, a1f, b1f, a2f, b2f : std_logic_vector(27 downto 0);
    variable area_f : std_logic_vector(51 downto 0);
    variable tl_f   : std_logic_vector(3 downto 0);
    variable xmin_f, xmax_f : std_logic_vector(11 downto 0);
    variable ymin_f, ymax_f : std_logic_vector(7 downto 0);
    variable rej_f  : character;
    variable rows, errors : natural := 0;

    procedure fail(msg : string) is
    begin
      if errors < 10 then
        report msg severity error;
      end if;
      errors := errors + 1;
    end procedure;

    procedure check(n : integer; name : string; got, exp : std_logic_vector) is
    begin
      if got /= exp then
        fail("tri " & integer'image(n) & ": " & name & " = " & to_hstring(got) &
             ", expected " & to_hstring(exp));
      end if;
    end procedure;

    -- Present one triangle and wait for the input transfer
    procedure send_tri(x0, y0, x1, y1, x2, y2 : q16_t;
                       zz0, zz1, zz2 : unsigned(7 downto 0);
                       col : pixel_t; last : std_logic) is
    begin
      vx0 <= x0; vy0 <= y0; z0 <= zz0;
      vx1 <= x1; vy1 <= y1; z1 <= zz1;
      vx2 <= x2; vy2 <= y2; z2 <= zz2;
      color <= col; in_last <= last; in_valid <= '1';
      wait until rising_edge(clk) and in_ready = '1';
      in_valid <= '0';
    end procedure;

    procedure wait_clks(n : natural) is
    begin
      for k in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    function px(n : integer) return q16_t is
    begin
      return to_signed(n * Q16_ONE, 32);
    end function;

    -- Triangle 1 of setup.csv: (40,30) (200,30) (40,180)
    procedure send_tri1 is
    begin
      send_tri(px(40), px(30), px(200), px(30), px(40), px(180),
               x"0A", x"C8", x"64", x"01", '1');
    end procedure;

    procedure check_tri1 is
    begin
      wait until rising_edge(clk) and out_valid = '1';
      check(1, "area2", std_logic_vector(resize(tri.area2, 52)), x"05DC000000000");
      check(1, "TL", tri.tl, "101");
      check(1, "xmin", std_logic_vector(tri.xmin), std_logic_vector(to_unsigned(40, FB_X_W)));
      check(1, "xmax", std_logic_vector(tri.xmax), std_logic_vector(to_unsigned(200, FB_X_W)));
      check(1, "ymin", std_logic_vector(tri.ymin), std_logic_vector(to_unsigned(30, FB_Y_W)));
      check(1, "ymax", std_logic_vector(tri.ymax), std_logic_vector(to_unsigned(180, FB_Y_W)));
    end procedure;

  begin
    rst_n <= '0';
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst_n <= '1';

    ---------------------------------------------------------------- phase 1
    file_open(f, "setup.csv", read_mode);
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0 or l(l'left) = '#';
      read(l, n_tri); read(l, c);
      hread(l, x0f); read(l, c); hread(l, y0f); read(l, c); hread(l, z0f); read(l, c);
      hread(l, x1f); read(l, c); hread(l, y1f); read(l, c); hread(l, z1f); read(l, c);
      hread(l, x2f); read(l, c); hread(l, y2f); read(l, c); hread(l, z2f); read(l, c);
      hread(l, a0f); read(l, c); hread(l, b0f); read(l, c);
      hread(l, a1f); read(l, c); hread(l, b1f); read(l, c);
      hread(l, a2f); read(l, c); hread(l, b2f); read(l, c);
      hread(l, area_f); read(l, c); hread(l, tl_f); read(l, c);
      hread(l, xmin_f); read(l, c); hread(l, xmax_f); read(l, c);
      hread(l, ymin_f); read(l, c); hread(l, ymax_f); read(l, c);
      read(l, rej_f);

      send_tri(signed(x0f), signed(y0f), signed(x1f), signed(y1f), signed(x2f), signed(y2f),
               unsigned(z0f), unsigned(z1f), unsigned(z2f),
               std_logic_vector(to_unsigned(n_tri mod 256, 8)), '1');

      if rows mod 3 = 2 then
        -- back-pressure: output must stay valid and the block must stay busy
        out_ready <= '0';
        wait until rising_edge(clk) and out_valid = '1';
        for k in 1 to 5 loop
          wait until rising_edge(clk);
          if out_valid /= '1' or in_ready /= '0' then
            fail("tri " & integer'image(n_tri) & ": valid dropped or ready rose during back-pressure");
          end if;
        end loop;
      end if;
      out_ready <= '1';
      wait until rising_edge(clk) and out_valid = '1';

      check(n_tri, "A0", std_logic_vector(resize(tri.a(0), 28)), a0f);
      check(n_tri, "B0", std_logic_vector(resize(tri.b(0), 28)), b0f);
      check(n_tri, "A1", std_logic_vector(resize(tri.a(1), 28)), a1f);
      check(n_tri, "B1", std_logic_vector(resize(tri.b(1), 28)), b1f);
      check(n_tri, "A2", std_logic_vector(resize(tri.a(2), 28)), a2f);
      check(n_tri, "B2", std_logic_vector(resize(tri.b(2), 28)), b2f);
      check(n_tri, "area2", std_logic_vector(resize(tri.area2, 52)), area_f);
      check(n_tri, "TL", tri.tl, tl_f(2 downto 0));
      check(n_tri, "xmin", std_logic_vector(tri.xmin), xmin_f(8 downto 0));
      check(n_tri, "xmax", std_logic_vector(tri.xmax), xmax_f(8 downto 0));
      check(n_tri, "ymin", std_logic_vector(tri.ymin), ymin_f);
      check(n_tri, "ymax", std_logic_vector(tri.ymax), ymax_f);
      if rej_f = '1' then
        check(n_tri, "empty", (0 => tri.empty), "1");
      else
        check(n_tri, "empty", (0 => tri.empty), "0");
      end if;

      check(n_tri, "x0", std_logic_vector(tri.vx(0)), x0f);
      check(n_tri, "y0", std_logic_vector(tri.vy(0)), y0f);
      check(n_tri, "x1", std_logic_vector(tri.vx(1)), x1f);
      check(n_tri, "y1", std_logic_vector(tri.vy(1)), y1f);
      check(n_tri, "x2", std_logic_vector(tri.vx(2)), x2f);
      check(n_tri, "y2", std_logic_vector(tri.vy(2)), y2f);
      check(n_tri, "z0", std_logic_vector(tri.z(0)(7 downto 0)), z0f);
      check(n_tri, "z1", std_logic_vector(tri.z(1)(7 downto 0)), z1f);
      check(n_tri, "z2", std_logic_vector(tri.z(2)(7 downto 0)), z2f);
      check(n_tri, "color", tri.color, std_logic_vector(to_unsigned(n_tri mod 256, 8)));
      check(n_tri, "last", (0 => tri.last), "1");
      out_ready <= '0';
      rows := rows + 1;
    end loop;
    file_close(f);

    ---------------------------------------------------------------- phase 2
    -- Drop: tri 7 (collinear) that is not last never reaches the output
    out_ready <= '1';
    send_tri(px(20), px(20), px(100), px(100), px(60), px(60),
             x"00", x"00", x"00", x"07", '0');
    for k in 1 to 20 loop
      wait until rising_edge(clk);
      if out_valid /= '0' then
        fail("drop: out_valid rose for a rejected non-last triangle");
      end if;
    end loop;
    if in_ready /= '1' then
      fail("drop: in_ready did not return to '1'");
    end if;

    -- Reset in the middle of a triangle, then a good triangle must come out
    send_tri1;
    wait_clks(2);
    rst_n <= '0';
    wait_clks(2);
    rst_n <= '1';
    if out_valid /= '0' then
      fail("reset: out_valid still high");
    end if;
    wait_clks(10);
    if out_valid /= '0' or in_ready /= '1' then
      fail("reset: block did not return to idle");
    end if;
    send_tri1;
    check_tri1;

    if errors = 0 and rows = N_ROWS then
      report "tri_setup_tb: " & integer'image(rows) & " rows bit-exact with the Ada reference";
      report "tri_setup_tb: ALL TESTS PASSED";
    else
      report "FAIL: errors=" & integer'image(errors) & " rows=" & integer'image(rows)
        severity failure;
    end if;
    done <= true;
    wait;
  end process;
end architecture;
