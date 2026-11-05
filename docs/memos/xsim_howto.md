# Counter simulation

Run the 8-bit counter testbench with Vivado Simulator (xsim); no FPGA board is required. The testbench checks asynchronous active-low reset, enabled increments, and disabled hold behavior over 20 cycles.

# Prerequisites

- Vivado with xsim, and GNU Make on `PATH`.
- The testbench requires VHDL-2008 (`std.env.finish`).
- Files used: the repository `Makefile`, the shared `scripts/sim.tcl`, `rtl/counter.vhd`, and `tb/counter_tb.vhd`.

# Run

In Windows Command Prompt, enter these commands separately. Replace the repository path, and adjust the Vivado path if necessary.

```bat
cd /d "C:\path\to\nexys4_qogpu"
```

```bat
call "C:\Xilinx\Vivado\2024.2\settings64.bat"
```

Check that every tool resolves, and fix any that are missing before running `make`:

```bat
where make
where vivado
where xvhdl
where xelab
where xsim
```

Run the simulation, then capture the exit code immediately:

```bat
make sim-counter
```

```bat
echo %ERRORLEVEL%
```

The setup script changes this terminal's environment only, not the permanent `PATH`. The recipe lives in the `sim-counter` target of the `Makefile`.

# Expected result

- The console prints `PASS: counter_tb`.
- The exit code is `0`.
- `build/sim/counter_tb/xsim.log` contains `counter_tb: ALL TESTS PASSED`.

Investigate any nonzero result or tool error; an echoed command is not a test result.

# What the runner does

The shared runner resolves paths from its own location, recreates `build/sim/counter_tb`, compiles with `xvhdl --2008`, elaborates, and runs xsim in batch mode. Preserve logs before rerunning, and avoid concurrent runs in one checkout.

# What sim.tcl runs

If the runner fails, run these commands by hand, in order, to isolate the failing step:

```bat
xvhdl --2008 rtl/counter.vhd tb/counter_tb.vhd
xelab -debug off -s counter_tb_sim work.counter_tb
xsim counter_tb_sim -runall -log xsim.log
```

# Limitations

- The runner checks for the final-report substring, not separate error markers.
- There is no Windows wrapper.
- The shared-runner success path passed a fresh-clone test on 2026-10-26.

## Sprint 2: framebuffer dump and PPM

This is simulation-only: no FPGA board is needed. `tb/frame_dump_tb.vhd`
fills the 320x240 RGB332 framebuffer with a known gradient, then calls
`dump_frame("gradient.hex", clk, rd_addr, rd_data)` from `tb/frame_dump_pkg.vhd`.
The read signals are explicit because the package cannot directly access the
DUT memory. Disable framebuffer writes during the dump. The procedure waits
for each registered read before using VHDL-2008 `hwrite` and `writeline`.

### Framebuffer dump format for the Ada reference

Alex reports that Vance is still implementing the Ada reference and will follow
our lead. This section defines the framebuffer snapshot format for that work.

Each line contains exactly two ASCII hexadecimal digits encoding one unsigned
8-bit RGB332 pixel (00..FF). Bits 7..5 are red, bits 4..2 are green, and bits
1..0 are blue. No spaces, `0x` prefix, or Ada `16#...#` notation are written.
For example, these five illustrative pixel lines mean black, red, green, blue,
and white respectively (they are not the first five pixels of the gradient):

```text
00
E0
1C
03
FF
```

A complete frame contains exactly 76,800 lines, with no header, addresses,
comments, blank lines, or byte-order mark. Each line ends in LF or CRLF;
the writer emits uppercase and the Ada reader accepts either hex case.

The origin is the top-left corner. Pixels run left to right, then top to bottom:
address = y * 320 + x. For one-based line number n, address = n - 1,
x = (n - 1) mod 320, and y = floor((n - 1) / 320).
Line 1 is (0,0), line 320 is (319,0), line 321 is (0,1), and line 76,800 is
(319,239). Include every pixel, including black and unchanged pixels.

Each line describes the stored pixel in a completed framebuffer snapshot,
not a write event or a clock cycle. Stop framebuffer writes during the dump.
Vance's reference should emit its final framebuffer in the same order and
format to compare corresponding pixels. RGB332-to-RGB888 scaling is below.

This defines the framebuffer dump only. It does not settle any separate
transaction trace's cycle, operation, address, or other fields. Compatibility
with Vance's reference output and the Ada trace-diff tool still needs an
end-to-end comparison when those are available; it has not been tested yet.

### Run on this computer

Open PowerShell in `C:\Users\freelal\rq85-fix`. This direct Vivado command
uses the existing runner and does not require GNU Make:

```powershell
$env:Path = 'C:\Xilinx\Vivado\2024.2\bin;' + $env:Path
vivado.bat -mode batch -nojournal -nolog -notrace -source scripts/sim.tcl -tclargs frame_dump_tb rtl/qogpu_pkg.vhd rtl/framebuffer.vhd tb/frame_dump_pkg.vhd tb/frame_dump_tb.vhd
$LASTEXITCODE
```

Expect exit 0 and `PASS: frame_dump_tb`. The dump is
`build/sim/frame_dump_tb/gradient.hex`. If Make is installed, `make sim-frame-dump`
runs the same simulation. Rerunning replaces this testbench's build directory.

Build and run the standalone host Ada tool (adjust the GNAT path on other PCs):

```powershell
$env:Path = 'C:\Users\freelal\AppData\Local\alire\cache\toolchains\gnat_native_16.1.0_bbd69633\bin;' + $env:Path
New-Item -ItemType Directory -Path build\ada -Force | Out-Null
gnatmake -gnat2022 -D build\ada -o build\ada\fb2ppm.exe sw\ada\tools\fb2ppm.adb
.\build\ada\fb2ppm.exe --check
.\build\ada\fb2ppm.exe build\sim\frame_dump_tb\gradient.hex build\sim\frame_dump_tb\gradient.ppm
$LASTEXITCODE
```

Stop if a command fails. `--check` verifies `00` maps to black, `FF` to white,
and `E0`, `1C`, `03` to red, green, blue; checks do not depend on assertion flags.
The converter rejects invalid hex and missing or extra pixels before opening
the output. Use a different output filename from the input; an existing output
is replaced. All generated files stay under ignored `build/`.

RGB expansion uses integer division: R = ((P / 32) mod 8) * 255 / 7,
G = ((P / 4) mod 8) * 255 / 7, B = (P mod 4) * 85.
The PPM starts with `P6\n320 240\n255\n`, then 230,400 binary RGB bytes,
for exactly 230,415 bytes total. It uses Ada.Streams.Stream_IO so Windows
newline conversion cannot alter the header or pixels.
See the [official PPM format](https://netpbm.sourceforge.net/doc/ppm.html).

Open `gradient.ppm` in a viewer that supports PPM. Expect stepped red from
left to right, green from top to bottom, and blue diagonally. The first pixel
is black and the final pixel is white. RGB332 has only 256 colors, so visible
color steps are expected.

### Local verification -- 2026-11-03

Vivado 2024.2 completed `frame_dump_tb` with exit 0. GNAT 16.1 compiled the
converter with warnings enabled and no warnings; `--check` passed. The generated
PPM was opened and visually checked. A separate PowerShell check verified all
76,800 hex pixels and all 230,400 RGB bytes against the gradient formula, plus
the exact header and 230,415-byte size. Invalid hex, a short input, a three-digit
line, and an extra pixel all returned failure without replacing existing output.
Both the direct Vivado command and `make sim-frame-dump` passed with exit 0.
Trace-diff compatibility remains unverified until the Ada reference/tool is available.
