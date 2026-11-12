# Block D: triangle setup (RQ-92)

Files: `rtl/tri_setup.vhd`, `rtl/raster_pkg.vhd`, `tb/tri_setup_tb.vhd`.
Run: `make sim-tri-setup` (regression), `make synth-tri-setup` (resources).

## What it computes

Bit-exact with `Qogpu_Raster.Setup` (numeric contract rules 7, 8, 9, 11, 12), no
rounding anywhere:

- `A_i = y_i - y_(i+1)` (25 bit), `B_i = x_(i+1) - x_i` (26 bit)
- `area2 = A_0 (x_2 - x_0) + B_0 (y_2 - y_0)` (51 bit, exact)
- `area2 < 0`: negate every A, B and area2, so E1-E3 see one winding
- `TL_i = A_i > 0 or (A_i = 0 and B_i > 0)`, on the normalized A/B
- bounding box: floor of the min and max, clamped to 0..319 and 0..239.
  Vertices are never clamped.
- `area2 = 0`: rejected. Dropped, unless it is the last triangle; then it is
  sent with `empty = '1'` so the frame still finishes.

There is no C term. E1/E2 evaluate `E_i = A_i (x - x_i) + B_i (y - y_i)`, so D
passes the three vertices through.

## Microarchitecture

Serial FSM, about 7 clocks per triangle (latency does not matter at two
triangles per frame):

    IDLE -> EDGE -> MUL -> SUM -> NORM -> FLAGS -> OUTPUT -> IDLE
                                           \-> IDLE   (rejected, not last)

| State | Work |
|---|---|
| IDLE | `in_ready_o` high. On `in_valid_i`: latch vertices, z, color, last |
| EDGE | A, B, `x2-x0`, `y2-y0`, bounding box |
| MUL | the two 25x26 products |
| SUM | add them in 52 bits |
| NORM | assert the sum fits 51 bits; negate A, B, area2 if negative |
| FLAGS | TL, `empty`, drop decision |
| OUTPUT | `out_valid_o` high, payload held until `out_ready_i` |

Output is one `tri_t` register, so it cannot change while `valid` is high and
`ready` is low. `fx_mul` is not used: it rounds and shifts by 16.

Input range (x 0..320, y 0..240, raw 16.16) and the 51-bit fit are checked with
`assert ... severity failure`, the same style as `qogpu_fx_pkg`.

## Verification

`tri_setup_tb` reads `tb/vectors/setup.csv` (8 directed and 200 random rows,
from `make vectors`) and checks A, B, area2, TL, bbox, `empty` and the
pass-through fields on every row. Every third row is held with `out_ready_i`
low for 5 clocks. A separate process checks the payload is stable while
`valid` and not `ready`. Then:

- a collinear triangle that is not last is dropped (no `out_valid_o` for 20 clocks)
- reset in the middle of a triangle, then triangle 1 comes out correctly

Not covered: a vertex with a fraction that crosses 320 or 240 exactly. Block C
cannot produce it (rule 2).

## Synthesis (out of context, xc7a100t, 100 MHz, Vivado 2024.2)

4 DSP48E1, 556 registers, 1093 LUTs, setup slack +0.83 ns.
Run `make synth-tri-setup` to reproduce.
