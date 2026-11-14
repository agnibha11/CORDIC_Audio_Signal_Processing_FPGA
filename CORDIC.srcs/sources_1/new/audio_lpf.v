`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  audio_lpf.v -- audio-band low-pass filter: four cascaded 4-sample moving
//                 averages (a "sinc^4" filter), no multipliers
//
//  Why it exists: the receiver's raw output still contains noise over the
//  whole 0..25 kHz band, but speech only needs about 3 kHz.  Everything above
//  the audio band is thrown away here -- this is where FM earns its noise
//  advantage, because an FM discriminator puts most of its noise at high
//  frequencies.
//
//  One stage:  y[n] = x[n] + x[n-1] + x[n-2] + x[n-3]
//  computed recursively as  acc += x[n] - x[n-4]  (exact in integers).
//  Four stages give a gain of 4^4 = 256, removed at the end by a rounding
//  shift of 8.  Response: -3 dB at 2.93 kHz, nulls at 12.5 and 25 kHz, first
//  side lobe -45 dB.  Linear phase: every frequency is delayed by exactly
//  6 samples, so the reference path can use an identical filter and stay
//  aligned sample for sample.
//
//  One stage is evaluated per clock (5 clocks per sample) to keep the adder
//  chain short.  Bit-exact with scripts/cordic_model.py (class BoxLPF).
// ============================================================================
module audio_lpf #(
    parameter integer IN_W = 20             // input width (signed)
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   en,       // pulse: new input sample
    input  wire signed [IN_W-1:0] x,
    output reg                    valid,    // pulse: y updated
    output reg  signed [15:0]     y
);
    localparam integer W = IN_W + 8;        // four stages, 2 bits of growth each

    reg  signed [W-1:0] acc [0:3];
    reg  signed [W-1:0] dl  [0:15];         // dl[4*k + j] = input of stage k, j+1 samples ago
    reg  signed [W-1:0] v;
    reg         [1:0]   k;
    reg                 run;
    integer             i;

    wire [3:0]          base = {k, 2'b00};
    wire signed [W-1:0] nv   = acc[k] + v - dl[base + 4'd3];
    wire signed [W-1:0] rnd  = (nv + 128) >>> 8;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            run <= 1'b0; k <= 2'd0; v <= {W{1'b0}}; y <= 16'sd0;
            for (i = 0; i < 4;  i = i + 1) acc[i] <= {W{1'b0}};
            for (i = 0; i < 16; i = i + 1) dl[i]  <= {W{1'b0}};
        end else if (!run) begin
            if (en) begin
                v   <= {{8{x[IN_W-1]}}, x};
                k   <= 2'd0;
                run <= 1'b1;
            end
        end else begin
            acc[k]           <= nv;
            dl[base + 4'd3]  <= dl[base + 4'd2];
            dl[base + 4'd2]  <= dl[base + 4'd1];
            dl[base + 4'd1]  <= dl[base];
            dl[base]         <= v;
            v                <= nv;
            k                <= k + 2'd1;
            if (k == 2'd3) begin
                run   <= 1'b0;
                valid <= 1'b1;
                if (rnd > 32767)       y <= 16'sd32767;
                else if (rnd < -32768) y <= -16'sd32768;
                else                   y <= rnd[15:0];
            end
        end
    end
endmodule
`default_nettype wire
