`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_fm_dsp_core.v -- the complete radio link, BIT-EXACT against the Python
//                      reference model
//
//  dsp_vectors.mem holds 2900 consecutive audio samples in ten parameter
//  segments (FM / PM / AM / bypass, tone and microphone source, channel noise
//  from off to C/N = 0 dB, extreme settings).  For every sample the five
//  outputs of the link -- reference audio, channel signal, recovered audio,
//  transmitted signal, tone -- must equal the model's to the last bit.
//  The DUT is the real parameter path: param_controller (driven through its
//  VIO override) -> recip_divider -> fm_dsp_core, wired as in
//  cordic_fm_system.  Since the analysis figures are computed with the same
//  model, this bench is what ties the published curves to the hardware.
//  Also measured: clocks per sample of the DSP sequence.
// ============================================================================
module tb_fm_dsp_core;
    localparam integer NV = 2900;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [6:0]  v_fc = 40, v_beta = 40;
    reg  [5:0]  v_fm = 8, v_amp = 16;
    reg  [1:0]  v_mode = 0;
    reg         v_src = 0;
    reg  [4:0]  v_noise = 0;
    reg         in_valid = 0;
    reg  signed [15:0] x_mic = 0;

    wire [6:0]  fc_idx, beta_q;
    wire [5:0]  fm_idx, amp;
    wire [4:0]  noise_idx;
    wire [1:0]  mode, mon_sel;
    wire        source, hold, coarse, params_changed;
    wire [31:0] fcw_c, fcw_m, kdev, gain_recip;
    wire [30:0] kpm;
    wire [15:0] mu_q;
    wire [25:0] div_den;
    param_controller u_par (
        .clk(clk), .rst(rst), .key_valid(1'b0), .key_code(4'd0),
        .btn_fc_up(1'b0), .btn_fc_dn(1'b0), .btn_mode(1'b0), .btn_hold(1'b0),
        .vio_override(1'b1), .vio_fc_idx(v_fc), .vio_beta_q(v_beta), .vio_fm_idx(v_fm), .vio_amp(v_amp),
        .vio_mode(v_mode), .vio_source(v_src), .vio_hold(1'b0), .vio_noise(v_noise),
        .fc_idx(fc_idx), .beta_q(beta_q), .fm_idx(fm_idx), .amp(amp), .noise_idx(noise_idx), .mode(mode),
        .source(source), .hold(hold), .coarse(coarse), .mon_sel(mon_sel),
        .fcw_c(fcw_c), .fcw_m(fcw_m), .kdev(kdev), .kpm(kpm), .mu_q(mu_q),
        .div_den(div_den), .params_changed(params_changed)
    );
    wire div_busy, div_done;
    reg  div_pending;
    wire div_start = div_pending & ~div_busy & ~div_done;
    always @(posedge clk) begin
        if (rst)                 div_pending <= 1'b1;
        else if (params_changed) div_pending <= 1'b1;
        else if (div_start)      div_pending <= 1'b0;
    end
    recip_divider #(.NUM_SHIFT(39), .DEN_W(26), .Q_W(32)) u_div (
        .clk(clk), .rst(rst), .start(div_start), .den(div_den), .busy(div_busy), .done(div_done), .quot(gain_recip));

    wire out_valid, cordic_busy;
    wire signed [15:0] m_o, r_o, mh_o, s_o, tone_o;
    fm_dsp_core dut (
        .clk(clk), .rst(rst), .in_valid(in_valid), .x_mic(x_mic),
        .mode(mode), .source(source), .amp(amp), .noise_idx(noise_idx),
        .fcw_c(fcw_c), .fcw_m(fcw_m), .kdev(kdev), .kpm(kpm), .mu_q(mu_q), .gain_recip(gain_recip),
        .out_valid(out_valid), .m_out(m_o), .r_out(r_o), .mhat_out(mh_o), .s_out(s_o), .tone_out(tone_o),
        .cordic_busy(cordic_busy)
    );

    integer checks = 0, errors = 0;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; if (errors <= 20) $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    reg [31:0] vec [0:NV*13-1];
    integer k, b, lat, lat_min, lat_max, busy_clks, bad_m, bad_r, bad_mh, bad_s, bad_t;
    always @(posedge clk) if (cordic_busy) busy_clks = busy_clks + 1;

    initial begin
        $readmemh("dsp_vectors.mem", vec);
        lat_min = 100000; lat_max = 0; bad_m = 0; bad_r = 0; bad_mh = 0; bad_s = 0; bad_t = 0;
        repeat (6) @(negedge clk); rst = 0;
        repeat (120) @(negedge clk);
        for (k = 0; k < NV; k = k + 1) begin
            b = 13 * k;
            if (vec[b][6:0] !== v_fc || vec[b+1][6:0] !== v_beta || vec[b+2][5:0] !== v_fm || vec[b+3][5:0] !== v_amp ||
                vec[b+4][1:0] !== v_mode || vec[b+5][0] !== v_src || vec[b+6][4:0] !== v_noise) begin
                v_fc = vec[b][6:0]; v_beta = vec[b+1][6:0]; v_fm = vec[b+2][5:0]; v_amp = vec[b+3][5:0];
                v_mode = vec[b+4][1:0]; v_src = vec[b+5][0]; v_noise = vec[b+6][4:0];
                repeat (120) @(negedge clk);            // constants (3 clocks) + reciprocal (42 clocks) settle
                $display("segment @ sample %0d: fc=%0d00 Hz beta_q=%0d fm_idx=%0d amp=%0d mode=%0d source=%0d noise_idx=%0d  (G=%0d)",
                         k, v_fc, v_beta, v_fm, v_amp, v_mode, v_src, v_noise, gain_recip);
            end
            x_mic = vec[b+7][15:0];
            busy_clks = 0;
            @(negedge clk); in_valid = 1; @(negedge clk); in_valid = 0;
            lat = 1;
            while (!out_valid) begin @(negedge clk); lat = lat + 1; end
            if (lat < lat_min) lat_min = lat; if (lat > lat_max) lat_max = lat;
            if (m_o    !== $signed(vec[b+8][15:0]))  bad_m  = bad_m + 1;
            if (r_o    !== $signed(vec[b+9][15:0]))  bad_r  = bad_r + 1;
            if (mh_o   !== $signed(vec[b+10][15:0])) bad_mh = bad_mh + 1;
            if (s_o    !== $signed(vec[b+11][15:0])) bad_s  = bad_s + 1;
            if (tone_o !== $signed(vec[b+12][15:0])) bad_t  = bad_t + 1;
            check(m_o    === $signed(vec[b+8][15:0]),  "reference audio bit-exact");
            check(r_o    === $signed(vec[b+9][15:0]),  "channel signal bit-exact");
            check(mh_o   === $signed(vec[b+10][15:0]), "recovered audio bit-exact");
            check(s_o    === $signed(vec[b+11][15:0]), "transmitted signal bit-exact");
            check(tone_o === $signed(vec[b+12][15:0]), "tone bit-exact");
            repeat (3) @(negedge clk);
        end
        $display("mismatches over %0d samples: reference %0d, channel %0d, recovered %0d, transmitted %0d, tone %0d", NV, bad_m, bad_r, bad_mh, bad_s, bad_t);
        $display("DSP sequence: %0d clocks per sample (min %0d, max %0d); CORDIC busy %0d clocks", lat_max, lat_min, lat_max, busy_clks);
        check(lat_min == lat_max, "deterministic sequence length");
        check(lat_max < 150, "sequence fits easily in a 2000-clock sample");
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
