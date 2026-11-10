# VGA Timing Memo (640x480 @ 60 Hz)

Helen Xu, last edited 10/27/2026

Step 0 research for the VGA controller. This memo records the timing parameters that `rtl/vga_timing.vhd` implements.

## Background

A VGA monitor has no frame buffer interface. It receives analog color levels continuously, along with two synchronization signals: hsync marks the end of a scan line and vsync marks the end of a frame. The monitor draws pixels at whatever position the sync pulses dictate, so the controller has to generate that timing exactly.

The timing generator does three main things:

1. Tracks the current pixel (`x`) and line (`y`) position.
2. Drives `hsync_n` and `vsync_n` at the correct positions.
3. Asserts `active` while the position is inside the visible 640x480 area, so downstream logic knows when to output pixel data and when to output black.

## Timing parameters

| | Visible | Front porch | Sync pulse | Back porch | Total |
|---|---|---|---|---|---|
| Horizontal (pixel clocks) | 640 | 16 | 96 | 48 | **800** |
| Vertical (lines) | 480 | 10 | 2 | 33 | **525** |

- Pixel clock: 25 MHz (40 ns period).
- `hsync_n` and `vsync_n` are both active low.

Each scan line is 800 clocks, of which only the first 640 carry picture data. The remaining 160 are blanking: front porch, sync pulse, back porch. The frame follows the same structure vertically, so the visible image occupies the top-left 640x480 region of an 800x525 grid. The blanking intervals date from CRT displays, which needed time to return the beam, and LCD monitors still expect them.

## Signal positions (counting from 0)

| Signal | Condition | Duration |
|---|---|---|
| `active` = 1 | x < 640 and y < 480 | 307,200 clocks per frame |
| `hsync_n` = 0 | 656 <= x <= 751 | 96 clocks |
| `vsync_n` = 0 | 490 <= y <= 491 | 2 lines (1,600 clocks) |
| x wraps | 799 to 0, y increments | |
| y wraps | 524 to 0 | |

The sync pulses begin right after the front porch: 640 + 16 = 656 horizontally and 480 + 10 = 490 vertically.

## Derived timing

- Line period: 800 / 25 MHz = 32 us (31.25 kHz line rate). hsync pulse width: 3.84 us.
- Frame period: 800 x 525 = 420,000 clocks = 16.8 ms, or 59.52 Hz. vsync pulse width: 64 us.

## Implementation

Two counters: `x` increments on every clock where the pixel enable `pix_en_i` is high (every clock at 25 MHz, every fourth clock at the board's 100 MHz) and wraps at 799; `y` increments when `x` wraps and wraps at 524. This is equivalent to a nested loop with `x` as the inner counter. The three outputs are combinational comparisons on the counters, so no other state is needed.

## Figures

**VGA diagram.** 

![vga_timing block](../architecture/images/vga_timing_block.png)

<!-- **Compiled design.** 

![vga_timing compiled](../images/vga_timing_compiled.png) comment -->

## Verification
- `tb/vga_timing_tb.vhd` (VHDL-2008) runs 3 frames and asserts 800 pixels per line, 525 lines per frame, hsync low for 96 pixels, vsync low for 2 lines, and 307,200 active pixels per frame. `make sim-vga-timing` runs it at 25 MHz, and `make sim-vga-timing-100` runs it at 100 MHz with the pixel enable high one clock in four, as on the board.

## Reference

[Digilent Nexys VGA reference manual](https://reference.digilentinc.com/nexys_vga/refmanual)