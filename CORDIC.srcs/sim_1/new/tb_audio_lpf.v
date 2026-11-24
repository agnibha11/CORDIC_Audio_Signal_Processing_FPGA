`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Hridayesh Kundu
//  Last Updated : 24 November 2026
// ============================================================================
module tb_audio_lpf;
    reg clk = 0, rst = 1, en = 0;
    reg signed [19:0] x = 0;
    always #5 clk = ~clk;
    wire valid;
    wire signed [15:0] y;
    audio_lpf #(.IN_W(20)) dut (.clk(clk), .rst(rst), .en(en), .x(x), .valid(valid), .y(y));

    integer checks = 0, errors = 0;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; if (errors <= 20) $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    integer taps [0:12];
    integer tmp  [0:12];
    integer hist [0:12];
    integer i, j, k, lat, acc, exp_y, tsum;

    task push; input signed [19:0] v;
        begin
            for (i = 12; i > 0; i = i - 1) hist[i] = hist[i-1];
            hist[0] = v;
            x = v;
            @(negedge clk); en = 1; @(negedge clk); en = 0;
            lat = 1;
            while (!valid) begin @(negedge clk); lat = lat + 1; end
            acc = 0;
            for (i = 0; i < 13; i = i + 1) acc = acc + taps[i] * hist[i];
            exp_y = (acc + 128) >>> 8;
            if (exp_y > 32767) exp_y = 32767; if (exp_y < -32768) exp_y = -32768;
        end
    endtask

    initial begin
        // taps = (1,1,1,1) convolved four times
        for (i = 0; i < 13; i = i + 1) taps[i] = (i == 0) ? 1 : 0;
        for (k = 0; k < 4; k = k + 1) begin
            for (i = 0; i < 13; i = i + 1) begin
                tmp[i] = 0;
                for (j = 0; j < 4; j = j + 1) if (i - j >= 0) tmp[i] = tmp[i] + taps[i-j];
            end
            for (i = 0; i < 13; i = i + 1) taps[i] = tmp[i];
        end
        tsum = 0; for (i = 0; i < 13; i = i + 1) tsum = tsum + taps[i];
        check(tsum == 256, "tap sum = 256");
        for (i = 0; i < 13; i = i + 1) begin hist[i] = 0; check(taps[i] == taps[12-i], "taps symmetric (linear phase)"); end
        $display("impulse response: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                 taps[0], taps[1], taps[2], taps[3], taps[4], taps[5], taps[6], taps[7], taps[8], taps[9], taps[10], taps[11], taps[12]);
        repeat (4) @(negedge clk); rst = 0;
        // 1. impulse of height 256 -> output = taps
        push(20'sd256); check(y == taps[0], "impulse response tap 0"); check(lat == 5, "latency 5 clocks");
        for (k = 1; k < 16; k = k + 1) begin push(20'sd0); check(y == ((k < 13) ? taps[k] : 0), "impulse response"); end
        // 2. random data, bit-exact
        for (k = 0; k < 3000; k = k + 1) begin
            if (k % 500 < 20)      push(20'sd524287);
            else if (k % 500 < 40) push(-20'sd524288);
            else                   push($random);
            check(y == exp_y, "bit-exact vs 13-tap convolution");
        end
        check(y == exp_y, "last");
        // 3. DC gain 1 and null at Fs/4
        for (k = 0; k < 20; k = k + 1) push(20'sd12345);
        check(y == 16'sd12345, "DC gain exactly 1");
        for (k = 0; k < 40; k = k + 1) begin
            case (k % 4) 0: push(20'sd20000); 1: push(20'sd0); 2: push(-20'sd20000); default: push(20'sd0); endcase
            if (k > 16) check(y == 0, "12.5 kHz (Fs/4) is nulled");
        end
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
