`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Hridayesh Kundu
//  Last Updated : 24 November 2026
// ============================================================================
module tb_awgn_gen;
    reg clk = 0, rst = 1, start = 0;
    reg [4:0] noise_idx = 0;
    always #5 clk = ~clk;
    wire done;
    wire signed [18:0] ni, nq;
    awgn_gen dut (.clk(clk), .rst(rst), .start(start), .noise_idx(noise_idx), .done(done), .ni(ni), .nq(nq));

    integer checks = 0, errors = 0;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; if (errors <= 20) $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    reg [31:0] vec [0:448*3-1];
    localparam integer LAT = 28;      // 1 (start) + 12 + 12 (sums) + 3 (scaling)
    integer k, lat, n_in;
    real s1, s2, sq, sxy, mean_i, sig_i, sig_q, rho, maxabs;

    task one; input [4:0] idx;
        begin
            noise_idx = idx;
            @(negedge clk); start = 1; @(negedge clk); start = 0;
            lat = 1;
            while (!done) begin @(negedge clk); lat = lat + 1; end
        end
    endtask

    initial begin
        $readmemh("awgn_vectors.mem", vec);
        repeat (4) @(negedge clk); rst = 0;
        // 1. bit-exact
        for (k = 0; k < 448; k = k + 1) begin
            one(vec[3*k][4:0]);
            check(ni === $signed(vec[3*k+1][18:0]) && nq === $signed(vec[3*k+2][18:0]), "bit-exact vs Python model");
            check(lat == LAT, "latency");
            if (vec[3*k][4:0] == 0) check(ni == 0 && nq == 0, "noise off -> zero");
        end
        // 2. start while busy is ignored (result identical to an undisturbed run is covered by the statistics run continuing bit-exact;
        //    here: a second start mid-run must not restart the sequence -> latency stays 27)
        noise_idx = 5'd31;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        repeat (5) @(negedge clk); start = 1; @(negedge clk); start = 0;
        lat = 7; while (!done) begin @(negedge clk); lat = lat + 1; end
        check(lat == LAT, "start while busy ignored");
        // 3. statistics at C/N = 0 dB
        s1 = 0; s2 = 0; sq = 0; sxy = 0; maxabs = 0; n_in = 0;
        for (k = 0; k < 20000; k = k + 1) begin
            one(5'd31);
            s1 = s1 + ni; s2 = s2 + 1.0 * ni * ni; sq = sq + 1.0 * nq * nq; sxy = sxy + 1.0 * ni * nq;
            if (ni > maxabs) maxabs = ni; if (-ni > maxabs) maxabs = -ni;
            if (ni < 23170 && ni > -23170) n_in = n_in + 1;
        end
        mean_i = s1 / 20000.0; sig_i = $sqrt(s2 / 20000.0); sig_q = $sqrt(sq / 20000.0); rho = sxy / 20000.0 / (sig_i * sig_q);
        $display("statistics (20000 samples, C/N 0 dB): mean %0.1f  sigma_I %0.1f  sigma_Q %0.1f  (table 23170)  rho_IQ %0.4f  max|n| %0.0f = %0.2f sigma  inside 1 sigma: %0.2f %%",
                 mean_i, sig_i, sig_q, rho, maxabs, maxabs / 23170.0, n_in / 200.0);
        check(mean_i > -500.0 && mean_i < 500.0, "mean ~ 0");
        check(sig_i > 0.98 * 23170 && sig_i < 1.02 * 23170, "sigma I within 2 %");
        check(sig_q > 0.98 * 23170 && sig_q < 1.02 * 23170, "sigma Q within 2 %");
        check(rho > -0.03 && rho < 0.03, "I and Q uncorrelated");
        check(maxabs <= 6.0 * 23170, "bounded by 6 sigma (sum of 12 uniforms)");
        check(n_in > 13460 && n_in < 13860, "68.3 % within one sigma (+/- 1 %)");
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
