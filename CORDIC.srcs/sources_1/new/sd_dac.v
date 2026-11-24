`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
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
