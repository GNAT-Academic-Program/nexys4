-- 8-bit up counter with enable and asynchronous active-low reset.
-- xsim batch-flow example (RQ-85); see docs/memos/xsim_howto.md.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
    port (
        clk_i   : in  std_logic;
        rst_n_i : in  std_logic; -- asynchronous, active low
        en_i    : in  std_logic; -- '1' counts, '0' holds
        q_o     : out unsigned(7 downto 0) -- wraps from 255 to 0
    );
end entity;

architecture rtl of counter is
    signal count : unsigned(7 downto 0);
begin
    q_o <= count;

    process (clk_i, rst_n_i)
    begin
        if rst_n_i = '0' then
            count <= (others => '0');
        elsif rising_edge(clk_i) then
            if en_i = '1' then
                count <= count + 1;
            end if;
        end if;
    end process;
end architecture;
