`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
// ============================================================================
module btn_debounce #(
    parameter integer STABLE_CLKS = 1_000_000
)(
    input  wire clk,
    input  wire rst,
    input  wire din,
    output reg  level,
    output reg  press
);
    reg [19:0] cnt;
    always @(posedge clk) begin
        press <= 1'b0;
        if (rst) begin
            cnt   <= 20'd0;
            level <= 1'b0;
        end else if (din == level) begin
            cnt <= 20'd0;
        end else if (cnt == STABLE_CLKS - 1) begin
            cnt   <= 20'd0;
            level <= din;
            press <= din;
        end else begin
            cnt <= cnt + 20'd1;
        end
    end
endmodule
`default_nettype wire
