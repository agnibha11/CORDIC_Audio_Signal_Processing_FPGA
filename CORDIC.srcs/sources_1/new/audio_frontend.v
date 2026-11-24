`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
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
