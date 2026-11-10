-- Runs fx_mul_tb with ROUND = 0 (truncate), the comparison mode. Generics
-- cannot be passed through scripts/sim.tcl, so this mode gets its own top level.
entity fx_mul_trunc_tb is
end entity;

architecture sim of fx_mul_trunc_tb is
begin
  t : entity work.fx_mul_tb
    generic map (ROUND => 0, TB_NAME => "fx_mul_trunc_tb");
end architecture;
