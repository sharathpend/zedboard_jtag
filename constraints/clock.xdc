# Physical clocks
create_clock -name CLK_IN -period 10.0 [get_ports {clk_in}]
create_clock -name JTAG_TCK -period 1000.0 [get_ports {tck}]

# Generated clocks
create_generated_clock -name CLK -source [get_clocks CLK_IN] -divide_by 1

# Clock properties
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets tck_IBUF]

# Clock relationship
set_clock_groups -asynchronous -group [get_clocks JTAG_TCK] -group [get_clocks CLK]