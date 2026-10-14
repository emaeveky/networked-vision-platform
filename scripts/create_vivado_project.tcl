set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set project_dir [file join $root build vivado]

create_project -force vision_uart $project_dir -part xc7s50csga324-1

add_files [list \
    [file join $root rtl uart_rx.sv] \
    [file join $root rtl uart_tx.sv] \
    [file join $root rtl proto_parser.sv] \
    [file join $root rtl packet_tracker.sv] \
    [file join $root rtl frame_engine.sv] \
    [file join $root rtl pixel_writer.sv] \
    [file join $root rtl double_buffer_ctrl.sv] \
    [file join $root rtl frame_mem.sv] \
    [file join $root rtl vision_core.sv] \
    [file join $root rtl img_threshold.sv] \
    [file join $root rtl img_sobel.sv] \
    [file join $root rtl motion_box.sv] \
    [file join $root rtl bg_frame.sv] \
    [file join $root rtl arty_s7_uart_top.sv] \
]
add_files -fileset constrs_1 [file join $root constraints arty_s7_50_uart.xdc]

set_property file_type SystemVerilog [get_files *.sv]
set_property top arty_s7_uart_top [get_filesets sources_1]
set_property top_auto_set 0 [get_filesets sources_1]

update_compile_order -fileset sources_1
puts "Created $project_dir/vision_uart.xpr"
puts "Open the project, run synthesis/implementation, then generate the bitstream."
