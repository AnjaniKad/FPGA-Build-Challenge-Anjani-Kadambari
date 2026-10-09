# de10lite_uart_top.sdc
# Timing constraints for the DE10-Lite UART design.

# 50 MHz onboard oscillator -> 20 ns period.
create_clock -name MAX10_CLK1_50 -period 20.000 [get_ports MAX10_CLK1_50]

# Derive all other clock-related timing checks (not strictly needed here
# since there's only one clock domain, but standard practice).
derive_clock_uncertainty

# The UART RX/TX lines and the reset button are fully asynchronous to the
# system clock (that's the entire point of rx_line_sync.v's 2-flop
# synchronizer). Treat them as false paths so TimeQuest doesn't try to
# apply a synchronous timing relationship to signals that were never meant
# to have one.
set_false_path -from [get_ports GPIO_RX]
set_false_path -from [get_ports KEY0]
set_false_path -to   [get_ports GPIO_TX]
set_false_path -to   [get_ports LEDR[*]]
