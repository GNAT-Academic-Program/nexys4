-- Runs vga_timing_tb at 100 MHz with a one-in-four pixel enable (PIX_DIV = 4),
-- as on the board. Generics cannot be passed through scripts/sim.tcl, so
-- this rate gets its own top level.
entity vga_timing_100_tb is
end entity;

architecture sim of vga_timing_100_tb is
begin
  t : entity work.vga_timing_tb
    generic map (PIX_DIV => 4, TB_NAME => "vga_timing_100_tb");
end architecture;
