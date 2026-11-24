`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Agnibha Sarkar
//  Last Updated : 24 November 2026
// ============================================================================
module sync_2ff #(
    parameter integer WIDTH = 1,
    parameter [WIDTH-1:0] INIT = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] s1 = INIT;
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] s2 = INIT;
    always @(posedge clk) begin
        s1 <= d;
        s2 <= s1;
    end
    assign q = s2;
endmodule
`default_nettype wire
