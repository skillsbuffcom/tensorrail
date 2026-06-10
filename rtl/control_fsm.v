// =============================================================================
// control_fsm.v — Tile Orchestrator and CSR Register File
// TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept
//
// State machine:
//
//   IDLE ──(start)──► LOAD_W ──(all cols loaded)──► COMPUTE
//                                                       │
//                                                  (all rows fed)
//                                                       ▼
//                                                     DRAIN ──(psum_valid)──► DONE
//                                                                               │
//                                                                           (auto)──► IDLE
//
// CSR register map (word-addressed, 32-bit, read/write via simple bus):
//
//   0x00  CTRL   [0]   start     W1S — write 1 to begin a tile computation
//                [1]   sw_reset  W1S — soft reset (returns to IDLE)
//   0x04  STATUS [0]   busy      RO  — asserted while not in IDLE/DONE
//                [1]   done      RO  — pulses for one cycle when tile finishes
//                [5:3] state_dbg RO  — current FSM state for JTAG debug
//   0x08  TILE_M [15:0] rows     RW  — activation rows per tile (≤ ROWS)
//   0x0C  TILE_N [15:0] cols     RW  — weight / output cols per tile (≤ COLS)
//   0x10  TILE_K [15:0] k        RW  — inner dimension (weight shift cycles per col)
//
// Weight loading:
//   The FSM issues weight_load_en for TILE_K cycles per column, iterating
//   across all TILE_N columns.  weight_data is driven from a small internal
//   shift register (preloaded via CSR write in the simulation stub; in a real
//   design this would come from a DMA / external-memory read engine).
//
// Simulation note:
//   The DMA read stub drives weight_data and act_row_in from constants.
//   Replace with real memory-read logic when integrating with top.v.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module control_fsm #(
    parameter ROWS       = 4,
    parameter COLS       = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Simple CSR bus (word address, 32-bit data)
    input  wire [4:0]            csr_addr,
    input  wire [31:0]           csr_wdata,
    input  wire                  csr_wen,
    output reg  [31:0]           csr_rdata,

    // Systolic array control
    output reg  [DATA_WIDTH-1:0]      weight_data,
    output reg  [$clog2(COLS)-1:0]    weight_col_sel,
    output reg                        weight_load_en,

    output reg  [ROWS*DATA_WIDTH-1:0] act_row_in,
    output reg                        act_valid,
    input  wire                       act_ready,

    input  wire [COLS*ACC_WIDTH-1:0]  psum_col_out,
    input  wire                       psum_valid,
    output reg                        flush,

    output wire                       busy,
    output wire                       done_pulse
);

    // ── FSM states ─────────────────────────────────────────────────────────────
    localparam [2:0]
        S_IDLE    = 3'd0,
        S_LOAD_W  = 3'd1,
        S_COMPUTE = 3'd2,
        S_DRAIN   = 3'd3,
        S_DONE    = 3'd4;

    reg [2:0] state;

    // ── CSR registers ──────────────────────────────────────────────────────────
    reg        csr_start;
    reg        csr_sw_reset;
    reg [15:0] csr_tile_m;   // Activation rows
    reg [15:0] csr_tile_n;   // Weight / output columns
    reg [15:0] csr_tile_k;   // Inner dimension (K)
    reg        csr_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_start    <= 1'b0;
            csr_sw_reset <= 1'b0;
            csr_tile_m   <= ROWS;
            csr_tile_n   <= COLS;
            csr_tile_k   <= COLS;   // Default: square tile
        end else begin
            csr_start    <= 1'b0;   // Auto-clear after one cycle
            csr_sw_reset <= 1'b0;
            if (csr_wen) begin
                case (csr_addr)
                    5'h00: begin
                        csr_start    <= csr_wdata[0];
                        csr_sw_reset <= csr_wdata[1];
                    end
                    5'h02: csr_tile_m <= csr_wdata[15:0];
                    5'h03: csr_tile_n <= csr_wdata[15:0];
                    5'h04: csr_tile_k <= csr_wdata[15:0];
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (csr_addr)
            5'h00: csr_rdata = {29'b0, state};
            5'h01: csr_rdata = {26'b0, csr_done, (state != S_IDLE && state != S_DONE), state};
            5'h02: csr_rdata = {16'b0, csr_tile_m};
            5'h03: csr_rdata = {16'b0, csr_tile_n};
            5'h04: csr_rdata = {16'b0, csr_tile_k};
            default: csr_rdata = 32'hDEAD_BEEF;
        endcase
    end

    // ── Counters ───────────────────────────────────────────────────────────────
    reg [15:0] row_cnt;   // Activation rows injected so far
    reg [15:0] col_cnt;   // Weight columns loaded so far
    reg [15:0] k_cnt;     // Weight shifts within current column

    // ── FSM ────────────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || csr_sw_reset) begin
            state          <= S_IDLE;
            row_cnt        <= 16'b0;
            col_cnt        <= 16'b0;
            k_cnt          <= 16'b0;
            weight_data    <= {DATA_WIDTH{1'b0}};
            weight_col_sel <= {$clog2(COLS){1'b0}};
            weight_load_en <= 1'b0;
            act_row_in     <= {(ROWS*DATA_WIDTH){1'b0}};
            act_valid      <= 1'b0;
            flush          <= 1'b0;
            csr_done       <= 1'b0;
        end else begin
            // Defaults — asserted for one cycle only unless held below
            weight_load_en <= 1'b0;
            act_valid      <= 1'b0;
            flush          <= 1'b0;
            csr_done       <= 1'b0;

            case (state)
                // ── Wait for host to write CTRL[0]=1 ────────────────────────
                S_IDLE: begin
                    row_cnt <= 16'b0;
                    col_cnt <= 16'b0;
                    k_cnt   <= 16'b0;
                    if (csr_start)
                        state <= S_LOAD_W;
                end

                // ── Load weights column by column ────────────────────────────
                // Drives weight_load_en for csr_tile_k cycles per column.
                // In this stub, weight_data is the column index (for testing).
                // Replace with external-memory DMA reads in top.v.
                S_LOAD_W: begin
                    weight_load_en <= 1'b1;
                    weight_col_sel <= col_cnt[$clog2(COLS)-1:0];
                    weight_data    <= col_cnt[DATA_WIDTH-1:0];  // Stub data

                    if (k_cnt == csr_tile_k - 1) begin
                        k_cnt <= 16'b0;
                        if (col_cnt == csr_tile_n - 1) begin
                            col_cnt <= 16'b0;
                            state   <= S_COMPUTE;
                        end else begin
                            col_cnt <= col_cnt + 1;
                        end
                    end else begin
                        k_cnt <= k_cnt + 1;
                    end
                end

                // ── Stream activation rows ────────────────────────────────────
                // Injects csr_tile_m activation rows, one per cycle (when ready).
                // Stub: fills the activation vector with the row index value.
                S_COMPUTE: begin
                    if (act_ready) begin
                        act_valid  <= 1'b1;
                        // Stub: fill all lanes with row_cnt low byte
                        act_row_in <= {ROWS{row_cnt[DATA_WIDTH-1:0]}};
                        if (row_cnt == csr_tile_m - 1) begin
                            row_cnt <= 16'b0;
                            state   <= S_DRAIN;
                        end else begin
                            row_cnt <= row_cnt + 1;
                        end
                    end
                end

                // ── Flush and wait for psum_valid ─────────────────────────────
                S_DRAIN: begin
                    flush <= 1'b1;
                    if (psum_valid)
                        state <= S_DONE;
                end

                // ── Signal completion, return to IDLE ─────────────────────────
                S_DONE: begin
                    csr_done <= 1'b1;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy       = (state != S_IDLE) && (state != S_DONE);
    assign done_pulse = csr_done;

endmodule

`default_nettype wire
