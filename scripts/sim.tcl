# Run one VHDL tb in Vivado xsim with no GUI
# To use:
#   vivado -mode batch -nojournal -nolog -notrace -source scripts/sim.tcl \
#       -tclargs <tb> <src_1.vhd> [<src_2.vhd> ...]
# Sources are compiled in order given
# Generics are not passed on the command line: on Windows the Vivado .bat
# launchers split arguments at '=', so a testbench that needs another
# generic value gets a small wrapper entity (see tb/mem_ctrl_bram_w16_tb.vhd)
# Files in tb/vectors/ are copied into the run directory, so a testbench
# opens them by bare file name
#
# Pass/fail rule: testbench must print "<tb>: ALL TESTS PASSED"
# Anything else exits with code 1
# Outputs go to build/sim/<tb>/

if {[llength $argv] < 2} {
    puts "usage: -tclargs <tb> <src.vhd ..."
    exit 2
}
set top [lindex $argv 0]
set repo [file normalize [file join [file dirname [info script]] ..]]
set srcs {}
foreach f [lrange $argv 1 end] {
    lappend srcs [file normalize [file join $repo $f]]
}
set run_dir [file join $repo build sim $top]
file delete -force $run_dir
file mkdir $run_dir
# Stage the asset file where the VHDL loader expects it.
file mkdir [file join $run_dir data]
file copy -force \
    [file join $repo rtl data cube_init.txt] \
    [file join $run_dir data cube_init.txt]
foreach v [glob -nocomplain -directory [file join $repo tb vectors] *.txt *.csv] {
    file copy -force $v $run_dir
}
cd $run_dir

set ext [expr {$::tcl_platform(platform) eq "windows" ? ".bat" : ""}]

proc step {name args} {
    puts "== $name"
    if {[catch {exec -ignorestderr {*}$args} out]} {
        puts $out
        puts "FAIL: $name failed (see logs in [pwd])"
        exit 1
    }
}

step xvhdl xvhdl$ext --2008 {*}$srcs
step xelab xelab$ext -debug off -s ${top}_sim work.$top
# xsim might exit 0 even after a failed assert, so check logs
catch {exec -ignorestderr xsim$ext ${top}_sim -runall -log xsim.log} out

set fh [open xsim.log r]
set log [read $fh]
close $fh
if {[string first "$top: ALL TESTS PASSED" $log] >= 0} {
    puts "PASS: $top"
    exit 0
}
puts $log
puts "FAIL: $top (no pass line. Log in [file join $run_dir xsim.log])"
exit 1