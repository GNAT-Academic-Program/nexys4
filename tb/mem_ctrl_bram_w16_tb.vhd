-- Runs the same testbench with DEPTH_W = 16 (scripts/sim.tcl cannot set
-- generics, so the second width gets its own top level).
entity mem_ctrl_bram_w16_tb is
end entity;

architecture sim of mem_ctrl_bram_w16_tb is
begin
  t : entity work.mem_ctrl_bram_tb
    generic map (DEPTH_W => 16, TB_NAME => "mem_ctrl_bram_w16_tb");
end architecture;
