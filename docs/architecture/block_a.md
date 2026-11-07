# Block A Command Controller

Team 05 — QOGPU Graphics Pipeline

Connor Bodie

Block A coordinates each frame and supplies the rotation coefficients to Block C. It captures the next rotation when a frame is requested, clears the framebuffer and depth buffer, starts Block B, and waits for the rendering pipeline to finish. The current interface is defined by [`command_controller` in block_a.vhd](../../rtl/block_a.vhd).

## Geometry data

In the prototype, cube vertices and faces are preloaded into BRAM. [generate_cube_bram.py](../../scripts/generate_cube_bram.py) encodes the geometry as [32-bit binary words](../../rtl/data/cube_init.txt) using the [asset memory map](../spec/memory_map.md). [asset_memory.vhd](../../rtl/asset_memory.vhd) loads that file and provides a synchronous read port. The texture regions are currently zero-filled.

Block B owns face traversal and reads the asset BRAM directly. Block A sends one start request per frame and has no geometry address or data ports. Loading geometry from NEORV32 is future work; the prototype uses the fixed image.

## Per-frame rotation

Block A stores six signed 16.16 coefficients in a pending register bank and an active register bank. Synchronous reset sets both banks to identity: all cosines are `+1.0` (`0x00010000`) and all sines are zero.

Writes update the pending bank, including while rendering is in progress. When Block A accepts `start_i`, it copies the pending values into the active bank. Block C sees those values continuously and can use them throughout the frame. A write sampled on the same edge as an accepted start is excluded from that frame's snapshot. To use a complete set of new values, write all six before requesting the frame.

The rotation write ports are a local interface for a future NEORV32 bus adapter. Without a CPU, a testbench or other prototype logic can issue `start_i`; if no rotation writes are made, the controller uses identity.

## Signals

All directions are relative to Block A. Inputs are sampled on rising edges of `clk_i`. The `DEPTH_W` generic selects the depth width from 1 to 16 bits and defaults to 8.

| Signal | Direction | Bit width | Description |
| --- | --- | ---: | --- |
| `clk_i` | Input | 1 | Common pipeline clock. |
| `rstn_i` | Input | 1 | Synchronous active-low reset. Returns the controller to idle, clears error status, and resets both rotation banks to identity. |
| `start_i` | Input | 1 | One-cycle frame request. Accepted only while idle with no current or latched error; busy requests are not queued. |
| `busy_o` | Output | 1 | High during clearing, the launch handshake with B, and the wait for frame completion. Check `error_o` as well before requesting another frame. |
| `done_o` | Output | 1 | Pulses for one cycle when a frame finishes without an error. |
| `err_i` | Input | 1 | Pipeline error indication. A sampled high latches `error_o`. |
| `error_o` | Output | 1 | Sticky error status. Blocks new frames and suppresses the success pulse until shared pipeline reset. Does not cancel a frame or retract a pending start handshake. |
| `rot_wr_en_i` | Input | 1 | Enables a write to one pending rotation register on the rising edge. |
| `rot_wr_sel_i` | Input | 3 | Unsigned selector: 0 = cos X, 1 = sin X, 2 = cos Y, 3 = sin Y, 4 = cos Z, 5 = sin Z. Writes to selectors 6 and 7 are ignored. |
| `rot_wr_data_i` | Input | 32 | Bit pattern of the signed 16.16 value to write. |
| `cos_x_o` | Output | 32 | Active cosine for rotation about X, signed 16.16. |
| `sin_x_o` | Output | 32 | Active sine for rotation about X, signed 16.16. |
| `cos_y_o` | Output | 32 | Active cosine for rotation about Y, signed 16.16. |
| `sin_y_o` | Output | 32 | Active sine for rotation about Y, signed 16.16. |
| `cos_z_o` | Output | 32 | Active cosine for rotation about Z, signed 16.16. |
| `sin_z_o` | Output | 32 | Active sine for rotation about Z, signed 16.16. |
| `clr_start_o` | Output | 1 | One-cycle request to the clear engine. The clear engine must accept the pulse. |
| `clr_color_o` | Output | 8 | Framebuffer clear color: RGB332 black (`0x00`). |
| `clr_depth_o` | Output | `DEPTH_W` | Depth clear value: all ones, the maximum depth in the [memory interface](../spec/memory_interface.md). |
| `clr_done_i` | Input | 1 | Clear engine confirms both buffers are cleared, per the memory backend's write completion contract. Block A waits for this before launching B. |
| `frame_start_valid_o` | Output | 1 | Requests that Block B begin a frame. Held high until the launch handshake is accepted. |
| `frame_start_ready_i` | Input | 1 | Block B can accept a frame request. One frame launches on a rising edge with ready and valid both high. B then controls when it fetches each triangle. |
| `frame_done_i` | Input | 1 | Downstream pipeline reports that the final triangle has finished and all frame writes are complete under the memory interface contract. Acceptance of the launch by B does not complete the frame. |

## Frame sequence

1. Accept `start_i` while idle and capture the pending rotation.
2. Pulse `clr_start_o` and wait for `clr_done_i`.
3. Assert `frame_start_valid_o` and hold it until Block B accepts the request.
4. Wait for `frame_done_i`, then return to idle. Pulse `done_o` only if no error was seen.

This prototype interface replaces the per-face handshake in the [earlier MVP interface list](mvp_block_diagram.md). There is no `face_ready_i` on Block A.

The [Block A testbench](../../tb/command_controller_tb.vhd) covers the clear wait, launch backpressure, rotation snapshots, completion, and reset after an error.
