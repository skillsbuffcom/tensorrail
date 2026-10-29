// =============================================================================
// tb_asic_top.v — the OpenLane macro behaves like the bare array, one cycle late
//
// Drives systolic_array and tensorrail_asic_top with the same random stimulus
// (weight loads, activations, flushes) and checks the macro's outputs equal the
// array's from one cycle earlier: its boundary registers add latency, nothing else.
//
// Run: iverilog -g2012 -o tb_asic_top.vvp rtl/sim/tb_asic_top.v \
//        rtl/tensorrail_asic_top.v rtl/systolic_array.v rtl/mac_cell.v && vvp tb_asic_top.vvp
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_asic_top;
    localparam ROWS = 4, COLS = 4, DW = 8, AW = 32;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    reg [DW-1:0]        weight_data;
    reg [1:0]           weight_col_sel;
    reg                 weight_load_en;
    reg [ROWS*DW-1:0]   act_row_in;
    reg                 act_valid;
    reg                 flush;

    wire                ref_ready, dut_ready, ref_valid, dut_valid;
    wire [COLS*AW-1:0]  ref_psum, dut_psum;

    systolic_array #(.ROWS(ROWS), .COLS(COLS), .DATA_WIDTH(DW), .ACC_WIDTH(AW)) ref_array (
        .clk(clk), .rst_n(rst_n),
        .weight_data(weight_data), .weight_col_sel(weight_col_sel), .weight_load_en(weight_load_en),
        .act_row_in(act_row_in), .act_valid(act_valid), .act_ready(ref_ready),
        .psum_col_out(ref_psum), .psum_valid(ref_valid), .flush(flush)
    );

    tensorrail_asic_top #(.ROWS(ROWS), .COLS(COLS), .DATA_WIDTH(DW), .ACC_WIDTH(AW)) dut (
        .clk(clk), .rst_n(rst_n),
        .weight_data(weight_data), .weight_col_sel(weight_col_sel), .weight_load_en(weight_load_en),
        .act_row_in(act_row_in), .act_valid(act_valid), .act_ready(dut_ready),
        .flush(flush), .psum_col_out(dut_psum), .psum_valid(dut_valid)
    );

    // The array's outputs one cycle ago
    reg [COLS*AW-1:0] ref_psum_d;
    reg               ref_valid_d, ref_ready_d;
    always @(posedge clk) begin
        ref_psum_d  <= ref_psum;
        ref_valid_d <= ref_valid;
        ref_ready_d <= ref_ready;
    end

    integer cycle, errors = 0, tiles = 0;
    initial begin
        $dumpfile("tb_asic_top.vcd");
        $dumpvars(0, tb_asic_top);
        {weight_data, weight_col_sel, weight_load_en, act_row_in, act_valid, flush} = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        for (cycle = 0; cycle < 4000; cycle = cycle + 1) begin
            @(negedge clk);
            // Compare after the previous edge, once both pipelines are primed.
            if (cycle > 2) begin
                if (dut_psum !== ref_psum_d || dut_valid !== ref_valid_d || dut_ready !== ref_ready_d) begin
                    if (errors < 5) $display("FAIL: cycle %0d dut %h/%b ref %h/%b", cycle, dut_psum, dut_valid, ref_psum_d, ref_valid_d);
                    errors = errors + 1;
                end
                if (dut_valid) tiles = tiles + 1;
            end
            weight_data    = $random;
            weight_col_sel = $random;
            weight_load_en = ($random % 4) == 0;
            act_row_in     = {$random, $random};
            act_valid      = ($random % 2) == 0;
            flush          = ($random % 23) == 0;
        end

        if (tiles == 0) begin $display("FAIL: no flush reached the outputs"); errors = errors + 1; end
        else $display("PASS: %0d tiles matched the bare array, one cycle later", tiles);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule

`default_nettype wire
