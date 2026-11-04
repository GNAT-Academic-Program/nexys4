-- Flat-port wrapper so Vivado can synthesize the controller as a top level
-- (record ports are not usable on a top-level entity). Synthesis check only.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_if_pkg.all;

entity mem_ctrl_bram_synth_top is
  generic (DEPTH_W : positive range 1 to MEM_DATA_W := 8);
  port (
    clk_i, rst_n_i : in  std_logic;
    req_valid      : in  std_logic;
    req_we         : in  std_logic;
    req_addr       : in  std_logic_vector(MEM_ADDR_W - 1 downto 0);
    req_wdata      : in  std_logic_vector(MEM_DATA_W - 1 downto 0);
    req_ready      : out std_logic;
    rsp_valid      : out std_logic;
    rsp_rdata      : out std_logic_vector(MEM_DATA_W - 1 downto 0);
    mem_ready      : out std_logic
  );
end entity;

architecture rtl of mem_ctrl_bram_synth_top is
  signal req : mem_req_t;
  signal rsp : mem_rsp_t;
begin
  req.valid <= req_valid;
  req.we    <= req_we;
  req.addr  <= unsigned(req_addr);
  req.wdata <= req_wdata;
  rsp_valid <= rsp.valid;
  rsp_rdata <= rsp.rdata;

  u : entity work.mem_ctrl_bram
    generic map (DEPTH_W => DEPTH_W)
    port map (clk_i => clk_i, rst_n_i => rst_n_i, req => req,
              req_ready => req_ready, rsp => rsp, mem_ready => mem_ready);
end architecture;
