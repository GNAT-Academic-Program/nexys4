-- Block A: frame sequencing and frame-stable rotation coefficients.
-- Block B owns face traversal and reads the separate asset memory directly.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity command_controller is
  generic (
    DEPTH_W : positive range 1 to 16 := 8
  );
  port (
    clk_i   : in std_logic;
    rstn_i  : in std_logic; -- Synchronous active-low pipeline reset.

    start_i : in  std_logic; -- One-cycle request; accepted only when idle.
    busy_o  : out std_logic;
    done_o  : out std_logic; -- One-cycle pulse on successful frame completion.
    err_i   : in  std_logic;
    error_o : out std_logic; -- Sticky until shared pipeline reset.

    -- Writes update the pending bank, even while a frame is active.
    rot_wr_en_i   : in std_logic;
    rot_wr_sel_i  : in unsigned(2 downto 0);
    rot_wr_data_i : in std_logic_vector(31 downto 0);

    -- Active signed 16.16 coefficients, held for the entire frame.
    cos_x_o : out signed(31 downto 0);
    sin_x_o : out signed(31 downto 0);
    cos_y_o : out signed(31 downto 0);
    sin_y_o : out signed(31 downto 0);
    cos_z_o : out signed(31 downto 0);
    sin_z_o : out signed(31 downto 0);

    -- The clear engine accepts the start pulse and reports both buffers clear.
    clr_start_o : out std_logic;
    clr_color_o : out std_logic_vector(7 downto 0);
    clr_depth_o : out std_logic_vector(DEPTH_W - 1 downto 0);
    clr_done_i  : in  std_logic;

    -- Start B once per frame. Completion comes from the end of the pipeline.
    frame_start_valid_o : out std_logic;
    frame_start_ready_i : in  std_logic;
    frame_done_i        : in  std_logic
  );
end entity command_controller;

architecture rtl of command_controller is
  type state_t is (IDLE, REQUEST_CLEAR, WAIT_CLEAR, START_FETCH, WAIT_FRAME);
  signal state : state_t;
  signal frame_accept : std_logic;
  signal error_latched : std_logic;

  -- Selector order: cos X, sin X, cos Y, sin Y, cos Z, sin Z.
  type rotation_t is array (0 to 5) of signed(31 downto 0);
  constant ONE_Q16 : signed(31 downto 0) := to_signed(65536, 32);
  constant IDENTITY_ROTATION : rotation_t := (
    0 | 2 | 4 => ONE_Q16,
    others    => (others => '0')
  );
  signal pending_rotation : rotation_t;
  signal active_rotation  : rotation_t;
begin
  frame_accept <= '1' when state = IDLE and start_i = '1'
                        and error_latched = '0' and err_i = '0' else '0';
  busy_o  <= '0' when state = IDLE else '1';
  error_o <= error_latched;

  clr_start_o <= '1' when state = REQUEST_CLEAR else '0';
  clr_color_o <= (others => '0'); -- RGB332 black.
  clr_depth_o <= (others => '1'); -- Far depth, per memory_interface.md.
  frame_start_valid_o <= '1' when state = START_FETCH else '0';

  cos_x_o <= active_rotation(0);
  sin_x_o <= active_rotation(1);
  cos_y_o <= active_rotation(2);
  sin_y_o <= active_rotation(3);
  cos_z_o <= active_rotation(4);
  sin_z_o <= active_rotation(5);

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      done_o <= '0';
      if rstn_i = '0' then
        state <= IDLE;
        error_latched <= '0';
        pending_rotation <= IDENTITY_ROTATION;
        active_rotation  <= IDENTITY_ROTATION;
      else
        -- Keep any outstanding handshake intact on error. A shared reset
        -- is required before starting again; no abort/drain port is assumed.
        if err_i = '1' then
          error_latched <= '1';
        end if;

        if rot_wr_en_i = '1' then
          case rot_wr_sel_i is
            when "000" | "001" | "010" | "011" | "100" | "101" =>
              pending_rotation(to_integer(rot_wr_sel_i)) <= signed(rot_wr_data_i);
            when others => null;
          end case;
        end if;

        if frame_accept = '1' then
          -- Same-edge writes belong to the next frame, not this snapshot.
          active_rotation <= pending_rotation;
        end if;

        case state is
          when IDLE =>
            if frame_accept = '1' then
              state <= REQUEST_CLEAR;
            end if;
          when REQUEST_CLEAR | WAIT_CLEAR =>
            if clr_done_i = '1' then
              state <= START_FETCH;
            else
              state <= WAIT_CLEAR;
            end if;
          when START_FETCH =>
            if frame_start_ready_i = '1' then
              state <= WAIT_FRAME;
            end if;
          when WAIT_FRAME =>
            if frame_done_i = '1' then
              state <= IDLE;
              if error_latched = '0' and err_i = '0' then
                done_o <= '1';
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
