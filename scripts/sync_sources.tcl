# ============================================================================
#  sync_sources.tcl -- adds source files that exist in CORDIC.srcs/ but are not
#  yet part of the open Vivado project (for example after pulling new code),
#  so the project in vivado/ does not have to be recreated.  Sourced by
#  create_project.tcl, build_bitstream.tcl and run_sims.tcl.
# ============================================================================
set _sync_root [file normalize [file join [file dirname [info script]] ..]]
proc _sync_fileset {fs patterns} {
    set have {}
    foreach f [get_files -quiet -of_objects [get_filesets $fs]] { lappend have [file normalize $f] }
    set new {}
    foreach p $patterns {
        foreach f [glob -nocomplain $p] {
            if {[lsearch -exact $have [file normalize $f]] < 0} { lappend new $f }
        }
    }
    if {[llength $new] > 0} {
        add_files -norecurse -fileset $fs $new
        puts "sync_sources: added to $fs: [join $new {, }]"
    }
}
_sync_fileset sources_1 [list "$_sync_root/CORDIC.srcs/sources_1/new/*.v"]
_sync_fileset sim_1     [list "$_sync_root/CORDIC.srcs/sim_1/new/*.v" "$_sync_root/CORDIC.srcs/sim_1/new/*.mem"]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
