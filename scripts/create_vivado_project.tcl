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
    [file join $root rtl ddr3_pattern.sv] \
    [file join $root rtl ddr3_board.sv] \
    [file join $root rtl arty_s7_uart_top.sv] \
]
set_property file_type SystemVerilog [get_files *.sv]

create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_200
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {12.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.USE_RESET {false} \
    CONFIG.USE_LOCKED {true} \
] [get_ips clk_wiz_200]

create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_arty
set_property CONFIG.XML_INPUT_FILE [file normalize [file join $root ip arty_s7_50_mig.prj]] [get_ips mig_arty]
generate_target all [get_ips clk_wiz_200]
generate_target all [get_ips mig_arty]
add_files -fileset constrs_1 [file join $root constraints arty_s7_50_uart.xdc]

set_property top arty_s7_uart_top [get_filesets sources_1]
set_property top_auto_set 0 [get_filesets sources_1]

update_compile_order -fileset sources_1
puts "Created $project_dir/vision_uart.xpr"
puts "Open the project, run synthesis/implementation, then generate the bitstream."
