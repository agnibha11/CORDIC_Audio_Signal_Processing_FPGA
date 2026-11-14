`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  sd_dac.v -- one-bit sigma-delta digital-to-analog converter for the
//              Pmod AMP2 audio input
//
//  The Pmod AMP2 has no digital interface: its AIN pin is an analog input
//  with an on-board RC low-pass ("reconstruction") filter in front of the
//  SSM2377 class-D amplifier.  A single FPGA pin can still deliver audio to
//  it if the pin toggles fast and the AVERAGE of the bit stream follows the
//  audio sample.  A first-order sigma-delta modulator does exactly that:
//
//      acc[n] = acc[n-1] + u          (u = sample as an unsigned 16-bit number)
//      out    = carry of that addition
//
//  The carry is 1 in u out of every 65536 additions, so the density of ones
//  is u / 65536.  The quantisation error is pushed to high frequencies
//  (noise shaping) where the RC filter and the loudspeaker remove it.
//  Bit rate = clk / DIV = 6.25 MHz: 125 bits per audio sample.
// ============================================================================
module sd_dac #(
    parameter integer DIV = 16              // clk cycles per output bit
)(
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] sample,       // Q15 audio (held between updates)
    output reg                bit_out
);
    reg [7:0]  div;
    reg [15:0] acc;
    wire [15:0] u   = {~sample[15], sample[14:0]};      // two's complement -> offset binary
    wire [16:0] sum = {1'b0, acc} + {1'b0, u};

    always @(posedge clk) begin
        if (rst) begin
            div <= 8'd0; acc <= 16'd0; bit_out <= 1'b0;
        end else if (div == DIV - 1) begin
            div     <= 8'd0;
            acc     <= sum[15:0];
            bit_out <= sum[16];
        end else begin
            div <= div + 8'd1;
        end
    end
endmodule
`default_nettype wire
