## Nexys4 DDR Constraints — RV32I Core
## Target: Artix-7 XC7A100T (xc7a100tcsg324-1)

## Clock — 100MHz oscillator
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK100MHZ]

## Derived 50MHz core clock (100MHz / 2 divider in fpga_top)
create_generated_clock -name core_clk -source [get_ports CLK100MHZ] -divide_by 2 [get_pins clk_div_reg/Q]

## Reset — CPU_RESETN (active-low pushbutton)
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports CPU_RESETN]

## UART — USB-UART bridge (FTDI chip)
## UART_TXD_IN (C4) = FTDI TX -> FPGA RX (data INTO FPGA)
## UART_RXD_OUT (D4) = FPGA TX -> FTDI RX (data OUT of FPGA)
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports UART_TXD_IN]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports UART_RXD_OUT]

## Debug LEDs
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports LED0]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports LED1]

## Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
