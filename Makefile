# Wrapper around Vivado batch TCL  scripts
# Need Vivado on $PATH

VIVADO ?= vivado
VBATCH = $(VIVADO) -mode batch -nojournal -nolog -notrace

FB_SRCS = rtl/qogpu_pkg.vhd rtl/framebuffer.vhd
BRAM_SRCS = rtl/qogpu_pkg.vhd rtl/mem_if_pkg.vhd rtl/mem_ctrl_bram.vhd

.PHONY: sim sim-framebuffer sim-counter sim-bram sim-bram-w16 synth-framebuffer synth-framebuffer-35t synth-bram build clean

# all tb, add each new sim-* targ here
sim: sim-framebuffer sim-counter sim-bram sim-bram-w16

sim-framebuffer:
	$(VBATCH) -source scripts/sim.tcl -tclargs framebuffer_tb $(FB_SRCS) tb/framebuffer_tb.vhd

sim-counter:
	$(VBATCH) -source scripts/sim.tcl -tclargs counter_tb rtl/counter.vhd tb/counter_tb.vhd

sim-bram:
	$(VBATCH) -source scripts/sim.tcl -tclargs mem_ctrl_bram_tb $(BRAM_SRCS) tb/mem_ctrl_bram_tb.vhd

sim-bram-w16:
	$(VBATCH) -source scripts/sim.tcl -tclargs mem_ctrl_bram_w16_tb $(BRAM_SRCS) tb/mem_ctrl_bram_tb.vhd tb/mem_ctrl_bram_w16_tb.vhd

# NEXYS A7-100T (MVP demo)
synth-framebuffer:
	$(VBATCH) -source scripts/synth_ooc.tcl -tclargs framebuffer xc7a100tcsg324-1 clk_i 10.0 $(FB_SRCS)

# Mercury 2 - part string needs confirming
synth-framebuffer-35t:
	$(VBATCH) -source scripts/synth_ooc.tcl -tclargs framebuffer xc7a35tftg256-1 clk_i 10.0 $(FB_SRCS)

synth-bram:
	$(VBATCH) -source scripts/synth_ooc.tcl -tclargs mem_ctrl_bram_synth_top xc7a100tcsg324-1 clk_i 10.0 $(BRAM_SRCS) rtl/mem_ctrl_bram_synth_top.vhd

build:

clean:
	rm -rf build .Xil
.PHONY: sim-frame-dump
sim-frame-dump:
	$(VBATCH) -source scripts/sim.tcl -tclargs frame_dump_tb $(FB_SRCS) tb/frame_dump_pkg.vhd tb/frame_dump_tb.vhd
