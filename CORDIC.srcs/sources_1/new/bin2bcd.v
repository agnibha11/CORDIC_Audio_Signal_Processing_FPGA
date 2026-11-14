`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  bin2bcd.v -- binary to decimal digits, one bit per clock ("double dabble")
//
//  The VGA read-outs need decimal digits.  Shift the binary number left into
//  a row of 4-bit digits; before each shift add 3 to every digit that is 5 or
//  more, so that the doubling carries into the next digit at 10 instead of 16.
//  After W shifts the digits hold the decimal value.  The numbers on screen
//  change at human speed, so a slow serial converter (W clocks) is free and
//  keeps long combinational adders out of the pixel path.
// ============================================================================
module bin2bcd #(
    parameter integer W = 8,                // input bits
    parameter integer D = 3                 // decimal digits
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [W-1:0]     bin,
    output reg  [4*D-1:0]   bcd             // updated when a conversion completes
);
    reg [W-1:0]   sh;
    reg [4*D-1:0] dg;
    reg [5:0]     n;
    reg           run;
    reg [4*D-1:0] adj;
    integer       i;

    always @(*) begin
        adj = dg;
        for (i = 0; i < D; i = i + 1)
            if (dg[4*i +: 4] >= 4'd5) adj[4*i +: 4] = dg[4*i +: 4] + 4'd3;
    end

    always @(posedge clk) begin
        if (rst) begin
            run <= 1'b0; n <= 6'd0; sh <= {W{1'b0}}; dg <= {(4*D){1'b0}}; bcd <= {(4*D){1'b0}};
        end else if (!run) begin
            if (start) begin
                sh  <= bin;
                dg  <= {(4*D){1'b0}};
                n   <= 6'd0;
                run <= 1'b1;
            end
        end else begin
            dg <= {adj[4*D-2:0], sh[W-1]};
            sh <= {sh[W-2:0], 1'b0};
            n  <= n + 6'd1;
            if (n == W - 1) begin
                run <= 1'b0;
                bcd <= {adj[4*D-2:0], sh[W-1]};
            end
        end
    end
endmodule
`default_nettype wire
