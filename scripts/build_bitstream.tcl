# ============================================================================
#  build_bitstream.tcl -- batch build + report collection
#     vivado -mode batch -source scripts/build_bitstream.tcl   (from CORDIC/)
#  Opens vivado/CORDIC.xpr (creates it first if missing), runs synthesis and
#  implementation, writes the bitstream and collects the reports the
#  README's resource / timing / power sections are based on into reports/.
# ============================================================================
set here [file normalize [file dirname [info script]]]
set root [file normalize "$here/.."]
if {![file exists "$root/vivado/CORDIC.xpr"]} { source "$root/create_project.tcl" } elseif {[catch {current_project}]} { open_project "$root/vivado/CORDIC.xpr" }
file mkdir "$root/reports"

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1

report_utilization              -file "$root/reports/utilization.rpt"
report_utilization -hierarchical -file "$root/reports/utilization_hier.rpt"
report_timing_summary            -file "$root/reports/timing_summary.rpt" -max_paths 10
report_power                     -file "$root/reports/power.rpt"
report_drc                       -file "$root/reports/drc.rpt"
report_methodology               -file "$root/reports/methodology.rpt"
report_clock_utilization         -file "$root/reports/clock_utilization.rpt"
report_io                        -file "$root/reports/io.rpt"
puts "bitstream: $root/vivado/CORDIC.runs/impl_1/cordic_fm_top.bit"
puts "probes   : $root/vivado/CORDIC.runs/impl_1/cordic_fm_top.ltx"
