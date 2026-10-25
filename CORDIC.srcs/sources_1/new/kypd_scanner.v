`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  kypd_scanner.v -- Pmod KYPD 4x4 matrix keypad scanner with debounce and
//                    auto-repeat
//
//  Electrical (Pmod KYPD reference manual): rows have on-board pull-ups; the
//  host drives ONE column low at a time and reads the rows -- a low row
//  means the key at (row, column) is pressed.
//
//  Physical layout (COL1 is the left column, ROW1 the top row):
//        COL1 COL2 COL3 COL4
//  ROW1   1    2    3    A
//  ROW2   4    5    6    B
//  ROW3   7    8    9    C
//  ROW4   0    F    E    D
//
//  Scan: each column is driven for SCAN_CLKS clocks (82 us) and the rows are
//  sampled at the end of that window, so a full 4-column scan takes 328 us.
//  A key image must be identical for DEBOUNCE_SCANS consecutive scans before
//  it is accepted (5.2 ms).  A single new key produces one `key_valid` pulse;
//  holding it for REPEAT_DELAY scans (~0.5 s) produces repeats every
//  REPEAT_RATE scans (~0.1 s).  Chords (two keys) are ignored.
// ============================================================================
module kypd_scanner #(
    parameter integer SCAN_CLKS      = 8192,
    parameter integer DEBOUNCE_SCANS = 16,
    parameter integer REPEAT_DELAY   = 1500,
    parameter integer REPEAT_RATE    = 300
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] row,          // row[0] = ROW1 ... row[3] = ROW4 (synchronised, active low)
    output reg  [3:0] col,          // col[0] = COL1 ... col[3] = COL4 (active low drive)
    output reg        key_valid,    // one-cycle pulse per accepted press / repeat
    output reg  [3:0] key_code,     // 0x0..0xF as printed on the key cap
    output reg        key_down      // level: a single key is currently held
);
    // key cap value for (row r, column c)
    function [3:0] keymap;
        input [1:0] r;
        input [1:0] c;
        begin
            case ({r, c})
                4'b00_00: keymap = 4'h1; 4'b00_01: keymap = 4'h2; 4'b00_10: keymap = 4'h3; 4'b00_11: keymap = 4'hA;
                4'b01_00: keymap = 4'h4; 4'b01_01: keymap = 4'h5; 4'b01_10: keymap = 4'h6; 4'b01_11: keymap = 4'hB;
                4'b10_00: keymap = 4'h7; 4'b10_01: keymap = 4'h8; 4'b10_10: keymap = 4'h9; 4'b10_11: keymap = 4'hC;
                default : begin
                    case (c)
                        2'd0: keymap = 4'h0; 2'd1: keymap = 4'hF; 2'd2: keymap = 4'hE; default: keymap = 4'hD;
                    endcase
                end
            endcase
        end
    endfunction

    // one-hot test and encode of the 16-bit key image (bit = c*4 + r)
    function onehot;
        input [15:0] v;
        begin
            onehot = (v != 16'd0) && ((v & (v - 16'd1)) == 16'd0);
        end
    endfunction

    function [3:0] enc16;
        input [15:0] v;
        integer k;
        begin
            enc16 = 4'd0;
            for (k = 0; k < 16; k = k + 1)
                if (v[k]) enc16 = k[3:0];
        end
    endfunction

    reg [13:0] tick;
    reg [1:0]  cidx;
    reg [15:0] raw, raw_prev, stable;
    reg [7:0]  same_cnt;
    reg [11:0] held_cnt;
    reg        scan_done;

    wire [3:0]  idx_now   = enc16(stable);
    wire [3:0]  idx_raw   = enc16(raw);
    wire [3:0]  code_now  = keymap(idx_now[1:0], idx_now[3:2]);

    always @(posedge clk) begin
        key_valid <= 1'b0;
        scan_done <= 1'b0;
        if (rst) begin
            tick     <= 14'd0;
            cidx     <= 2'd0;
            col      <= 4'b1110;
            raw      <= 16'd0;
            raw_prev <= 16'd0;
            stable   <= 16'd0;
            same_cnt <= 8'd0;
            held_cnt <= 12'd0;
            key_code <= 4'd0;
            key_down <= 1'b0;
        end else begin
            // ---------------- column walk ----------------
            if (tick == SCAN_CLKS - 1) begin
                tick <= 14'd0;
                raw[cidx*4 +: 4] <= ~row;             // pressed keys read low
                cidx <= cidx + 2'd1;
                case (cidx)                            // drive the NEXT column low
                    2'd0: col <= 4'b1101;
                    2'd1: col <= 4'b1011;
                    2'd2: col <= 4'b0111;
                    default: begin col <= 4'b1110; scan_done <= 1'b1; end
                endcase
            end else begin
                tick <= tick + 14'd1;
            end

            // ---------------- debounce (once per full scan) ----------------
            if (scan_done) begin
                raw_prev <= raw;
                if (raw == raw_prev) begin
                    if (same_cnt != 8'hFF) same_cnt <= same_cnt + 8'd1;
                end else begin
                    same_cnt <= 8'd0;
                end

                if ((raw == raw_prev) && (same_cnt >= DEBOUNCE_SCANS - 1) && (raw != stable)) begin
                    // accepted new key image
                    stable   <= raw;
                    held_cnt <= 12'd0;
                    if (onehot(raw)) begin
                        key_valid <= 1'b1;
                        key_code  <= keymap(idx_raw[1:0], idx_raw[3:2]);
                        key_down  <= 1'b1;
                    end else begin
                        key_down  <= 1'b0;
                    end
                end else if (onehot(stable) && (raw == stable)) begin
                    // key held: auto-repeat
                    if (held_cnt == REPEAT_DELAY - 1) begin
                        key_valid <= 1'b1;
                        key_code  <= code_now;
                        held_cnt  <= REPEAT_DELAY - REPEAT_RATE;
                    end else begin
                        held_cnt <= held_cnt + 12'd1;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
