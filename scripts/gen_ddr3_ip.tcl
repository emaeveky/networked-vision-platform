# Generate the Arty S7-50 DDR3 controller and the 200 MHz reference clock
# into a side project. The main bitstream project is created later.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set probe [file join $root build mig_probe]

create_project -force mig_probe $probe -part xc7s50csga324-1

create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_200
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {12.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.USE_RESET {false} \
    CONFIG.USE_LOCKED {true} \
] [get_ips clk_wiz_200]

create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_arty
set_property CONFIG.XML_INPUT_FILE [file normalize [file join $root ip arty_s7_50_mig.prj]] [get_ips mig_arty]

generate_target {instantiation_template} [get_ips clk_wiz_200]
generate_target {instantiation_template} [get_ips mig_arty]
puts "DDR3 IP templates are in $probe"
