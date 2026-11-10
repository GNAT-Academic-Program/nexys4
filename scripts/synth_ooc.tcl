# Out of context synth of one block, print BRAM count and timing est
# To use:
#   vivado -mode batch -nojournal -nolog -notrace -source scripts/synth_ooc.tcl \
#       -tclargs <top> <part> <clk_port> <period_ns> <src_1.vhd> [<src_2.vhd> ...]
#
# Reports go to build/synth/<top>_<part>/

if {[llength $argv] < 5 } {
    puts "usage: -tclargs <top> <part> <clk_port> <period_ns> <src.vhd> ..."
    exit 2
}
lassign $argv top part clk_port period
set repo [file normalize [ file join [file dirname [ info script]] ..]]
set out_dir [file join $repo build synth ${top}_$part]
file mkdir $out_dir

foreach f [lrange $argv 4 end] {
    read_vhdl -vhdl2008 [file normalize [file join $repo $f]]
}
set synth_args [list -top $top -part $part -mode out_of_context]
if {$top eq "asset_memory"} {
    set init_file [file join $repo rtl data cube_init.txt]
    lappend synth_args -generic "INIT_FILE=$init_file"
}
synth_design {*}$synth_args
create_clock -name clk -period $period [get_ports $clk_port]

report_utilization      -file [file join $out_dir utilization.rpt]
report_timing_summary   -file [file join $out_dir timing_summary.rpt]

set n36 [llength [get_cells -hier -quiet -filter {REF_NAME =~ RAMB36*}]]
set n18 [llength [get_cells -hier -quiet -filter {REF_NAME =~ RAMB18*}]]
set nlut [llength [get_cells -hier -quiet -filter {REF_NAME =~ LUT*}]]
set path [get_timing_paths -setup -max_paths 1 -nworst 1]
set wns [expr {[llength $path] ? [get_property SLACK $path] : "n/a"}]

puts "RESULT: $top on $part: RAMB36=$n36 RAMB18=$n18 LUT=$nlut WNS=${wns} ns at ${period} ns"
puts "Reports: $out_dir"
exit 0