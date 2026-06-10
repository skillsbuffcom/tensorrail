// =============================================================================
// tb_systolic_array.v — Self-Checking Testbench for systolic_array.v
// TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept
//
// Tests a 4×4 INT8 weight-stationary systolic array against four deterministic
// test vectors that match simulation/golden_model.py exactly (bitwise).
//
// Run with Icarus Verilog:
//   cd rtl/sim
//   iverilog -g2012 -o tb_sa \
//       ../mac_cell.v ../systolic_array.v \
//       tb_systolic_array.v
//   vvp tb_sa
//
// VCD is written to rtl/sim/tensorrail_tb.vcd (relative to working directory).
//
// Expected console output:
//
//   === TEST 1: Identity weight matrix ===
//   Expected  col[0]=         1  col[1]=         2  col[2]=         3  col[3]=         4
//   Actual    col[0]=         1  col[1]=         2  col[2]=         3  col[3]=         4
//   [PASS] Test 1
//
//   === TEST 2: All-ones weight matrix ===
//   Expected  col[0]=         8  col[1]=         8  col[2]=         8  col[3]=         8
//   Actual    col[0]=         8  col[1]=         8  col[2]=         8  col[3]=         8
//   [PASS] Test 2
//
//   === TEST 3: Signed negative weights ===
//   Expected  col[0]=FFFFFFF4  col[1]=FFFFFFF4  col[2]=FFFFFFF4  col[3]=FFFFFFF4
//   Actual    col[0]=FFFFFFF4  col[1]=FFFFFFF4  col[2]=FFFFFFF4  col[3]=FFFFFFF4
//   [PASS] Test 3
//
//   === TEST 4: Max INT8 values ===
//   Expected  col[0]=     FC04  col[1]=     FC04  col[2]=     FC04  col[3]=     FC04
//   Actual    col[0]=     FC04  col[1]=     FC04  col[2]=     FC04  col[3]=     FC04
//   [PASS] Test 4
//
//   === All 4 tests passed ===
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_systolic_array;

    // ── Parameters ─────────────────────────────────────────────────────────────
    localparam ROWS       = 4;
    localparam COLS       = 4;
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 32;
    localparam CLK_HALF   = 5;          // 10 ns period → 100 MHz sim clock

    // ── DUT signals ────────────────────────────────────────────────────────────
    reg                            clk;
    reg                            rst_n;
    reg  [DATA_WIDTH-1:0]          weight_data;
    reg  [$clog2(COLS)-1:0]        weight_col_sel;
    reg                            weight_load_en;
    reg  [ROWS*DATA_WIDTH-1:0]     act_row_in;
    reg                            act_valid;
    wire                           act_ready;
    wire [COLS*ACC_WIDTH-1:0]      psum_col_out;
    wire                           psum_valid;
    reg                            flush;

    // ── DUT instantiation ──────────────────────────────────────────────────────
    systolic_array #(
        .ROWS      (ROWS),
        .COLS      (COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .weight_data    (weight_data),
        .weight_col_sel (weight_col_sel),
        .weight_load_en (weight_load_en),
        .act_row_in     (act_row_in),
        .act_valid      (act_valid),
        .act_ready      (act_ready),
        .psum_col_out   (psum_col_out),
        .psum_valid     (psum_valid),
        .flush          (flush)
    );

    // ── Clock ──────────────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always  #CLK_HALF clk = ~clk;

    // ── Pass/fail counter ──────────────────────────────────────────────────────
    integer pass_cnt;
    integer fail_cnt;

    // ── Task: hard reset ───────────────────────────────────────────────────────
    task do_reset;
        begin
            rst_n          = 1'b0;
            weight_data    = {DATA_WIDTH{1'b0}};
            weight_col_sel = {$clog2(COLS){1'b0}};
            weight_load_en = 1'b0;
            act_row_in     = {(ROWS*DATA_WIDTH){1'b0}};
            act_valid      = 1'b0;
            flush          = 1'b0;
            repeat(4) @(posedge clk);
            @(negedge clk);   // change rst_n away from clock edge
            rst_n = 1'b1;
            repeat(2) @(posedge clk);
        end
    endtask

    // ── Task: load one weight column ──────────────────────────────────────────
    // weights[r*DW +: DW] → weight for row r of the chosen column.
    // Serial shift-in: row 0 first, row ROWS-1 last (matches systolic_array.v).
    task load_column;
        input [$clog2(COLS)-1:0]    col;
        input [ROWS*DATA_WIDTH-1:0] weights;
        integer r;
        begin
            for (r = 0; r < ROWS; r = r + 1) begin
                @(posedge clk);
                weight_col_sel <= col;
                weight_data    <= weights[r*DATA_WIDTH +: DATA_WIDTH];
                weight_load_en <= 1'b1;
            end
            @(posedge clk);
            weight_load_en <= 1'b0;
        end
    endtask

    // ── Task: inject one activation row ───────────────────────────────────────
    // act[r*DW +: DW] → activation value for row r.
    // Waits for act_ready to avoid injecting during a drain.
    task inject_act;
        input [ROWS*DATA_WIDTH-1:0] act;
        begin
            @(posedge clk);
            while (!act_ready) @(posedge clk);
            act_row_in <= act;
            act_valid  <= 1'b1;
            @(posedge clk);
            act_valid  <= 1'b0;
        end
    endtask

    // ── Task: flush, wait for psum_valid, print and check result ──────────────
    // Always prints both expected and actual columns regardless of pass/fail,
    // so differences are immediately visible in the simulation log.
    integer timeout_cnt;
    task drain_check;
        input [COLS*ACC_WIDTH-1:0] expected;
        input integer              test_id;
        integer c;
        reg    match;
        begin
            // Assert flush for one cycle to start drain
            @(posedge clk); flush <= 1'b1;
            @(posedge clk); flush <= 1'b0;

            // Wait up to ROWS+8 cycles for psum_valid
            timeout_cnt = 0;
            while (!psum_valid && timeout_cnt < (ROWS + 8)) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            if (!psum_valid) begin
                $display("[FAIL] Test %0d: psum_valid never asserted (timeout after %0d cycles)",
                         test_id, timeout_cnt);
                fail_cnt = fail_cnt + 1;
                disable drain_check;
            end

            // ── Print expected ─────────────────────────────────────────────────
            $write("  Expected");
            for (c = 0; c < COLS; c = c + 1)
                $write("  col[%0d]=%08X", c, expected[c*ACC_WIDTH +: ACC_WIDTH]);
            $write("\n");

            // ── Print actual ───────────────────────────────────────────────────
            $write("  Actual  ");
            for (c = 0; c < COLS; c = c + 1)
                $write("  col[%0d]=%08X", c, psum_col_out[c*ACC_WIDTH +: ACC_WIDTH]);
            $write("\n");

            // ── Compare ────────────────────────────────────────────────────────
            match = (psum_col_out === expected);
            if (match) begin
                $display("  [PASS] Test %0d", test_id);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] Test %0d: mismatch on column(s):", test_id);
                for (c = 0; c < COLS; c = c + 1) begin
                    if (psum_col_out[c*ACC_WIDTH +: ACC_WIDTH] !==
                        expected    [c*ACC_WIDTH +: ACC_WIDTH])
                        $display("    col[%0d]  got=%08X  exp=%08X",
                            c,
                            psum_col_out[c*ACC_WIDTH +: ACC_WIDTH],
                            expected    [c*ACC_WIDTH +: ACC_WIDTH]);
                end
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ── Test variables ─────────────────────────────────────────────────────────
    integer i, j;
    reg [ROWS*DATA_WIDTH-1:0] col_weights;
    reg [ROWS*DATA_WIDTH-1:0] act_vec;
    reg [COLS*ACC_WIDTH-1:0]  expected_psum;

    // ── Main test sequence ─────────────────────────────────────────────────────
    initial begin : test_main
        // VCD: written to rtl/sim/tensorrail_tb.vcd when vvp is run from rtl/sim/
        $dumpfile("tensorrail_tb.vcd");
        $dumpvars(0, tb_systolic_array);

        pass_cnt = 0;
        fail_cnt = 0;

        // ──────────────────────────────────────────────────────────────────────
        // TEST 1 — Identity weight matrix
        //
        // Weight matrix W (column-major):
        //   col 0: [1, 0, 0, 0]   col 1: [0, 1, 0, 0]
        //   col 2: [0, 0, 1, 0]   col 3: [0, 0, 0, 1]
        //
        // Activation row A = [1, 2, 3, 4]  (one row fed into ROWS=4 lanes)
        //
        // psum[c] = sum_r( W[c][r] * A[r] ) = A[c]
        // Expected: [1, 2, 3, 4]
        // ──────────────────────────────────────────────────────────────────────
        $display("\n=== TEST 1: Identity weight matrix ===");
        do_reset;

        for (j = 0; j < COLS; j = j + 1) begin
            col_weights = {(ROWS*DATA_WIDTH){1'b0}};
            col_weights[j*DATA_WIDTH +: DATA_WIDTH] = 8'h01;   // Only row j = 1
            load_column(j[($clog2(COLS)-1):0], col_weights);
        end

        act_vec = {(ROWS*DATA_WIDTH){1'b0}};
        for (i = 0; i < ROWS; i = i + 1)
            act_vec[i*DATA_WIDTH +: DATA_WIDTH] = i[DATA_WIDTH-1:0] + 8'd1; // 1,2,3,4

        inject_act(act_vec);

        expected_psum = {(COLS*ACC_WIDTH){1'b0}};
        for (j = 0; j < COLS; j = j + 1)
            expected_psum[j*ACC_WIDTH +: ACC_WIDTH] = j + 1;   // 1,2,3,4

        drain_check(expected_psum, 1);
        repeat(4) @(posedge clk);

        // ──────────────────────────────────────────────────────────────────────
        // TEST 2 — All-ones weight matrix
        //
        // W = 1 everywhere.  A = all 2s.
        // psum[c] = sum_r( 1 * 2 ) = 2 * ROWS = 8  for all c.
        // Expected: [8, 8, 8, 8]
        // ──────────────────────────────────────────────────────────────────────
        $display("\n=== TEST 2: All-ones weight matrix ===");
        do_reset;

        col_weights = {ROWS{8'h01}};
        for (j = 0; j < COLS; j = j + 1)
            load_column(j[($clog2(COLS)-1):0], col_weights);

        act_vec = {ROWS{8'h02}};
        inject_act(act_vec);

        expected_psum = {(COLS*ACC_WIDTH){1'b0}};
        for (j = 0; j < COLS; j = j + 1)
            expected_psum[j*ACC_WIDTH +: ACC_WIDTH] = 32'd8;

        drain_check(expected_psum, 2);
        repeat(4) @(posedge clk);

        // ──────────────────────────────────────────────────────────────────────
        // TEST 3 — Signed negative weights
        //
        // W = −1 (8'hFF in 2's-complement INT8) everywhere.  A = +3 everywhere.
        // psum[c] = sum_r( (-1) * 3 ) = -3 * ROWS = -12
        // -12 in 32-bit 2's-complement = 32'hFFFFFFF4
        // Expected: [0xFFFFFFF4, 0xFFFFFFF4, 0xFFFFFFF4, 0xFFFFFFF4]
        // ──────────────────────────────────────────────────────────────────────
        $display("\n=== TEST 3: Signed negative weights ===");
        do_reset;

        col_weights = {ROWS{8'hFF}};       // -1 as INT8
        for (j = 0; j < COLS; j = j + 1)
            load_column(j[($clog2(COLS)-1):0], col_weights);

        act_vec = {ROWS{8'h03}};           // +3
        inject_act(act_vec);

        expected_psum = {(COLS*ACC_WIDTH){1'b0}};
        for (j = 0; j < COLS; j = j + 1)
            expected_psum[j*ACC_WIDTH +: ACC_WIDTH] = 32'hFFFFFFF4;  // -12

        drain_check(expected_psum, 3);
        repeat(4) @(posedge clk);

        // ──────────────────────────────────────────────────────────────────────
        // TEST 4 — Maximum INT8 values (overflow check)
        //
        // W = +127 (8'h7F) everywhere.  A = +127 everywhere.
        // Per cell: 127 * 127 = 16129
        // psum[c] = 16129 * ROWS = 16129 * 4 = 64516 = 32'h0000FC04
        // Max possible with ROWS=4: fits comfortably in INT32 (max ~2.1e9).
        // Expected: [64516, 64516, 64516, 64516]
        // ──────────────────────────────────────────────────────────────────────
        $display("\n=== TEST 4: Max INT8 values ===");
        do_reset;

        col_weights = {ROWS{8'h7F}};       // +127
        for (j = 0; j < COLS; j = j + 1)
            load_column(j[($clog2(COLS)-1):0], col_weights);

        act_vec = {ROWS{8'h7F}};           // +127
        inject_act(act_vec);

        expected_psum = {(COLS*ACC_WIDTH){1'b0}};
        for (j = 0; j < COLS; j = j + 1)
            expected_psum[j*ACC_WIDTH +: ACC_WIDTH] = 32'd64516;    // 0x0000FC04

        drain_check(expected_psum, 4);
        repeat(8) @(posedge clk);

        // ── Summary ────────────────────────────────────────────────────────────
        $display("");
        if (fail_cnt == 0)
            $display("=== All %0d tests passed ===", pass_cnt);
        else
            $display("=== %0d/%0d tests FAILED — see above ===",
                     fail_cnt, pass_cnt + fail_cnt);

        $finish;
    end

    // ── Watchdog: abort if sim runs more than 10 000 cycles ───────────────────
    initial begin
        #(CLK_HALF * 2 * 10_000);
        $display("[TIMEOUT] Simulation exceeded 10 000 cycles — aborting");
        $finish;
    end

endmodule

`default_nettype wire
