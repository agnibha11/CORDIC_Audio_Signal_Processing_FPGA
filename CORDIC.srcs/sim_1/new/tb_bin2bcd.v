`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_bin2bcd.v -- serial binary-to-BCD converter: every 8-bit value and 2000
//  random 20-bit values against the simulator's own / and % operators;
//  conversion time = W clocks.
// ============================================================================
module tb_bin2bcd;
    reg clk = 0, rst = 1, st8 = 0, st20 = 0;
    reg [7:0]  b8 = 0;
    reg [19:0] b20 = 0;
    always #5 clk = ~clk;
    wire [11:0] d8;
    wire [23:0] d20;
    bin2bcd #(.W(8),  .D(3)) u8  (.clk(clk), .rst(rst), .start(st8),  .bin(b8),  .bcd(d8));
    bin2bcd #(.W(20), .D(6)) u20 (.clk(clk), .rst(rst), .start(st20), .bin(b20), .bcd(d20));

    integer checks = 0, errors = 0, k, v;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; if (errors <= 20) $display("FAIL @%0t: %0s", $time, msg); end end
    endtask
    function [23:0] dec; input integer val;              // decimal digits by / and %
        integer i, t;
        begin
            t = val; dec = 24'd0;
            for (i = 0; i < 6; i = i + 1) begin dec[4*i +: 4] = t % 10; t = t / 10; end
        end
    endfunction
    initial begin
        repeat (4) @(negedge clk); rst = 0;
        for (k = 0; k < 256; k = k + 1) begin
            b8 = k; @(negedge clk); st8 = 1; @(negedge clk); st8 = 0; b8 = ~k;      // input may change after start
            repeat (8) @(negedge clk);
            check(d8 == dec(k), "8-bit value");
        end
        for (k = 0; k < 2000; k = k + 1) begin
            v = (k == 0) ? 0 : (k == 1) ? 999999 : (k == 2) ? 317500 : ($random & 20'hFFFFF) % 1000000;
            b20 = v; @(negedge clk); st20 = 1; @(negedge clk); st20 = 0;
            repeat (20) @(negedge clk);
            check(d20 == dec(v), "20-bit value");
        end
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
