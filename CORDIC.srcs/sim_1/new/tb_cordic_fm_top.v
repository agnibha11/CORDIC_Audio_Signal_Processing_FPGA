`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_cordic_fm_top.v -- smoke test of the board wrapper (pins, power-on
//  reset, synchronisers, LEDs, AMP2 pins).
//  The reset button is NEVER pressed: the design must come up in its reset
//  state from the power-on reset alone, exactly as after FPGA configuration.
//  Runs 40 samples: the ADC model must see conversions, the DAC models
//  updates, the AMP2 pin must toggle, LED7 heartbeat / mode LEDs / key-code
//  LED mode must behave (full-speed keypad timing: one press costs ~12 ms of
//  simulated time), BTNU and the switches must act.
// ============================================================================
module tb_cordic_fm_top;
    reg clk = 0, btn_rst = 0, btn_u = 0, btn_l = 0, btn_r = 0, btn_c = 0;
    reg [7:0] sw = 0;
    always #5 clk = ~clk;
    wire [7:0] led;
    wire adc_cs_n, adc_sclk, adc_sdata, dac_sync_n, dac_dina, dac_dinb, dac_sclk, vga_hs, vga_vs;
    wire amp_ain, amp_gain, amp_shutdown_n;
    wire [3:0] kypd_col, kypd_row, vga_r, vga_g, vga_b;
    reg  [15:0] pressed = 0;

    cordic_fm_top dut (
        .clk100(clk), .btn_rst(btn_rst), .btn_u(btn_u), .btn_l(btn_l), .btn_r(btn_r), .btn_c(btn_c), .sw(sw), .led(led),
        .adc_cs_n(adc_cs_n), .adc_miso(adc_sdata), .adc_sclk(adc_sclk),
        .dac_sync_n(dac_sync_n), .dac_dina(dac_dina), .dac_dinb(dac_dinb), .dac_sclk(dac_sclk),
        .kypd_col(kypd_col), .kypd_row(kypd_row),
        .amp_ain(amp_ain), .amp_gain(amp_gain), .amp_shutdown_n(amp_shutdown_n),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs)
    );
    wire [31:0] conv, perr;
    model_adcs7476 adc (.cs_n(adc_cs_n), .sclk(adc_sclk), .sdata(adc_sdata), .analog_code(12'd2500), .conversions(conv), .protocol_errors(perr));
    wire [11:0] da, db; wire [1:0] pa, pb; wire [31:0] ua, ub, ea, eb;
    model_dac121s101 ma (.sync_n(dac_sync_n), .sclk(dac_sclk), .din(dac_dina), .dac_reg(da), .pd_mode(pa), .updates(ua), .protocol_errors(ea));
    model_dac121s101 mb (.sync_n(dac_sync_n), .sclk(dac_sclk), .din(dac_dinb), .dac_reg(db), .pd_mode(pb), .updates(ub), .protocol_errors(eb));
    model_kypd kp (.col(kypd_col), .row(kypd_row), .pressed(pressed));

    integer checks = 0, errors = 0, amp_edges = 0;
    always @(amp_ain) amp_edges = amp_edges + 1;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    initial begin
        // power-on: no button, no explicit reset
        repeat (4) @(negedge clk);
        check(dut.rst === 1'b1 && amp_shutdown_n === 1'b0, "power-on reset active, amplifier held off");
        repeat (30) @(negedge clk);
        check(dut.rst === 1'b0, "power-on reset released after 16 clocks");
        check(dut.fc_idx == 40 && dut.beta_q == 40 && dut.fm_idx == 8 && dut.amp == 16 && dut.noise_idx == 0, "parameter defaults loaded without pressing reset");
        repeat (40 * 2000) @(negedge clk);
        check(conv >= 39 && perr == 0, "ADC conversions");
        check(ua >= 38 && ub >= 38 && ea == 0 && eb == 0, "DAC updates on both channels");
        check(dut.gain_recip != 0, "receiver gain calibrated");
        check(amp_edges > 1000 && amp_gain == 1'b1 && amp_shutdown_n == 1'b1, "AMP2: bit stream toggling, 6 dB, running");
        check(led[7] == 1'b1, "heartbeat LED on in the first half second");
        check(led[1:0] == 2'b00 && led[2] == 1'b0 && led[3] == 1'b0 && led[4] == 1'b0, "mode FM, source mic, not held, noise off");
        // switches: SW6 loud, SW7 mute
        sw[6] = 1; sw[7] = 1; repeat (10) @(negedge clk);
        check(amp_gain == 1'b0 && amp_shutdown_n == 1'b0, "SW6 -> 12 dB, SW7 -> shutdown");
        sw[6] = 0; sw[7] = 0;
        // press key '8' (row 2, col 1): mode -> PM, key activity LED
        pressed = 16'd1 << (2*4 + 1);
        repeat (20 * 4 * 8192) @(negedge clk);          // 16 debounce scans of 328 us
        check(led[1:0] == 2'b01, "mode LED = PM after key 8");
        check(led[6] == 1'b1, "key activity LED");
        sw[3] = 1;
        repeat (10) @(negedge clk);
        check(led[3:0] == 4'h8 && led[7] == 1'b1, "SW3: LEDs show the held key code");
        pressed = 0; sw[3] = 0;
        repeat (20 * 4 * 8192) @(negedge clk);
        // key '9' (row 2, col 2): channel noise on -> LD4
        pressed = 16'd1 << (2*4 + 2);
        repeat (20 * 4 * 8192) @(negedge clk);
        pressed = 0;
        repeat (20 * 4 * 8192) @(negedge clk);
        check(led[4] == 1'b1 && dut.noise_idx == 5'd1, "key 9: channel noise on, LD4");
        // BTNU cycles the mode too (debounced 10 ms)
        btn_u = 1; repeat (1_100_000) @(negedge clk); btn_u = 0; repeat (1_100_000) @(negedge clk);
        check(led[1:0] == 2'b10, "BTNU: mode = AM");
        // BTND restores the reset state
        btn_rst = 1; repeat (10) @(negedge clk); btn_rst = 0; repeat (10) @(negedge clk);
        check(led[1:0] == 2'b00 && dut.noise_idx == 5'd0, "BTND: back to defaults");
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
