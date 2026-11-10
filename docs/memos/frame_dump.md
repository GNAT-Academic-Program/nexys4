# Framebuffer dump and PPM conversion (RQ-90)

Alex Freel. Moved out of `xsim_howto.md` on 11/8/2026.

This is simulation-only: no FPGA board is needed. `tb/frame_dump_tb.vhd`
fills the 320x240 RGB332 framebuffer with a known gradient, then calls
`dump_frame("gradient.hex", clk, rd_addr, rd_data)` from `tb/frame_dump_pkg.vhd`.
The read signals are explicit because the package cannot directly access the
DUT memory. Disable framebuffer writes during the dump. The procedure waits
for each registered read before using VHDL-2008 `hwrite` and `writeline`.

## Framebuffer dump format

This format is the framebuffer snapshot that the Ada reference renderer
(RQ-43) and the comparison tool (RQ-50) must also produce or read.

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

This defines the framebuffer dump only. It does not settle any separate
transaction trace's cycle, operation, address, or other fields. Compatibility
with the Ada reference output and the trace-diff tool still needs an
end-to-end comparison when those are available; it has not been tested yet.

## Run

Put Vivado's `bin` directory on `PATH` (for example by running Vivado's
`settings64` script), then from the repo root:

```text
make sim-frame-dump
```

Expect `PASS: frame_dump_tb`. The dump is `build/sim/frame_dump_tb/gradient.hex`.
Rerunning replaces this testbench's build directory.

Build and run the host Ada tool with GNAT (from Alire or a native install) on
`PATH`:

```text
gprbuild -P sw/ada/tools/fb2ppm.gpr
build/ada/fb2ppm --check
build/ada/fb2ppm build/sim/frame_dump_tb/gradient.hex build/sim/frame_dump_tb/gradient.ppm
```

Stop if a command fails. `--check` verifies `00` maps to black, `FF` to white,
and `E0`, `1C`, `03` to red, green, blue; checks do not depend on assertion flags.
The converter rejects invalid hex and missing or extra pixels before opening
the output, and prints the reason. Use a different output filename from the
input; an existing output is replaced. All generated files stay under ignored
`build/`.

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

## Local verification, 2026-11-03 (Alex, Windows)

Vivado 2024.2 completed `frame_dump_tb` with exit 0. GNAT 16.1 compiled the
converter with warnings enabled and no warnings; `--check` passed. The generated
PPM was opened and visually checked. A separate PowerShell check verified all
76,800 hex pixels and all 230,400 RGB bytes against the gradient formula, plus
the exact header and 230,415-byte size. Invalid hex, a short input, a three-digit
line, and an extra pixel all returned failure without replacing existing output.
Both the direct Vivado command and `make sim-frame-dump` passed with exit 0.
Trace-diff compatibility remains unverified until the Ada reference/tool is available.

The 11/8 changes (error messages, CRLF handling, project file) were checked
with GHDL 4.1 and GNAT 13 on Linux, not yet with Vivado.
