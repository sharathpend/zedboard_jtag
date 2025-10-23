create_clock -name clk_in -period 10.000 [get_ports {clk_in}]
create_generated_clock -name clk -source [get_clocks clk_in] -divide_by 1