// =============================================================================
// mac_cell.v — Single INT8 Multiply-Accumulate Cell
// TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept
//
// Computes one element of a weight-stationary systolic array:
//
//   acc_out <= acc_in + signed(a_in) * signed(b_in)
//
// Data movement:
//   Activations (A) : west → east  (registered, one hop per cycle)
//   Weights     (B) : stationary — loaded once, held during tile compute
//   Partial sums    : north → south (accumulated and passed down)
//
// Arithmetic:
//   INT8 × INT8 → 16-bit signed product, sign-extended to ACC_WIDTH before add.
//   No overflow is possible for K ≤ 127 accumulations: 127×127×127 = 2,048,383
//   which comfortably fits in INT32.  For larger K the caller must use a wider
//   accumulator or tile the K dimension.
//
// Synthesis target: Lattice ECP5 (MULT18X18D DSP tile).
//   One ECP5 DSP tile handles one 18×18 → 36-bit multiply, so one DSP per MAC
//   cell.  A 4×4 array uses 16 DSPs out of 56 available on LFE5U-25F (29%).
//
// Parameters:
//   DATA_WIDTH  Width of A and B operands in bits.  Default 8 (INT8).
//   ACC_WIDTH   Width of the accumulator in bits.   Default 32 (INT32).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module mac_cell #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  en,          // Pipeline enable / valid

    // Activation path — flows west to east
    input  wire [DATA_WIDTH-1:0] a_in,
    output reg  [DATA_WIDTH-1:0] a_out,

    // Weight — stationary; driven from weight_reg in systolic_array.v
    input  wire [DATA_WIDTH-1:0] b_in,

    // Partial sum path — flows north to south
    input  wire [ACC_WIDTH-1:0]  acc_in,
    output reg  [ACC_WIDTH-1:0]  acc_out
);

    // Sign-extended product: INT8 × INT8 → 16 bits, then zero-/sign-padded to ACC_WIDTH
    wire signed [DATA_WIDTH*2-1:0] product;
    assign product = $signed(a_in) * $signed(b_in);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out   <= {DATA_WIDTH{1'b0}};
            acc_out <= {ACC_WIDTH{1'b0}};
        end else if (en) begin
            a_out   <= a_in;
            // Sign-extend product from 2*DATA_WIDTH to ACC_WIDTH before accumulating
            acc_out <= acc_in + {{(ACC_WIDTH - DATA_WIDTH*2){product[DATA_WIDTH*2-1]}}, product};
        end
    end

endmodule

`default_nettype wire
