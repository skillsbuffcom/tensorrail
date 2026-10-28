// =============================================================================
// tb_top.v — TensorRail-Mini top level: the UART status report
//
// Releases reset, lets the auto-started tile finish, decodes the UART line and
// checks it is "TILE_DONE psum[0]=XXXXXXXX ... psum[3]=XXXXXXXX\r\n" carrying
// the sums the array produced.
//
// Run: iverilog -g2012 -o tb_top.vvp rtl/sim/tb_top.v rtl/top.v rtl/control_fsm.v \
//        rtl/systolic_array.v rtl/mac_cell.v && vvp tb_top.vvp
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_top;
    localparam BAUD_DIV = 48_000_000 / 115_200;  // matches top.v
    localparam MSG_LEN  = 79;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    wire uart_tx;
    wire [3:0] led;
    wire psram0_cs_n, psram0_sck, psram0_si, psram1_cs_n, psram1_sck, psram1_si;

    tensorrail_top dut (
        .clk_in(clk), .rst_n(rst_n),
        .uart_tx(uart_tx), .uart_rx(1'b1),
        .psram0_cs_n(psram0_cs_n), .psram0_sck(psram0_sck), .psram0_si(psram0_si), .psram0_so(1'b0),
        .psram1_cs_n(psram1_cs_n), .psram1_sck(psram1_sck), .psram1_si(psram1_si), .psram1_so(1'b0),
        .led(led)
    );

    reg [7:0] line [0:MSG_LEN-1];
    integer n = 0;
    integer errors = 0;
    integer i;

    // 8N1 receiver: wait for a start bit, sample each bit mid-period.
    task automatic receive_byte(output [7:0] b);
        integer bit_i;
        begin
            @(negedge uart_tx);
            repeat (BAUD_DIV / 2) @(posedge clk);
            if (uart_tx !== 1'b0) begin $display("FAIL: framing (start bit)"); errors = errors + 1; end
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                repeat (BAUD_DIV) @(posedge clk);
                b[bit_i] = uart_tx;
            end
            repeat (BAUD_DIV) @(posedge clk);
            if (uart_tx !== 1'b1) begin $display("FAIL: framing (stop bit)"); errors = errors + 1; end
        end
    endtask

    function [7:0] hex_digit(input [3:0] v);
        hex_digit = (v < 10) ? (8'h30 + v) : (8'h37 + v);
    endfunction

    reg [7:0] b;
    reg [8*MSG_LEN-1:0] text;
    reg [31:0] word;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        fork
            begin
                for (n = 0; n < MSG_LEN; n = n + 1) begin
                    receive_byte(b);
                    line[n] = b;
                end
            end
            begin
                #20_000_000;
                $display("FAIL: timeout after %0d bytes", n);
                $finish;
            end
        join_any
        disable fork;

        for (i = 0; i < MSG_LEN; i = i + 1) text = {text[8*MSG_LEN-9:0], line[i]};
        $display("UART: %s", text[8*MSG_LEN-1:16]);

        if (text[8*MSG_LEN-1 -: 8*18] !== "TILE_DONE psum[0]=") begin $display("FAIL: prefix"); errors = errors + 1; end
        if (line[MSG_LEN-2] !== 8'h0D || line[MSG_LEN-1] !== 8'h0A) begin $display("FAIL: no CRLF"); errors = errors + 1; end
        else $display("PASS: line ends in CRLF");

        // Each reported sum matches what the array produced.
        for (i = 0; i < 4; i = i + 1) begin : check_sum
            integer k;
            reg ok;
            word = dut.psum_latched[i*32 +: 32];
            ok = (line[9 + i*17 + 6] == (8'h30 + i));
            for (k = 0; k < 8; k = k + 1)
                if (line[9 + i*17 + 9 + k] !== hex_digit(word[31 - 4*k -: 4])) ok = 1'b0;
            // control_fsm's stub loads weight c into column c and feeds rows 0..3,
            // each row's activations all equal to the row index: 4 rows × (0+1+2+3) × c.
            if (word !== 24 * i) begin
                $display("FAIL: psum[%0d] = %0d, expected %0d", i, word, 24 * i);
                ok = 1'b0;
            end
            if (ok) $display("PASS: psum[%0d] = %08h", i, word);
            else begin $display("FAIL: psum[%0d] report doesn't match %08h", i, word); errors = errors + 1; end
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule

`default_nettype wire
