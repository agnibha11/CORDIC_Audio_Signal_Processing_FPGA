`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  fm_dsp_core.v -- per-sample DSP sequencer (FSMD) around ONE CORDIC engine
//
//  At 50 kS/s there are 2000 clocks per sample, and an 18-iteration CORDIC
//  needs 19.  Instead of three unrolled CORDIC pipelines, one folded engine
//  is time-shared by a small sequencer that runs three jobs per sample:
//
//    job 1  rotation   sin(phi_m)                 -> internal test tone
//    job 2  rotation   cos/sin(theta)             -> carrier I/Q  (the modulated signal)
//    job 3  vectoring  atan2(Q,I), |I+jQ|         -> demodulator (phase / envelope detector)
//
//  Modulation (m = modulating signal, Q15, A = amplitude):
//    FM     theta[n] = theta[n-1] + fcw_c + kdev*m[n]        instantaneous f = f_c + Df*m
//    PM     theta[n] = phi_c[n]   + kpm*m[n]                 phase = w_c n + beta*m
//    AM     s[n]     = cos(phi_c[n]) * (1 + mu*m[n]) / 2
//    BYPASS s[n]     = m[n]
//  Demodulation (vectoring CORDIC on the same I/Q):
//    FM     m_hat ~ (theta_hat[n] - theta_hat[n-1] - fcw_c) / kdev
//    PM     m_hat ~ (theta_hat[n] - phi_c[n]) / kpm
//    AM     m_hat ~ (|I+jQ|/K - 1/2) / (mu/2)
//  The division is a multiplication by `gain_recip` = 2^39 / D supplied by
//  recip_divider (D selected by mode in param_controller).
//
//  Whole sequence: 3 x (N+2) + 10 = 70 clocks per sample, i.e. the CORDIC is
//  busy 2.9 % of the time -- the same engine could serve ~30 channels.
// ============================================================================
module fm_dsp_core #(
    parameter integer W = 24,
    parameter integer Z = 24,
    parameter integer N = 18
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire signed [15:0] x_mic,        // DC-free microphone sample, Q15
    // parameters (quasi-static)
    input  wire        [1:0]  mode,         // 0 FM, 1 PM, 2 AM, 3 bypass
    input  wire               source,       // 0 microphone, 1 internal tone
    input  wire        [5:0]  amp,          // Q2.4 gain on the modulating signal
    input  wire        [31:0] fcw_c,
    input  wire        [31:0] fcw_m,
    input  wire        [31:0] kdev,
    input  wire        [33:0] kpm,
    input  wire        [18:0] mu_q,
    input  wire        [31:0] gain_recip,
    // results, all valid together when out_valid pulses
    output reg                out_valid,
    output reg  signed [15:0] m_out,        // modulating signal actually applied
    output reg  signed [15:0] s_out,        // modulated output -> DAC A
    output reg  signed [15:0] mhat_out,     // demodulated signal
    output reg  signed [15:0] tone_out,     // internal tone (before gain)
    output reg  signed [15:0] q_out,        // carrier quadrature component
    output wire        [Z-1:0] theta_hat_out,
    output wire               cordic_busy
);
    // CORDIC start vector: (32767 << 4) / K,  K = 1.6467602581 (N >= 16)
    localparam signed [W-1:0] X0        = 318366;
    // vectoring magnitude of a half-scale envelope: K * 16384
    localparam signed [17:0]  AM_OFFSET = 18'sd26981;

    localparam [1:0] MODE_FM = 2'd0, MODE_PM = 2'd1, MODE_AM = 2'd2, MODE_BYP = 2'd3;

    localparam [3:0] S_IDLE     = 4'd0,
                     S_TONE_W   = 4'd1,
                     S_SRC      = 4'd2,
                     S_GAIN     = 4'd3,
                     S_SAT      = 4'd4,
                     S_PHMUL    = 4'd5,
                     S_PHUPD    = 4'd6,
                     S_CAR_W    = 4'd7,
                     S_AMMUL    = 4'd8,
                     S_OUTSEL   = 4'd9,
                     S_DEM_W    = 4'd10,
                     S_DEM_R    = 4'd11,
                     S_DEM_MUL  = 4'd12,
                     S_DEM_FIN  = 4'd13;

    // ------------------------------------------------------------------
    // the shared CORDIC engine
    // ------------------------------------------------------------------
    reg                 c_start, c_vec;
    reg  signed [W-1:0] c_x, c_y;
    reg         [Z-1:0] c_z;
    wire                c_done;
    wire signed [W-1:0] c_xo, c_yo;
    wire        [Z-1:0] c_zo;

    cordic_engine #(.W(W), .Z(Z), .N(N)) u_cordic (
        .clk(clk), .rst(rst), .start(c_start), .vectoring(c_vec),
        .x_in(c_x), .y_in(c_y), .z_in(c_z),
        .busy(cordic_busy), .done(c_done),
        .x_out(c_xo), .y_out(c_yo), .z_out(c_zo)
    );

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------
    // (v + 8) >>> 4, W-bit engine value -> Q15 (fits by construction)
    function signed [15:0] rnd16;
        input signed [W-1:0] v;
        reg   signed [W-1:0] t;
        begin
            t     = v + 8;
            rnd16 = t[19:4];
        end
    endfunction

    function signed [15:0] sat16;
        input signed [39:0] v;
        begin
            if (v > 40'sd32767)       sat16 = 16'sd32767;
            else if (v < -40'sd32768) sat16 = -16'sd32768;
            else                      sat16 = v[15:0];
        end
    endfunction

    // ------------------------------------------------------------------
    // datapath registers
    // ------------------------------------------------------------------
    reg  [3:0]          st;
    reg  signed [15:0]  x_mic_r, tone_r, src_r, m_r, i_r, q_r, s_r, env_r;
    reg  signed [22:0]  gain_p;                // 16 x 7
    reg         [31:0]  phi_m, phi_c, theta;
    reg  signed [48:0]  p_fm;                  // 33 x 16
    reg  signed [50:0]  p_pm;                  // 35 x 16
    reg  signed [35:0]  p_am;                  // 20 x 16
    reg  signed [31:0]  iam_p, qam_p;          // 16 x 16
    reg         [Z-1:0] theta_hat, theta_hat_prev;
    reg  signed [W-1:0] mag_r;
    reg  signed [Z:0]   r_r;                   // raw demodulator output
    reg  signed [Z+33:0] p_dem;                // 25 x 33

    assign theta_hat_out = theta_hat;

    // combinational pieces of the phase update
    wire        [31:0] phi_c_nx = phi_c + fcw_c;
    wire        [31:0] dphi_fm  = p_fm[46:15];                 // (kdev * m) >>> 15, modulo 2^32
    wire        [31:0] dphi_pm  = p_pm[46:15];
    wire signed [19:0] env_hi   = p_am[35:16];                 // (mu * m) >>> 16
    wire signed [15:0] env_nx   = sat16($signed({{20{env_hi[19]}}, env_hi}) + 40'sd16384);
    wire        [31:0] phi_c_fm = phi_c_nx + dphi_fm;
    wire        [31:0] theta_nx = (mode == MODE_FM) ? phi_c_fm :
                                  (mode == MODE_PM) ? (phi_c_nx + dphi_pm) : phi_c_nx;
    wire signed [15:0] i_am     = iam_p[30:15];                // (I * env) >>> 15, |.| <= 32767
    wire signed [15:0] q_am     = qam_p[30:15];
    // vectoring magnitude -> Q15 scale (17-bit unsigned), rounded
    wire signed [W-1:0] mag_p8  = mag_r + 8;
    wire        [16:0]  mag16   = mag_p8[20:4];
    wire        [Z-1:0] dth     = theta_hat - theta_hat_prev;
    wire        [Z-1:0] r_fm    = dth - fcw_c[31:32-Z];
    wire        [Z-1:0] r_pm    = theta_hat - phi_c[31:32-Z];
    wire signed [Z+33:0] dem_sh = p_dem >>> 24;

    always @(posedge clk) begin
        c_start   <= 1'b0;
        out_valid <= 1'b0;
        if (rst) begin
            st             <= S_IDLE;
            c_vec          <= 1'b0;
            c_x            <= {W{1'b0}};
            c_y            <= {W{1'b0}};
            c_z            <= {Z{1'b0}};
            phi_m          <= 32'd0;
            phi_c          <= 32'd0;
            theta          <= 32'd0;
            theta_hat      <= {Z{1'b0}};
            theta_hat_prev <= {Z{1'b0}};
            x_mic_r <= 16'sd0; tone_r <= 16'sd0; src_r <= 16'sd0; m_r <= 16'sd0;
            i_r <= 16'sd0; q_r <= 16'sd0; s_r <= 16'sd0; env_r <= 16'sd0;
            gain_p <= 23'sd0;
            p_fm <= 49'sd0; p_pm <= 51'sd0; p_am <= 36'sd0; iam_p <= 32'sd0; qam_p <= 32'sd0;
            mag_r <= {W{1'b0}}; r_r <= {(Z+1){1'b0}}; p_dem <= {(Z+34){1'b0}};
            m_out <= 16'sd0; s_out <= 16'sd0; mhat_out <= 16'sd0; tone_out <= 16'sd0; q_out <= 16'sd0;
        end else begin
            case (st)
                // ---------------- job 1: internal tone -----------------------
                S_IDLE: if (in_valid) begin
                    x_mic_r <= x_mic;
                    c_start <= 1'b1;
                    c_vec   <= 1'b0;
                    c_x     <= X0;
                    c_y     <= {W{1'b0}};
                    c_z     <= phi_m[31:32-Z];
                    phi_m   <= phi_m + fcw_m;
                    st      <= S_TONE_W;
                end
                S_TONE_W: if (c_done) begin
                    tone_r <= rnd16(c_yo);                       // sin(phi_m)
                    st     <= S_SRC;
                end
                // ---------------- modulating signal --------------------------
                S_SRC: begin
                    src_r <= source ? tone_r : x_mic_r;
                    st    <= S_GAIN;
                end
                S_GAIN: begin
                    gain_p <= src_r * $signed({1'b0, amp});
                    st     <= S_SAT;
                end
                S_SAT: begin
                    m_r <= sat16($signed({{17{gain_p[22]}}, gain_p}) >>> 4);
                    st  <= S_PHMUL;
                end
                // ---------------- phase / envelope update --------------------
                S_PHMUL: begin
                    p_fm <= $signed({1'b0, kdev}) * m_r;
                    p_pm <= $signed({1'b0, kpm})  * m_r;
                    p_am <= $signed({1'b0, mu_q}) * m_r;
                    st   <= S_PHUPD;
                end
                S_PHUPD: begin
                    phi_c   <= (mode == MODE_FM) ? phi_c_fm : phi_c_nx;
                    theta   <= theta_nx;
                    env_r   <= env_nx;
                    c_start <= 1'b1;                             // job 2: carrier
                    c_vec   <= 1'b0;
                    c_x     <= X0;
                    c_y     <= {W{1'b0}};
                    c_z     <= theta_nx[31:32-Z];
                    st      <= S_CAR_W;
                end
                S_CAR_W: if (c_done) begin
                    i_r <= rnd16(c_xo);                          // cos(theta)
                    q_r <= rnd16(c_yo);                          // sin(theta)
                    st  <= S_AMMUL;
                end
                S_AMMUL: begin
                    iam_p <= i_r * env_r;
                    qam_p <= q_r * env_r;
                    st    <= S_OUTSEL;
                end
                S_OUTSEL: begin
                    case (mode)
                        MODE_AM: begin s_r <= i_am; c_x <= {{(W-20){i_am[15]}}, i_am, 4'b0000}; c_y <= {{(W-20){q_am[15]}}, q_am, 4'b0000}; end
                        MODE_BYP:begin s_r <= m_r;  c_x <= {{(W-20){i_r[15]}},  i_r,  4'b0000}; c_y <= {{(W-20){q_r[15]}},  q_r,  4'b0000}; end
                        default: begin s_r <= i_r;  c_x <= {{(W-20){i_r[15]}},  i_r,  4'b0000}; c_y <= {{(W-20){q_r[15]}},  q_r,  4'b0000}; end
                    endcase
                    c_start <= 1'b1;                             // job 3: vectoring on the same I/Q
                    c_vec   <= 1'b1;
                    st      <= S_DEM_W;
                end
                // ---------------- job 3: demodulator --------------------------
                S_DEM_W: if (c_done) begin
                    theta_hat <= c_zo;                           // atan2(Q, I)
                    mag_r     <= c_xo;                           // K * |I + jQ|
                    st        <= S_DEM_R;
                end
                S_DEM_R: begin
                    case (mode)
                        MODE_FM: r_r <= $signed({r_fm[Z-1], r_fm});
                        MODE_PM: r_r <= $signed({r_pm[Z-1], r_pm});
                        MODE_AM: r_r <= $signed({{(Z-17){1'b0}}, mag16}) - $signed({{(Z-17){AM_OFFSET[17]}}, AM_OFFSET});
                        default: r_r <= {(Z+1){1'b0}};
                    endcase
                    theta_hat_prev <= theta_hat;
                    st             <= S_DEM_MUL;
                end
                S_DEM_MUL: begin
                    p_dem <= r_r * $signed({1'b0, gain_recip});
                    st    <= S_DEM_FIN;
                end
                S_DEM_FIN: begin
                    mhat_out  <= (mode == MODE_BYP) ? m_r : sat16(dem_sh[39:0]);
                    m_out     <= m_r;
                    s_out     <= s_r;
                    tone_out  <= tone_r;
                    q_out     <= (mode == MODE_AM) ? q_am : q_r;
                    out_valid <= 1'b1;
                    st        <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
