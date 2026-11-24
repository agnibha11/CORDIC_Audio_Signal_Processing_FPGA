`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Agnibha Sarkar
//  Last Updated : 24 November 2026
// ============================================================================
module cordic_engine #(
    parameter integer W = 24,      // data path width
    parameter integer Z = 24,      // angle width, 2^Z per turn
    parameter integer N = 18       // number of micro-rotations
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                start,       // load inputs and begin (ignored while busy)
    input  wire                vectoring,   // 0 = rotation mode, 1 = vectoring mode
    input  wire signed [W-1:0] x_in,
    input  wire signed [W-1:0] y_in,
    input  wire        [Z-1:0] z_in,        // rotation angle (BAM); ignored in vectoring mode
    output reg                 busy,
    output reg                 done,        // one-cycle pulse, outputs valid from this cycle on
    output wire signed [W-1:0] x_out,
    output wire signed [W-1:0] y_out,
    output wire        [Z-1:0] z_out        // vectoring: atan2 (BAM); rotation: residual (~0)
);

    function [Z-1:0] atan_bam;
        input [5:0] idx;
        reg   [31:0] t;
        begin
            case (idx)
                6'd0 : t = 32'd536870912;   // 45.000 deg
                6'd1 : t = 32'd316933406;   // 26.565 deg
                6'd2 : t = 32'd167458907;   // 14.036 deg
                6'd3 : t = 32'd85004756;    //  7.125 deg
                6'd4 : t = 32'd42667331;
                6'd5 : t = 32'd21354465;
                6'd6 : t = 32'd10679838;
                6'd7 : t = 32'd5340245;
                6'd8 : t = 32'd2670163;
                6'd9 : t = 32'd1335087;
                6'd10: t = 32'd667544;
                6'd11: t = 32'd333772;
                6'd12: t = 32'd166886;
                6'd13: t = 32'd83443;
                6'd14: t = 32'd41722;
                6'd15: t = 32'd20861;
                6'd16: t = 32'd10430;
                6'd17: t = 32'd5215;
                6'd18: t = 32'd2608;
                6'd19: t = 32'd1304;
                6'd20: t = 32'd652;
                6'd21: t = 32'd326;
                6'd22: t = 32'd163;
                6'd23: t = 32'd81;
                default: t = 32'd0;
            endcase
            // round-to-nearest from 32 to Z bits
            atan_bam = (t + (32'd1 << (32 - Z - 1))) >> (32 - Z);
        end
    endfunction

    localparam [Z-1:0] QUARTER = {2'b01, {(Z-2){1'b0}}};   // +90 degrees

    reg  signed [W-1:0] x, y;
    reg  signed [Z-1:0] z;
    reg         [5:0]   i;
    reg                 running;
    reg                 vec_r;

    wire signed [W-1:0] xs = x >>> i;      // arithmetic shifts: i is self-determined
    wire signed [W-1:0] ys = y >>> i;
    wire        [Z-1:0] a_i = atan_bam(i);
    // d = +1 (counter-clockwise micro-rotation) ?
    wire                d_pos = vec_r ? y[W-1] : ~z[Z-1];

    assign x_out = x;
    assign y_out = y;
    assign z_out = z;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            running <= 1'b0;
            busy    <= 1'b0;
            i       <= 6'd0;
            vec_r   <= 1'b0;
            x       <= {W{1'b0}};
            y       <= {W{1'b0}};
            z       <= {Z{1'b0}};
        end else if (!running) begin
            if (start) begin
                running <= 1'b1;
                busy    <= 1'b1;
                i       <= 6'd0;
                vec_r   <= vectoring;
                if (vectoring) begin
                    // bring the vector into the right half-plane
                    if (x_in[W-1]) begin
                        if (!y_in[W-1]) begin        // quadrant II  : rotate by -90
                            x <= y_in;  y <= -x_in;  z <= QUARTER;
                        end else begin               // quadrant III : rotate by +90
                            x <= -y_in; y <= x_in;   z <= -QUARTER;
                        end
                    end else begin
                        x <= x_in;  y <= y_in;  z <= {Z{1'b0}};
                    end
                end else begin
                    // reduce the target angle to [-90, +90) degrees
                    case (z_in[Z-1:Z-2])
                        2'b01:   begin x <= -y_in; y <= x_in;  z <= z_in - QUARTER; end // [ 90,180)
                        2'b10:   begin x <= y_in;  y <= -x_in; z <= z_in + QUARTER; end // [-180,-90)
                        default: begin x <= x_in;  y <= y_in;  z <= z_in;           end
                    endcase
                end
            end
        end else begin
            if (d_pos) begin
                x <= x - ys;
                y <= y + xs;
                z <= z - $signed(a_i);
            end else begin
                x <= x + ys;
                y <= y - xs;
                z <= z + $signed(a_i);
            end
            i <= i + 6'd1;
            if (i == N - 1) begin
                running <= 1'b0;
                busy    <= 1'b0;
                done    <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
