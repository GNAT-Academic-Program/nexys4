# QOGPU MVP Block Diagram and Interface List

RQ-79 · Sprint 1 · Owner: Vance Steele

**Scope:** two overlapping flat-colored triangles, vertices given directly (no rotation, no texturing).

**Flow:** A → B → C → D → E1 → E2 → E3 → E4 → E6 → memory controller → VGA (E5 skipped until texturing)

- 16.16 signed fixed point in the shared buffer
- Screen space is 320x240 after Block C
- RGB332 framebuffer in BRAM (320x240x8), 2x scaled to 640x480 by VGA
- Depth buffer behind the memory controller, `DEPTH_W` = 8 by default
- valid/ready between blocks, one clock domain (`clk_i`, `rst_n_i` active low)

**Handshake:** a transfer happens on the rising edge where `valid` and `ready` are both high. A source must not wait for `ready` before raising `valid`, and must hold its payload steady until the transfer happens.

## Summary

| Block | Inputs | Outputs | Handshake | Owner task |
|---|---|---|---|---|
| A command/status + shared buffer | XBUS (optional), start, frame done, error | face index, vertex buffer data, clear request | XBUS (Wishbone) to CPU; valid/ready to B | RQ-86, RQ-102 |
| B fetch | face index from A | 3 vertices (x,y,z) + color | valid/ready | RQ-108 |
| C transform (single) | 3 vertices, 16.16 normalized | 3 vertices, screen space + depth | valid/ready | RQ-91 |
| D setup | 3 screen-space vertices | bounding box, edge coefficients, area | valid/ready | RQ-92 |
| E1 scan | triangle setup | pixel (x,y) | valid/ready | RQ-93 |
| E2 coverage | pixel (x,y) | pixel + inside flag + edge weights | valid/ready | RQ-93 |
| E3 depth interp | pixel + edge weights | pixel + z | valid/ready | RQ-93 |
| E4 depth test | pixel + z | pixel + pass/fail | valid/ready; memory req/rsp | RQ-94 |
| E6 write-back | passing pixel + z | color write, depth write, done | valid/ready; memory req | RQ-95 |
| Memory controller | requests from clear, E4, E6 | read data | req/rsp (valid/ready) | RQ-106, RQ-107, RQ-109 |
| Framebuffer | writes from clear/E6 | pixel data to VGA | fixed 1-cycle BRAM read | RQ-84 |
| Clear engine | clear request from A | framebuffer + depth fill | memory req; done pulse | RQ-89 |
| VGA | framebuffer data | hsync, vsync, RGB | fixed 1-cycle BRAM read | RQ-83, RQ-87 |

## Ports by block

All blocks also have `clk_i` and `rst_n_i`. Edge and area widths follow numeric contract rule 9 (`docs/spec/qogpu_numeric_contract.md`).

### Block A: command/status + shared buffer

| Port | Dir | Width | Description |
|---|---|---|---|
| `xbus_adr_i` | in | 32 | XBUS address (only used when `CPU_EN`) |
| `xbus_dat_i` | in | 32 | XBUS write data |
| `xbus_we_i` | in | 1 | XBUS write enable |
| `xbus_sel_i` | in | 4 | XBUS byte select |
| `xbus_stb_i` | in | 1 | XBUS strobe |
| `xbus_cyc_i` | in | 1 | XBUS cycle |
| `xbus_dat_o` | out | 32 | XBUS read data |
| `xbus_ack_o` | out | 1 | XBUS acknowledge |
| `xbus_err_o` | out | 1 | XBUS error |
| `start_i` | in | 1 | Start pulse when no CPU (button or auto-start) |
| `face_valid_o` | out | 1 | Face index valid |
| `face_ready_i` | in | 1 | B ready for a face |
| `face_idx_o` | out | 8 | Face number |
| `face_last_o` | out | 1 | Last face in frame |
| `buf_raddr_i` | in | `BUF_ADDR_W` | Shared buffer read address from B |
| `buf_rdata_o` | out | 32 | Shared buffer read data (1-cycle latency) |
| `num_verts_o` | out | 8 | Vertex count, for B's index check |
| `clr_start_o` | out | 1 | Start clear pulse |
| `clr_color_o` | out | 8 | Clear color (RGB332) |
| `clr_depth_o` | out | `DEPTH_W` | Clear depth value |
| `clr_done_i` | in | 1 | Clear finished pulse |
| `frame_done_i` | in | 1 | From E6: last pixel of last triangle written |
| `err_i` | in | 1 | From B: bad vertex index |

Shared buffer is preloaded from `INIT_FILE`. Register offsets and buffer layout are in the memory map (RQ-80).

### Block B: fetch

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` | in | 1 | Face index valid |
| `in_ready_o` | out | 1 | Ready for a face |
| `in_face_idx_i` | in | 8 | Face number |
| `in_last_i` | in | 1 | Last face |
| `buf_raddr_o` | out | `BUF_ADDR_W` | Shared buffer read address |
| `buf_rdata_i` | in | 32 | Shared buffer read data |
| `num_verts_i` | in | 8 | Vertex count |
| `out_valid_o` | out | 1 | Triangle valid |
| `out_ready_i` | in | 1 | C ready |
| `out_v0_x_o`, `out_v0_y_o`, `out_v0_z_o` | out | 32 each | Vertex 0, 16.16 |
| `out_v1_x_o`, `out_v1_y_o`, `out_v1_z_o` | out | 32 each | Vertex 1, 16.16 |
| `out_v2_x_o`, `out_v2_y_o`, `out_v2_z_o` | out | 32 each | Vertex 2, 16.16 |
| `out_color_o` | out | 8 | Face color, RGB332 |
| `out_last_o` | out | 1 | Last triangle |
| `err_o` | out | 1 | Vertex index ≥ `num_verts_i` |

### Block C: transform (single)

Scale/offset to 320x240 and depth range mapping (z −1..1 to 0..2^`DEPTH_W`−1), serial over the 3 vertices.

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` / `in_ready_o` | in / out | 1 | Handshake from B |
| `in_v{0,1,2}_{x,y,z}_i` | in | 32 each | Vertices, 16.16 normalized |
| `in_color_i` | in | 8 | Face color |
| `in_last_i` | in | 1 | Last triangle |
| `out_valid_o` / `out_ready_i` | out / in | 1 | Handshake to D |
| `out_v{0,1,2}_x_o` | out | 32 each | Screen x, 16.16 (0..320) |
| `out_v{0,1,2}_y_o` | out | 32 each | Screen y, 16.16 (0..240) |
| `out_v{0,1,2}_z_o` | out | `DEPTH_W` each | Mapped depth |
| `out_color_o` | out | 8 | Face color |
| `out_last_o` | out | 1 | Last triangle |

### Block D: triangle setup

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` / `in_ready_o` | in / out | 1 | Handshake from C |
| `in_v{0,1,2}_{x,y}_i` | in | 32 each | Screen coordinates |
| `in_v{0,1,2}_z_i` | in | `DEPTH_W` each | Depth |
| `in_color_i`, `in_last_i` | in | 8, 1 | Pass-through |
| `out_valid_o` / `out_ready_i` | out / in | 1 | Handshake to E1 |
| `out_xmin_o`, `out_xmax_o` | out | 9 | Bounding box x, clamped to screen |
| `out_ymin_o`, `out_ymax_o` | out | 8 | Bounding box y, clamped to screen |
| `out_e{0,1,2}_a_o` | out | 25 each | Edge x coefficient A_i = y_i − y_{i+1}, signed Q16 difference |
| `out_e{0,1,2}_b_o` | out | 26 each | Edge y coefficient B_i = x_{i+1} − x_i, signed Q16 difference |
| `out_v{0,1,2}_{x,y}_o` | out | 32 each | Vertex positions, the reference point of each edge function |
| `out_area_o` | out | 51 | Twice the triangle area (area2), ≥ 0 after winding normalization (rule 12) |
| `out_tl_o` | out | 3 | Top-left flag per edge (rule 11) |
| `out_z{0,1,2}_o` | out | `DEPTH_W` each | Vertex depths |
| `out_color_o`, `out_last_o` | out | 8, 1 | Pass-through |
| `out_empty_o` | out | 1 | Zero-area triangle; only sent when it is the last one, so the frame still finishes |

### E1: pixel scan

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` / `in_ready_o` | in / out | 1 | Handshake from D |
| `in_*` | in | — | All D outputs |
| `out_valid_o` / `out_ready_i` | out / in | 1 | Handshake to E2 |
| `out_px_o` | out | 9 | Pixel x |
| `out_py_o` | out | 8 | Pixel y |
| `out_eot_o` | out | 1 | Last pixel of this triangle |
| `out_eof_o` | out | 1 | Last pixel of the frame |
| `out_tri_o` | out | — | Held copy of D's outputs for E2, E3, E6 |

### E2: coverage

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` / `in_ready_o` | in / out | 1 | Handshake from E1 |
| `in_px_i`, `in_py_i` | in | 9, 8 | Pixel |
| `in_eot_i`, `in_eof_i` | in | 1, 1 | Markers |
| `in_tri_i` | in | — | Edge coefficients |
| `out_valid_o` / `out_ready_i` | out / in | 1 | Handshake to E3 |
| `out_px_o`, `out_py_o` | out | 9, 8 | Pixel |
| `out_w{0,1,2}_o` | out | 51 each | Edge function values E_i, signed 18.32 raw |
| `out_kill_o` | out | 1 | Pixel outside triangle |
| `out_eot_o`, `out_eof_o` | out | 1, 1 | Markers |

### E3: depth interpolation

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` / `in_ready_o` | in / out | 1 | Handshake from E2 |
| `in_px_i`, `in_py_i`, `in_w{0,1,2}_i` | in | — | From E2 |
| `in_kill_i`, `in_eot_i`, `in_eof_i` | in | 1 each | From E2 |
| `in_tri_i` | in | — | z0..z2, area |
| `out_valid_o` / `out_ready_i` | out / in | 1 | Handshake to E4 |
| `out_px_o`, `out_py_o` | out | 9, 8 | Pixel |
| `out_z_o` | out | `DEPTH_W` | Interpolated depth |
| `out_kill_o`, `out_eot_o`, `out_eof_o` | out | 1 each | Pass-through |

### E4: depth test

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` / `in_ready_o` | in / out | 1 | Handshake from E3 |
| `in_px_i`, `in_py_i`, `in_z_i` | in | 9, 8, `DEPTH_W` | Pixel and depth |
| `in_kill_i`, `in_eot_i`, `in_eof_i` | in | 1 each | Markers |
| `mem_*` | — | — | Memory client port, read only (see below) |
| `out_valid_o` / `out_ready_i` | out / in | 1 | Handshake to E6 |
| `out_px_o`, `out_py_o`, `out_z_o` | out | 9, 8, `DEPTH_W` | Pixel and depth |
| `out_kill_o` | out | 1 | Set if killed or depth test failed |
| `out_eot_o`, `out_eof_o` | out | 1 each | Markers |

Skips the read when `in_kill_i` is set

### E6: write-back

| Port | Dir | Width | Description |
|---|---|---|---|
| `in_valid_i` / `in_ready_o` | in / out | 1 | Handshake from E4 |
| `in_px_i`, `in_py_i`, `in_z_i` | in | 9, 8, `DEPTH_W` | Pixel and depth |
| `in_kill_i`, `in_eot_i`, `in_eof_i` | in | 1 each | Markers |
| `in_tri_i` | in | — | Face color |
| `fb_we_o` | out | 1 | Framebuffer write enable |
| `fb_waddr_o` | out | 17 | Framebuffer address (y*320 + x) |
| `fb_wdata_o` | out | 8 | Color, RGB332 |
| `mem_*` | — | — | Memory client port, write only (see below) |
| `tri_done_o` | out | 1 | Pulse on the `eot` pixel |
| `frame_done_o` | out | 1 | Pulse on the `eof` pixel, to A |

### Memory controller: client port (one per client)

Clients: clear engine (write), E4 (read), E6 (write), latency and ordering rules go in the memory interface

| Port | Dir (client side) | Width | Description |
|---|---|---|---|
| `mem_req_valid_o` | out | 1 | Request valid |
| `mem_req_ready_i` | in | 1 | Controller accepts request |
| `mem_req_we_o` | out | 1 | 1 = write, 0 = read |
| `mem_req_addr_o` | out | 17 | Depth word address (y*320 + x) |
| `mem_req_wdata_o` | out | `DEPTH_W` | Write data |
| `mem_rsp_valid_i` | in | 1 | Read data valid, one-cycle pulse; there is no response back-pressure (memory interface rule 9) |
| `mem_rsp_rdata_i` | in | `DEPTH_W` | Read data |

The controller's back-end (BRAM, or DDR2 through the MIG core) is chosen by `MEM_BACKEND` and is not seen by the pipeline

### Framebuffer

| Port | Dir | Width | Description |
|---|---|---|---|
| `wr_en_i` | in | 1 | Write enable (from clear engine or E6) |
| `wr_addr_i` | in | 17 | Write address |
| `wr_data_i` | in | 8 | RGB332 |
| `rd_addr_i` | in | 17 | Read address from VGA |
| `rd_data_o` | out | 8 | Read data, 1-cycle latency |

### Clear engine

| Port | Dir | Width | Description |
|---|---|---|---|
| `start_i` | in | 1 | From A |
| `color_i` | in | 8 | Clear color |
| `depth_i` | in | `DEPTH_W` | Clear depth |
| `fb_we_o`, `fb_waddr_o`, `fb_wdata_o` | out | 1, 17, 8 | Framebuffer write |
| `mem_*` | — | — | Memory client port, write only |
| `done_o` | out | 1 | Pulse when both buffers are filled |

### VGA

| Port | Dir | Width | Description |
|---|---|---|---|
| `fb_raddr_o` | out | 17 | Framebuffer address, 2x2 doubled |
| `fb_rdata_i` | in | 8 | RGB332 |
| `pix_en_i` | in | 1 | Pixel-rate enable (one clock in four at 100 MHz) |
| `vga_hs_n_o` | out | 1 | Horizontal sync, active low |
| `vga_vs_n_o` | out | 1 | Vertical sync, active low |
| `vga_r_o` | out | 3 | Red |
| `vga_g_o` | out | 3 | Green |
| `vga_b_o` | out | 2 | Blue |

640x480@60 timing from a pixel enable on the system clock (one clock domain). RGB and syncs leave from registers. The top level maps RGB332 onto the board's 4-4-4 VGA pins.
