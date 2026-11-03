-- Memory client port types for the depth buffer
-- Rules are in docs/spec/memory_interface.md
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qogpu_pkg.all;

package mem_if_pkg is
    constant MEM_WORDS  : positive := FB_PIXELS; -- one depth word per pixel
    constant MEM_ADDR_W : positive := FB_ADDR_W;
    constant MEM_DATA_W : positive := 16; -- widest DEPTH_W

    -- Read w no response after this many clk_i cycles is a bug
    constant MEM_RSP_WATCHDOG : positive := 1000;

    -- Arbiter client
    constant MEM_CLIENTS      : positive := 3;
    constant MEM_CLIENT_CLEAR : natural  := 0;
    constant MEM_CLIENT_E6    : natural  := 1;
    constant MEM_CLIENT_E4    : natural  := 2;

    subtype mem_addr_t is unsigned(MEM_ADDR_W - 1 downto 0);
    subtype mem_data_t is std_logic_vector(MEM_DATA_W - 1 downto 0);

    -- req_ready and mem_ready run the other way
    -- req_ready can drop at any time
    -- mem_ready stays low until init is done
    type mem_req_t is record
        valid : std_logic;
        we    : std_logic; -- 1 = write, 0 = read
        addr  : mem_addr_t; -- y * FB_W + x, use fb_addr()
        wdata : mem_data_t; -- low DEPTH_W bits used
    end record;

    -- One response per read
    type mem_rsp_t is record
        valid : std_logic;
        rdata : mem_data_t; -- low DEPTH_W bits used
    end record;

    type mem_req_array_t is array (natural range <>) of mem_req_t;
    type mem_rsp_array_t is array (natural range <>) of mem_rsp_t;

    constant MEM_REQ_IDLE : mem_req_t := (
        valid => '0',
        we    => '0',
        addr  => (others => '0'),
        wdata => (others => '0')
    );
    constant MEM_RSP_IDLE : mem_rsp_t := (
        valid => '0',
        rdata => (others => '0')
    );

    -- Go between DEPTH_W ports and fixed width records
    function to_mem_data(d : std_logic_vector) return mem_data_t;
    function from_mem_data(d : mem_data_t; depth_w : positive) return std_logic_vector;

    -- Clear to 2^DEPTH_W - 1
    function depth_clear(depth_w : positive) return std_logic_vector;
end package;

package body mem_if_pkg is
    function to_mem_data(d : std_logic_vector) return mem_data_t is
    begin
        assert d'length <= MEM_DATA_W
            report "mem_if_pkg: DEPTH_W is wider than MEM_DATA_W"
            severity failure;
        return std_logic_vector(resize(unsigned(d), MEM_DATA_W));
    end function;

    function from_mem_data(d : mem_data_t; depth_w : positive) return std_logic_vector is
    begin
        assert depth_w <= MEM_DATA_W
            report "mem_if_pkg: DEPTH_W is wider than MEM_DATA_W"
            severity failure;
        return d(depth_w - 1 downto 0);
    end function;

    function depth_clear(depth_w : positive) return std_logic_vector is
        constant ones : std_logic_vector(depth_w - 1 downto 0) := (others => '1');
    begin
        return ones;
    end function;
end package body;
