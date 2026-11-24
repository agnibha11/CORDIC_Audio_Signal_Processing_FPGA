`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
// ============================================================================
module tb_sd_dac;
    localparam integer DIV = 16;
    reg clk = 0, rst = 1;
    reg signed [15:0] sample = 0;
    always #5 clk = ~clk;
    wire b;
    sd_dac #(.DIV(DIV)) dut (.clk(clk), .rst(rst), .sample(sample), .bit_out(b));

    integer checks = 0, errors = 0;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; if (errors <= 20) $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    integer ones, k, n, lvl, exp1;
    integer levels [0:8];
    real t, acc_b, acc_s, worst;
    realtime t_edge, t_prev, min_gap;
    always @(b) begin t_prev = t_edge; t_edge = $realtime; if (t_prev > 0 && (t_edge - t_prev) < min_gap) min_gap = t_edge - t_prev; end

    initial begin
        min_gap = 1.0e9; t_edge = 0;
        levels[0] = -32768; levels[1] = -32767; levels[2] = -16384; levels[3] = -1; levels[4] = 0;
        levels[5] = 1; levels[6] = 12345; levels[7] = 16384; levels[8] = 32767;
        repeat (4) @(negedge clk); rst = 0;
        for (lvl = 0; lvl < 9; lvl = lvl + 1) begin
            sample = levels[lvl];
            repeat (DIV * 4) @(negedge clk);
            ones = 0;
            for (k = 0; k < 65536; k = k + 1) begin repeat (DIV) @(negedge clk); ones = ones + b; end
            exp1 = levels[lvl] + 32768;
            check(ones >= exp1 - 1 && ones <= exp1 + 1, "ones density = (sample + 32768) / 65536");
            $display("sample %6d : %5d ones in 65536 bits (expected %5d)", levels[lvl], ones, exp1);
        end
        check(min_gap >= DIV * 10.0 - 0.01, "bit period = DIV clocks");
        // sine tracking: 1 kHz, amplitude 20000, sample held for 20 us like the real 50 kS/s source
        worst = 0.0;
        for (n = 0; n < 20; n = n + 1) begin        // 20 windows of 0.1 ms (5 samples); compare window averages
            acc_b = 0; acc_s = 0;
            for (k = 0; k < 5; k = k + 1) begin
                t = (n * 5 + k) * 20.0e-6;
                sample = $rtoi(20000.0 * $sin(2.0 * 3.14159265358979 * 1000.0 * t));
                acc_s = acc_s + sample;
                repeat (125) begin repeat (DIV) @(negedge clk); acc_b = acc_b + b; end
            end
            // window average of the bit stream, mapped back to Q15
            t = (acc_b / 625.0) * 65536.0 - 32768.0 - acc_s / 5.0;
            if (t < 0) t = -t;
            if (t > worst) worst = t;
        end
        $display("1 kHz sine: worst window-average error = %0.0f LSB (%0.2f %% of full scale)", worst, worst / 327.68);
        check(worst < 328.0, "bit-stream average follows a 1 kHz sine within 1 %");
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
