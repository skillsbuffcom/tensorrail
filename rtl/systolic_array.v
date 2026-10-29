// =============================================================================
// systolic_array.v — N×N INT8 Weight-Stationary Column MAC Array
// TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept
//
// Architecture: weight-stationary column MAC array.
//
//   ┌──────────────────────────────────────────────────┐
//   │           weight_data → (serial shift-in)        │
//   │                  ↓  ↓  ↓  ↓                     │
//   │  act[0] → [0,0]─[0,1]─[0,2]─[0,3]               │
//   │  act[1] → [1,0]─[1,1]─[1,2]─[1,3]               │
//   │  act[2] → [2,0]─[2,1]─[2,2]─[2,3]               │
//   │  act[3] → [3,0]─[3,1]─[3,2]─[3,3]               │
//   │             ↓    ↓    ↓    ↓                     │
//   │           psum[0..3]  (available after ROWS cyc) │
//   └──────────────────────────────────────────────────┘
//
// Weight loading:
//   Assert weight_load_en for ROWS consecutive cycles per column.
//   Set weight_col_sel to the target column index.
//   weight_data is shifted serially into the column's weight registers
//   from row 0 (top) to row ROWS-1 (bottom).
//
// Compute:
//   Assert act_valid and present act_row_in (all ROWS activations packed).
//   Each column computes one dot product against its stationary weight vector
//   and accumulates across consecutive act_valid cycles until flush.
//
// Flush:
//   Assert flush for one cycle.  The accumulated column sums are captured on
//   psum_col_out and psum_valid pulses for one cycle.  Internal accumulators
//   are cleared for the next tile.
//
// Parameters:
//   ROWS        Number of rows (= output rows per tile).   Default 4.
//   COLS        Number of columns (= output cols per tile). Default 4.
//   DATA_WIDTH  Operand width.  Default 8 (INT8).
//   ACC_WIDTH   Accumulator width.  Default 32 (INT32).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module systolic_array #(
    parameter ROWS       = 4,
    parameter COLS       = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                            clk,
    input  wire                            rst_n,

    // Weight loading (serial per column)
    input  wire [DATA_WIDTH-1:0]           weight_data,
    input  wire [$clog2(COLS)-1:0]         weight_col_sel,
    input  wire                            weight_load_en,

    // Activation streaming
    input  wire [ROWS*DATA_WIDTH-1:0]      act_row_in,
    input  wire                            act_valid,
    output wire                            act_ready,   // Low while draining

    // Partial sum output (one column per cycle after drain)
    output wire [COLS*ACC_WIDTH-1:0]       psum_col_out,
    output wire                            psum_valid,

    // Flush: start drain sequence
    input  wire                            flush
);

    // ── Weight registers ───────────────────────────────────────────────────────
    // weight_reg[c][r]: weight at column c, row r.
    // Loaded serially: row 0 first, row ROWS-1 last.  New data enters at the
    // bottom of the shift chain so the final register order matches the input
    // order used by the testbench and golden model.
    reg [DATA_WIDTH-1:0] weight_reg [0:COLS-1][0:ROWS-1];

    integer lc, lr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (lc = 0; lc < COLS; lc = lc + 1)
                for (lr = 0; lr < ROWS; lr = lr + 1)
                    weight_reg[lc][lr] <= {DATA_WIDTH{1'b0}};
        end else if (weight_load_en) begin
            // Shift column toward row 0; new value enters at row ROWS-1.
            // After ROWS cycles, the first value loaded resides at row 0.
            for (lr = 0; lr < ROWS-1; lr = lr + 1)
                weight_reg[weight_col_sel][lr] <= weight_reg[weight_col_sel][lr+1];
            weight_reg[weight_col_sel][ROWS-1] <= weight_data;
        end
    end

    // ── Column dot products and accumulators (two pipeline stages) ─────────────
    // Stage 1 registers each column's dot product for the cycle's activations:
    //   dot[c] = sum_r signed(act[r]) * signed(weight[c][r])
    // Stage 2 adds it into the column accumulator. Splitting the multiply/add
    // tree from the 32-bit accumulate is what lets the ASIC macro meet 50 MHz.
    // A flush folds a product still in stage 1 into the latched sum, so flush
    // and psum_valid keep their one-cycle timing.
    localparam DOT_WIDTH = DATA_WIDTH * 2 + $clog2(ROWS);

    reg signed [ACC_WIDTH-1:0] accum [0:COLS-1];
    reg signed [DOT_WIDTH-1:0] dot   [0:COLS-1];
    reg                        dot_valid;
    reg [COLS*ACC_WIDTH-1:0] psum_latch;
    reg                      psum_valid_r;
    reg signed [DOT_WIDTH-1:0] next_dot;

    function signed [DOT_WIDTH-1:0] mac_product_ext;
        input [DATA_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] b;
        reg signed [DATA_WIDTH-1:0] a_s;
        reg signed [DATA_WIDTH-1:0] b_s;
        reg signed [DATA_WIDTH*2-1:0] prod_s;
        begin
            a_s = a;
            b_s = b;
            prod_s = a_s * b_s;
            mac_product_ext = {{(DOT_WIDTH - DATA_WIDTH*2){prod_s[DATA_WIDTH*2-1]}}, prod_s};
        end
    endfunction

    function signed [ACC_WIDTH-1:0] dot_ext;
        input signed [DOT_WIDTH-1:0] d;
        dot_ext = {{(ACC_WIDTH - DOT_WIDTH){d[DOT_WIDTH-1]}}, d};
    endfunction

    // Stage 1: dot products
    integer ar, ac;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dot_valid <= 1'b0;
            for (ac = 0; ac < COLS; ac = ac + 1)
                dot[ac] <= {DOT_WIDTH{1'b0}};
        end else begin
            // As before the pipeline, activations arriving with flush are not counted.
            dot_valid <= act_valid && !flush;
            if (act_valid && !flush) begin
                // next_dot is a per-column scratch sum, never a register:
                // blocking assignment is intended here.
                /* verilator lint_off BLKSEQ */
                for (ac = 0; ac < COLS; ac = ac + 1) begin
                    next_dot = {DOT_WIDTH{1'b0}};
                    for (ar = 0; ar < ROWS; ar = ar + 1)
                        next_dot = next_dot + mac_product_ext(
                            act_row_in[ar*DATA_WIDTH +: DATA_WIDTH],
                            weight_reg[ac][ar]
                        );
                    dot[ac] <= next_dot;
                    /* verilator lint_on BLKSEQ */
                end
            end
        end
    end

    // Stage 2: accumulate, latch on flush
    integer fc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_latch   <= {(COLS*ACC_WIDTH){1'b0}};
            psum_valid_r <= 1'b0;
            for (fc = 0; fc < COLS; fc = fc + 1)
                accum[fc] <= {ACC_WIDTH{1'b0}};
        end else if (flush) begin
            for (fc = 0; fc < COLS; fc = fc + 1) begin
                psum_latch[fc*ACC_WIDTH +: ACC_WIDTH] <= dot_valid ? accum[fc] + dot_ext(dot[fc]) : accum[fc];
                accum[fc] <= {ACC_WIDTH{1'b0}};
            end
            psum_valid_r <= 1'b1;
        end else begin
            psum_valid_r <= 1'b0;
            if (dot_valid)
                for (fc = 0; fc < COLS; fc = fc + 1)
                    accum[fc] <= accum[fc] + dot_ext(dot[fc]);
        end
    end

    assign psum_col_out = psum_latch;
    assign psum_valid   = psum_valid_r;
    assign act_ready    = ~flush;

endmodule

`default_nettype wire
