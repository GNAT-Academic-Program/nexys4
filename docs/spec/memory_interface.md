# Team 05 QOGPU Graphics Pipeline

**Author:** Vance Steele  
**Date:** 11/02/2026  
**Ticket:** RQ-106 · Sprint 2

---

## Memory Interface

This document defines the one interface between the depth buffer clients (clear engine, E4, E6) and the memory controller. Clients are written once against these rules and work with any back-end. `MEM_BACKEND = BRAM | DDR2` is set in the board config package (RQ-113). DDR2 is the default on the Nexys A7-100T, and BRAM is the fallback (replan v5). The port types are in `rtl/mem_if_pkg.vhd`.

The framebuffer is not behind this interface. It stays in BRAM with its own write port.

## Decisions

| # | Rule | Decision | Reason |
|---|---|---|---|
| **1** | Clock | The interface is one clock domain, `clk_i`. Any crossing to `ui_clk` stays inside the DDR2 back-end | Clients and the arbiter never see a second clock |
| **2** | Reset | `rst_n_i`, active low, synchronous | Matches `vga_timing.vhd` |
| **3** | Address | 17-bit word address, `y * 320 + x`, valid range 0..76799. Use `fb_addr()` | One depth word per pixel, same address as the framebuffer |
| **4** | Data width | `DEPTH_W` on entity ports, 8 by default, 16 at most. Records carry 16 bits and use the low `DEPTH_W` bits | Records in a package cannot take a generic, and winter 16-bit depth fits without a port change |
| **5** | Byte enables | None. One request moves one whole depth word | Masks are a DDR2 detail and stay inside RQ-112 |
| **6** | Writes | No response. A write is complete when it is accepted | E6 and the clear engine have nothing to do with a response |
| **7** | Reads | Exactly one response per accepted read, in request order | E4 needs no ID field |
| **8** | Latency | Not fixed and not reported. Clients wait for `rsp.valid` | BRAM takes 1 cycle, DDR2 takes tens and varies |
| **9** | Response back-pressure | None. `rsp.valid` is a one-cycle pulse and the client must take it. This drops `mem_rsp_ready` from the block diagram | A client with one read outstanding is always ready, and RQ-94 and RQ-107 are already written this way |
| **10** | Outstanding reads | Each client has at most 1 in the MVP. The port does not limit this, so more can be added later | Rule 7 already covers more than one |
| **11** | Ordering | Accepted requests take effect in acceptance order across all clients. A read accepted after a write to the same address returns the new value | Depth test depends on it, and writes are posted (rule 6) |
| **12** | Init status | `mem_ready` is low until the back-end can take requests. Once high it stays high until the next reset | Covers DDR2 calibration |
| **13** | Stalls | `req_ready` can drop at any time, even with `mem_ready` high, and a client can never assume how long | Covers DDR2 refresh |
| **14** | Clear value | Every word is cleared to $2^D - 1$, using `depth_clear()` | Numeric contract rule 13 |

## Ports

### Client port

Names follow `mvp_block_diagram.md`. Write-only clients leave out `mem_rsp_*`. E4 ties `mem_req_we_o` to `'0'` and leaves out `mem_req_wdata_o`.

| Port | Dir (client side) | Width | Description |
|---|---|---|---|
| `mem_req_valid_o` | out | 1 | Request valid |
| `mem_req_ready_i` | in | 1 | Controller accepts request |
| `mem_req_we_o` | out | 1 | 1 = write, 0 = read |
| `mem_req_addr_o` | out | 17 | Depth word address |
| `mem_req_wdata_o` | out | `DEPTH_W` | Write data |
| `mem_rsp_valid_i` | in | 1 | Read data valid, one-cycle pulse |
| `mem_rsp_rdata_i` | in | `DEPTH_W` | Read data |

The clear engine also takes `mem_ready_i` (see Reset). E4 and E6 do not need it.

### Back-end and arbiter side

The arbiter and back-ends may use the package records. `to_mem_data()` and `from_mem_data()` convert between `DEPTH_W` ports and the 16-bit record fields.

| Signal | Type | Direction | Description |
|---|---|---|---|
| `req` | `mem_req_t` | to back-end | `valid`, `we`, `addr`, `wdata` |
| `req_ready` | `std_logic` | from back-end | Accepts `req` this cycle |
| `rsp` | `mem_rsp_t` | from back-end | `valid`, `rdata` |
| `mem_ready` | `std_logic` | from back-end | Init or calibration done |

## Handshake Rules

Same rule as the rest of the pipeline: a transfer happens on the rising edge where `valid` and `ready` are both high.

1. A client must not wait for `ready` before raising `valid`.
2. Once `valid` is high, the client holds it and every request field steady until the transfer happens.
3. `valid` must not depend combinationally on `ready`.
4. A back-end's `req_ready` must not depend combinationally on `req.valid`. The arbiter's `ready` to a client may depend on the other clients' `valid`.
5. `rsp.valid` is high for exactly one cycle per read, and `rsp.rdata` is only good in that cycle. The client must latch it.
6. A response never arrives in the cycle that accepts the read, so the smallest latency is 1.
7. `rsp.valid` is low when no read is outstanding.

## Waveforms

Each column is one `clk_i` cycle, and a signal in cycle n is what gets sampled at the rising edge that ends cycle n. Latency L means a read accepted in cycle a has its response in cycle a + L.

### W1: accept and a 1-cycle response (BRAM)

A write to A, then a read of A, then a read of B, all back to back. The read of A returns the new value (rule 11). The write gets no response.

```
cycle     0  1  2  3  4  5  6  7
req.valid ___‾‾‾‾‾‾‾‾‾____________
req_ready ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req.we    ...W  R     ............
req.addr  ...A     B  ............
rsp.valid _________‾‾‾‾‾‾_________
rsp.rdata .........a  b  .........
```

### W2: worked example, a read with 3-cycle latency

The read is accepted in cycle 2 and the response is in cycle 5. An N-cycle read is the same with the pulse N cycles after acceptance.

```
cycle     0  1  2  3  4  5  6  7
req.valid ______‾‾‾_______________
req_ready ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req.we    ......R  ...............
req.addr  ......A  ...............
rsp.valid _______________‾‾‾______
rsp.rdata ...............a  ......
```

### W3: `req_ready` drops mid-stream

Writes to A, B, C and D. A is accepted in cycle 1. `req_ready` drops in cycles 2 and 3, so the client holds B until cycle 4. Then C and D go through.

```
cycle     0  1  2  3  4  5  6  7  8  9
req.valid ___‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾_________
req_ready ‾‾‾‾‾‾______‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req.we    ...W                 .........
req.addr  ...A  B        C  D  .........
```

### W4: DDR2 style, `req_ready` low for several cycles and then a 30-cycle read

One character per cycle here. The client raises `valid` in cycle 1 and holds it through 5 cycles of `req_ready` low. The read is accepted in cycle 6 and the response is in cycle 36.

```
cycle     0         1         2         3
req.valid _‾‾‾‾‾‾_________________________________
req_ready ‾_____‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req.we    .RRRRRR.................................
req.addr  .AAAAAA.................................
rsp.valid ____________________________________‾___
rsp.rdata ....................................a...
```

## Address Map and Clear

| Region | Word address | Size | Notes |
|---|---|---|---|
| Depth buffer | 0..76799 | 76,800 words | `DEPTH_BASE` = 0 on the interface |
| Illegal | 76800..131071 | | Client bug, see below |

- Each back-end maps word addresses onto its own memory. The DDR2 byte address and the `BASE_ADDR` offset belong to RQ-112.
- An address above 76799 is a client bug. Back-ends `assert` with `severity failure` in simulation. In hardware the stored data is undefined, but a read must still get its one response so the pipeline cannot hang.
- There is no fast clear. The clear engine writes every word through this interface, one request per address, so a clear takes as long as the back-end needs.
- Depth contents are undefined after power-up and after reset, so a clear must finish before the first draw.
- The clear engine's `done_o` pulses only after the last depth write is accepted. It uses one address counter for both buffers and writes each framebuffer pixel when the depth write at that address is accepted, so a stall also holds the framebuffer write.

## Latency

| Back-end | Read latency (`clk_i` cycles) | Maximum `req_ready` low after `mem_ready` | Status |
|---|---|---|---|
| BRAM | Fixed 1 | 0, `req_ready` stays high | Set here, RQ-107 |
| DDR2 | Varies, tens of cycles | Varies | Measured value goes here in RQ-112 |

- Clients have no timeout in hardware. They wait.
- Testbenches fail a read after `MEM_RSP_WATCHDOG` (1000) `clk_i` cycles. This number only catches a lost response, and it is not a performance bound.
- Testbenches should cover read latency past 40 cycles. RQ-94's 10 to 40 range is in cycles of the model, but MIG latency counts in `ui_clk` and the FIFO crossing adds more on top. A published MIG test on another board and DDR3 saw about 26 to 35 cycles per read, and some writes took up to 71 cycles [1]. Our numbers come from RQ-110 and RQ-112, not from that test.

## Reset and Init

| State | `mem_ready` | `req_ready` | `rsp.valid` |
|---|---|---|---|
| In reset | 0 | 0 | 0 |
| After reset, before init is done | 0 | 0 | 0 |
| Running | 1 | 0 or 1 | Pulses only for reads |

- BRAM raises `mem_ready` on the first clock after reset is released.
- DDR2 raises it after `init_calib_complete` and after its FIFOs are out of reset. It must be synchronized into `clk_i` inside the back-end.
- Reset drops all in-flight work. No response from a read accepted before reset may appear after it, and writes accepted before reset may or may not land.
- Only the clear engine waits on `mem_ready`. A `start_i` that arrives early is kept, and the first request waits until `mem_ready` is high. E4 and E6 cannot run until `clr_done_i` reaches Block A, so they follow it automatically. No client may raise `valid` before `mem_ready`. The arbiter `assert`s this in simulation.

## Arbitration and Hazards

Three clients share one back-end port (RQ-109). Integration 1's priority mux (RQ-96) follows the same order.

- Priority is clear, then E6, then E4. Since Block A only starts faces after the clear finishes, clear never competes with E4 or E6.
- Only E4 reads, so every response goes to E4.
- The arbiter forwards one request at a time and never reorders accepted requests.

**Within one triangle** E1 visits each pixel once, so no depth word is touched by a read after a pending write.

**Between triangles** E4 of the next triangle could read a pixel before E6 has written it from the last one. This is a pipeline hazard, and rule 11 cannot fix a write that has not been requested yet. The MVP removes it by draining:

| Rule | Statement |
|---|---|
| **H1** | E1 does not start the next triangle until it sees `tri_done_o` from E6 for the current one |
| **H2** | E6 pulses `tri_done_o` only after the depth write for the `eot` pixel is accepted, or right away on a killed `eot` pixel once earlier writes are accepted |
| **H3** | `frame_done_o` follows the same rule for the `eof` pixel |
| **H4** | Every triangle that enters E1 produces an `eot` pixel, even if all of its pixels are killed, so H1 cannot deadlock |

The cost is one short drain per triangle, which is nothing for two triangles. Revisit this for the winter cube.

## Back-End Checklist

Every back-end must pass the same testbench (RQ-111), which checks:

1. Write then read of the same address, first address, last address and random addresses.
2. A read in the cycle right after a write to the same address returns the new value (rule 11, W1).
3. Back-to-back requests.
4. A random read and write mix against a model array.
5. Exactly one response per read, in order, and none for a write.
6. A response is never in the accepting cycle, and is within `MEM_RSP_WATCHDOG`.
7. `req_ready` dropping at random, with no request lost or duplicated.
8. `mem_ready` and `req_ready` low in reset, and no request taken before `mem_ready`.
9. No response appears after reset for a read accepted before it.
10. `DEPTH_W` = 8 and one other width.

## Open Items

| Item | Owner | Task |
|---|---|---|
| Confirm rule 11 holds through MIG. Use `ORDERING = "STRICT"` in the `.prj` unless UG586 shows normal ordering keeps a read behind a write to the same address | Helen | RQ-110 |
| Replace the DDR2 row in the Latency table with measured values | Connor | RQ-112 |
| Add the depth port and stall behavior to the clear engine. RQ-89 is closed without it | Helen | RQ-96 |

## Works Cited

* **[1]** “Comparing the Xilinx MIG with an open source DDR3 controller,” *ZipCPU*, May 28, 2025. Accessed: Nov. 02, 2026. [Online]. Available: [https://zipcpu.com/zipcpu/2025/05/28/memtest.html](https://zipcpu.com/zipcpu/2025/05/28/memtest.html)
