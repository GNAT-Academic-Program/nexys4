--Initializes BRAM with vertex and face data found in "data/cube_init.txt"
--https://docs.amd.com/r/2024.2-English/ug901-vivado-synthesis/Initializing-Block-RAM-From-an-External-Data-File-Verilog

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity asset_memory is
   generic (
      INIT_FILE : string := "data/cube_init.txt"
   );
   port (
      clk  : in  std_logic;
      addr : in  unsigned(9 downto 0);           -- Word address: 0..1023
      data : out std_logic_vector(31 downto 0)
   );
end entity asset_memory;

architecture rtl of asset_memory is
   type rom_t is array (0 to 1023) of bit_vector(31 downto 0);

   impure function load_rom(filename : string) return rom_t is
      file input_file : text open read_mode is filename;
      variable row    : line;
      variable result : rom_t;
   begin
      for i in result'range loop
         readline(input_file, row);
         read(row, result(i));
      end loop;
      return result;
   end function;

   signal rom : rom_t := load_rom(INIT_FILE);

   attribute rom_style : string;
   attribute rom_style of rom : signal is "block";
begin
   process(clk)
   begin
      if rising_edge(clk) then
         data <= to_stdlogicvector(rom(to_integer(addr)));
      end if;
   end process;
end architecture rtl;