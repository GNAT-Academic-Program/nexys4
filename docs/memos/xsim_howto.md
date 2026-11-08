# Counter simulation

Run the 8-bit counter testbench with Vivado Simulator (xsim); no FPGA board is required. The testbench checks asynchronous active-low reset, enabled increments, disabled hold behavior, and 8-bit rollover over 280 cycles.

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

# Other testbenches

The framebuffer dump and PPM converter are described in `frame_dump.md`.
