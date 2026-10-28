// =============================================================================
// top.v — TensorRail-Mini Top-Level (ECP5 Target)
// TensorRail-Mini · ECP5 Carrier Board Proof-of-Concept
//
// Target: Lattice ECP5 LFE5U-85F (OrangeCrab 85F Feather module)
// Toolchain: Yosys + nextpnr-ecp5 + ecppack (open-source)
//
// External I/O (mapped to carrier board Feather header pins):
//
//   clk_in          Pin from FPGA module oscillator (48 MHz internal osc on
//                   OrangeCrab; adjust PLL multiplier for desired frequency)
//   rst_n           Active-low reset from carrier RESET_N pin (J3 pin 3)
//
//   uart_tx         UART transmit → external 3.3 V USB-UART adapter
//   uart_rx         UART receive  ← external 3.3 V USB-UART adapter
//
//   psram0_cs_n     Future memory chip select / expansion SPI CS
//   psram0_sck      Future memory SPI clock
//   psram0_si       Future memory MOSI
//   psram0_so       Future memory MISO
//
//   psram1_cs_n     Future second memory chip select / expansion SPI CS
//   psram1_sck      Future second memory SPI clock
//   psram1_si       Future second memory MOSI
//   psram1_so       Future second memory MISO
//
//   led[3:0]        Status LEDs D2–D5 on carrier (FPGA_GPIO12–15 / J3 pins 4–7)
//                   led[0] = power-on (always 1 after reset)
//                   led[1] = busy (systolic array is computing)
//                   led[2] = done (pulses when tile finishes)
//                   led[3] = heartbeat (~1 Hz toggle)
//
// Clock plan:
//   The OrangeCrab 85F provides a 48 MHz oscillator.  The ECP5 EHXPLLL PLL
//   generates 24 MHz for UART timing and 48 MHz (pass-through) for the
//   systolic array.  For a real design targeting higher throughput, raise the
//   core to 100–200 MHz by adjusting CLKFB_DIV / CLKI_DIV / CLKOP_DIV.
//
// External memory interface (stub):
//   This top-level includes a minimal SPI bit-bang controller to demonstrate
//   the interface.  In a production design replace with an ECP5 LSRC/JTAG
//   macro or a proper SPI master with FIFO.
//
// UART status port (115200 8N1):
//   Sends a one-line ASCII status message after each tile computation:
//   "TILE_DONE psum[0]=XXXXXXXX ... psum[3]=XXXXXXXX\r\n"
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tensorrail_top (
    input  wire        clk_in,       // 48 MHz from ECP5 module oscillator
    input  wire        rst_n,        // Active-low reset (carrier J3 pin 3)

    // UART (to external 3.3 V USB-UART adapter)
    output wire        uart_tx,
    input  wire        uart_rx,      // Not used in this stub

    // Future memory 0 — weight buffer (SPI stub)
    output wire        psram0_cs_n,
    output wire        psram0_sck,
    output wire        psram0_si,
    input  wire        psram0_so,

    // Future memory 1 — activation buffer (SPI stub)
    output wire        psram1_cs_n,
    output wire        psram1_sck,
    output wire        psram1_si,
    input  wire        psram1_so,

    // Status LEDs on carrier board
    output wire [3:0]  led
);

    // ── Parameters ─────────────────────────────────────────────────────────────
    localparam ROWS       = 4;
    localparam COLS       = 4;
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = 32;

    // ── Clock and reset ────────────────────────────────────────────────────────
    // Pass clk_in straight through (48 MHz).  Insert EHXPLLL here for higher
    // frequencies.  Reset is synchronised with a two-stage shift register.
    wire clk = clk_in;

    reg [1:0] rst_sync_sr;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rst_sync_sr <= 2'b00;
        else        rst_sync_sr <= {rst_sync_sr[0], 1'b1};

    wire rst_sync_n = rst_sync_sr[1];

    // ── Systolic array ─────────────────────────────────────────────────────────
    wire [DATA_WIDTH-1:0]         weight_data;
    wire [$clog2(COLS)-1:0]       weight_col_sel;
    wire                          weight_load_en;
    wire [ROWS*DATA_WIDTH-1:0]    act_row_in;
    wire                          act_valid;
    wire                          act_ready;
    wire [COLS*ACC_WIDTH-1:0]     psum_col_out;
    wire                          psum_valid;
    wire                          flush;

    systolic_array #(
        .ROWS(ROWS), .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) u_array (
        .clk            (clk),
        .rst_n          (rst_sync_n),
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

    // ── Control FSM ────────────────────────────────────────────────────────────
    // Auto-start: write CTRL[0]=1 one cycle after reset deasserts.
    wire        busy, done_pulse;
    wire [4:0]  csr_addr;
    wire [31:0] csr_wdata;
    wire        csr_wen;
    wire [31:0] csr_rdata;

    // One-shot start: pulse csr_wen with start bit set two cycles after reset
    reg [2:0] start_sr;
    always @(posedge clk or negedge rst_sync_n)
        if (!rst_sync_n) start_sr <= 3'b000;
        else             start_sr <= {start_sr[1:0], 1'b1};

    assign csr_wen   = (start_sr == 3'b011);  // Rising edge of sync'd reset release
    assign csr_addr  = 5'h00;
    assign csr_wdata = 32'h1;                 // CTRL[0] = start

    control_fsm #(
        .ROWS(ROWS), .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) u_ctrl (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .csr_addr       (csr_addr),
        .csr_wdata      (csr_wdata),
        .csr_wen        (csr_wen),
        .csr_rdata      (csr_rdata),
        .weight_data    (weight_data),
        .weight_col_sel (weight_col_sel),
        .weight_load_en (weight_load_en),
        .act_row_in     (act_row_in),
        .act_valid      (act_valid),
        .act_ready      (act_ready),
        .psum_col_out   (psum_col_out),
        .psum_valid     (psum_valid),
        .flush          (flush),
        .busy           (busy),
        .done_pulse     (done_pulse)
    );

    // ── Result latch ──────────────────────────────────────────────────────────
    // psum_valid pulses for one cycle as the array drains; hold the four column
    // sums for the UART report.
    reg [COLS*ACC_WIDTH-1:0] psum_latched;
    always @(posedge clk or negedge rst_sync_n)
        if (!rst_sync_n)     psum_latched <= {(COLS*ACC_WIDTH){1'b0}};
        else if (psum_valid) psum_latched <= psum_col_out;

    // ── UART status report (115200 baud, 8N1) ────────────────────────────────
    // After each tile: "TILE_DONE psum[0]=XXXXXXXX psum[1]=... psum[3]=XXXXXXXX\r\n"
    // (79 bytes, hex, most significant nibble first).
    localparam BAUD_DIV = 48_000_000 / 115_200;  // = 417 counts
    localparam MSG_LEN  = 9 + COLS * 17 + 2;     // "TILE_DONE" + 4 × " psum[n]=XXXXXXXX" + CRLF

    function [7:0] hex_digit(input [3:0] n);
        hex_digit = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});  // '0'-'9', 'A'-'F'
    endfunction

    // Byte i of the report for the latched sums p.
    function [7:0] msg_byte(input [6:0] i, input [COLS*ACC_WIDTH-1:0] p);
        reg [6:0]  j;
        reg [6:0]  g;
        reg [6:0]  k;
        reg [31:0] w;
        begin
            if (i < 7'd9) begin
                case (i)
                    7'd0: msg_byte = "T"; 7'd1: msg_byte = "I"; 7'd2: msg_byte = "L";
                    7'd3: msg_byte = "E"; 7'd4: msg_byte = "_"; 7'd5: msg_byte = "D";
                    7'd6: msg_byte = "O"; 7'd7: msg_byte = "N"; default: msg_byte = "E";
                endcase
            end else if (i == MSG_LEN - 2) begin
                msg_byte = 8'h0D;
            end else if (i == MSG_LEN - 1) begin
                msg_byte = 8'h0A;
            end else begin
                j = i - 7'd9;
                g = j / 7'd17;            // which column sum
                k = j % 7'd17;            // position within " psum[n]=XXXXXXXX"
                w = p >> (g * ACC_WIDTH);
                case (k)
                    7'd0: msg_byte = " ";
                    7'd1: msg_byte = "p";
                    7'd2: msg_byte = "s";
                    7'd3: msg_byte = "u";
                    7'd4: msg_byte = "m";
                    7'd5: msg_byte = "[";
                    7'd6: msg_byte = 8'h30 + {1'b0, g};
                    7'd7: msg_byte = "]";
                    7'd8: msg_byte = "=";
                    default: msg_byte = hex_digit(w[31 - 4 * (k - 9) -: 4]);
                endcase
            end
        end
    endfunction

    reg [$clog2(BAUD_DIV+1):0] baud_cnt;
    reg [9:0]  tx_shift;    // {stop, data[7:0], start}
    reg [3:0]  tx_bits;     // Remaining bits of the current byte
    reg        tx_active;   // Sending the report
    reg [6:0]  msg_idx;     // Byte of the report being sent

    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            baud_cnt  <= 0;
            tx_shift  <= 10'h3FF;
            tx_bits   <= 4'd0;
            tx_active <= 1'b0;
            msg_idx   <= 7'd0;
        end else begin
            if (done_pulse && !tx_active) begin
                // Start bit, first byte, stop bit
                tx_shift  <= {1'b1, msg_byte(7'd0, psum_latched), 1'b0};
                tx_bits   <= 4'd10;
                tx_active <= 1'b1;
                msg_idx   <= 7'd0;
                baud_cnt  <= 0;
            end else if (tx_active) begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    if (tx_bits == 1) begin
                        // Byte done: next byte, or stop after the line feed.
                        if (msg_idx == MSG_LEN - 1) begin
                            tx_active <= 1'b0;
                            tx_shift  <= 10'h3FF;
                        end else begin
                            msg_idx  <= msg_idx + 7'd1;
                            tx_shift <= {1'b1, msg_byte(msg_idx + 7'd1, psum_latched), 1'b0};
                            tx_bits  <= 4'd10;
                        end
                    end else begin
                        tx_shift <= {1'b1, tx_shift[9:1]};  // LSB first
                        tx_bits  <= tx_bits - 1;
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end
        end
    end

    assign uart_tx = tx_active ? tx_shift[0] : 1'b1;

    // ── External-memory stubs (held idle) ─────────────────────────────────────
    // Both future memory interfaces are deselected.  A real design would have a SPI master here
    // to load weights and activations before each tile computation.
    assign psram0_cs_n = 1'b1;
    assign psram0_sck  = 1'b0;
    assign psram0_si   = 1'b0;

    assign psram1_cs_n = 1'b1;
    assign psram1_sck  = 1'b0;
    assign psram1_si   = 1'b0;

    // ── Status LEDs ────────────────────────────────────────────────────────────
    reg [25:0] hb_cnt;
    always @(posedge clk or negedge rst_sync_n)
        if (!rst_sync_n) hb_cnt <= 26'b0;
        else             hb_cnt <= hb_cnt + 1;

    // led[3] toggles at 48MHz / 2^26 ≈ 0.71 Hz (close enough to "~1 Hz")
    assign led[0] = rst_sync_n;        // On once reset is released
    assign led[1] = busy;
    assign led[2] = done_pulse;        // Pulses for one cycle — persistence from eye
    assign led[3] = hb_cnt[25];

endmodule

`default_nettype wire
