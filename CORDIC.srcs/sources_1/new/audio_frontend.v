`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  audio_frontend.v -- ADC code -> signed Q15 audio with DC removal
//
//  The MIC3 delivers unsigned 12-bit codes biased near mid-scale (2048).
//  1. offset binary -> two's complement, scaled to Q15 (<< 4)
//  2. first-order DC blocker  y[n] = x[n] - x[n-1] + (1 - 2^-8) y[n-1]
//     implemented with 8 fractional guard bits (acc is Q15.8):
//        acc <= acc - (acc >>> 8) + ((x - x_prev) << 8)
//     corner frequency  fc = Fs * 2^-8 / (2 pi) ~ 31 Hz at Fs = 50 kHz,
//     so the microphone bias (and any ADC offset) never reaches the
//     modulator, where a DC term would become a constant carrier offset.
//  3. clip flag: raw code within 64 LSB of either rail.
//  Latency: 1 clock after `in_valid`.
// ============================================================================
module audio_frontend (
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire        [11:0] adc_code,
    output reg                out_valid,
    output reg  signed [15:0] audio,        // Q15, DC free
    output reg                clip          // sticky for one sample
);
    localparam integer DC_SHIFT = 8;

    wire signed [15:0] x    = {~adc_code[11], adc_code[10:0], 4'b0000};  // (code - 2048) << 4
    reg  signed [15:0] x_prev;
    reg  signed [27:0] acc;                                              // Q15.8
    wire signed [16:0] diff = x - x_prev;
    wire signed [27:0] acc_nx = acc - (acc >>> DC_SHIFT) + (diff <<< DC_SHIFT);
    wire signed [19:0] y_full = acc_nx >>> DC_SHIFT;

    function signed [15:0] sat16;
        input signed [19:0] v;
        begin
            if (v > 20'sd32767)       sat16 = 16'sd32767;
            else if (v < -20'sd32768) sat16 = -16'sd32768;
            else                      sat16 = v[15:0];
        end
    endfunction

    always @(posedge clk) begin
        out_valid <= 1'b0;
        if (rst) begin
            x_prev <= 16'sd0;
            acc    <= 28'sd0;
            audio  <= 16'sd0;
            clip   <= 1'b0;
        end else if (in_valid) begin
            x_prev    <= x;
            acc       <= acc_nx;
            audio     <= sat16(y_full);
            clip      <= (adc_code < 12'd64) || (adc_code > 12'd4031);
            out_valid <= 1'b1;
        end
    end
endmodule
`default_nettype wire
