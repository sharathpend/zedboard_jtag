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
  localparam BITS_REQUIRED = $clog2(CYCLES_IN_1_SEC); // bits required in the counter to toggle roughly every second.
  localparam CONRLEN = 32; // JTAG config reg size
  localparam TRCAL_SIZE = 32; // JTAG shift reg size

  wire clk;

  // LED toggle
  reg [BITS_REQUIRED-1:0] clk_blink_counter = 0;
  reg [31:0] num_toggles = 0;
  reg led_0_d = 0;

  // JTAG
  wire shift_dr;
  wire pause_dr;
  wire update_dr;
  wire capture_dr;
  reg  capture_dr_d;

  wire extest_sel;
  wire sample_preload_sel;
  wire mbist_sel;
  wire debug_sel;

  wire [CONRLEN-1:0] tcr; // JTAG control register
  reg  [TRCAL_SIZE-1:0] trcal_reg; // JTAG shift register
  wire [TRCAL_SIZE-1:0] trcal_in;
  wire [TRCAL_SIZE-1:0] trcal_out;

  BUFGCE BUFGCE_clk_inst (
    .O  (clk),    // 1-bit output: Clock output
    .CE (clk_en), // 1-bit input: Clock enable input for I0
    .I  (clk_in)  // 1-bit input: Primary clock
  );

  // counter to toggle LED
  always@ (posedge clk) begin
    clk_blink_counter <= clk_blink_counter + 1'b1;
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
  always@ (posedge clk) begin
    casex(tcr[(CONRLEN-1) -: 8]) // MSB 8 bits are for selecting various registers to load on JTAG Shift Register for EXTEST??
      8'h0: begin
        trcal_reg <= 128'h0;
      end
      8'h1: begin
        trcal_reg <= {fdt_bias_control_reg_o, uart_status_reg_1_o, bit_period_status_reg_1_o, ac_control_reg};
      end
      8'h2: begin
        trcal_reg <= {ac_status_reg_1_o, ac_status_reg_2_o, decoder_status_reg_1_o, state_machine_status_reg_1_o};
      end
      8'h3: begin
        if (update_dr && extest_sel && tcr[(CONRLEN-9)]) begin // write
            trcal_reg <= trcal_out;
        end else if (capture_dr && extest_sel) begin // read (this might be too late, as the same condition is used inside test_interface, added capture_dr_d)
            trcal_reg <= {fdt_bias_control_reg_o, uart_status_reg_1_o, bit_period_status_reg_1_o, ac_control_reg};
        end
      end
      8'h4: begin
        if (update_dr && extest_sel && tcr[(CONRLEN-9)]) begin // write
            trcal_reg <= trcal_out;
        end else if (capture_dr && extest_sel) begin // read (this might be too late, as the same condition is used inside test_interface, added capture_dr_d)
            trcal_reg <= {ac_status_reg_1_o, ac_status_reg_2_o, decoder_status_reg_1_o, state_machine_status_reg_1_o};
        end
      end
      8'h8: begin // When addr is 8, update_dr will force trcal_reg to update
        if (update_dr && extest_sel) begin
            trcal_reg <= trcal_out;
        end
        load_bias_jtag <= ~trcal_reg[0];
        bias_logic_1_jtag <= trcal_reg[15:8];
        bias_logic_0_jtag <= trcal_reg[23:16];
        uart_prescale_jtag <= trcal_reg[47:32];
      end
      8'h9: begin // When addr is 9, program some important MUX
        if (update_dr && extest_sel) begin
            trcal_reg <= trcal_out;
        end
        clk_select_jtag <= trcal_reg[0];
        rst_select_jtag <= trcal_reg[8];
        ac_control_reg <= trcal_reg[63:32];
        UID_backup_wire_i_debug_jtag <= trcal_reg[95:64];
        UID_source_selector_i_debug_jtag <= trcal_reg[96];
        UID_mem_addr_selector_i_debug_jtag <= trcal_reg[101:100];
      end
      8'd15: begin
        trcal_reg <= 128'hDEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF; // Dummy value for EXTEST DEBUG
      end
      default: begin
        trcal_reg <= 128'h0;
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
      .mbist_tdi_i                (tdi_bist) // from Mbist Chain
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
  ) test_interface_inst (			   
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
      .tdo2                (tdo2),

      .txbitout_in         (real_encoder_output), // input from encoder
      .txbitout_out        (encoded_bit_o_analog), // muxed output to Analog Modulator (after debug interface), select between encoded_bit and chiptdi
      
      .txbitouten_in       (real_encoder_enable), // input from encoder
      .txbitouten_out      (output_enable_o_analog), // muxed output to Analog Modulator (after debug interface), select between encoded_bit and chiptdi
      
      .NFC_demod_in        (analog_output_i_analog), // input from analog receiver
      .used_demodin        (analog_demod_in), // muxed output to Decoder (through debug interface), select between analog_output_i_analog and chiptdi

      // These tell what instruction is currently loaded (from jtag_tap)
      .extest_sel          (extest_sel),
      .sample_preload_sel  (sample_preload_sel),
      .mbist_sel           (mbist_sel),
      .debug_sel           (debug_sel),

      // Control Reg
      // Upper 8 bits are used for MUX in data into JTAG Shift Register trcal_in. Other bits could be used for MUX for tdo
      // Bit (CONRLEN-9) is used to select between read and then write to the JTAG Shift Register (1), or just read from it (0).
      .tcr_out                    (tcr),

      .chipreset                  (rst), // unused

      // JTAG Shift Register
      .trcal_tr_in                (trcal_in), // I think this is the register that is used to store the data you want to send out/receive through JTAG
      .trcal_tr_out               (trcal_out)

  );


endmodule