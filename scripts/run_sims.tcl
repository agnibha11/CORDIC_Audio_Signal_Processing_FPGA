# ============================================================================
#  run_sims.tcl -- runs every self-checking test bench in XSim, one after the
#  other, and prints a PASS/FAIL table.    (Vivado Tcl console, from CORDIC/)
#     source scripts/run_sims.tcl
# ============================================================================
set tbs {tb_cordic_engine tb_mic3_adc_spi tb_da2_dac_spi tb_kypd_scanner tb_recip_divider tb_cordic_fm_system tb_cordic_fm_top}
set results {}
foreach tb $tbs {
    set_property top $tb [get_filesets sim_1]
    set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
    launch_simulation
    set log [file join [get_property DIRECTORY [current_project]] CORDIC.sim sim_1 behav xsim simulate.log]
    set fh [open $log r]; set txt [read $fh]; close $fh
    if {[regexp {ALL PASS \((\d+) checks\)} $txt -> n]} { lappend results "$tb : PASS ($n checks)" } else { lappend results "$tb : FAIL  (see $log)" }
    close_sim
}
puts "=============================================="
foreach r $results { puts $r }
puts "=============================================="
