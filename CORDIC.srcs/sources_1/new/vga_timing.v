`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
// ============================================================================
module vga_timing (
    input  wire       clk,
    input  wire       rst,
    output reg        pix_en,       // one clock in four: advance one pixel
    output reg  [9:0] h,            // 0..799, valid with pix_en
    output reg  [9:0] v,            // 0..524
    output wire       active,       // h < 640 && v < 480
    output wire       hs_n,         // combinational from h (register with pix_en downstream)
    output wire       vs_n,
    output wire       vblank,       // v >= 480
    output reg        frame_start   // one-cycle pulse at (h,v) = (0,0)
);
    localparam [9:0] H_VIS = 10'd640, H_FP = 10'd16, H_SYNC = 10'd96, H_TOTAL = 10'd800;
    localparam [9:0] V_VIS = 10'd480, V_FP = 10'd10, V_SYNC = 10'd2,  V_TOTAL = 10'd525;

    reg [1:0] div;
    always @(posedge clk) begin
        pix_en      <= 1'b0;
        frame_start <= 1'b0;
        if (rst) begin
            div <= 2'd0;
            h   <= 10'd0;
            v   <= 10'd0;
        end else begin
            div <= div + 2'd1;
            if (div == 2'd3) begin
                pix_en <= 1'b1;
                if (h == H_TOTAL - 1) begin
                    h <= 10'd0;
                    if (v == V_TOTAL - 1) begin
                        v           <= 10'd0;
                        frame_start <= 1'b1;
                    end else begin
                        v <= v + 10'd1;
                    end
                end else begin
                    h <= h + 10'd1;
                end
            end
        end
    end

    assign active = (h < H_VIS) && (v < V_VIS);
    assign hs_n   = ~((h >= H_VIS + H_FP) && (h < H_VIS + H_FP + H_SYNC));
    assign vs_n   = ~((v >= V_VIS + V_FP) && (v < V_VIS + V_FP + V_SYNC));
    assign vblank = (v >= V_VIS);
endmodule
`default_nettype wire
