`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  model_kypd.v -- behavioural model of the Pmod KYPD matrix
//
//  `pressed[15:0]` holds the key image (bit = row*4 + col, row 0 = top).
//  Rows read low when a pressed key connects them to a column that the host
//  drives low; otherwise the pull-ups hold them high.  A settling delay of
//  SETTLE_NS mimics the RC of the pull-ups and the ribbon cable.
// ============================================================================
module model_kypd #(
    parameter integer SETTLE_NS = 2000
)(
    input  wire [3:0]  col,       // col[0] = COL1 (left)
    output reg  [3:0]  row,       // row[0] = ROW1 (top)
    input  wire [15:0] pressed
);
    integer r, c;
    reg [3:0] row_i;
    always @(*) begin
        row_i = 4'b1111;
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
                if (pressed[r*4 + c] && !col[c]) row_i[r] = 1'b0;
    end
    always @(row_i) row <= #(SETTLE_NS) row_i;
    initial row = 4'b1111;
endmodule
`default_nettype wire
