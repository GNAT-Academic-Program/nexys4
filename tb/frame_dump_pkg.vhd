-- Simulation only. Provisional format: one RGB332 byte (two hex digits) per line.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.qogpu_pkg.all;

package frame_dump_pkg is
  procedure dump_frame(
    file_name : in string;
    signal clk : in std_logic;
    signal rd_addr : out fb_addr_t;
    signal rd_data : in pixel_t);
end package;

package body frame_dump_pkg is
  procedure dump_frame(
    file_name : in string;
    signal clk : in std_logic;
    signal rd_addr : out fb_addr_t;
    signal rd_data : in pixel_t) is
    file output : text open write_mode is file_name;
    variable row : line;
  begin
    -- Caller must disable writes and keep the clock running during the dump.
    for address in 0 to FB_PIXELS - 1 loop
      rd_addr <= to_unsigned(address, FB_ADDR_W);
      wait until rising_edge(clk);
      wait for 1 ns; -- allow the framebuffer's registered read to settle
      assert not is_x(rd_data)
        report "dump_frame: unknown pixel at address " & integer'image(address)
        severity failure;
      hwrite(row, rd_data);
      writeline(output, row);
    end loop;
    file_close(output);
  end procedure;
end package body;
