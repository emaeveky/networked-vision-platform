# Program the current bitstream without rebuilding the project.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set bitfile [file join $root build vivado vision_uart.runs impl_1 arty_s7_uart_top.bit]
if {![file exists $bitfile]} {
    error "No bitstream at $bitfile"
}

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
