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

// A second top module by design (the OpenLane macro); top.v is the board top.
/* verilator lint_off MULTITOP */
module tensorrail_asic_top #(
/* verilator lint_on MULTITOP */
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

    // ── Boundary registers ─────────────────────────────────────────────────────
    // Every input is registered at the macro edge, so each timing path inside
    // starts at a flop instead of at a port whose arrival time depends on the
    // surrounding chip. All inputs shift by the same one cycle, so the array's
    // behaviour is unchanged; act_ready follows the registered flush.
    reg [DATA_WIDTH-1:0]      weight_data_q;
    reg [$clog2(COLS)-1:0]    weight_col_sel_q;
    reg                       weight_load_en_q;
    reg [ROWS*DATA_WIDTH-1:0] act_row_in_q;
    reg                       act_valid_q;
    reg                       flush_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_data_q    <= {DATA_WIDTH{1'b0}};
            weight_col_sel_q <= {$clog2(COLS){1'b0}};
            weight_load_en_q <= 1'b0;
            act_row_in_q     <= {(ROWS*DATA_WIDTH){1'b0}};
            act_valid_q      <= 1'b0;
            flush_q          <= 1'b0;
        end else begin
            weight_data_q    <= weight_data;
            weight_col_sel_q <= weight_col_sel;
            weight_load_en_q <= weight_load_en;
            act_row_in_q     <= act_row_in;
            act_valid_q      <= act_valid;
            flush_q          <= flush;
        end
    end

    systolic_array #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_array (
        .clk(clk),
        .rst_n(rst_n),
        .weight_data(weight_data_q),
        .weight_col_sel(weight_col_sel_q),
        .weight_load_en(weight_load_en_q),
        .act_row_in(act_row_in_q),
        .act_valid(act_valid_q),
        .act_ready(act_ready),
        .psum_col_out(psum_col_out),
        .psum_valid(psum_valid),
        .flush(flush_q)
    );

endmodule

`default_nettype wire
