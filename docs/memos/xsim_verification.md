# Counter simulation verification

| Item | Value |
|---|---|
| Status | Pass run must be re-recorded: the testbench changed on 11/8 (280 cycles with a rollover check). Failure run and clean-clone check pending (see below) |
| Date | 2026-10-26 |
| OS | Windows 11 Enterprise 10.0.26100 |
| Vivado / xsim | 2024.2 (SW Build 5239630) |
| Make | GNU Make 4.4.1 |
| Code commit | PASS: fill in after the current `rtl/counter.vhd` and `tb/counter_tb.vhd` changes are committed |

## Pass run

The run below used the earlier 20-cycle testbench, which never reached
rollover. On 11/8 the testbench was extended to the 280 cycles listed under
Coverage and now fails unless the count wraps 255 -> 0. It passed under GHDL
4.1 on Linux; rerun `make sim-counter` under Vivado and replace this section.

Command: `make sim-counter`

Output: `PASS: counter_tb`

Exit code: 0

Run on a copy of the working tree (Makefile, scripts, rtl, tb), not a fresh clone, because the code changes are not committed yet.

Clean git status: PASS. Repeat from a fresh `git clone --no-local` of the commit above and record that `git status --short` prints nothing.

## Failure run (shared runner)

PENDING. Plan: in a scratch copy, change `expected + 1` to `expected + 2` in `tb/counter_tb.vhd`, run `make sim-counter`, and record the assertion text, the printed result and a nonzero exit code. Restore the file afterward.

## Coverage

Checked every cycle against a reference model, 280 cycles:

- Power-on asynchronous reset (q is 0 before any clock edge).
- Mid-run asynchronous reset (cycle 15: q is 0 before the clock edge, with a guard that the count was nonzero).
- Reset over enable (`rst_n = '0'` with `en = '1'` must give 0).
- Hold (`en = '0'`, cycles 8-9).
- Resume after hold.
- Rollover (255 to 0, via `mod 256` in the model).

Not covered:

- X or unknown inputs.
- Timing on hardware (simulation is functional only; no board run).

## Historical tests (old standalone runner, 2026-10-25)

These used the former xsim-starter workspace and the `scripts/sim_counter.tcl` wrapper, not the shared runner or the current testbench (20 cycles, old port names).

- Initial simulation: exit 0, PASS at 201 ns.
- Intentional mismatch (expected + 1): assertion failed at cycle 1, 7 ns. xsim returned 0; the old failure guard made the outer Vivado return 1. Testbench restored afterward.
- Restored source: exit 0, PASS at 201 ns.
- Run from a path containing spaces: exit 0, PASS.
