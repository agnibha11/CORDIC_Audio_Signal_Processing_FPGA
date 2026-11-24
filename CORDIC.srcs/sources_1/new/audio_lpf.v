`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Hridayesh Kundu
//  Last Updated : 24 November 2026
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
