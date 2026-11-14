# ============================================================================
#  create_project.tcl -- creates the Vivado project vivado/CORDIC.xpr
#
#  Usage (either):
#     vivado -mode batch -source create_project.tcl          (from this folder)
#     Vivado GUI -> Tcl Console ->  cd <this folder>; source create_project.tcl
#
#  The sources already live in the Vivado layout
#     CORDIC.srcs/sources_1/new/*.v      RTL
#     CORDIC.srcs/constrs_1/new/*.xdc    constraints
#     CORDIC.srcs/sim_1/new/*.v *.mem    test benches, models, vectors
#  and the project in vivado/ references them without copying.  The script also generates the
#  VIO debug core (vio_0) and sets USE_VIO for synthesis only, so the same
#  top level simulates without any IP.
# ============================================================================
set proj_name  "CORDIC"
set root       [file normalize [file dirname [info script]]]
set proj_dir   "$root/vivado"
set part       "xc7z020clg484-1"
set top        "cordic_fm_top"

# The project lives in its own folder, vivado/, and references the sources in
# CORDIC.srcs/ in place.  Vivado refuses to create a project named CORDIC next to
# an existing CORDIC.srcs folder, and -force must not be used because it may clear
# that folder.  To rebuild the project from scratch (for example after the VIO
# probe list changed), close it and delete the vivado/ folder.
cd $root
if {[file exists "$proj_dir/$proj_name.xpr"]} {
    puts "vivado/CORDIC.xpr already exists -- opening it.  Delete vivado/ first for a fresh project."
    open_project "$proj_dir/$proj_name.xpr"
    return
}
create_project $proj_name $proj_dir -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]
# optional: Avnet ZedBoard board file if installed (raw part works fine without it)
catch { set_property board_part em.avnet.com:zed:part0:1.4 [current_project] }

# ---------------- design sources ----------------
set rtl [glob -nocomplain $root/CORDIC.srcs/sources_1/new/*.v]
add_files -norecurse -fileset sources_1 $rtl
set_property top $top [get_filesets sources_1]
set_property verilog_define {USE_VIO=1} [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---------------- constraints ----------------
add_files -norecurse -fileset constrs_1 [glob $root/CORDIC.srcs/constrs_1/new/*.xdc]

# ---------------- simulation sources ----------------
set sim [concat [glob -nocomplain $root/CORDIC.srcs/sim_1/new/*.v] \
                [glob -nocomplain $root/CORDIC.srcs/sim_1/new/*.mem]]
add_files -norecurse -fileset sim_1 $sim
set_property top tb_cordic_fm_system [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {false} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

# ---------------- VIO debug core ----------------
# 20 input probes, 10 output probes; widths must match cordic_fm_top.v
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN   {20} \
    CONFIG.C_NUM_PROBE_OUT  {10}  \
    CONFIG.C_PROBE_IN0_WIDTH  {7}  CONFIG.C_PROBE_IN1_WIDTH  {7}  CONFIG.C_PROBE_IN2_WIDTH  {6}  \
    CONFIG.C_PROBE_IN3_WIDTH  {6}  CONFIG.C_PROBE_IN4_WIDTH  {2}  CONFIG.C_PROBE_IN5_WIDTH  {1}  \
    CONFIG.C_PROBE_IN6_WIDTH  {5}  CONFIG.C_PROBE_IN7_WIDTH  {4}  CONFIG.C_PROBE_IN8_WIDTH  {12} \
    CONFIG.C_PROBE_IN9_WIDTH  {16} CONFIG.C_PROBE_IN10_WIDTH {16} CONFIG.C_PROBE_IN11_WIDTH {16} \
    CONFIG.C_PROBE_IN12_WIDTH {48} CONFIG.C_PROBE_IN13_WIDTH {48} CONFIG.C_PROBE_IN14_WIDTH {16} \
    CONFIG.C_PROBE_IN15_WIDTH {7}  CONFIG.C_PROBE_IN16_WIDTH {48} CONFIG.C_PROBE_IN17_WIDTH {8}  \
    CONFIG.C_PROBE_IN18_WIDTH {32} CONFIG.C_PROBE_IN19_WIDTH {26} \
    CONFIG.C_PROBE_OUT0_WIDTH {1}  CONFIG.C_PROBE_OUT1_WIDTH {7}  CONFIG.C_PROBE_OUT2_WIDTH {7}  \
    CONFIG.C_PROBE_OUT3_WIDTH {6}  CONFIG.C_PROBE_OUT4_WIDTH {6}  CONFIG.C_PROBE_OUT5_WIDTH {2}  \
    CONFIG.C_PROBE_OUT6_WIDTH {1}  CONFIG.C_PROBE_OUT7_WIDTH {1}  CONFIG.C_PROBE_OUT8_WIDTH {11} \
    CONFIG.C_PROBE_OUT9_WIDTH {5}  \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x0} CONFIG.C_PROBE_OUT1_INIT_VAL {0x28} CONFIG.C_PROBE_OUT2_INIT_VAL {0x28} \
    CONFIG.C_PROBE_OUT3_INIT_VAL {0x8} CONFIG.C_PROBE_OUT4_INIT_VAL {0x10} \
] [get_ips vio_0]
generate_target all [get_ips vio_0]

# ---------------- run strategies ----------------
set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]

puts "============================================================"
puts " Project $proj_name created in $proj_dir"
puts " Top: $top   Part: $part"
puts " Next: launch_runs impl_1 -to_step write_bitstream -jobs 8"
puts "       or Flow Navigator -> Generate Bitstream"
puts "============================================================"
