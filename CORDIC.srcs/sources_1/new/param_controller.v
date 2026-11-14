`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  param_controller.v -- user parameters, keypad command decode and the
//                        derived DSP constants
//
//  User-facing parameters (what the keypad edits and the VGA shows):
//     fc_idx    : carrier frequency      f_c  = fc_idx * 100 Hz        1..100
//     beta_q    : modulation index       beta = beta_q / 8  (Q4.3)     0..127
//     fm_idx    : modulating frequency   f_m  = fm_idx * 50 Hz         1..40
//     amp       : modulating amplitude   A    = amp / 16   (Q2.4)      0..63
//     noise_idx : channel noise          0 = off, else C/N = 31 - noise_idx dB
//     mode      : 0 FM, 1 PM, 2 AM, 3 bypass          source: 0 MIC, 1 tone
//     mon_sel   : what the loudspeaker and DAC-B play
//                 0 recovered audio, 1 original, 2 channel signal, 3 error
//
//  Derived constants (all exact integer arithmetic, Fs = 50 kHz):
//     fcw_c = fc_idx * round(100 * 2^32 / Fs)       carrier phase increment
//     fcw_m = fm_idx * round( 50 * 2^32 / Fs)       tone phase increment
//     kdev  = beta * fcw_m                          FM: peak deviation Df = beta * f_m
//     kpm   = min(beta, 2) * 2^32 / (2 pi)          PM: peak phase deviation, limited to 2 rad
//     mu_q  = min(beta, 1)  (Q15)                   AM: modulation depth, limited to 100 %
//     div_den: divisor for the receiver's reciprocal gain, selected by mode
//  The PM and AM limits keep the memoryless phase / envelope detectors inside
//  their valid range (|phase| < pi, envelope > 0) for every keypad setting.
//
//  Keypad map (see kypd_scanner.v for the physical layout):
//     1/4 fc +/-   2/5 beta +/-   3/6 fm +/-    A/B amp +/-
//     7 source     8 mode         9/E noise +/- C hold/run
//     0 defaults   F coarse step  D monitor select
//  Board buttons duplicate the most-used actions: BTNL/BTNR fc -/+,
//  BTNU mode, BTNC hold/run.  With vio_override = 1 the VIO dashboard
//  drives every parameter directly (bench use without a keypad).
//
//  The derived constants are computed in three registered steps so that no
//  path contains two multipliers in series.
// ============================================================================
module param_controller (
    input  wire        clk,
    input  wire        rst,
    // keypad / buttons (one-cycle pulses)
    input  wire        key_valid,
    input  wire [3:0]  key_code,
    input  wire        btn_fc_up,
    input  wire        btn_fc_dn,
    input  wire        btn_mode,
    input  wire        btn_hold,
    // VIO override
    input  wire        vio_override,
    input  wire [6:0]  vio_fc_idx,
    input  wire [6:0]  vio_beta_q,
    input  wire [5:0]  vio_fm_idx,
    input  wire [5:0]  vio_amp,
    input  wire [1:0]  vio_mode,
    input  wire        vio_source,
    input  wire        vio_hold,
    input  wire [4:0]  vio_noise,
    // live parameters
    output reg  [6:0]  fc_idx,
    output reg  [6:0]  beta_q,
    output reg  [5:0]  fm_idx,
    output reg  [5:0]  amp,
    output reg  [4:0]  noise_idx,
    output reg  [1:0]  mode,
    output reg         source,
    output reg         hold,
    output reg         coarse,
    output reg  [1:0]  mon_sel,
    // derived constants (registered, quasi-static)
    output reg  [31:0] fcw_c,
    output reg  [31:0] fcw_m,
    output reg  [31:0] kdev,
    output reg  [30:0] kpm,
    output reg  [15:0] mu_q,
    output reg  [25:0] div_den,
    output reg         params_changed   // pulse: div_den changed -> recompute reciprocal
);
    // ---- scaling constants (scripts/cordic_model.py) -----------------------
    localparam [23:0] FCW_PER_100HZ = 24'd8589935;    // round(100 * 2^32 / 50000)
    localparam [22:0] FCW_PER_50HZ  = 23'd4294967;    // round( 50 * 2^32 / 50000)
    localparam [26:0] KPM_UNIT      = 27'd85445659;   // round(2^32 / (16 pi))  per beta_q
    localparam [17:0] AM_D_UNIT     = 18'd215845;     // round(64 * K * 16384 / 8), K = 1.64676
    localparam [6:0]  PM_BETA_MAX   = 7'd16;          // 2.0 rad
    localparam [6:0]  AM_BETA_MAX   = 7'd8;           // 100 %
    // ---- defaults: f_c 4 kHz, beta 5, f_m 400 Hz -> FM deviation 2 kHz ------
    localparam [6:0] DEF_FC   = 7'd40;
    localparam [6:0] DEF_BETA = 7'd40;
    localparam [5:0] DEF_FM   = 6'd8;
    localparam [5:0] DEF_AMP  = 6'd16;    // 1.0
    localparam [6:0] FC_MAX   = 7'd100;
    localparam [5:0] FM_MAX   = 6'd40;

    // keypad step sizes
    wire [6:0] st_fc = coarse ? 7'd10 : 7'd1;
    wire [6:0] st_b  = coarse ? 7'd8  : 7'd1;
    wire [5:0] st_fm = coarse ? 6'd4  : 6'd1;
    wire [5:0] st_a  = coarse ? 6'd4  : 6'd1;
    wire [4:0] st_n  = coarse ? 5'd5  : 5'd1;

    wire [7:0] fc_up  = {1'b0, fc_idx} + {1'b0, st_fc};
    wire [7:0] b_up   = {1'b0, beta_q} + {1'b0, st_b};
    wire [6:0] fm_up  = {1'b0, fm_idx} + {1'b0, st_fm};
    wire [6:0] a_up   = {1'b0, amp}    + {1'b0, st_a};
    wire [5:0] n_up   = {1'b0, noise_idx} + {1'b0, st_n};

    always @(posedge clk) begin
        if (rst) begin
            fc_idx    <= DEF_FC;
            beta_q    <= DEF_BETA;
            fm_idx    <= DEF_FM;
            amp       <= DEF_AMP;
            noise_idx <= 5'd0;
            mode      <= 2'd0;
            source    <= 1'b0;
            hold      <= 1'b0;
            coarse    <= 1'b0;
            mon_sel   <= 2'd0;
        end else if (vio_override) begin
            fc_idx    <= (vio_fc_idx == 7'd0) ? 7'd1 : (vio_fc_idx > FC_MAX) ? FC_MAX : vio_fc_idx;
            beta_q    <= vio_beta_q;
            fm_idx    <= (vio_fm_idx == 6'd0) ? 6'd1 : (vio_fm_idx > FM_MAX) ? FM_MAX : vio_fm_idx;
            amp       <= vio_amp;
            mode      <= vio_mode;
            source    <= vio_source;
            hold      <= vio_hold;
            noise_idx <= vio_noise;
            if (key_valid && key_code == 4'hD) mon_sel <= mon_sel + 2'd1;   // the monitor stays on the keypad
        end else begin
            if (key_valid) begin
                case (key_code)
                    4'h1: fc_idx <= (fc_up > {1'b0, FC_MAX}) ? FC_MAX : fc_up[6:0];
                    4'h4: fc_idx <= (fc_idx > st_fc) ? fc_idx - st_fc : 7'd1;
                    4'h2: beta_q <= (b_up > 8'd127) ? 7'd127 : b_up[6:0];
                    4'h5: beta_q <= (beta_q > st_b) ? beta_q - st_b : 7'd0;
                    4'h3: fm_idx <= (fm_up > {1'b0, FM_MAX}) ? FM_MAX : fm_up[5:0];
                    4'h6: fm_idx <= (fm_idx > st_fm) ? fm_idx - st_fm : 6'd1;
                    4'hA: amp    <= (a_up > 7'd63) ? 6'd63 : a_up[5:0];
                    4'hB: amp    <= (amp > st_a) ? amp - st_a : 6'd0;
                    4'h9: noise_idx <= (n_up > 6'd31) ? 5'd31 : n_up[4:0];         // more noise
                    4'hE: noise_idx <= (noise_idx > st_n) ? noise_idx - st_n : 5'd0; // less noise
                    4'h7: source <= ~source;
                    4'h8: mode   <= mode + 2'd1;
                    4'hC: hold   <= ~hold;
                    4'h0: begin
                        fc_idx <= DEF_FC;  beta_q <= DEF_BETA; fm_idx <= DEF_FM; amp <= DEF_AMP; noise_idx <= 5'd0;
                        mode <= 2'd0; source <= 1'b0; coarse <= 1'b0; mon_sel <= 2'd0;
                    end
                    4'hF: coarse  <= ~coarse;
                    4'hD: mon_sel <= mon_sel + 2'd1;
                    default: ;
                endcase
            end
            // board buttons (same semantics as the keypad)
            if (btn_fc_up) fc_idx <= (fc_up > {1'b0, FC_MAX}) ? FC_MAX : fc_up[6:0];
            if (btn_fc_dn) fc_idx <= (fc_idx > st_fc) ? fc_idx - st_fc : 7'd1;
            if (btn_mode)  mode   <= mode + 2'd1;
            if (btn_hold)  hold   <= ~hold;
        end
    end

    // ---- derived constants: three registered steps ---------------------------
    wire [6:0]  b_pm = (beta_q > PM_BETA_MAX) ? PM_BETA_MAX : beta_q;
    wire [6:0]  b_am = (beta_q > AM_BETA_MAX) ? AM_BETA_MAX : beta_q;

    // step 1: frequency control words
    wire [30:0] fcw_c_w = fc_idx * FCW_PER_100HZ;          //  7 x 24 -> 31 bits
    wire [28:0] fcw_m_w = fm_idx * FCW_PER_50HZ;           //  6 x 23 -> 29 bits
    // step 2: products with beta (uses the registered fcw_m)
    wire [35:0] kdev_w  = beta_q * fcw_m[28:0];            //  7 x 29 -> 36 bits (beta is Q4.3)
    wire [33:0] kpm_w   = b_pm * KPM_UNIT;                 //  7 x 27 (<= 16 * 85445659 < 2^31)
    wire [24:0] dam_w   = b_am * AM_D_UNIT;                //  7 x 18 -> 25 bits
    reg  [18:0] d_am;

    reg  [25:0] div_den_prev;
    always @(posedge clk) begin
        // step 1
        fcw_c <= {1'b0, fcw_c_w};
        fcw_m <= {3'b0, fcw_m_w};
        // step 2
        kdev  <= kdev_w[34:3];                             // / 8  (fits: Df < 50 kHz for all settings)
        kpm   <= kpm_w[30:0];
        mu_q  <= {b_am[3:0], 12'd0};                       // min(beta,1) * 32768
        d_am  <= dam_w[24:6];
        // step 3: divisor of the receiver gain
        case (mode)
            2'd0:    div_den <= kdev[31:8];                // FM : full-scale deviation per sample, Z = 24 units
            2'd1:    div_den <= {3'd0, kpm[30:8]};         // PM : full-scale phase deviation, Z = 24 units
            2'd2:    div_den <= {7'd0, d_am};              // AM : K * mu * 2^14
            default: div_den <= 26'd0;                     // bypass: no demodulation
        endcase
        div_den_prev   <= div_den;
        params_changed <= (div_den != div_den_prev) & ~rst;
    end
endmodule
`default_nettype wire
