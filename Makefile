# Wrapper around Vivado batch TCL scripts and the host Ada tools
# Needs Vivado on $PATH for sim-* and synth-*, GNAT + gprbuild for vectors/tools
#
#   make sim       every testbench (make -k sim keeps going after a failure)
#   make vectors   regenerate the golden vectors in tb/vectors/ from the Ada reference
#   make tools     build the host tools (fb2ppm) into build/ada/

VIVADO ?= vivado
VBATCH = $(VIVADO) -mode batch -nojournal -nolog -notrace
SIM    = $(VBATCH) -source scripts/sim.tcl -tclargs
SYNTH  = $(VBATCH) -source scripts/synth_ooc.tcl -tclargs
PART   = xc7a100tcsg324-1

FB_SRCS   = rtl/qogpu_pkg.vhd rtl/framebuffer.vhd
BRAM_SRCS = rtl/qogpu_pkg.vhd rtl/mem_if_pkg.vhd rtl/mem_ctrl_bram.vhd
VGA_SRCS  = rtl/qogpu_pkg.vhd rtl/vga_timing.vhd rtl/vga_scanout.vhd
SETUP_SRCS = rtl/qogpu_pkg.vhd rtl/qogpu_fx_pkg.vhd rtl/raster_pkg.vhd rtl/tri_setup.vhd

# every testbench; add each new sim-* target here
SIM_TARGETS = sim-framebuffer sim-clear-engine sim-counter sim-bram sim-bram-w16 \
              sim-vga-timing sim-vga-timing-100 sim-vga-scanout sim-vga-scanout-100 \
              sim-fx-mul sim-fx-mul-trunc sim-fx-pkg sim-frame-dump sim-tri-setup

.PHONY: sim $(SIM_TARGETS) synth-framebuffer synth-bram synth-fx-mul synth-tri-setup \
        vectors tools build clean

sim: $(SIM_TARGETS)

sim-framebuffer:
	$(SIM) framebuffer_tb $(FB_SRCS) tb/framebuffer_tb.vhd

sim-clear-engine:
	$(SIM) clear_engine_tb $(FB_SRCS) rtl/clear_engine.vhd tb/clear_engine_tb.vhd

sim-counter:
	$(SIM) counter_tb rtl/counter.vhd tb/counter_tb.vhd

sim-bram:
	$(SIM) mem_ctrl_bram_tb $(BRAM_SRCS) tb/mem_ctrl_bram_tb.vhd

sim-bram-w16:
	$(SIM) mem_ctrl_bram_w16_tb $(BRAM_SRCS) tb/mem_ctrl_bram_tb.vhd tb/mem_ctrl_bram_w16_tb.vhd

# 25 MHz clock, pixel enable tied high
sim-vga-timing:
	$(SIM) vga_timing_tb rtl/vga_timing.vhd tb/vga_timing_tb.vhd

# 100 MHz clock, pixel enable one clock in four (as on the board)
sim-vga-timing-100:
	$(SIM) vga_timing_100_tb rtl/vga_timing.vhd tb/vga_timing_tb.vhd tb/vga_timing_100_tb.vhd

sim-vga-scanout:
	$(SIM) vga_scanout_tb $(VGA_SRCS) tb/vga_scanout_tb.vhd

sim-vga-scanout-100:
	$(SIM) vga_scanout_100_tb $(VGA_SRCS) tb/vga_scanout_tb.vhd tb/vga_scanout_100_tb.vhd

# rounding per numeric contract rule 5 (vectors_round.txt)
sim-fx-mul:
	$(SIM) fx_mul_tb rtl/fx_mul.vhd tb/fx_mul_tb.vhd

# truncating variant (vectors_trunc.txt), kept for comparison
sim-fx-mul-trunc:
	$(SIM) fx_mul_trunc_tb rtl/fx_mul.vhd tb/fx_mul_tb.vhd tb/fx_mul_trunc_tb.vhd

# VHDL contract helpers against the Ada golden vectors (mul.csv, viewport.csv)
sim-fx-pkg:
	$(SIM) qogpu_fx_pkg_tb rtl/qogpu_fx_pkg.vhd tb/qogpu_fx_pkg_tb.vhd

sim-frame-dump:
	$(SIM) frame_dump_tb $(FB_SRCS) tb/frame_dump_pkg.vhd tb/frame_dump_tb.vhd

# Block D against setup.csv (208 rows) plus drop, back-pressure and reset checks
sim-tri-setup:
	$(SIM) tri_setup_tb $(SETUP_SRCS) tb/tri_setup_tb.vhd

# Nexys A7-100T, the delivery board (replan v5)
synth-framebuffer:
	$(SYNTH) framebuffer $(PART) clk_i 10.0 $(FB_SRCS)

synth-bram:
	$(SYNTH) mem_ctrl_bram_synth_top $(PART) clk_i 10.0 $(BRAM_SRCS) rtl/mem_ctrl_bram_synth_top.vhd

# check utilization.rpt for DSP48E1 > 0
synth-fx-mul:
	$(SYNTH) fx_mul $(PART) clk 10.0 rtl/fx_mul.vhd

# check utilization.rpt for DSP48E1 = 4 (two 25x26 products)
synth-tri-setup:
	$(SYNTH) tri_setup $(PART) clk_i 10.0 $(SETUP_SRCS)

# Golden vectors from the Ada reference (numeric contract, RQ-38).
# Writes mul, viewport, setup and depth_test (committed) and edge and
# interp (git-ignored, several MB), then the fx_mul vectors from fx_ref.
vectors:
	gprbuild -q -P sw/ada/ref/qogpu_ref.gpr
	build/ada/gen_vectors tb/vectors
	mkdir -p build/ada/fx_ref
	cd build/ada/fx_ref && gnatmake -q -gnat2022 -gnata ../../../model/fx_ref.adb
	cd tb/vectors && ../../build/ada/fx_ref/fx_ref 0 && ../../build/ada/fx_ref/fx_ref 1

tools:
	gprbuild -q -P sw/ada/tools/fb2ppm.gpr

build: tools

clean:
	rm -rf build .Xil
