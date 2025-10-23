//=====================================================
// Designer: Sharath Pendyala
//=====================================================



module fpga_wrapper (
  // Clock
  input  wire clk_in, // GCLK, 100MHz
  input  wire clk_en, // SW0

  // Simple JTAG Interface
  input  wire tck,  // JA1
  input  wire tms,  // JA2
  input  wire tdi,  // JA3
  output wire tdo,  // JA4
  input  wire trst, // JA7

  // Simple LED power ON
  output wire led_0 // LD0
);

  localparam CLOCK_PERIOD = 10; // ns
  localparam CYCLES_IN_1_SEC = $rtoi($floor(1000000000/CLOCK_PERIOD));
  localparam BITS_REQUIRED = $clog2(CYCLES_IN_1_SEC);

  wire clk;

  reg [BITS_REQUIRED-1:0] clk_blink_counter = 0;

  BUFGCE BUFGCE_clk_inst (
    .O  (clk),    // 1-bit output: Clock output
    .CE (clk_en), // 1-bit input: Clock enable input for I0
    .I  (clk_in)  // 1-bit input: Primary clock
  );

  always@ (posedge clk) begin
    clk_blink_counter <= clk_blink_counter + 1'b1;
  end

  assign led_0 = clk_blink_counter[BITS_REQUIRED-1];

endmodule