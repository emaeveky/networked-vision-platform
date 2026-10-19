## Digilent Arty S7-50 Rev. E
## Pin names are taken from Digilent's Arty-S7-50-Master.xdc.

set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports CLK12MHZ]
create_clock -add -name clk12 -period 83.333 -waveform {0 41.667} [get_ports CLK12MHZ]

set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN J16 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN H13 IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]
# Board buttons already have pulldowns. The FPGA pulldown keeps a floating
# pad from holding the design in reset.
set_property PULLTYPE PULLDOWN [get_ports {btn[*]}]

set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

# FTDI transmit -> FPGA receive. Pull up so an undriven line stays at UART idle.
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports uart_txd_in]
set_property PULLTYPE PULLUP [get_ports uart_txd_in]
# FPGA transmit -> FTDI receive
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports uart_rxd_out]

set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property INTERNAL_VREF 0.675 [get_iobanks 34]

# The DDR user clock and the 12 MHz UART clock are unrelated. The only
# crossing is the first flop of the synchronizer that copies the memory-test
# result, plus the mailboxes that carry a received frame into DDR.
set_false_path -to [get_cells {u_ddr/sync0_reg[*]}]
set_false_path -to [get_cells -hier -filter {NAME =~ *cdc_sync*_reg*}]
