`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  fm_dsp_core.v -- one complete radio link per audio sample, built around
//                   ONE time-shared CORDIC engine
//
//      modulating signal m --> TRANSMITTER --> CHANNEL --> RECEIVER --> m_hat
//                              (CORDIC,        (+ noise)   (CORDIC,
//                               rotation)                   vectoring)
//
//  At 50 kS/s there are 2000 clocks per sample and an 18-iteration CORDIC
//  needs 19, so one folded engine is used three times per sample:
//
//    job 1  rotation   sin(phi_m)             -> internal test tone
//    job 2  rotation   cos/sin(theta)         -> carrier I/Q  (the transmitter)
//    job 3  vectoring  atan2(Q,I), |I+jQ|     -> phase / envelope detector
//                                                (the receiver)
//
//  Transmitter (m = modulating signal, Q15):
//    FM     theta[n] = theta[n-1] + fcw_c + kdev*m[n]     frequency follows m
//    PM     theta[n] = phi_c[n]   + kpm*m[n]              phase follows m
//    AM     tx       = cos(phi_c[n]) * (1 + mu*m[n]) / 2  amplitude follows m
//    BYPASS tx       = m[n]                               base-band reference
//  Channel: independent Gaussian noise is added to both quadratures
//    rx_i = tx_i + n_i ,  rx_q = tx_q + n_q                (awgn_gen)
//  Receiver (vectoring CORDIC on the NOISY I/Q):
//    FM     raw = theta_hat[n] - theta_hat[n-1] - fcw_c
//    PM     raw = theta_hat[n] - phi_c[n]
//    AM     raw = |rx| - carrier level
//    m_hat_raw = raw * gain_recip   (gain_recip = 2^39 / D from recip_divider)
//  Audio filter: the SAME low-pass filter runs on m (the reference) and on
//  m_hat_raw (the receiver output), so that both are band-limited and delayed
//  identically and can be compared sample by sample.
//
//  Every multiplication is registered on both sides and at most 25 x 18 bits,
//  i.e. one DSP48E1 with a full clock period; wide products are assembled
//  from two partial products in the following state.
//  Bit-exact with scripts/cordic_model.py (class FMCore).
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
    input  wire        [4:0]  noise_idx,    // channel noise level, 0 = off
    input  wire        [31:0] fcw_c,
    input  wire        [31:0] fcw_m,
    input  wire        [31:0] kdev,
    input  wire        [30:0] kpm,
    input  wire        [15:0] mu_q,
    input  wire        [31:0] gain_recip,
    // results, all valid together when out_valid pulses
    output reg                out_valid,
    output reg  signed [15:0] m_out,        // reference: modulating signal after the audio filter
    output reg  signed [15:0] r_out,        // channel signal: (transmitted + noise) / 2, in-phase
    output reg  signed [15:0] mhat_out,     // recovered audio after the audio filter
    output reg  signed [15:0] s_out,        // transmitted signal before the channel
    output reg  signed [15:0] tone_out,     // internal tone (before gain)
    output wire               cordic_busy
);
    // CORDIC start vector: (32767 << 4) / K,  K = 1.6467602581 (N >= 16)
    localparam signed [W-1:0] X0        = 318366;
    // vectoring magnitude of a half-scale envelope: K * 16384
    localparam signed [24:0]  AM_OFFSET = 25'sd26981;

    localparam [1:0] MODE_FM = 2'd0, MODE_PM = 2'd1, MODE_AM = 2'd2, MODE_BYP = 2'd3;

    localparam [4:0] S_IDLE    = 5'd0,
                     S_TONE_W  = 5'd1,
                     S_SRC     = 5'd2,
                     S_GAIN    = 5'd3,
                     S_SAT     = 5'd4,
                     S_PHMUL   = 5'd5,
                     S_PHSUM   = 5'd6,
                     S_PHUPD   = 5'd7,
                     S_CAR_W   = 5'd8,
                     S_AMMUL   = 5'd9,
                     S_OUTSEL  = 5'd10,
                     S_CHAN    = 5'd11,
                     S_DEM_GO  = 5'd12,
                     S_DEM_W   = 5'd13,
                     S_DEM_R   = 5'd14,
                     S_DEM_MUL = 5'd15,
                     S_DEM_SUM = 5'd16,
                     S_DEM_FIN = 5'd17,
                     S_LPF_GO  = 5'd18,
                     S_LPF_W   = 5'd19,
                     S_OUT     = 5'd20;

    reg  [4:0]          st;

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
    // the channel noise source (runs in parallel with jobs 1 and 2)
    // ------------------------------------------------------------------
    wire               n_done;
    wire signed [18:0] n_i, n_q;
    reg                n_ready;
    awgn_gen u_awgn (
        .clk(clk), .rst(rst), .start(in_valid && (st == S_IDLE)), .noise_idx(noise_idx),
        .done(n_done), .ni(n_i), .nq(n_q)
    );

    // ------------------------------------------------------------------
    // audio filters: reference path and receiver path
    // ------------------------------------------------------------------
    reg                lpf_en;
    reg  signed [19:0] mhat_raw;
    wire               lpf_valid, lpf_valid_ref;
    wire signed [15:0] mhat_f, mref_f;
    reg  signed [15:0] m_r;
    audio_lpf #(.IN_W(20)) u_lpf_ref (.clk(clk), .rst(rst), .en(lpf_en), .x({{4{m_r[15]}}, m_r}), .valid(lpf_valid_ref), .y(mref_f));
    audio_lpf #(.IN_W(20)) u_lpf_rx  (.clk(clk), .rst(rst), .en(lpf_en), .x(mhat_raw),            .valid(lpf_valid),     .y(mhat_f));

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------
    // (v + 8) >>> 4, W-bit engine value -> Q15 (fits by construction for rotation results)
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

    function signed [19:0] sat20;
        input signed [39:0] v;
        begin
            if (v > 40'sd524287)       sat20 = 20'sd524287;
            else if (v < -40'sd524288) sat20 = -20'sd524288;
            else                       sat20 = v[19:0];
        end
    endfunction

    // ------------------------------------------------------------------
    // datapath registers
    // ------------------------------------------------------------------
    reg  signed [15:0]  x_mic_r, tone_r, src_r, i_r, q_r, s_r, env_r, r_r16;
    reg  signed [22:0]  gain_p;                    // 16 x 7
    reg         [31:0]  phi_m, phi_c, theta;
    reg  signed [33:0]  fm_lo;                     // 18 x 16 partial products
    reg  signed [31:0]  fm_hi;
    reg  signed [33:0]  pm_lo;
    reg  signed [30:0]  pm_hi;
    reg  signed [48:0]  p_fm, p_pm;
    reg  signed [32:0]  p_am;                      // 17 x 16
    reg  signed [31:0]  iam_p, qam_p;              // 16 x 16
    reg  signed [19:0]  rx_i, rx_q;                // received I/Q (signal + noise)
    reg         [Z-1:0] theta_hat, theta_hat_prev;
    reg  signed [W-1:0] mag_r;
    reg  signed [Z:0]   raw_r;                     // raw detector output
    reg  signed [Z+18:0] dem_lo;                   // 25 x 18
    reg  signed [Z+16:0] dem_hi;                   // 25 x 16
    reg  signed [Z+33:0] p_dem;

    // partial-product operands
    wire signed [17:0] kdev_lo = {1'b0, kdev[16:0]};
    wire signed [15:0] kdev_hi = {1'b0, kdev[31:17]};
    wire signed [17:0] kpm_lo  = {1'b0, kpm[16:0]};
    wire signed [14:0] kpm_hi  = {1'b0, kpm[30:17]};
    wire signed [16:0] mu_s    = {1'b0, mu_q};
    wire signed [17:0] g_lo    = {1'b0, gain_recip[16:0]};
    wire signed [15:0] g_hi    = {1'b0, gain_recip[31:17]};

    // combinational pieces of the phase update
    wire        [31:0] phi_c_nx = phi_c + fcw_c;
    wire        [31:0] dphi_fm  = p_fm[46:15];                 // (kdev * m) >>> 15, modulo 2^32
    wire        [31:0] dphi_pm  = p_pm[46:15];
    wire signed [16:0] env_hi   = p_am[32:16];                 // (mu * m) >>> 16
    wire signed [15:0] env_nx   = sat16($signed({{23{env_hi[16]}}, env_hi}) + 40'sd16384);
    wire        [31:0] phi_c_fm = phi_c_nx + dphi_fm;
    wire        [31:0] theta_nx = (mode == MODE_FM) ? phi_c_fm :
                                  (mode == MODE_PM) ? (phi_c_nx + dphi_pm) : phi_c_nx;
    wire signed [15:0] i_am     = iam_p[30:15];                // (I * env) >>> 15, |.| <= 32767
    wire signed [15:0] q_am     = qam_p[30:15];
    // what the transmitter puts on the wire
    wire signed [15:0] tx_i     = (mode == MODE_AM) ? i_am : (mode == MODE_BYP) ? m_r : i_r;
    wire signed [15:0] tx_q     = (mode == MODE_AM) ? q_am : q_r;
    // vectoring magnitude -> Q15 scale, rounded (can exceed 16 bits when noise is added)
    wire signed [W-1:0] mag_p8  = mag_r + 8;
    wire signed [24:0]  mag20   = {{5{1'b0}}, mag_p8[W-1:4]};
    wire        [Z-1:0] dth     = theta_hat - theta_hat_prev;
    wire        [Z-1:0] r_fm    = dth - fcw_c[31:32-Z];
    wire        [Z-1:0] r_pm    = theta_hat - phi_c[31:32-Z];
    wire signed [Z+33:0] dem_sh = p_dem >>> 24;

    always @(posedge clk) begin
        c_start   <= 1'b0;
        out_valid <= 1'b0;
        lpf_en    <= 1'b0;
        if (rst) begin
            st             <= S_IDLE;
            n_ready        <= 1'b0;
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
            i_r <= 16'sd0; q_r <= 16'sd0; s_r <= 16'sd0; env_r <= 16'sd0; r_r16 <= 16'sd0;
            gain_p <= 23'sd0;
            fm_lo <= 34'sd0; fm_hi <= 32'sd0; pm_lo <= 34'sd0; pm_hi <= 31'sd0;
            p_fm <= 49'sd0; p_pm <= 49'sd0; p_am <= 33'sd0; iam_p <= 32'sd0; qam_p <= 32'sd0;
            rx_i <= 20'sd0; rx_q <= 20'sd0; mhat_raw <= 20'sd0;
            mag_r <= {W{1'b0}}; raw_r <= {(Z+1){1'b0}};
            dem_lo <= {(Z+19){1'b0}}; dem_hi <= {(Z+17){1'b0}}; p_dem <= {(Z+34){1'b0}};
            m_out <= 16'sd0; r_out <= 16'sd0; mhat_out <= 16'sd0; s_out <= 16'sd0; tone_out <= 16'sd0;
        end else begin
            if (n_done) n_ready <= 1'b1;
            case (st)
                // ---------------- job 1: internal tone -----------------------
                S_IDLE: if (in_valid) begin
                    n_ready <= 1'b0;                              // awgn_gen starts on the same pulse
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
                // ---------------- transmitter: phase / envelope ---------------
                S_PHMUL: begin
                    fm_lo <= kdev_lo * m_r;
                    fm_hi <= kdev_hi * m_r;
                    pm_lo <= kpm_lo  * m_r;
                    pm_hi <= kpm_hi  * m_r;
                    p_am  <= mu_s    * m_r;
                    st    <= S_PHSUM;
                end
                S_PHSUM: begin
                    p_fm <= ($signed({{17{fm_hi[31]}}, fm_hi}) <<< 17) + $signed({{15{fm_lo[33]}}, fm_lo});
                    p_pm <= ($signed({{18{pm_hi[30]}}, pm_hi}) <<< 17) + $signed({{15{pm_lo[33]}}, pm_lo});
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
                    s_r <= tx_i;                                 // transmitted signal
                    st  <= S_CHAN;
                end
                // ---------------- channel: add the noise -----------------------
                S_CHAN: if (n_ready) begin
                    rx_i <= $signed({{4{tx_i[15]}}, tx_i}) + $signed({n_i[18], n_i});
                    rx_q <= $signed({{4{tx_q[15]}}, tx_q}) + $signed({n_q[18], n_q});
                    st   <= S_DEM_GO;
                end
                // ---------------- job 3: receiver -------------------------------
                S_DEM_GO: begin
                    r_r16   <= sat16($signed({{21{rx_i[19]}}, rx_i[19:1]}));   // half scale: headroom for the noise
                    c_x     <= {rx_i, 4'b0000};                  // W = 24 = 20 + 4
                    c_y     <= {rx_q, 4'b0000};
                    c_start <= 1'b1;
                    c_vec   <= 1'b1;
                    st      <= S_DEM_W;
                end
                S_DEM_W: if (c_done) begin
                    theta_hat <= c_zo;                           // atan2(rx_q, rx_i)
                    mag_r     <= c_xo;                           // K * |rx_i + j rx_q|
                    st        <= S_DEM_R;
                end
                S_DEM_R: begin
                    case (mode)
                        MODE_FM: raw_r <= $signed({r_fm[Z-1], r_fm});
                        MODE_PM: raw_r <= $signed({r_pm[Z-1], r_pm});
                        MODE_AM: raw_r <= mag20 - AM_OFFSET;
                        default: raw_r <= {(Z+1){1'b0}};
                    endcase
                    theta_hat_prev <= theta_hat;
                    st             <= S_DEM_MUL;
                end
                S_DEM_MUL: begin
                    dem_lo <= raw_r * g_lo;
                    dem_hi <= raw_r * g_hi;
                    st     <= S_DEM_SUM;
                end
                S_DEM_SUM: begin
                    p_dem <= ($signed({{17{dem_hi[Z+16]}}, dem_hi}) <<< 17) + $signed({{15{dem_lo[Z+18]}}, dem_lo});
                    st    <= S_DEM_FIN;
                end
                S_DEM_FIN: begin
                    mhat_raw <= (mode == MODE_BYP) ? rx_i : sat20(dem_sh[39:0]);
                    st       <= S_LPF_GO;
                end
                // ---------------- audio filters, then publish -------------------
                S_LPF_GO: begin
                    lpf_en <= 1'b1;
                    st     <= S_LPF_W;
                end
                S_LPF_W: if (lpf_valid) st <= S_OUT;
                S_OUT: begin
                    m_out     <= mref_f;
                    mhat_out  <= mhat_f;
                    r_out     <= r_r16;
                    s_out     <= s_r;
                    tone_out  <= tone_r;
                    out_valid <= 1'b1;
                    st        <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
