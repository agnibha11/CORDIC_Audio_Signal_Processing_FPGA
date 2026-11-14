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
//  m is the modulating signal and m_hat the receiver output, both after the
//  same audio filter, so the difference is exactly what the link (modulator,
//  noisy channel, demodulator) did to the audio.  With the channel noise off
//  the result is the CORDIC's own noise floor; with it on, the meter traces
//  the textbook SNR-versus-C/N curves of FM, PM and AM.
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

    // ---- SNR estimate:  10 log10(sum_sig / sum_err)  without a divider ----
    // log2 of each sum is taken as (position of the leading one) * 8 + the next
    // three mantissa bits, i.e. log2 in units of 1/8 by linear interpolation.
    // The sums only change once per window, so the estimate is computed in
    // four registered steps (in the five clocks after a window ends) to keep
    // every path short.
    function [5:0] lead1;                       // position of the leading one
        input [47:0] xx;
        integer kk;
        begin
            lead1 = 6'd0;
            for (kk = 0; kk < 48; kk = kk + 1)
                if (xx[kk]) lead1 = kk[5:0];
        end
    endfunction

    reg  [5:0]  p_sig, p_err;                   // step 1
    reg  [47:0] sh_sig, sh_err;                 // step 2: leading one moved to bit 47
    reg  [5:0]  p_sig2, p_err2;
    reg  [9:0]  l_dif;                          // step 3
    reg  [2:0]  est;                            // estimate sequencer
    wire [8:0]  l_sig = {p_sig2, sh_sig[46:44]};
    wire [8:0]  l_err = {p_err2, sh_err[46:44]};
    wire [15:0] snr_x = l_dif[8:0] * 10'd24;    // * (3.0103 / 8) ~ * 24 / 64

    always @(posedge clk) begin
        v1          <= 1'b0;
        window_done <= 1'b0;
        if (rst) begin
            m_sq     <= 32'd0;  e_sq <= 34'd0;  e_abs_r <= 16'd0;
            acc_sig  <= 48'd0;  acc_err <= 48'd0;  acc_peak <= 16'd0;
            cnt      <= {WLOG{1'b0}};
            sum_sig  <= 48'd0;  sum_err <= 48'd0;  peak_err <= 16'd0;  snr_db <= 7'd0;
            p_sig <= 6'd0; p_err <= 6'd0; p_sig2 <= 6'd0; p_err2 <= 6'd0; sh_sig <= 48'd0; sh_err <= 48'd0; l_dif <= 10'd0; est <= 3'd0;
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
            // SNR estimate: runs for five clocks after each window (four pipeline steps)
            if (v1 && cnt == {WLOG{1'b1}}) est <= 3'd6;
            else if (est != 3'd0)          est <= est - 3'd1;
            if (est != 3'd0 && est != 3'd6) begin
                p_sig  <= lead1(sum_sig);                 p_err  <= lead1(sum_err);
                sh_sig <= sum_sig << (6'd47 - p_sig);     sh_err <= sum_err << (6'd47 - p_err);
                p_sig2 <= p_sig;                          p_err2 <= p_err;
                l_dif  <= {1'b0, l_sig} - {1'b0, l_err};
                if (sum_sig == 48'd0)       snr_db <= 7'd0;
                else if (sum_err == 48'd0)  snr_db <= 7'd99;
                else if (l_dif[9])          snr_db <= 7'd0;                 // error > signal
                else if (snr_x[15:6] > 10'd99) snr_db <= 7'd99;
                else                        snr_db <= snr_x[12:6];
            end
        end
    end
endmodule
`default_nettype wire
