//=====================================================
// Designer: Sharath Pendyala
//=====================================================


module fpga_wrapper (
  // Clock and clock_enable (enable controlled via switch)
  input  wire clk_in, // GCLK, 100MHz
  input  wire clk_en, // SW0

  // JTAG Interface
  input  wire tck,  // JA1
  input  wire tms,  // JA2
  input  wire tdi,  // JA3
  output wire tdo,  // JA4
  input  wire trst, // JA7

  // LED toggle
  output wire led_0, // LD0

  // Divided clock output (maybe to external scope), selected via JTAG
  output wire clk_div_o // JA8
);

  localparam CLOCK_PERIOD = 10; // ns
  localparam CYCLES_IN_1_SEC = $rtoi($floor(1000000000/CLOCK_PERIOD));
  localparam BITS_REQUIRED = $clog2(CYCLES_IN_1_SEC); // bits required in the counter to toggle roughly every second.
  localparam CONRLEN = 32; // JTAG config reg size
  localparam TRCAL_SIZE = 32; // JTAG shift reg size

  // Simple divided clock output, selected via JTAG to test its functionality.
  localparam CLK_DIV_1 = 10; // How much to divide the clock and send outside to observe.
  localparam CLK_DIV_2 = 20; // How much to divide the clock and send outside to observe.
  localparam CLK_DIV_1_BITS = $clog2(CLK_DIV_1);
  localparam CLK_DIV_2_BITS = $clog2(CLK_DIV_2);

  wire clk; // target 100MHz
  wire clk_ila; // target 10MHz, to scan a 1MHz JTAG
  reg  clk_div_1 = 0;
  reg  clk_div_2 = 0;
  reg  [CLK_DIV_1_BITS-1:0] clk_div_1_counter = 0;
  reg  [CLK_DIV_2_BITS-1:0] clk_div_2_counter = 0;
  
  // PLL
  wire CLKFBOUT;
  wire CLKFBIN;

  // LED toggle
  reg  [BITS_REQUIRED-1:0] clk_blink_counter = 0;
  reg  [1:0] led_blink_speed_1 = 1;
  reg  [1:0] led_blink_speed_2 = 2;
  wire [1:0] led_blink_speed; // selected via JTAG
  reg  [CONRLEN-1:0] num_toggles = 0;
  reg  led_0_d = 0;

  // JTAG
  wire tdoen;
  wire test_logic_reset;
  wire shift_dr;
  wire pause_dr;
  wire update_dr;
  wire capture_dr;
  reg  capture_dr_d = 0;
  wire extest_sel;
  wire sample_preload_sel;
  wire mbist_sel;
  wire debug_sel;
  wire tdi_debug;
  wire tdi_boundary_scan;
  wire tdi_bist;
  wire [CONRLEN-1:0] tcr; // JTAG control register
  reg  [TRCAL_SIZE-1:0] trcal_reg = 0; // JTAG shift register
  reg  [TRCAL_SIZE-1:0] trcal_reg_in = {TRCAL_SIZE{1'b1}}; // Input from JTAG Shift Reg (write into User Design from JTAG)
  wire [TRCAL_SIZE-1:0] trcal_in;
  wire [TRCAL_SIZE-1:0] trcal_out;

  // JTAG ILA
  reg        ila_tck = 0;
  reg        ila_tms = 0;
  reg        ila_tdi = 0;
  reg        ila_tdo = 0;
  wire [3:0] ila_latched_jtag_ir;
  wire       ila_extest_select;
  wire       ila_sample_preload_select;
  wire       ila_idcode_select;
  wire       ila_mbist_select;
  wire       ila_debug_select;
  wire       ila_feedthru_select;
  wire       ila_bypass_select;


  BUFGCE BUFGCE_clk_inst (
    .O  (clk),    // 1-bit output: Clock output
    .CE (clk_en), // 1-bit input: Clock enable input for I0
    .I  (clk_in)  // 1-bit input: Primary clock
  );

  /*
  There are some values that these need to be betweem, which varies based on MMCM/PLL.
  D,M,O can take certain rages and steps based on MMCM/PLL
  Fpfd = Fin/D (I think this is only for MMCM. Not completely sure.)
  Fvco = Fin*(M/D)
  Fout = Fvco / O
  */
  // Generate 20MHz clock for ILA using PLLE2
  PLLE2_ADV #(
    .BANDWIDTH("OPTIMIZED"),  // OPTIMIZED, HIGH, LOW
    .CLKFBOUT_MULT(41),        // Multiply value for all CLKOUT, (2-64)
    .CLKFBOUT_PHASE(0.0),     // Phase offset in degrees of CLKFB, (-360.000-360.000).
    // CLKIN_PERIOD: Input clock period in nS to ps resolution (i.e. 33.333 is 30 MHz).
    .CLKIN1_PERIOD(CLOCK_PERIOD),
    // CLKOUT0_DIVIDE - CLKOUT5_DIVIDE: Divide amount for CLKOUT (1-128)
    .CLKOUT0_DIVIDE(82),
    // CLKOUT0_DUTY_CYCLE - CLKOUT5_DUTY_CYCLE: Duty cycle for CLKOUT outputs (0.001-0.999).
    .CLKOUT0_DUTY_CYCLE(0.5),
    // CLKOUT0_PHASE - CLKOUT5_PHASE: Phase offset for CLKOUT outputs (-360.000-360.000).
    .CLKOUT0_PHASE(0.0),
    .COMPENSATION("ZHOLD"),   // ZHOLD, BUF_IN, EXTERNAL, INTERNAL
    .DIVCLK_DIVIDE(5),        // Master division value (1-56)
    // REF_JITTER: Reference input jitter in UI (0.000-0.999).
    .REF_JITTER1(0.0),
    .REF_JITTER2(0.0),
    .STARTUP_WAIT("FALSE")    // Delay DONE until PLL Locks, ("TRUE"/"FALSE")
  ) PLLE2_ADV_inst (
    // Clock Outputs: 1-bit (each) output: User configurable clock outputs
    .CLKOUT0(clk_ila),   // 1-bit output: CLKOUT0
    // Feedback Clocks: 1-bit (each) output: Clock feedback ports
    .CLKFBOUT(CLKFBOUT), // 1-bit output: Feedback clock
    .LOCKED(LOCKED),     // 1-bit output: LOCK
    // Clock Inputs: 1-bit (each) input: Clock inputs
    .CLKIN1(clk_in),     // 1-bit input: Primary clock
    // Control Ports: 1-bit (each) input: PLL control ports
    .CLKINSEL(1'b1), // 1-bit input: Clock select, High=CLKIN1 Low=CLKIN2
    .PWRDWN(1'b0),     // 1-bit input: Power-down
    .RST(1'b0),           // 1-bit input: Reset
    // Feedback Clocks: 1-bit (each) input: Clock feedback ports
    .CLKFBIN(CLKFBIN)    // 1-bit input: Feedback clock
  );
   
  assign CLKFBIN = CLKFBOUT;

  // counters to generate clk_div_1 and clk_div_2
  always@ (posedge clk) begin
    if (clk_div_1_counter == CLK_DIV_1-1) begin
      clk_div_1 <= ~clk_div_1;
      clk_div_1_counter <= 0;
    end else
      clk_div_1_counter <= clk_div_1_counter + 1'b1;
    
    if (clk_div_2_counter == CLK_DIV_2-1) begin
      clk_div_2 <= ~clk_div_2;
      clk_div_2_counter <= 0;
    end else
      clk_div_2_counter <= clk_div_2_counter + 1'b1;
  end

  // counter to toggle LED
  always@ (posedge clk) begin
    clk_blink_counter <= clk_blink_counter + led_blink_speed;
  end

  assign led_0 = clk_blink_counter[BITS_REQUIRED-1];

  // counter to cound how many times LED toggled ON.
  always@ (posedge clk) begin
    led_0_d <= led_0;
    if (led_0 & ~led_0_d) begin
      num_toggles <= num_toggles + 1'b1;
    end
  end


  // JTAG Shift Register (trcal_reg)
  // MSB 8 bits of tcr are for selecting various registers to load on JTAG Shift Register for EXTEST
  // tcr[(CONRLEN-9)] is used to select between write (1) and read (0) in cases where write is allowed
  always@ (posedge clk) begin
    casex(tcr[(CONRLEN-1) -: 8])
      8'h0: begin // Default value for EXTEST DEBUG 
        trcal_reg <= 0;
      end
      8'h1: begin // Dummy value for EXTEST DEBUG
        trcal_reg <= 'hDEAD_BEEF;
      end
      8'h2: begin // Example of reading a value from User Design
        trcal_reg <= num_toggles;
      end
      8'h3: begin // Write/Read operation example
        if (update_dr && extest_sel && tcr[(CONRLEN-9)]) begin // write
          trcal_reg_in <= trcal_out;
        end else if (capture_dr && extest_sel) begin // read
          trcal_reg <= trcal_reg_in;
        end
      end
      default: begin // Dummy value for EXTEST DEBUG
        trcal_reg <= 'hBEEF_BEEF;
      end
    endcase
  end

  assign trcal_in = trcal_reg;

  // JTAG modules
  jtag_tap jtag_tap_inst (
      // JTAG Pins
      .tms_pad_i                  (tms),      // JTAG test mode select pad (input)
      .tck_pad_i                  (tck),      // JTAG test clock pad (input)
      .trst_pad_i                 (trst),     // JTAG test reset pad (input)
      .tdi_pad_i                  (tdi),      // JTAG test data input pad (input)
      .tdo_pad_o                  (tdo),      // JTAG test data output pad (output)
      .tdo_padoe_o                (tdoen),    // Output enable for JTAG test data output pad (output)

      // Output from jtag_tap to test_interface, to allow monitoring of TAP states
      .shift_dr_o                 (shift_dr),
      .pause_dr_o                 (pause_dr),
      .update_dr_o                (update_dr),
      .capture_dr_o               (capture_dr),
      .test_logic_reset_o         (test_logic_reset),

      // Select signals for boundary scan or mbist (outputs that tell what instruction is currently loaded)
      .extest_select_o            (extest_sel),
      .sample_preload_select_o    (sample_preload_sel),
      .mbist_select_o             (mbist_sel),
      .debug_select_o             (debug_sel),

      // TDO signal that is connected to TDI of sub-modules.
      .tdo_o                      (chiptdi),

      // TDI signals from sub-modules
      .debug_tdi_i                (tdi_debug), // from debug module
      .bs_chain_tdi_i             (tdi_boundary_scan), // from Boundary Scan Chain
      .mbist_tdi_i                (tdi_bist), // from Mbist Chain

      .ila_latched_jtag_ir        (ila_latched_jtag_ir),
      .ila_extest_select          (ila_extest_select),
      .ila_sample_preload_select  (ila_sample_preload_select),
      .ila_idcode_select          (ila_idcode_select),
      .ila_mbist_select           (ila_mbist_select),
      .ila_debug_select           (ila_debug_select),
      .ila_feedthru_select        (ila_feedthru_select),
      .ila_bypass_select          (ila_bypass_select)
  );

  always@ (posedge tck or posedge trst) begin
      if (trst) begin
          capture_dr_d <= 1'b0;
      end else begin
          capture_dr_d <= capture_dr;
      end
  end

  jtag_test_interface #(
      .CONRLEN            (CONRLEN), // JTAG configuration register length
      .TRCAL_SIZE         (TRCAL_SIZE) // JTAG shift register size
  ) jtag_test_interface_inst (			   
      .tclk               (tck),  // JTAG test clock pad
      .test_logic_reset_i (test_logic_reset), 
      
      // Input from jtag_tap to monitor TAP states
      .shift_dr_i          (shift_dr),
      .pause_dr_i          (pause_dr),
      .update_dr_i         (update_dr),
      .capture_dr_i        (capture_dr_d),
      
      .debug_tdi_o         (tdi_debug),
      .bs_chain_tdi_o      (tdi_boundary_scan),
      .mbist_tdi_o         (tdi_bist),

      .chiptdi             (chiptdi),

      .sel_1_in_1          (clk_div_1),
      .sel_1_in_2          (clk_div_2),
      .sel_1_out           (clk_div_o),
      .sel_2_in_1          (led_blink_speed_1),
      .sel_2_in_2          (led_blink_speed_2),
      .sel_2_out           (led_blink_speed),

      // These tell what instruction is currently loaded (from jtag_tap)
      .extest_sel          (extest_sel),
      .sample_preload_sel  (sample_preload_sel),
      .mbist_sel           (mbist_sel),
      .debug_sel           (debug_sel),

      // Control Reg
      // Upper 8 bits are used for MUX in data into JTAG Shift Register trcal_in.
      // Other bits could be used for MUX for tdo
      // Bit (CONRLEN-9) is used to select between read and then write to the JTAG
      // Shift Register (1), or just read from it (0).
      .tcr_out                    (tcr),

      // JTAG Shift Register
      .trcal_tr_in                (trcal_in), // the data you want to send out/receive through JTAG
      .trcal_tr_out               (trcal_out)

  );

  always@ (posedge clk_ila) begin
    ila_tck <= tck;
    ila_tms <= tms;
    ila_tdi <= tdi;
    ila_tdo <= tdo;
  end
  
  // ILA to debug the JTAG interface
  jtag_ila jtag_ila_inst (
    .clk     (clk_ila), // input wire clk

    .probe0  (ila_tck), // input wire [0:0]  probe0  
    .probe1  (ila_tms), // input wire [0:0]  probe1 
    .probe2  (ila_tdi), // input wire [0:0]  probe2 
    .probe3  (ila_tdo), // input wire [0:0]  probe3 
    .probe4  (ila_latched_jtag_ir), // input wire [3:0]  probe4 
    .probe5  (ila_extest_select), // input wire [0:0]  probe5 
    .probe6  (ila_sample_preload_select), // input wire [0:0]  probe6 
    .probe7  (ila_idcode_select), // input wire [0:0]  probe7 
    .probe8  (ila_mbist_select), // input wire [0:0]  probe8 
    .probe9  (ila_debug_select), // input wire [0:0]  probe9 
    .probe10 (ila_feedthru_select), // input wire [0:0]  probe10 
    .probe11 (ila_bypass_select) // input wire [0:0]  probe11
  );
  

endmodule