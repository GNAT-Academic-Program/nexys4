library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity command_controller_tb is
end entity;

architecture sim of command_controller_tb is
  type rotation_t is array (0 to 5) of signed(31 downto 0);
  constant IDENTITY : rotation_t := (
    0 | 2 | 4 => to_signed(65536, 32), others => (others => '0')
  );
  constant FIRST_ROTATION : rotation_t := (
    to_signed(32768, 32), to_signed(-56756, 32),
    to_signed(0, 32), to_signed(65536, 32),
    to_signed(-65536, 32), to_signed(0, 32)
  );
  constant NEXT_COS_X : signed(31 downto 0) := to_signed(0, 32);
  constant NEXT_SIN_X : signed(31 downto 0) := to_signed(65536, 32);

  signal clk : std_logic := '0';
  signal rstn, start, err, wr_en, clr_done, fetch_ready, frame_done : std_logic := '0';
  signal busy, done, error, clr_start, fetch_valid : std_logic;
  signal wr_sel : unsigned(2 downto 0) := (others => '0');
  signal wr_data : std_logic_vector(31 downto 0) := (others => '0');
  signal rotation : rotation_t;
  signal clr_color : std_logic_vector(7 downto 0);
  signal clr_depth : std_logic_vector(15 downto 0);
begin
  clk <= not clk after 5 ns;

  dut : entity work.command_controller
    generic map (DEPTH_W => 16)
    port map (
      clk_i => clk, rstn_i => rstn,
      start_i => start, busy_o => busy, done_o => done,
      err_i => err, error_o => error,
      rot_wr_en_i => wr_en, rot_wr_sel_i => wr_sel, rot_wr_data_i => wr_data,
      cos_x_o => rotation(0), sin_x_o => rotation(1),
      cos_y_o => rotation(2), sin_y_o => rotation(3),
      cos_z_o => rotation(4), sin_z_o => rotation(5),
      clr_start_o => clr_start, clr_color_o => clr_color,
      clr_depth_o => clr_depth, clr_done_i => clr_done,
      frame_start_valid_o => fetch_valid, frame_start_ready_i => fetch_ready,
      frame_done_i => frame_done
    );

  stimulus : process
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;

    procedure write_rotation(sel : natural; value : signed(31 downto 0)) is
    begin
      wr_en <= '1';
      wr_sel <= to_unsigned(sel, wr_sel'length);
      wr_data <= std_logic_vector(value);
      tick;
      wr_en <= '0';
    end procedure;

    variable expected : rotation_t;
  begin
    tick;
    assert busy = '0' and done = '0' and error = '0'
      and clr_start = '0' and fetch_valid = '0' and rotation = IDENTITY
      report "Reset must leave Block A idle with identity rotation" severity failure;
    assert clr_color = x"00" and clr_depth = x"FFFF"
      report "Expected black and maximum depth for a 16-bit depth buffer" severity failure;
    rstn <= '1';

    for sel in FIRST_ROTATION'range loop
      write_rotation(sel, FIRST_ROTATION(sel));
    end loop;
    write_rotation(6, to_signed(123, 32));
    write_rotation(7, to_signed(456, 32));
    assert rotation = IDENTITY report "Writes must only update pending rotation" severity failure;

    -- A write concurrent with start is excluded from the current snapshot.
    start <= '1';
    write_rotation(0, NEXT_COS_X);
    start <= '0';
    assert busy = '1' and clr_start = '1' and fetch_valid = '0'
      and rotation = FIRST_ROTATION
      report "Start must capture all six coefficients and request clear" severity failure;

    -- Ready from B must not cause a launch before the buffers are clear.
    fetch_ready <= '1';
    tick;
    assert busy = '1' and clr_start = '0' and fetch_valid = '0'
      report "Clear request must pulse once; B must wait for clear completion" severity failure;
    tick;
    assert busy = '1' and clr_start = '0' and fetch_valid = '0'
      report "Controller left the clear wait without clr_done" severity failure;

    clr_done <= '1';
    fetch_ready <= '0';
    tick;
    clr_done <= '0';
    assert fetch_valid = '1' report "Clear completion must request B to start" severity failure;

    start <= '1'; -- Busy start must neither clear again nor resnapshot.
    write_rotation(1, NEXT_SIN_X);
    start <= '0';
    for cycle in 1 to 2 loop
      assert busy = '1' and fetch_valid = '1' and clr_start = '0'
        and done = '0' and rotation = FIRST_ROTATION
        report "B backpressure must hold valid and preserve active rotation" severity failure;
      tick;
    end loop;
    fetch_ready <= '1';
    tick;
    assert busy = '1' and fetch_valid = '0' and done = '0'
      report "A must issue exactly one launch, then wait for downstream completion" severity failure;
    tick;
    assert busy = '1' and fetch_valid = '0' and rotation = FIRST_ROTATION
      report "B accepting the start must not complete the frame" severity failure;

    frame_done <= '1';
    tick;
    frame_done <= '0';
    assert busy = '0' and done = '1' and rotation = FIRST_ROTATION
      report "Successful frame must pulse done and retain its rotation" severity failure;
    tick;
    assert done = '0' and busy = '0' and clr_start = '0'
      report "Done must be a single cycle; busy start must not be queued" severity failure;

    start <= '1';
    tick;
    start <= '0';
    expected := FIRST_ROTATION;
    expected(0) := NEXT_COS_X;
    expected(1) := NEXT_SIN_X;
    assert clr_start = '1' and rotation = expected
      report "Next frame must capture pending updates" severity failure;

    clr_done <= '1';
    fetch_ready <= '0';
    tick;
    clr_done <= '0';
    err <= '1';
    tick;
    err <= '0';
    assert error = '1' and fetch_valid = '1' and busy = '1'
      report "Error must latch without retracting an outstanding start handshake" severity failure;
    fetch_ready <= '1';
    tick;
    frame_done <= '1';
    tick;
    frame_done <= '0';
    assert error = '1' and done = '0'
      report "A failed frame must not report successful completion" severity failure;

    start <= '1';
    tick;
    start <= '0';
    assert error = '1' and clr_start = '0' and fetch_valid = '0' and rotation = expected
      report "Sticky error must prevent another frame from starting" severity failure;

    rstn <= '0';
    tick;
    rstn <= '1';
    assert error = '0' and busy = '0' and rotation = IDENTITY
      report "Shared reset must clear the fault and restore identity rotation" severity failure;
    start <= '1';
    tick;
    assert clr_start = '1' and busy = '1' and rotation = IDENTITY
      report "After reset, a new frame must start with identity in both banks" severity failure;

    report "command_controller_tb: ALL TESTS PASSED";
    finish(0);
    wait;
  end process;
end architecture;
