`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  fidelity_meter.v -- quantifies "what modulation did to the audio"
//
//  Over a window of 2^WLOG samples it accumulates
//        sum_sig = sum m[n]^2            (original modulating signal)
//        sum_err = sum (m[n] - m_hat[n])^2   (original minus demodulated)
//  and the peak |error|.  SNR(dB) = 10 log10(sum_sig / sum_err) is shown on
//  the VGA using a leading-one log2 estimator (+/- 0.5 dB); the exact sums
//  are exported to the VIO for an offline calculation.
//  The demodulator sees the SAME CORDIC-generated I/Q that drives the DAC,
//  so this is a loop-back measurement of the modulator + demodulator pair:
//  it isolates the CORDIC's own contribution (angle quantisation, finite
//  iterations, truncation) from the analog path.
// ============================================================================
module fidelity_meter #(
    parameter integer WLOG = 15            // 32768 samples = 0.66 s at 50 kS/s
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire signed [15:0] m,
    input  wire signed [15:0] m_hat,
    output reg         [47:0] sum_sig,
    output reg         [47:0] sum_err,
    output reg         [15:0] peak_err,
    output reg         [6:0]  snr_db,      // 0..99, estimated
    output reg                window_done  // pulse when the outputs update
);
    wire signed [16:0] e     = m - m_hat;
    wire        [16:0] e_abs = e[16] ? (-e) : e;

    // stage 1: squares (DSP48)
    reg  [31:0] m_sq;
    reg  [33:0] e_sq;
    reg  [15:0] e_abs_r;
    reg         v1;
    // stage 2: accumulate
    reg  [47:0] acc_sig, acc_err;
    reg  [15:0] acc_peak;
    reg  [WLOG-1:0] cnt;

    // floor(log2(x)) * 8 + next three mantissa bits  (log2 in Q3 by linear interpolation)
    function [8:0] log2q3;
        input [47:0] x;
        integer k;
        reg [5:0] p;
        reg [47:0] sh;
        begin
            p = 6'd0;
            for (k = 0; k < 48; k = k + 1)
                if (x[k]) p = k[5:0];
            sh = x << (6'd47 - p);          // leading one now at bit 47
            log2q3 = {p, sh[46:44]};
        end
    endfunction

    wire [8:0]  l_sig = log2q3(sum_sig);
    wire [8:0]  l_err = log2q3(sum_err);
    wire [9:0]  l_dif = {1'b0, l_sig} - {1'b0, l_err};
    wire [15:0] snr_x = l_dif[8:0] * 10'd24;          // * (3.0103 / 8) ~ * 24 / 64

    always @(posedge clk) begin
        v1          <= 1'b0;
        window_done <= 1'b0;
        if (rst) begin
            m_sq     <= 32'd0;  e_sq <= 34'd0;  e_abs_r <= 16'd0;
            acc_sig  <= 48'd0;  acc_err <= 48'd0;  acc_peak <= 16'd0;
            cnt      <= {WLOG{1'b0}};
            sum_sig  <= 48'd0;  sum_err <= 48'd0;  peak_err <= 16'd0;  snr_db <= 7'd0;
        end else begin
            if (in_valid) begin
                m_sq    <= m * m;
                e_sq    <= e * e;
                e_abs_r <= (e_abs > 17'd65535) ? 16'hFFFF : e_abs[15:0];
                v1      <= 1'b1;
            end
            if (v1) begin
                if (cnt == {WLOG{1'b1}}) begin
                    sum_sig     <= acc_sig + {16'd0, m_sq};
                    sum_err     <= acc_err + {14'd0, e_sq};
                    peak_err    <= (e_abs_r > acc_peak) ? e_abs_r : acc_peak;
                    acc_sig     <= 48'd0;
                    acc_err     <= 48'd0;
                    acc_peak    <= 16'd0;
                    window_done <= 1'b1;
                end else begin
                    acc_sig  <= acc_sig + {16'd0, m_sq};
                    acc_err  <= acc_err + {14'd0, e_sq};
                    if (e_abs_r > acc_peak) acc_peak <= e_abs_r;
                end
                cnt <= cnt + 1'b1;
            end
            // SNR estimate from the latched sums (quasi-static)
            if (sum_sig == 48'd0)       snr_db <= 7'd0;
            else if (sum_err == 48'd0)  snr_db <= 7'd99;
            else if (l_dif[9])          snr_db <= 7'd0;                 // error > signal
            else if (snr_x[15:6] > 10'd99) snr_db <= 7'd99;
            else                        snr_db <= snr_x[12:6];
        end
    end
endmodule
`default_nettype wire
