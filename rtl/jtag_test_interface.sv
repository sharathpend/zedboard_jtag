// -----------------------------------------------------------------------------
// Digital Test Interface between User Design and JTAG TAP
// -----------------------------------------------------------------------------
//
// This module provides a JTAG-accessible test interface for the digital core.
// It allows configuration and observation of internal signals via a JTAG TAP.
// The interface includes a configuration register (TCR) that controls muxes
// and debug paths, and a shift register for JTAG data movement. The TCR is
// only updated on JTAG UPDATE_DR, so muxes are stable during shifting.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module jtag_test_interface #(
    parameter CONRLEN = 32,      // JTAG configuration register length
    parameter TRCAL_SIZE = 32    // JTAG shift register size
) (
    // -------------------------------------------------------------------------
    // JTAG Interface Ports
    // -------------------------------------------------------------------------
    input  wire tclk,                // JTAG test clock
    input  wire test_logic_reset_i,   // JTAG test reset pad

    // TAP state monitor inputs
    input  wire shift_dr_i,
    input  wire pause_dr_i,
    input  wire update_dr_i,
    input  wire capture_dr_i,

    // JTAG chain outputs
    output wire debug_tdi_o,          // Debug chain
    output reg  bs_chain_tdi_o = 0,   // Boundary scan chain
    output wire mbist_tdi_o,          // MBIST chain

    input  wire chiptdi,              // The tap's tdo_o pin (connects to tdi_pad_i)

    // -------------------------------------------------------------------------
    // JTAG MUX Interface Ports (Connected to User Design)
    // -------------------------------------------------------------------------
    input  wire sel_1_in_1,
    input  wire sel_1_in_2,
    input  wire sel_1_out,
    input  wire sel_2_in_1,
    input  wire sel_2_in_2,
    input  wire sel_2_out,

    // -------------------------------------------------------------------------
    // JTAG Instruction Select
    // -------------------------------------------------------------------------
    input  wire sample_preload_sel,   // SAMPLE_PRELOAD instruction select
    input  wire extest_sel,           // EXTEST instruction select
    input  wire debug_sel,            // DEBUG instruction select
    input  wire mbist_sel,            // MBIST instruction select

    // -------------------------------------------------------------------------
    // Control Register and Test Data Ports
    // -------------------------------------------------------------------------
    output wire [CONRLEN-1:0] tcr_out,            // Output of the test control register
    input  wire [TRCAL_SIZE-1:0] trcal_tr_in,     // Input for trcal shift register
    output reg  [TRCAL_SIZE-1:0] trcal_tr_out = 0 // Output for trcal shift register
);

// -----------------------------------------------------------------------------
// Internal Registers
// -----------------------------------------------------------------------------
reg [CONRLEN-1:0] tcr = 0; // Latched config register (used for muxes)
reg [CONRLEN-1:0] tcr_shift = {CONRLEN{1'b1}};  // Shift register (for JTAG shifting)

// -----------------------------------------------------------------------------
// Mux Logic (TCR controls muxes)
// -----------------------------------------------------------------------------
// The following assignments allow the TCR to select any combination of values
// from the muxes. Only the latched TCR register is used for mux selection, so
// shifting does not cause glitches.

// If enabled, drive the sel_1_out from sel_1_in_2; otherwise, use sel_1_in_1.
assign sel_1_out = ((tcr[CONRLEN-10] && tcr[0]) == 1'b1) ? sel_1_in_2 : sel_1_in_1;

// If enabled, drive the sel_2_out from sel_2_in_2; otherwise, use sel_2_in_1.
assign sel_2_out = ((tcr[CONRLEN-10] && tcr[1]) == 1'b1) ? sel_2_in_2 : sel_2_in_1;

// If enabled, drive sel_1_out to debug_tdi_o; otherwise, 0. To observe is sle_1_out
// is getting selected correctly.
assign debug_tdi_o = ((tcr[CONRLEN-10] && tcr[2]) == 1'b1) ? sel_1_out : 1'b0;

// Boundary scan and MBIST TDI outputs are currently unused, so just set them to 0.
assign mbist_tdi_o = 1'b0;
// assign bs_chain_tdi_o = trcal_tr_out[0];

// -----------------------------------------------------------------------------
// JTAG Shift Register for trcal (EXTEST)
// -----------------------------------------------------------------------------
// Handles shifting for the EXTEST instruction. Registers shifting IN are clocked
// on the POSEDGE. Registers shifting OUT are clocked on the NEGEDGE.

always @(posedge tclk or posedge test_logic_reset_i) begin
    if (test_logic_reset_i) begin
        trcal_tr_out <= #1 0; // Default state. If JTAG is not powered, use PU/PD resistors at mux for default state.
        // trcal_tr_out <= #1 ~tcr;
    end else begin
        // EXTEST CAPTURE/UPDATE EXAMPLE
        if (extest_sel & shift_dr_i) begin
            trcal_tr_out[TRCAL_SIZE-1] <= #1 chiptdi;
            trcal_tr_out[TRCAL_SIZE-2:0] <= #1 trcal_tr_out[TRCAL_SIZE-1:1];
        end
        if (extest_sel & capture_dr_i) begin
            trcal_tr_out <= #1 trcal_tr_in; // Read out the current state to be shifted to the JTAG
        end
    end
end

always @(negedge tclk or posedge test_logic_reset_i) begin
    if (test_logic_reset_i) begin
        bs_chain_tdi_o <= #1 1'b0;
    end else if (extest_sel) begin
        bs_chain_tdi_o <= #1 trcal_tr_out[0];
    end else if (sample_preload_sel) begin
        bs_chain_tdi_o <= #1 tcr_shift[0];
    end
end

// -----------------------------------------------------------------------------
// TCR Shift/Capture/Update Logic (SAMPLE_PRELOAD)
// -----------------------------------------------------------------------------
// Handles JTAG shifting, capture, and update for the TCR. Only updates tcr
// (the latched config) on UPDATE_DR. Registers shifting IN are clocked on the POSEDGE.

always @(posedge tclk or posedge test_logic_reset_i) begin
    if (test_logic_reset_i) begin
        tcr <= #1 {CONRLEN{1'b0}}; // Default state. If JTAG is not powered, use PU/PD resistors at mux for default state.
        tcr_shift <= #1 ~tcr;
    end else begin
        // SAMPLE PRELOAD CAPTURE/UPDATE EXAMPLE
        if (sample_preload_sel & shift_dr_i) begin
            tcr_shift[CONRLEN-1] <= #1 chiptdi;
            tcr_shift[CONRLEN-2:0] <= #1 tcr_shift[CONRLEN-1:1];
        end
        if (sample_preload_sel & capture_dr_i) begin
            tcr_shift <= #1 tcr; // Read out the current state to be shifted to the JTAG
        end
        if (sample_preload_sel & update_dr_i) begin
            // Only update tcr if MSB (bit 31) is set (write operation)
            // On read (MSB == 0), tcr is not updated and remains unchanged
            if (tcr_shift[CONRLEN-1])
                tcr <= #1 {1'b0, tcr_shift[CONRLEN-2:0]}; // Mask out MSB so it does not affect mux logic
            // else: do nothing (read operation)
        end
    end
end

assign tcr_out = tcr;

endmodule