set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
source [file join $script_dir create_vivado_project.tcl]

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation failed: $impl_status"
}

set bitfile [lindex [glob -nocomplain [file join $project_dir vision_uart.runs impl_1 *.bit]] 0]
if {$bitfile eq ""} {
    error "No bitstream was produced"
}

# A partly-aborted reset can leave an old .bit behind. Programming it would look
# like the RTL fix did nothing, so compare against the newest source file.
set newest_src 0
set newest_name ""
foreach f [concat [glob [file join $root rtl *.sv]] \
                  [glob [file join $root constraints *.xdc]]] {
    set t [file mtime $f]
    if {$t > $newest_src} {
        set newest_src $t
        set newest_name $f
    }
}
if {[file mtime $bitfile] < $newest_src} {
    error "Bitstream is older than [file tail $newest_name]. The build did not rerun."
}
puts "Bitstream: $bitfile"
puts "Bitstream time: [clock format [file mtime $bitfile]]"

open_hw_manager
connect_hw_server
open_hw_target
set device [lindex [get_hw_devices] 0]
if {$device eq ""} {
    error "No hardware device found. Check the USB cable and that the Arty is powered."
}
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device
refresh_hw_device $device
puts "Programmed $device"
close_hw_manager
