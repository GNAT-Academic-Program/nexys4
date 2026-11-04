-------------------------------------------------------------------------------
-- mem_ctrl_bram.vhd : BRAM back-end for the depth buffer (RQ-107), VHDL-2008
-- Written against docs/spec/memory_interface.md (RQ-106) and mem_if_pkg.vhd.
--
-- Behaviour (spec rule numbers in brackets):
--   * One clock clk_i, synchronous active-low reset rst_n_i             [1,2]
--   * 76,800 words x DEPTH_W bits; records carry 16 bits, low DEPTH_W used [3,4]
--   * No byte enables; writes get no response                            [5,6]
--   * Exactly one rsp pulse per accepted read, fixed latency 1:
--     accepted in cycle a -> rsp.valid/rdata in cycle a+1               [7,8]
--   * No response back-pressure; rsp.valid is a one-cycle pulse          [9]
--   * Requests take effect in acceptance order; a read right after a write
--     to the same address returns the new value (1 request/cycle)        [11]
--   * mem_ready: low in reset, rises on the first clk_i after reset is
--     released, stays high until the next reset                          [12]
--   * req_ready = mem_ready: low in reset and before init, then stays high
--     (BRAM never stalls)                                              [13, Latency table]
--   * Reset drops in-flight work: rsp.valid is gated by rst_n_i so a read
--     accepted just before reset cannot respond after it.
--   * Address > 76799 is a client bug: assert failure in simulation. In
--     hardware the RAM access is skipped (stored data untouched, read data
--     undefined) but the read still gets its one response.
--   * RAM powers up as zeros (BRAM INIT). The spec calls depth contents
--     undefined; clients must not rely on this, the clear engine clears.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_if_pkg.all;

entity mem_ctrl_bram is
  generic (
    DEPTH_W : positive range 1 to MEM_DATA_W := 8
  );
  port (
    clk_i     : in  std_logic;
    rst_n_i   : in  std_logic;
    req       : in  mem_req_t;
    req_ready : out std_logic;
    rsp       : out mem_rsp_t;
    mem_ready : out std_logic
  );
end entity mem_ctrl_bram;

architecture rtl of mem_ctrl_bram is
  type ram_t is array (0 to MEM_WORDS - 1) of std_logic_vector(DEPTH_W - 1 downto 0);
  signal ram : ram_t := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  signal rdy    : std_logic := '0';
  signal rd_v   : std_logic := '0';
  signal ram_q  : std_logic_vector(DEPTH_W - 1 downto 0) := (others => '0');
  signal accept : std_logic;
  signal in_rng : std_logic;
begin
  mem_ready <= rdy;
  req_ready <= rdy;
  accept    <= req.valid and rdy;
  in_rng    <= '1' when req.addr < MEM_WORDS else '0';

  rsp.valid <= rd_v and rst_n_i;
  rsp.rdata <= to_mem_data(ram_q);

  -- BRAM inference process (one address port, read-first)
  bram : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if accept = '1' and in_rng = '1' then
        if req.we = '1' then
          ram(to_integer(req.addr)) <= from_mem_data(req.wdata, DEPTH_W);
        end if;
        ram_q <= ram(to_integer(req.addr));
      end if;
    end if;
  end process;

  ctl : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        rdy  <= '0';
        rd_v <= '0';
      else
        rdy  <= '1';
        rd_v <= accept and not req.we;
      end if;
    end if;
  end process;

  -- simulation-only check (ignored by synthesis)
  chk : process (clk_i)
  begin
    if rising_edge(clk_i) then
      assert not (accept = '1' and in_rng = '0')
        report "mem_ctrl_bram: address above 76799 (client bug)"
        severity failure;
    end if;
  end process;
end architecture rtl;
