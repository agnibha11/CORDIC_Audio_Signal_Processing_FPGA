`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  btn_debounce.v -- counter debouncer for a push button (input already
//  synchronised).  `level` follows the input once it has been stable for
//  STABLE_CLKS clocks (10 ms at 100 MHz); `press` is a one-cycle pulse on
//  the debounced rising edge.
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
