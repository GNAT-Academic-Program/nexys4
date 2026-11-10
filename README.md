# Nexys4 QOGPU
Team: Rose-Hulman Team 5: Connor Bodie, Landon Cahoon, Alex Freel, Vance Steele, Helen Xu
MVP Goal: Implement a GPU on the Nexys4 FPGA board.

# nexys4

Board support package for the Digilent Nexys 4 and Nexys 4 DDR running the
[neorv32_nexys4](https://github.com/GNAT-Academic-Program/neorv32_nexys4)
bitstream.

## Overview

`nexys4` is a board crate of the GAP NEORV32 stack. It instantiates the
[neorv32](https://github.com/GNAT-Academic-Program/neorv32_ghal) drivers for
the wiring of this board and gives applications a `Board` package, the same
way `mercury2` does for the Mercury 2. One crate covers both the Nexys 4 and
the Nexys 4 DDR: the GPIO numbers are the same, only the bitstream differs.

```
Application (examples/blinky)
   |
Board crate (nexys4)     <- this crate
   |
MCU crate (neorv32)
   |
Generic interfaces (gpio_generic, usart_generic, debug_generic)
```

## What the board offers today

With the current bitstream the SoC exposes the LEDs, switches, buttons and
the console UART. That is what this crate covers.

| `Board` name | Hardware |
|---|---|
| `Console` | UART0 on the USB-UART bridge. 19200 8N1, same as the bootloader, so one terminal covers both |
| `Leds (0 .. 15)`, `Led` | LD0 .. LD15. `Led` is LD0, also the bootloader status LED |
| `Switches (0 .. 15)`, `Switch_On` | SW0 .. SW15 |
| `Buttons (Center .. Down)`, `Button_Pressed` | BTNC, BTNU, BTNL, BTNR, BTND |

`Board.Initialize` opens the console, checks that the bitstream carries the
NEORV32 release the drivers were written for (v1.13.6), and configures the
GPIO. On a version mismatch it prints both versions and stops, blinking all
LEDs.

`Debug.Put_Line` writes to the console. The last chance handler prints the
exception on the console and blinks LD0 fast.

The clock is 100 MHz. The drivers read it from the SoC; the runtime gets it
from this crate's `alire.toml` (`light_tasking_neorv32.Clock_Frequency`).

The VGA port, the 7-segment display, the PMOD headers and the on-board memory
need gateware first.

## Requirements

- [Alire](https://alire.ada.dev/) 2.0 or newer and git. The RISC-V toolchain
  is fetched by Alire.
- A Nexys 4 or Nexys 4 DDR with the neorv32_nexys4 bitstream loaded, connected over USB.

## Build the example

From the root of this repo:

```
cd examples
```

```
alr build
```

Result: `examples/bin/blinky`.

## Run it on the board

The bootloader in the bitstream takes the program over the serial port. The
upload script converts the ELF, sends it, starts it, and then shows what the
program prints. Press Escape to quit.

1. Press CPU_RESET so the bootloader is waiting. It waits 8 seconds for a
   command.
2. Run the upload script from the root of this repo.

Linux:

```
bash upload/upload.sh examples/bin/blinky
```

Windows:

```
.\upload\upload.bat examples\bin\blinky
```

The script finds the board's serial port on its own. If it cannot, it says
so and tells you how to pass the port by hand.

Expected output:

```
blinky on nexys4
tick 1
tick 2
```

LD0 toggles every half second, LD1 .. LD15 follow SW1 .. SW15, and a pressed
button is named on the console.

Linux may refuse the serial port without `sudo`; the script prints the exact
command to run in that case. Windows may need "Load VCP" enabled once on
"USB Serial Converter B" in Device Manager; the neorv32_mercury2 README has
the steps, they apply to the Nexys as well.

## In application code

```ada
with Board;
with Gpio;
with Debug;

procedure Main is
begin
   Board.Initialize;
   Debug.Put_Line ("hello");
   loop
      Gpio.Toggle (Board.Led);
      delay 0.5;
   end loop;
end Main;
```

The project file needs the runtime, as in `examples/nexys4_examples.gpr`:

```ada
with "runtime_build.gpr";
with "ravenscar_build.gpr";

for Target use runtime_build'Target;
for Runtime ("Ada") use runtime_build'Runtime ("Ada");

package Linker is
   for Switches ("Ada") use Runtime_Build.Linker_Switches;
end Linker;
```

## Integration

Add to your `alire.toml`:

```toml
[[depends-on]]
nexys4 = "*"

[[pins]]
nexys4 = { url = "https://github.com/GNAT-Academic-Program/nexys4.git", branch = "main" }
```

## Layout

```
src/board.ads, board.adb        Board: console, LEDs, switches, buttons, Initialize
src/board_gpio.ads              every GPIO pin used, in one place
src/instances.ads               driver instances: UART0 -> Console
src/debug/                      Debug output and the last chance handler
examples/                       nexys4_examples crate: blinky
upload/                         upload scripts for Linux and Windows
```

## Dependencies

- `neorv32`: NEORV32 drivers (GPIO, UART, SYSINFO)
- `light_tasking_neorv32`: the Ada runtime
- `debug_generic`: generic debug output

## License

MIT OR Apache-2.0 WITH LLVM-exception
