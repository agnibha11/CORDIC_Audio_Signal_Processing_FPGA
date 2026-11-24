`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
// ============================================================================
module tb_kypd_scanner;
    localparam integer SCAN = 64, DEB = 4, RPT_D = 40, RPT_R = 10;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    wire [3:0] col, row;
    reg  [15:0] pressed = 0;
    wire key_valid, key_down;
    wire [3:0] key_code;

    kypd_scanner #(.SCAN_CLKS(SCAN), .DEBOUNCE_SCANS(DEB), .REPEAT_DELAY(RPT_D), .REPEAT_RATE(RPT_R)) dut (
        .clk(clk), .rst(rst), .row(row), .col(col), .key_valid(key_valid), .key_code(key_code), .key_down(key_down)
    );
    model_kypd #(.SETTLE_NS(100)) kp (.col(col), .row(row), .pressed(pressed));

    integer checks = 0, errors = 0, nvalid = 0;
    reg [3:0] last_code;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end end
    endtask
    always @(posedge clk) if (key_valid) begin nvalid = nvalid + 1; last_code = key_code; end

    function [3:0] cap; input integer r, c;
        begin
            case (r) 0: cap = (c==0)?4'h1:(c==1)?4'h2:(c==2)?4'h3:4'hA;
                     1: cap = (c==0)?4'h4:(c==1)?4'h5:(c==2)?4'h6:4'hB;
                     2: cap = (c==0)?4'h7:(c==1)?4'h8:(c==2)?4'h9:4'hC;
                     default: cap = (c==0)?4'h0:(c==1)?4'hF:(c==2)?4'hE:4'hD; endcase
        end
    endfunction

    integer r, c, n0, scans;
    initial begin
        repeat (3) @(negedge clk); rst = 0;
        for (r = 0; r < 4; r = r + 1) for (c = 0; c < 4; c = c + 1) begin
            n0 = nvalid;
            pressed = 16'd1 << (r*4 + c);
            repeat ((DEB + 3) * 4 * SCAN + 1000) @(negedge clk);
            check(nvalid == n0 + 1, "exactly one key_valid per press");
            check(last_code == cap(r, c), "key code");
            check(key_down, "key_down while held");
            pressed = 0;
            repeat ((DEB + 3) * 4 * SCAN + 1000) @(negedge clk);
            check(!key_down, "key_down cleared after release");
        end
        // bounce: press for 1 scan, release 1 scan, repeated -> never stable -> no key_valid
        n0 = nvalid;
        repeat (6) begin pressed = 16'h0001; repeat (4*SCAN) @(negedge clk); pressed = 0; repeat (4*SCAN) @(negedge clk); end
        repeat ((DEB + 3) * 4 * SCAN) @(negedge clk);
        check(nvalid == n0, "bouncing contact rejected");
        // auto-repeat: hold key '5' for RPT_D + 3*RPT_R scans after acceptance
        n0 = nvalid;
        pressed = 16'd1 << (1*4 + 1);
        repeat ((DEB + 2) * 4 * SCAN + 1000) @(negedge clk);
        check(nvalid == n0 + 1, "initial press");
        repeat ((RPT_D + 2 * RPT_R + RPT_R / 2) * 4 * SCAN) @(negedge clk);
        check(nvalid == n0 + 4, "three auto-repeats");
        check(last_code == 4'h5, "repeat code");
        pressed = 0;
        repeat ((DEB + 3) * 4 * SCAN + 1000) @(negedge clk);
        // chord: two keys at once -> ignored
        n0 = nvalid;
        pressed = 16'h0003;
        repeat ((DEB + 3) * 4 * SCAN + 1000) @(negedge clk);
        check(nvalid == n0, "chord ignored");
        check(!key_down, "no key_down for chord");
        pressed = 0;
        repeat ((DEB + 3) * 4 * SCAN) @(negedge clk);
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
