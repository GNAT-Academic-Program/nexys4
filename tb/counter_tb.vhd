library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity counter_tb is
end entity;

architecture sim of counter_tb is 
    constant T        : time := 10 ns;
    constant N_CYCLES : natural := 280;

    signal clk   : std_logic := '0'; -- := '0' starts the value off at 0
    signal rst_n : std_logic := '0';
    signal en    : std_logic := '0';
    signal q     : unsigned(7 downto 0);
    signal done  : boolean := false;
begin
   clk <= not clk after T/2 when not done else '0';

    dut : entity work.counter -- dut--> device under test
        port map (clk_i => clk, rst_n_i => rst_n, en_i => en, q_o => q);

    stimulus : process -- stimulus will set the input values going into the counter and check results
        variable expected : natural range 0 to 255 := 0;
        variable wrapped  : boolean := false;
    begin
        -- Check reset before any clock edge: its asynchronous, doesnt wait for clock edge.
        wait for 1 ns;
        assert q = to_unsigned(0, 8) --basically == checks if q == unsigned(0,8)
            report "FAIL: initial reset" severity failure;

        --  N_CYCLES clock cycles of 10 ns. After the reset at cycle 15 the
        --  counter is enabled for 265 cycles, so it wraps 255 -> 0 once.
        for cycle in 1 to N_CYCLES loop
            -- set the input values going into the counter while the clock is low.
            if cycle <= 2 or cycle = 15 then
                rst_n <= '0'; -- Reset at startup and again after counting.
                en    <= '1'; -- Reset must win over enable
            elsif cycle = 8 or cycle = 9 then
                rst_n <= '1'; -- reset is off here since it's active low
                en    <= '0';    -- Two cycles must hold the previous count.
            else
                rst_n <= '1';
                en    <= '1';
            end if;

             if cycle = 15 then
                assert expected /= 0
                    report "tb bug: counter already 0 before async reset check" severity failure;
                wait for 1 ns;
                assert q = to_unsigned(0, 8)
                    report "FAIL: cycle 15 reset is not asynchronous (q /= 0 before clk edge)"
                severity failure;
            end if;

            wait until rising_edge(clk);
            if rst_n = '0' then
                expected := 0;
            elsif en = '1' then
                expected := (expected + 1) mod 256;
            end if;

            -- Let the clocked register and q update before checking them.
            if rst_n = '1' and en = '1' and expected = 0 then
                wrapped := true; -- count went 255 -> 0 without a reset
            end if;
            wait for 1 ns;
            assert q = to_unsigned(expected, 8)
                report "FAIL: cycle " & integer'image(cycle) &
                       ", expected " & integer'image(expected) &
                       ", got " & integer'image(to_integer(q))
                severity failure;
        end loop;

        assert wrapped report "FAIL: counter never wrapped 255 -> 0" severity failure;
        report "counter_tb: ALL TESTS PASSED";
        done <= true;
        finish(0);
        wait;
    end process;
end architecture;
