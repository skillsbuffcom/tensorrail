// =============================================================================
// tensorrail_asic_top.v — ASIC-oriented wrapper for the TensorRail MAC array
//
// This is the clean physical-design top used by the OpenLane flow.  The FPGA
// board top in rtl/top.v includes UART, PSRAM stubs, and board-level concerns;
// this wrapper exposes only the compute-array interface that should become a
// small sky130 macro.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tensorrail_asic_top #(
    parameter ROWS       = 4,
    parameter COLS       = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire [DATA_WIDTH-1:0]           weight_data,
    input  wire [$clog2(COLS)-1:0]         weight_col_sel,
    input  wire                            weight_load_en,

    input  wire [ROWS*DATA_WIDTH-1:0]      act_row_in,
    input  wire                            act_valid,
    output wire                            act_ready,

    input  wire                            flush,
    output wire [COLS*ACC_WIDTH-1:0]       psum_col_out,
    output wire                            psum_valid
);

    systolic_array #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_array (
        .clk(clk),
        .rst_n(rst_n),
        .weight_data(weight_data),
        .weight_col_sel(weight_col_sel),
        .weight_load_en(weight_load_en),
        .act_row_in(act_row_in),
        .act_valid(act_valid),
        .act_ready(act_ready),
        .psum_col_out(psum_col_out),
        .psum_valid(psum_valid),
        .flush(flush)
    );

endmodule

`default_nettype wire
