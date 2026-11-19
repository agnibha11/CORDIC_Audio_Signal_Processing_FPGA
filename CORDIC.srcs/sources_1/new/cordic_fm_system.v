`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  cordic_fm_system.v -- board-independent integration of the whole design:
//                        a complete radio link on one chip
//
//   Pmod MIC -> mic_adc_spi -> audio_frontend -> +------------- fm_dsp_core --------------+
//                                                | TX (CORDIC) -> channel -> RX (CORDIC)  |
//   Pmod KYPD -> kypd_scanner -> param_controller| rotation      + noise     vectoring    |
//                                + recip_divider +----------------------------------------+
//                                                   |            |             |
//                                              m (reference)  r (channel)   m_hat (recovered)
//                                                   |            |             |
//             capture_scope_ram  <------------------+------------+-------------+--> fidelity_meter (SNR)
//                     |                                          |             |
//             vga_timing + vga_scope_render -> VGA          DAC-A (DA2)   monitor mux -> DAC-B (DA2)
//                                                                                    -> sd_dac -> Pmod AMP2
//
//  One sample period = CLK_PER_SAMPLE clocks (2000 = 50 kS/s).
// ============================================================================
module cordic_fm_system #(
    parameter integer CLK_PER_SAMPLE = 2000,
    parameter integer SCLK_DIV       = 20,
    parameter integer KYPD_SCAN_CLKS = 8192,
    parameter integer KYPD_DEBOUNCE  = 16,
    parameter integer KYPD_RPT_DELAY = 1500,
    parameter integer KYPD_RPT_RATE  = 300,
    parameter integer BTN_STABLE     = 1_000_000,
    parameter integer AUTO_TRIG      = 32768,
    parameter integer METER_WLOG     = 15,
    parameter integer CLIP_HOLD      = 25_000_000,
    parameter integer SD_DIV         = 16
)(
    input  wire        clk,
    input  wire        rst,
    // Pmod MIC (JC top row)
    output wire        adc_cs_n,
    output wire        adc_sclk,
    input  wire        adc_miso,          // synchronised
    // Pmod DA2 (JB top row)
    output wire        dac_sync_n,
    output wire        dac_dina,
    output wire        dac_dinb,
    output wire        dac_sclk,
    // Pmod AMP2 (JA top row)
    output wire        amp_ain,           // sigma-delta bit stream
    output wire        amp_gain,          // 1 = 6 dB, 0 = 12 dB
    output wire        amp_shutdown_n,    // 0 = amplifier off
    // Pmod KYPD (JD)
    input  wire [3:0]  kypd_row,          // synchronised
    output wire [3:0]  kypd_col,
    // board buttons and switches (synchronised, raw)
    input  wire        btn_u,
    input  wire        btn_l,
    input  wire        btn_r,
    input  wire        btn_c,
    input  wire [1:0]  sw_tbase,          // scope time base: 0 -> x1, 1 -> x2, 2/3 -> x4
    input  wire        sw_overlay_err,
    input  wire [1:0]  sw_spk_att,        // loudspeaker attenuation: 0 / 6 / 12 / 18 dB
    input  wire        sw_spk_loud,       // loudspeaker amplifier gain: 0 = 6 dB, 1 = 12 dB
    input  wire        sw_spk_mute,
    // VGA
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,
    // VIO override / read-back
    input  wire        vio_override,
    input  wire [6:0]  vio_fc_idx,
    input  wire [6:0]  vio_beta_q,
    input  wire [5:0]  vio_fm_idx,
    input  wire [5:0]  vio_amp,
    input  wire [1:0]  vio_mode,
    input  wire        vio_source,
    input  wire        vio_hold,
    input  wire [4:0]  vio_noise,
    input  wire [10:0] vio_rd_addr,
    output wire [47:0] vio_rd_data,
    // status
    output wire [6:0]  fc_idx,
    output wire [6:0]  beta_q,
    output wire [5:0]  fm_idx,
    output wire [5:0]  amp,
    output wire [4:0]  noise_idx,
    output wire [1:0]  mode,
    output wire        source,
    output wire        hold,
    output wire        coarse,
    output wire [1:0]  mon_sel,
    output wire        key_valid,
    output wire [3:0]  key_code,
    output wire        key_down,
    output wire        clip_sticky,
    output wire        recording,
    output wire        bank_disp,
    output wire        sample_tick,
    output wire [11:0] adc_code,
    output wire        out_valid,
    output wire signed [15:0] m_sample,      // original (reference) audio
    output wire signed [15:0] r_sample,      // channel signal (modulated + noise)
    output wire signed [15:0] mhat_sample,   // recovered audio
    output wire signed [15:0] mon_sample,    // what the loudspeaker / DAC-B play
    output wire [47:0] sum_sig,
    output wire [47:0] sum_err,
    output wire [15:0] peak_err,
    output wire [6:0]  snr_db,
    output wire [31:0] gain_recip,
    output wire [25:0] div_den,
    output wire        cordic_busy
);
    // ------------------------------------------------------------------
    // sample clock
    // ------------------------------------------------------------------
    reg [11:0] tick_cnt;
    reg        tick;
    always @(posedge clk) begin
        tick <= 1'b0;
        if (rst) begin
            tick_cnt <= 12'd0;
        end else if (tick_cnt == CLK_PER_SAMPLE - 1) begin
            tick_cnt <= 12'd0;
            tick     <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 12'd1;
        end
    end
    assign sample_tick = tick;

    // ------------------------------------------------------------------
    // ADC -> front end
    // ------------------------------------------------------------------
    wire        adc_valid;
    wire [11:0] adc_data;
    mic_adc_spi #(.SCLK_DIV(SCLK_DIV)) u_adc (
        .clk(clk), .rst(rst), .start(tick), .busy(), .valid(adc_valid), .data(adc_data),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_miso(adc_miso)
    );
    assign adc_code = adc_data;

    wire               fe_valid;
    wire signed [15:0] fe_audio;
    wire               fe_clip;
    audio_frontend u_fe (
        .clk(clk), .rst(rst), .in_valid(adc_valid), .adc_code(adc_data),
        .out_valid(fe_valid), .audio(fe_audio), .clip(fe_clip)
    );

    // ------------------------------------------------------------------
    // user interface
    // ------------------------------------------------------------------
    kypd_scanner #(
        .SCAN_CLKS(KYPD_SCAN_CLKS), .DEBOUNCE_SCANS(KYPD_DEBOUNCE),
        .REPEAT_DELAY(KYPD_RPT_DELAY), .REPEAT_RATE(KYPD_RPT_RATE)
    ) u_kypd (
        .clk(clk), .rst(rst), .row(kypd_row), .col(kypd_col),
        .key_valid(key_valid), .key_code(key_code), .key_down(key_down)
    );

    wire p_u, p_l, p_r, p_c;
    btn_debounce #(.STABLE_CLKS(BTN_STABLE)) u_db_u (.clk(clk), .rst(rst), .din(btn_u), .level(), .press(p_u));
    btn_debounce #(.STABLE_CLKS(BTN_STABLE)) u_db_l (.clk(clk), .rst(rst), .din(btn_l), .level(), .press(p_l));
    btn_debounce #(.STABLE_CLKS(BTN_STABLE)) u_db_r (.clk(clk), .rst(rst), .din(btn_r), .level(), .press(p_r));
    btn_debounce #(.STABLE_CLKS(BTN_STABLE)) u_db_c (.clk(clk), .rst(rst), .din(btn_c), .level(), .press(p_c));

    wire [31:0] fcw_c, fcw_m, kdev;
    wire [30:0] kpm;
    wire [15:0] mu_q;
    wire        params_changed;
    param_controller u_par (
        .clk(clk), .rst(rst),
        .key_valid(key_valid), .key_code(key_code),
        .btn_fc_up(p_r), .btn_fc_dn(p_l), .btn_mode(p_u), .btn_hold(p_c),
        .vio_override(vio_override), .vio_fc_idx(vio_fc_idx), .vio_beta_q(vio_beta_q),
        .vio_fm_idx(vio_fm_idx), .vio_amp(vio_amp), .vio_mode(vio_mode),
        .vio_source(vio_source), .vio_hold(vio_hold), .vio_noise(vio_noise),
        .fc_idx(fc_idx), .beta_q(beta_q), .fm_idx(fm_idx), .amp(amp), .noise_idx(noise_idx), .mode(mode),
        .source(source), .hold(hold), .coarse(coarse), .mon_sel(mon_sel),
        .fcw_c(fcw_c), .fcw_m(fcw_m), .kdev(kdev), .kpm(kpm), .mu_q(mu_q),
        .div_den(div_den), .params_changed(params_changed)
    );

    // receiver gain: compute the reciprocal once after reset and again
    // whenever the divisor changes (the parameters settle during reset, so
    // no `params_changed` pulse follows it -- hence the pending flag is SET
    // by reset)
    wire div_busy, div_done;
    reg  div_pending;
    wire div_start = div_pending & ~div_busy & ~div_done;
    always @(posedge clk) begin
        if (rst)                 div_pending <= 1'b1;
        else if (params_changed) div_pending <= 1'b1;
        else if (div_start)      div_pending <= 1'b0;
    end
    recip_divider #(.NUM_SHIFT(39), .DEN_W(26), .Q_W(32)) u_div (
        .clk(clk), .rst(rst), .start(div_start), .den(div_den),
        .busy(div_busy), .done(div_done), .quot(gain_recip)
    );

    // ------------------------------------------------------------------
    // the radio link: transmitter, channel, receiver
    // ------------------------------------------------------------------
    wire signed [15:0] s_sample, tone_sample;
    fm_dsp_core #(.W(24), .Z(24), .N(18)) u_dsp (
        .clk(clk), .rst(rst), .in_valid(fe_valid), .x_mic(fe_audio),
        .mode(mode), .source(source), .amp(amp), .noise_idx(noise_idx),
        .fcw_c(fcw_c), .fcw_m(fcw_m), .kdev(kdev), .kpm(kpm), .mu_q(mu_q), .gain_recip(gain_recip),
        .out_valid(out_valid), .m_out(m_sample), .r_out(r_sample), .mhat_out(mhat_sample),
        .s_out(s_sample), .tone_out(tone_sample), .cordic_busy(cordic_busy)
    );

    // ------------------------------------------------------------------
    // monitor: what the listener hears (loudspeaker and DAC-B)
    //   0 recovered audio   1 original audio   2 channel signal   3 error x4
    // ------------------------------------------------------------------
    wire signed [16:0] err_w  = m_sample - mhat_sample;
    wire signed [18:0] err_x4 = {err_w, 2'b00};
    wire signed [15:0] err_s  = (err_x4 > 19'sd32767)  ? 16'sd32767 :
                                (err_x4 < -19'sd32768) ? -16'sd32768 : err_x4[15:0];
    reg  signed [15:0] mon_r;
    always @(posedge clk) begin
        if (rst) mon_r <= 16'sd0;
        else case (mon_sel)
            2'd0:    mon_r <= mhat_sample;
            2'd1:    mon_r <= m_sample;
            2'd2:    mon_r <= r_sample;
            default: mon_r <= err_s;
        endcase
    end
    assign mon_sample = mon_r;

    // ------------------------------------------------------------------
    // Pmod DA2: channel A = channel signal, channel B = monitor
    // ------------------------------------------------------------------
    reg dac_go;
    always @(posedge clk) dac_go <= out_valid & ~rst;          // one clock later: mon_r is up to date
    wire [11:0] dac_a = {~r_sample[15], r_sample[14:4]};       // Q15 -> offset binary
    wire [11:0] dac_b = {~mon_r[15], mon_r[14:4]};
    da2_dac_spi #(.SCLK_DIV(SCLK_DIV)) u_dac (
        .clk(clk), .rst(rst), .start(dac_go), .data_a(dac_a), .data_b(dac_b),
        .busy(), .done(),
        .dac_sync_n(dac_sync_n), .dac_dina(dac_dina), .dac_dinb(dac_dinb), .dac_sclk(dac_sclk)
    );

    // ------------------------------------------------------------------
    // Pmod AMP2: sigma-delta bit stream of the monitor signal
    // ------------------------------------------------------------------
    wire signed [15:0] spk_sample = mon_r >>> sw_spk_att;            // digital volume: 6 dB per step
    sd_dac #(.DIV(SD_DIV)) u_sd (.clk(clk), .rst(rst), .sample(spk_sample), .bit_out(amp_ain));
    assign amp_gain       = ~sw_spk_loud;
    assign amp_shutdown_n = ~sw_spk_mute & ~rst;

    // ------------------------------------------------------------------
    // analysis: fidelity meter and clip indicator
    // ------------------------------------------------------------------
    fidelity_meter #(.WLOG(METER_WLOG)) u_meter (
        .clk(clk), .rst(rst), .in_valid(out_valid), .m(m_sample), .m_hat(mhat_sample),
        .sum_sig(sum_sig), .sum_err(sum_err), .peak_err(peak_err), .snr_db(snr_db), .window_done()
    );

    reg [24:0] clip_cnt;
    always @(posedge clk) begin
        if (rst)                        clip_cnt <= 25'd0;
        else if (fe_valid && fe_clip)   clip_cnt <= CLIP_HOLD;
        else if (clip_cnt != 25'd0)     clip_cnt <= clip_cnt - 25'd1;
    end
    assign clip_sticky = (clip_cnt != 25'd0);

    // ------------------------------------------------------------------
    // storage + VGA scope
    // ------------------------------------------------------------------
    wire        pix_en, active, hs_n, vs_n, vblank, frame_start;
    wire [9:0]  h, v;
    vga_timing u_vt (
        .clk(clk), .rst(rst), .pix_en(pix_en), .h(h), .v(v), .active(active),
        .hs_n(hs_n), .vs_n(vs_n), .vblank(vblank), .frame_start(frame_start)
    );

    // bank swap moment: first line of vertical blanking
    reg vblank_d;
    always @(posedge clk) vblank_d <= vblank & ~rst;
    wire vblank_start = vblank & ~vblank_d;

    wire [1:0]  tbase = (sw_tbase == 2'd3) ? 2'd2 : sw_tbase;
    wire [9:0]  rd_addr;
    wire [47:0] rd_data;
    capture_scope_ram #(.AUTO_TRIG(AUTO_TRIG)) u_cap (
        .clk(clk), .rst(rst), .in_valid(out_valid), .m(m_sample), .r(r_sample), .m_hat(mhat_sample),
        .hold(hold), .vblank_start(vblank_start),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .vio_addr(vio_rd_addr), .vio_data(vio_rd_data),
        .bank_disp(bank_disp), .recording(recording), .triggered()
    );

    vga_scope_render u_vga (
        .clk(clk), .rst(rst), .pix_en(pix_en), .h(h), .v(v), .active(active), .hs_n(hs_n), .vs_n(vs_n),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .fc_idx(fc_idx), .beta_q(beta_q), .fm_idx(fm_idx), .amp(amp), .noise_idx(noise_idx), .mode(mode), .source(source),
        .hold(hold), .tbase(tbase), .coarse(coarse), .mute(sw_spk_mute), .mon_sel(mon_sel), .snr_db(snr_db),
        .clip(clip_sticky), .recording(recording), .key_down(key_down), .key_code(key_code),
        .overlay_err(sw_overlay_err),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs)
    );
endmodule
`default_nettype wire
