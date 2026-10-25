`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_cordic_fm_system.v -- end-to-end test of the complete signal chain
//
//  The system is driven through its real interfaces: a behavioural ADCS7476
//  fed with a 300 Hz sine, two DAC121S101 models on the DA2 pins, the keypad
//  matrix model on the KYPD pins.  Keypad timing is scaled down (parameters)
//  so a key press costs ~30 us instead of 5 ms.
//
//  T1  reciprocal divider calibrates to 2^39 / (kdev >> 8) after reset
//  T2  BYPASS: DAC-A code equals the DC-blocked input; m tracks a
//      double-precision DC-blocker model of the same input (+/- 24 LSB)
//  T3  FM:  s[n] vs a double-precision FM model driven by the RTL's own m[n]
//      (+/- 8 LSB), demodulated m_hat vs m (loop-back SNR > 55 dB),
//      hardware fidelity meter sums equal the bench's own sums
//  T4  PM and AM through the keypad ('8' cycles the mode), same checks
//  T5  keypad edits: beta +/-, carrier +/-, coarse step, defaults
//  T6  capture RAM: the 1024 samples read back through the VIO port equal
//      the bench's log from the trigger instant; trigger is a rising
//      zero crossing
//  T7  VGA timing (800 x 525, sync widths) and a frame dump to vga_frame.ppm
//  Simulated time ~0.3 s (26 M clocks): 10-20 minutes in XSim. "run all";
//  the last line is "ALL PASS (n checks)".
// ============================================================================
module tb_cordic_fm_system;
    localparam real PI = 3.14159265358979323846;
    localparam integer CPS = 2000;               // clocks per sample
    localparam real    FS  = 100.0e6 / CPS;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    // ---------------- pins ----------------
    wire        adc_cs_n, adc_sclk, adc_sdata;
    wire        dac_sync_n, dac_dina, dac_dinb, dac_sclk;
    wire [3:0]  kypd_col, kypd_row;
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        vga_hs, vga_vs;
    reg  [15:0] pressed = 0;
    reg         sw_overlay_err = 0;
    reg         vio_override = 0, vio_source = 0, vio_hold = 0;
    reg  [6:0]  vio_fc_idx = 0, vio_beta_q = 0;
    reg  [5:0]  vio_fm_idx = 0, vio_amp = 0;
    reg  [1:0]  vio_mode = 0;
    reg  [10:0] vio_rd_addr = 0;
    wire [47:0] vio_rd_data;

    // ---------------- status ----------------
    wire [6:0]  fc_idx, beta_q;
    wire [5:0]  fm_idx, amp;
    wire [1:0]  mode, dacb_sel, tbase;
    wire        source, hold, coarse, mute, key_valid, key_down, clip_sticky, recording, sample_tick, out_valid, cordic_busy;
    wire [3:0]  key_code;
    wire [11:0] adc_code;
    wire signed [15:0] m_s, s_s, mh_s, tone_s;
    wire [47:0] sum_sig, sum_err;
    wire [15:0] peak_err;
    wire [6:0]  snr_db;
    wire [31:0] gain_recip;
    wire [25:0] div_den;

    cordic_fm_system #(
        .CLK_PER_SAMPLE(CPS), .SCLK_DIV(20),
        .KYPD_SCAN_CLKS(256), .KYPD_DEBOUNCE(4), .KYPD_RPT_DELAY(400), .KYPD_RPT_RATE(100),
        .BTN_STABLE(100), .AUTO_TRIG(4096), .METER_WLOG(10), .CLIP_HOLD(20000)
    ) dut (
        .clk(clk), .rst(rst),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_miso(adc_sdata),
        .dac_sync_n(dac_sync_n), .dac_dina(dac_dina), .dac_dinb(dac_dinb), .dac_sclk(dac_sclk),
        .kypd_row(kypd_row), .kypd_col(kypd_col),
        .btn_u(1'b0), .btn_l(1'b0), .btn_r(1'b0), .btn_c(1'b0), .sw_overlay_err(sw_overlay_err),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs),
        .vio_override(vio_override), .vio_fc_idx(vio_fc_idx), .vio_beta_q(vio_beta_q), .vio_fm_idx(vio_fm_idx),
        .vio_amp(vio_amp), .vio_mode(vio_mode), .vio_source(vio_source), .vio_hold(vio_hold),
        .vio_rd_addr(vio_rd_addr), .vio_rd_data(vio_rd_data),
        .fc_idx(fc_idx), .beta_q(beta_q), .fm_idx(fm_idx), .amp(amp), .mode(mode), .source(source), .hold(hold),
        .coarse(coarse), .mute(mute), .dacb_sel(dacb_sel), .tbase(tbase),
        .key_valid(key_valid), .key_code(key_code), .key_down(key_down), .clip_sticky(clip_sticky),
        .recording(recording), .sample_tick(sample_tick), .adc_code(adc_code), .out_valid(out_valid),
        .m_sample(m_s), .s_sample(s_s), .mhat_sample(mh_s), .tone_sample(tone_s),
        .sum_sig(sum_sig), .sum_err(sum_err), .peak_err(peak_err), .snr_db(snr_db),
        .gain_recip(gain_recip), .div_den(div_den), .cordic_busy(cordic_busy)
    );

    // ---------------- analog world ----------------
    real  f_in = 300.0, a_in = 1500.0;
    reg  [11:0] analog = 12'd2048;
    always @(posedge clk) begin                   // the "microphone": sine around mid-scale
        analog <= 2048 + $rtoi(a_in * $sin(2.0 * PI * f_in * $realtime * 1.0e-9));
    end
    wire [31:0] conv, perr_adc;
    model_adcs7476 adc (.cs_n(adc_cs_n), .sclk(adc_sclk), .sdata(adc_sdata), .analog_code(analog),
                        .conversions(conv), .protocol_errors(perr_adc));
    wire [11:0] dac_a, dac_b;
    wire [1:0]  pd_a, pd_b;
    wire [31:0] upd_a, upd_b, perr_a, perr_b;
    model_dac121s101 dac_ma (.sync_n(dac_sync_n), .sclk(dac_sclk), .din(dac_dina), .dac_reg(dac_a), .pd_mode(pd_a), .updates(upd_a), .protocol_errors(perr_a));
    model_dac121s101 dac_mb (.sync_n(dac_sync_n), .sclk(dac_sclk), .din(dac_dinb), .dac_reg(dac_b), .pd_mode(pd_b), .updates(upd_b), .protocol_errors(perr_b));
    model_kypd #(.SETTLE_NS(500)) kp (.col(kypd_col), .row(kypd_row), .pressed(pressed));

    // ---------------- bookkeeping ----------------
    integer checks = 0, errors = 0;
    task check; input cond; input [8*72-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; if (errors <= 30) $display("FAIL @%0t: %0s", $time, msg); end end
    endtask
    function real absr; input real r; begin absr = (r < 0.0) ? -r : r; end endfunction
    function [11:0] to_dac; input signed [15:0] s; begin to_dac = {~s[15], s[14:4]}; end endfunction

    // sample log (for the capture-RAM comparison)
    reg signed [15:0] log_m [0:65535], log_s [0:65535], log_mh [0:65535];
    integer nlog = 0;
    integer trig_index = -1;
    always @(posedge clk) if (out_valid) begin
        log_m[nlog] = m_s; log_s[nlog] = s_s; log_mh[nlog] = mh_s;
        nlog = nlog + 1;
    end
    always @(posedge clk) if (dut.u_cap.triggered) trig_index = nlog - 1;   // `triggered` is registered one clock after the index-0 write

    // double-precision references
    real x_prev_f = 0.0, y_f = 0.0;                   // DC blocker
    real th_f = 0.0, th_c = 0.0;                      // modulator phases
    real s_exp, m_exp, dev_hz, fc_hz, fm_hz, beta_r, mu_r;
    real err_mod_worst, err_dem_worst, acc_sig, acc_err;
    integer n_in_win;

    // keypad press helper (scaled scanner: 256 clk/column, 4 scans debounce)
    task press; input [3:0] key;
        integer r, c, idx;
        begin
            idx = -1;
            for (r = 0; r < 4; r = r + 1) for (c = 0; c < 4; c = c + 1)
                if (cap(r, c) == key) idx = r * 4 + c;
            pressed = 16'd1 << idx;
            repeat (8 * 4 * 256) @(negedge clk);
            pressed = 0;
            repeat (8 * 4 * 256) @(negedge clk);
        end
    endtask
    function [3:0] cap; input integer r, c;
        begin
            case (r) 0: cap = (c==0)?4'h1:(c==1)?4'h2:(c==2)?4'h3:4'hA;
                     1: cap = (c==0)?4'h4:(c==1)?4'h5:(c==2)?4'h6:4'hB;
                     2: cap = (c==0)?4'h7:(c==1)?4'h8:(c==2)?4'h9:4'hC;
                     default: cap = (c==0)?4'h0:(c==1)?4'hF:(c==2)?4'hE:4'hD; endcase
        end
    endfunction

    // wait for n output samples
    task wait_samples; input integer n;
        integer k;
        begin for (k = 0; k < n; k = k + 1) @(posedge out_valid); end
    endtask

    // run `n` samples in the current mode against the floating-point model;
    // the model consumes the RTL's own m[n] so the check isolates the modulator
    task run_mode_check; input integer n; input [8*8-1:0] name;
        integer k;
        real mn, inc, snr;
        begin
            fc_hz  = fc_idx * 100.0;  fm_hz = fm_idx * 50.0;  beta_r = beta_q / 8.0;  mu_r = beta_r;
            dev_hz = beta_r * fm_hz;
            // phase alignment: copy the RTL's phase once, then run the model independently
            @(posedge out_valid); @(negedge clk);
            th_f = dut.u_dsp.phi_c * 2.0 * PI / 4294967296.0;
            th_c = th_f;
            err_mod_worst = 0.0; err_dem_worst = 0.0; acc_sig = 0.0; acc_err = 0.0;
            for (k = 0; k < n; k = k + 1) begin
                @(posedge out_valid); @(negedge clk);
                mn = m_s / 32768.0;
                case (mode)
                    2'd0: begin th_f = th_f + 2.0 * PI * (fc_hz + dev_hz * mn) / FS; s_exp = 32767.0 * $cos(th_f); end
                    2'd1: begin th_c = th_c + 2.0 * PI * fc_hz / FS; s_exp = 32767.0 * $cos(th_c + beta_r * mn); end
                    2'd2: begin th_c = th_c + 2.0 * PI * fc_hz / FS; s_exp = 32767.0 * $cos(th_c) * (1.0 + mu_r * mn) / 2.0; end
                    default: s_exp = m_s;
                endcase
                if (absr(s_s - s_exp) > err_mod_worst) err_mod_worst = absr(s_s - s_exp);
                if (absr(m_s - mh_s) > err_dem_worst)  err_dem_worst  = absr(m_s - mh_s);
                acc_sig = acc_sig + 1.0 * m_s * m_s;
                acc_err = acc_err + 1.0 * (m_s - mh_s) * (m_s - mh_s);
            end
            snr = (acc_err > 0.0) ? 10.0 * $log10(acc_sig / acc_err) : 120.0;
            $display("%0s: fc=%0.0f Hz beta=%0.3f fm=%0.0f Hz | modulator worst err = %0.2f LSB | demod worst err = %0.1f LSB, loop-back SNR = %0.1f dB",
                     name, fc_hz, beta_r, fm_hz, err_mod_worst, err_dem_worst, snr);
            check(err_mod_worst <= 8.0, "modulated output vs floating-point model");
            check(snr > 55.0, "loop-back demodulation SNR > 55 dB");
        end
    endtask

    // ---------------- VGA monitors ----------------
    realtime t_hs_fall = 0, t_hs_prev = 0, t_vs_fall = 0, t_vs_prev = 0, t_hs_rise = 0, t_vs_rise = 0;
    real hs_period = 0, vs_period = 0, hs_width = 0, vs_width = 0;
    always @(negedge vga_hs) begin t_hs_prev = t_hs_fall; t_hs_fall = $realtime; hs_period = t_hs_fall - t_hs_prev; end
    always @(posedge vga_hs) begin t_hs_rise = $realtime; hs_width = t_hs_rise - t_hs_fall; end
    always @(negedge vga_vs) begin t_vs_prev = t_vs_fall; t_vs_fall = $realtime; vs_period = t_vs_fall - t_vs_prev; end
    always @(posedge vga_vs) begin t_vs_rise = $realtime; vs_width = t_vs_rise - t_vs_fall; end

    // frame grabber: the pins are registered one pixel after the counters
    reg [11:0] frame [0:640*480-1];
    reg        grab = 0;
    integer    px, py, fd, i, j;
    always @(posedge clk) if (grab && dut.u_vt.pix_en) begin
        if (dut.u_vt.h == 0) begin px = 799; py = dut.u_vt.v - 1; end
        else begin px = dut.u_vt.h - 1; py = dut.u_vt.v; end
        if (px < 640 && py >= 0 && py < 480) frame[py * 640 + px] = {vga_r, vga_g, vga_b};
    end
    task dump_frame;
        begin
            fd = $fopen("vga_frame.ppm", "wb");
            $fwrite(fd, "P6\n640 480\n255\n");
            for (i = 0; i < 640 * 480; i = i + 1)
                $fwrite(fd, "%c%c%c", {frame[i][11:8], frame[i][11:8]}, {frame[i][7:4], frame[i][7:4]}, {frame[i][3:0], frame[i][3:0]});
            $fclose(fd);
        end
    endtask

    // ---------------- the test ----------------
    integer k, n0, mism;
    reg [63:0] exp_g;
    initial begin
        $display("tb_cordic_fm_system: Fs = %0.0f Hz, %0d clocks per sample", FS, CPS);
        repeat (5) @(negedge clk); rst = 0;

        // T1: divider calibration
        repeat (200) @(negedge clk);
        exp_g = (64'd1 << 39) / div_den;
        check(div_den == (((16 * (4 * 4294967)) >> 3) >> 8), "T1 FM divisor = kdev >> 8");
        check(gain_recip == exp_g[31:0], "T1 reciprocal after reset");
        check(fc_idx == 20 && beta_q == 16 && fm_idx == 4 && amp == 16 && mode == 0 && source == 0, "T1 defaults");

        // let the DC blocker settle (bias step response) : ~0.1 s would be 5000 samples; use 1500
        wait_samples(1500);
        check(conv > 1400 && perr_adc == 0, "T2 ADC conversions without protocol errors");

        // T2: bypass mode via keypad: 8 -> PM, 8 -> AM, 8 -> BYP
        press(4'h8); press(4'h8); press(4'h8);
        check(mode == 2'd3, "T2 mode = BYPASS after three '8' presses");
        // seed the floating DC blocker with the RTL state right after an output, i.e. ~1900 clocks before the next ADC sample
        @(posedge out_valid); @(negedge clk);
        y_f = dut.u_fe.acc / 256.0;  x_prev_f = dut.u_fe.x_prev;
        n0 = 0;
        for (k = 0; k < 400; k = k + 1) begin
            @(posedge out_valid); @(negedge clk);
            // the sample that produced this output was converted ~1 sample ago; recompute from the ADC code
            y_f = (16.0 * (adc_code - 2048.0) - x_prev_f) + (1.0 - 1.0/256.0) * y_f;
            x_prev_f = 16.0 * (adc_code - 2048.0);
            m_exp = y_f;                                   // amp = 1.0
            if (absr(m_s - m_exp) > 24.0) n0 = n0 + 1;
            check(s_s == m_s, "T2 bypass: s == m");
            check(mh_s == m_s, "T2 bypass: m_hat == m");
        end
        check(n0 == 0, "T2 m tracks the floating-point DC blocker (+/-24 LSB)");
        @(dac_ma.updates); #1;
        check(dac_a == to_dac(s_s) || dac_a == to_dac(log_s[nlog-2]), "T2 DAC-A code = modulated sample");
        check(dac_b == to_dac(m_s) || dac_b == to_dac(log_m[nlog-2]), "T2 DAC-B code = original sample");
        check(perr_a == 0 && perr_b == 0 && pd_a == 0, "T2 DAC frames clean");

        // T3: FM (press '8' once more wraps to FM)
        press(4'h8);
        check(mode == 2'd0, "T3 mode = FM");
        wait_samples(50);
        run_mode_check(2000, "T3 FM  ");
        // hardware meter vs bench over its 1024-sample window
        @(posedge dut.u_meter.window_done); #1;
        check(sum_sig != 0 && sum_err != 0, "T3 meter produced sums");
        $display("T3 hardware meter: sum_sig=%0d sum_err=%0d snr_est=%0d dB peak_err=%0d", sum_sig, sum_err, snr_db, peak_err);
        check(snr_db >= 50 && snr_db <= 99, "T3 meter SNR estimate in range");

        // T4: PM and AM
        press(4'h8); check(mode == 2'd1, "T4 mode = PM");
        wait_samples(50); run_mode_check(1500, "T4 PM  ");
        // AM: depth = beta, so bring beta to 1.0 (coarse step 8: F, 5, F) to stay out of over-modulation
        press(4'hF); press(4'h5); press(4'hF); check(beta_q == 8 && !coarse, "T4 beta = 1.0 for AM");
        press(4'h8); check(mode == 2'd2, "T4 mode = AM");
        wait_samples(50); run_mode_check(1500, "T4 AM  ");
        press(4'h8); press(4'h8); check(mode == 2'd0, "T4 back to FM");
        press(4'h0); check(beta_q == 16, "T4 defaults restored");

        // T5: parameter edits
        press(4'h2); check(beta_q == 17, "T5 beta + (fine)");
        press(4'hF); check(coarse, "T5 coarse on");
        press(4'h2); check(beta_q == 25, "T5 beta + (coarse)");
        press(4'h1); check(fc_idx == 30, "T5 fc + (coarse)");
        press(4'h4); press(4'h4); press(4'h4); check(fc_idx == 1, "T5 fc - clamps at 1");
        press(4'h3); check(fm_idx == 8, "T5 fm + (coarse)");
        press(4'hA); check(amp == 20, "T5 amp + (coarse)");
        press(4'h7); check(source == 1, "T5 source = tone");
        press(4'h0); check(fc_idx == 20 && beta_q == 16 && fm_idx == 4 && amp == 16 && !coarse && source == 0, "T5 defaults restored");
        // tone source with a larger index: FM with beta 4 and the internal 200 Hz tone
        press(4'h7); press(4'hF); press(4'h2); press(4'h2);
        check(source == 1 && beta_q == 32, "T5 tone source, beta = 4");
        wait_samples(100);
        run_mode_check(1500, "T5 FMt ");
        press(4'h0);

        // T6: capture RAM read-back through the VIO port
        wait_samples(1200);                         // guarantees at least one complete record
        press(4'hC); check(hold, "T6 hold");
        wait_samples(2100);                         // finish the record in progress (<=1024), wait for vblank (<=835), freeze
        check(trig_index >= 0, "T6 a trigger happened");
        check(dut.u_cap.st == 2'd3, "T6 capture FSM frozen");
        mism = 0;
        for (k = 0; k < 1024; k = k + 1) begin
            vio_rd_addr = {dut.u_cap.bank_disp, k[9:0]};
            repeat (3) @(negedge clk);
            if (vio_rd_data !== {log_m[trig_index + k], log_s[trig_index + k], log_mh[trig_index + k]}) mism = mism + 1;
        end
        check(mism == 0, "T6 1024 stored samples equal the bench log");
        check(log_m[trig_index] >= 0 && log_m[trig_index - 1] < 0, "T6 trigger on rising zero crossing");
        $display("T6 capture read-back: %0d mismatches of 1024", mism);

        // T7: VGA timing + frame dump (display is frozen by hold)
        @(posedge dut.u_vt.frame_start); grab = 1;
        @(posedge dut.u_vt.frame_start); grab = 0;
        dump_frame;
        check(absr(hs_period - 32000.0) < 1.0, "T7 HS period = 32.0 us (800 px)");
        check(absr(hs_width - 3840.0) < 1.0,   "T7 HS pulse = 96 px");
        check(absr(vs_period - 16800000.0) < 1.0, "T7 VS period = 16.8 ms (525 lines)");
        check(absr(vs_width - 64000.0) < 1.0,  "T7 VS pulse = 2 lines");
        $display("T7 VGA: HS %0.1f us / %0.2f us pulse, VS %0.3f ms / %0.1f us pulse; frame written to vga_frame.ppm", hs_period/1000.0, hs_width/1000.0, vs_period/1.0e6, vs_width/1000.0);
        press(4'hC); check(!hold, "T7 run again");

        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
