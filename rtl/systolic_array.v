// =============================================================================
// systolic_array.v — N×N INT8 Weight-Stationary Systolic Array
// TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept
//
// Architecture: weight-stationary.
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
//   Assert act_valid and present act_row_in (all ROWS activations packed)
//   for each input row.  Activations ripple east; partial sums drain south.
//
// Drain:
//   Assert flush; partial sums at the south edge become valid after ROWS
//   additional clock cycles.  psum_valid pulses for one cycle.
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
    // Loaded serially: each weight_load_en cycle shifts new data into row 0
    // and pushes prior values down.
    reg [DATA_WIDTH-1:0] weight_reg [0:COLS-1][0:ROWS-1];

    integer lc, lr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (lc = 0; lc < COLS; lc = lc + 1)
                for (lr = 0; lr < ROWS; lr = lr + 1)
                    weight_reg[lc][lr] <= {DATA_WIDTH{1'b0}};
        end else if (weight_load_en) begin
            // Shift column down; new value enters at row 0
            for (lr = ROWS-1; lr > 0; lr = lr - 1)
                weight_reg[weight_col_sel][lr] <= weight_reg[weight_col_sel][lr-1];
            weight_reg[weight_col_sel][0] <= weight_data;
        end
    end

    // ── Activation and partial-sum wires ──────────────────────────────────────
    // a_wire[r][c]:   activation entering cell (r,c) from the west
    //                 a_wire[r][0] = external input; a_wire[r][COLS] = discarded
    // p_wire[r][c]:   partial sum entering cell (r,c) from the north
    //                 p_wire[0][c] = 0 (seed); p_wire[ROWS][c] = final accumulation
    wire [DATA_WIDTH-1:0] a_wire [0:ROWS-1][0:COLS];
    wire [ACC_WIDTH-1:0]  p_wire [0:ROWS][0:COLS-1];

    // Drive west boundary from packed activation input
    genvar ra;
    generate
        for (ra = 0; ra < ROWS; ra = ra + 1) begin : act_in_boundary
            assign a_wire[ra][0] = act_valid
                ? act_row_in[ra*DATA_WIDTH +: DATA_WIDTH]
                : {DATA_WIDTH{1'b0}};
        end
    endgenerate

    // Seed partial sums at north boundary with zero
    genvar ca;
    generate
        for (ca = 0; ca < COLS; ca = ca + 1) begin : psum_seed
            assign p_wire[0][ca] = {ACC_WIDTH{1'b0}};
        end
    endgenerate

    // ── MAC cell array ─────────────────────────────────────────────────────────
    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : row_gen
            for (c = 0; c < COLS; c = c + 1) begin : col_gen
                // b_wire: the weight for cell (r,c).
                // Weight is stationary — taken directly from weight_reg[c][r].
                // We declare a local wire to avoid multi-drive on the b_out port.
                wire [DATA_WIDTH-1:0] b_pass_unused;

                mac_cell #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) u_mac (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .en     (act_valid),
                    .a_in   (a_wire[r][c]),
                    .a_out  (a_wire[r][c+1]),   // Passes activation east
                    .b_in   (weight_reg[c][r]), // Stationary weight for this cell
                    .acc_in (p_wire[r][c]),
                    .acc_out(p_wire[r+1][c])    // Partial sum flows south
                );
            end
        end
    endgenerate

    // ── Drain logic ────────────────────────────────────────────────────────────
    // After flush is asserted, wait ROWS cycles for the last partial sum to
    // reach the south edge, then latch and pulse psum_valid.
    localparam DRAIN_CYCLES = ROWS;

    reg [$clog2(DRAIN_CYCLES+2):0] drain_cnt;
    reg draining;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drain_cnt <= 0;
            draining  <= 1'b0;
        end else begin
            if (flush && !draining) begin
                draining  <= 1'b1;
                drain_cnt <= DRAIN_CYCLES;
            end
            if (draining) begin
                if (drain_cnt == 0)
                    draining <= 1'b0;
                else
                    drain_cnt <= drain_cnt - 1;
            end
        end
    end

    // Latch psum_col_out on the last drain cycle
    reg [COLS*ACC_WIDTH-1:0] psum_latch;
    reg                      psum_valid_r;

    integer lcc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_latch   <= {(COLS*ACC_WIDTH){1'b0}};
            psum_valid_r <= 1'b0;
        end else if (draining && drain_cnt == 1) begin
            // Capture the south-edge partial sums
            for (lcc = 0; lcc < COLS; lcc = lcc + 1)
                psum_latch[lcc*ACC_WIDTH +: ACC_WIDTH] <= p_wire[ROWS][lcc];
            psum_valid_r <= 1'b1;
        end else begin
            psum_valid_r <= 1'b0;
        end
    end

    assign psum_col_out = psum_latch;
    assign psum_valid   = psum_valid_r;
    assign act_ready    = ~draining;   // Block new activations during drain

endmodule

`default_nettype wire
