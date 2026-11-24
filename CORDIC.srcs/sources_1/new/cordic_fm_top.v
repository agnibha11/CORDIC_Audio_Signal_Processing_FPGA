`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Agnibha Sarkar
//  Last Updated : 24 November 2026
// ============================================================================
module cordic_fm_top (
    input  wire       clk100,
    input  wire       btn_rst,
    input  wire       btn_u,
    input  wire       btn_l,
    input  wire       btn_r,
    input  wire       btn_c,
    input  wire [7:0] sw,
    output wire [7:0] led,
    // Pmod JC top row: MIC (1,3,4)
    output wire       adc_cs_n,
    input  wire       adc_miso,
    output wire       adc_sclk,
    // Pmod JA top row: DA2 (1,2,3,4)
    output wire       dac_sync_n,
    output wire       dac_dina,
    output wire       dac_dinb,
    output wire       dac_sclk,
    // Pmod JB: KYPD
    output wire [3:0] kypd_col,
    input  wire [3:0] kypd_row,
    // Pmod JD top row: AMP2
    output wire       amp_ain,
    output wire       amp_gain,
    output wire       amp_shutdown_n,
    // VGA
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire       vga_hs,
    output wire       vga_vs
);
    // ------------------------------------------------------------------
    // power-on reset + synchronisers (every asynchronous input crosses two flops)
    // ------------------------------------------------------------------
    reg  [15:0] por = 16'hFFFF;
    always @(posedge clk100) por <= {por[14:0], 1'b0};

    wire       rst_btn;
    wire       s_btn_u, s_btn_l, s_btn_r, s_btn_c, s_miso;
    wire [7:0] s_sw;
    wire [3:0] s_row;
    sync_2ff #(.WIDTH(1)) u_sy_rst (.clk(clk100), .d(btn_rst),  .q(rst_btn));
    sync_2ff #(.WIDTH(1)) u_sy_u   (.clk(clk100), .d(btn_u),    .q(s_btn_u));
    sync_2ff #(.WIDTH(1)) u_sy_l   (.clk(clk100), .d(btn_l),    .q(s_btn_l));
    sync_2ff #(.WIDTH(1)) u_sy_r   (.clk(clk100), .d(btn_r),    .q(s_btn_r));
    sync_2ff #(.WIDTH(1)) u_sy_c   (.clk(clk100), .d(btn_c),    .q(s_btn_c));
    sync_2ff #(.WIDTH(8)) u_sy_sw  (.clk(clk100), .d(sw),       .q(s_sw));
    sync_2ff #(.WIDTH(4), .INIT(4'b1111)) u_sy_row (.clk(clk100), .d(kypd_row), .q(s_row));
    sync_2ff #(.WIDTH(1)) u_sy_mi  (.clk(clk100), .d(adc_miso), .q(s_miso));

    reg rst = 1'b1;
    always @(posedge clk100) rst <= rst_btn | por[15];

    // ------------------------------------------------------------------
    // VIO signals
    // ------------------------------------------------------------------
    wire        vio_override;
    wire [6:0]  vio_fc_idx, vio_beta_q;
    wire [5:0]  vio_fm_idx, vio_amp;
    wire [1:0]  vio_mode;
    wire        vio_source, vio_hold;
    wire [4:0]  vio_noise;
    wire [10:0] vio_rd_addr;
    wire [47:0] vio_rd_data;

    wire [6:0]  fc_idx, beta_q;
    wire [5:0]  fm_idx, amp;
    wire [4:0]  noise_idx;
    wire [1:0]  mode, mon_sel;
    wire        source, hold, coarse, key_valid, key_down, clip_sticky, recording, bank_disp, sample_tick, out_valid, cordic_busy;
    wire [3:0]  key_code;
    wire [11:0] adc_code;
    wire signed [15:0] m_sample, r_sample, mhat_sample, mon_sample;
    wire [47:0] sum_sig, sum_err;
    wire [15:0] peak_err;
    wire [6:0]  snr_db;
    wire [31:0] gain_recip;
    wire [25:0] div_den;

    cordic_fm_system u_sys (
        .clk(clk100), .rst(rst),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_miso(s_miso),
        .dac_sync_n(dac_sync_n), .dac_dina(dac_dina), .dac_dinb(dac_dinb), .dac_sclk(dac_sclk),
        .amp_ain(amp_ain), .amp_gain(amp_gain), .amp_shutdown_n(amp_shutdown_n),
        .kypd_row(s_row), .kypd_col(kypd_col),
        .btn_u(s_btn_u), .btn_l(s_btn_l), .btn_r(s_btn_r), .btn_c(s_btn_c),
        .sw_tbase(s_sw[1:0]), .sw_overlay_err(s_sw[2]), .sw_spk_att(s_sw[5:4]), .sw_spk_loud(s_sw[6]), .sw_spk_mute(s_sw[7]),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs),
        .vio_override(vio_override), .vio_fc_idx(vio_fc_idx), .vio_beta_q(vio_beta_q),
        .vio_fm_idx(vio_fm_idx), .vio_amp(vio_amp), .vio_mode(vio_mode),
        .vio_source(vio_source), .vio_hold(vio_hold), .vio_noise(vio_noise),
        .vio_rd_addr(vio_rd_addr), .vio_rd_data(vio_rd_data),
        .fc_idx(fc_idx), .beta_q(beta_q), .fm_idx(fm_idx), .amp(amp), .noise_idx(noise_idx), .mode(mode), .source(source),
        .hold(hold), .coarse(coarse), .mon_sel(mon_sel),
        .key_valid(key_valid), .key_code(key_code), .key_down(key_down),
        .clip_sticky(clip_sticky), .recording(recording), .bank_disp(bank_disp), .sample_tick(sample_tick),
        .adc_code(adc_code), .out_valid(out_valid),
        .m_sample(m_sample), .r_sample(r_sample), .mhat_sample(mhat_sample), .mon_sample(mon_sample),
        .sum_sig(sum_sig), .sum_err(sum_err), .peak_err(peak_err), .snr_db(snr_db),
        .gain_recip(gain_recip), .div_den(div_den), .cordic_busy(cordic_busy)
    );

    // ------------------------------------------------------------------
    // LEDs
    // ------------------------------------------------------------------
    reg [26:0] hb_cnt;
    reg [24:0] key_act_cnt;
    always @(posedge clk100) begin
        if (rst) begin
            hb_cnt      <= 27'd0;
            key_act_cnt <= 25'd0;
        end else begin
            hb_cnt <= (hb_cnt == 27'd99_999_999) ? 27'd0 : hb_cnt + 27'd1;
            if (key_valid)                key_act_cnt <= 25'd20_000_000;     // 200 ms
            else if (key_act_cnt != 25'd0) key_act_cnt <= key_act_cnt - 25'd1;
        end
    end
    wire heartbeat = (hb_cnt < 27'd50_000_000);
    wire key_act   = (key_act_cnt != 25'd0);
    wire noise_on  = (noise_idx != 5'd0);

    assign led = s_sw[3] ? {key_down, 3'b000, key_code}
                         : {heartbeat, key_act, clip_sticky, noise_on, hold, source, mode};

    // ------------------------------------------------------------------
    // VIO (Xilinx Virtual I/O, generated by create_project.tcl)
    // ------------------------------------------------------------------
`ifdef USE_VIO
    wire [7:0] status = {clip_sticky, recording, coarse, hold, bank_disp, s_sw[7], mon_sel};
    vio_0 u_vio (
        .clk        (clk100),
        .probe_in0  (fc_idx),
        .probe_in1  (beta_q),
        .probe_in2  (fm_idx),
        .probe_in3  (amp),
        .probe_in4  (mode),
        .probe_in5  (source),
        .probe_in6  (noise_idx),
        .probe_in7  (key_code),
        .probe_in8  (adc_code),
        .probe_in9  (m_sample),
        .probe_in10 (r_sample),
        .probe_in11 (mhat_sample),
        .probe_in12 (sum_sig),
        .probe_in13 (sum_err),
        .probe_in14 (peak_err),
        .probe_in15 (snr_db),
        .probe_in16 (vio_rd_data),
        .probe_in17 (status),
        .probe_in18 (gain_recip),
        .probe_in19 (div_den),
        .probe_out0 (vio_override),
        .probe_out1 (vio_fc_idx),
        .probe_out2 (vio_beta_q),
        .probe_out3 (vio_fm_idx),
        .probe_out4 (vio_amp),
        .probe_out5 (vio_mode),
        .probe_out6 (vio_source),
        .probe_out7 (vio_hold),
        .probe_out8 (vio_rd_addr),
        .probe_out9 (vio_noise)
    );
`else
    assign vio_override = 1'b0;
    assign vio_fc_idx   = 7'd0;
    assign vio_beta_q   = 7'd0;
    assign vio_fm_idx   = 6'd0;
    assign vio_amp      = 6'd0;
    assign vio_mode     = 2'd0;
    assign vio_source   = 1'b0;
    assign vio_hold     = 1'b0;
    assign vio_noise    = 5'd0;
    assign vio_rd_addr  = 11'd0;
`endif
endmodule
`default_nettype wire
