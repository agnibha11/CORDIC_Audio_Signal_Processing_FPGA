`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  awgn_gen.v -- channel noise source: two independent Gaussian samples per
//                audio sample (one for each quadrature of the carrier)
//
//  A real radio link adds noise between transmitter and receiver.  This block
//  is that noise, generated on chip so the link can be degraded on purpose
//  and the receiver's behaviour measured.
//
//  1. Uniform numbers: a 32-bit xorshift generator (Marsaglia), three XOR
//     shifts per step, period 2^32 - 1.  The upper 16 bits of each state are
//     used as a signed uniform number.
//  2. Gaussian shape: the sum of 12 independent uniform numbers is very close
//     to a normal distribution (central limit theorem, "Irwin-Hall").  A
//     signed 16-bit uniform number has variance 2^32 / 12, so the sum of 12
//     has variance 2^32 exactly: sigma = 2^16.
//  3. Level: the sum is multiplied by a gain g and shifted right by 16, so the
//     output has sigma = g.  The gain table holds
//         g = (32767 / sqrt 2) / 10^(CNR/20),   CNR = 31 - noise_idx  dB
//     i.e. noise_idx 1 -> 30 dB carrier-to-noise ratio ... 31 -> 0 dB, and
//     noise_idx 0 switches the noise off.  CNR is the power of a full-scale
//     carrier (32767^2 / 2) over the variance of ONE quadrature component.
//
//  Sequence per `start`: 12 clocks sum I, 12 clocks sum Q, 3 clocks scale
//  (28 clocks from `start` to `done`).
//  Bit-exact with scripts/cordic_model.py (class Awgn).
// ============================================================================
module awgn_gen (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,        // one pulse per audio sample
    input  wire        [4:0]  noise_idx,    // 0 = off, 1..31 -> CNR = 31 - idx dB
    output reg                done,         // pulse: ni / nq updated
    output reg  signed [18:0] ni,           // in-phase noise sample
    output reg  signed [18:0] nq            // quadrature noise sample
);
    localparam [31:0] SEED = 32'h2545F491;

    // sigma for each level (scripts/cordic_model.py, NOISE_GAIN)
    function [14:0] gain_of;
        input [4:0] idx;
        begin
            case (idx)
                5'd0 : gain_of = 15'd0;     5'd1 : gain_of = 15'd733;   5'd2 : gain_of = 15'd822;   5'd3 : gain_of = 15'd922;
                5'd4 : gain_of = 15'd1035;  5'd5 : gain_of = 15'd1161;  5'd6 : gain_of = 15'd1303;  5'd7 : gain_of = 15'd1462;
                5'd8 : gain_of = 15'd1640;  5'd9 : gain_of = 15'd1840;  5'd10: gain_of = 15'd2065;  5'd11: gain_of = 15'd2317;
                5'd12: gain_of = 15'd2600;  5'd13: gain_of = 15'd2917;  5'd14: gain_of = 15'd3273;  5'd15: gain_of = 15'd3672;
                5'd16: gain_of = 15'd4120;  5'd17: gain_of = 15'd4623;  5'd18: gain_of = 15'd5187;  5'd19: gain_of = 15'd5820;
                5'd20: gain_of = 15'd6530;  5'd21: gain_of = 15'd7327;  5'd22: gain_of = 15'd8221;  5'd23: gain_of = 15'd9224;
                5'd24: gain_of = 15'd10350; 5'd25: gain_of = 15'd11612; 5'd26: gain_of = 15'd13029; 5'd27: gain_of = 15'd14619;
                5'd28: gain_of = 15'd16403; 5'd29: gain_of = 15'd18404; 5'd30: gain_of = 15'd20650; default: gain_of = 15'd23170;
            endcase
        end
    endfunction

    // one xorshift32 step
    function [31:0] xs32;
        input [31:0] v;
        reg   [31:0] t;
        begin
            t = v ^ (v << 13);
            t = t ^ (t >> 17);
            xs32 = t ^ (t << 5);
        end
    endfunction

    localparam [1:0] S_IDLE = 2'd0, S_SUM = 2'd1, S_MUL = 2'd2;

    reg  [1:0]         st;
    reg  [31:0]        x;
    reg  [3:0]         cnt;
    reg                sel_q;
    reg  [1:0]         mstep;
    reg  signed [19:0] acc, sum_i, sum_q;
    reg  signed [15:0] gain_r;               // 15-bit gain, sign bit 0
    reg  signed [35:0] prod;

    wire [31:0]        xn  = xs32(x);
    wire signed [15:0] w   = xn[31:16];
    wire signed [19:0] acc_nx = acc + w;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            st <= S_IDLE; x <= SEED; cnt <= 4'd0; sel_q <= 1'b0; mstep <= 2'd0;
            acc <= 20'sd0; sum_i <= 20'sd0; sum_q <= 20'sd0; gain_r <= 16'sd0; prod <= 36'sd0;
            ni <= 19'sd0; nq <= 19'sd0;
        end else begin
            case (st)
                S_IDLE: if (start) begin
                    acc    <= 20'sd0;
                    cnt    <= 4'd0;
                    sel_q  <= 1'b0;
                    gain_r <= {1'b0, gain_of(noise_idx)};
                    st     <= S_SUM;
                end
                S_SUM: begin
                    x <= xn;
                    if (cnt == 4'd11) begin
                        cnt <= 4'd0;
                        acc <= 20'sd0;
                        if (!sel_q) begin
                            sum_i <= acc_nx;
                            sel_q <= 1'b1;
                        end else begin
                            sum_q <= acc_nx;
                            mstep <= 2'd0;
                            st    <= S_MUL;
                        end
                    end else begin
                        cnt <= cnt + 4'd1;
                        acc <= acc_nx;
                    end
                end
                S_MUL: begin
                    mstep <= mstep + 2'd1;
                    case (mstep)
                        2'd0:    prod <= sum_i * gain_r;
                        2'd1:    begin ni <= prod[34:16]; prod <= sum_q * gain_r; end
                        default: begin nq <= prod[34:16]; done <= 1'b1; st <= S_IDLE; end
                    endcase
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
