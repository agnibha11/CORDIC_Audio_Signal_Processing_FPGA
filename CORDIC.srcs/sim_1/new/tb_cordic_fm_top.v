`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_cordic_fm_top.v -- smoke test of the board wrapper (pins, synchronisers,
//  LEDs).  Runs 40 samples: the ADC model must see conversions, the DAC models
//  updates, LED7 heartbeat / mode LEDs / key-code LED mode must behave, and
//  the key activity LED must light after a key press (full-speed keypad
//  timing: one press costs ~12 ms of simulated time).
// ============================================================================
module tb_cordic_fm_top;
    reg clk = 0, btn_rst = 1, btn_u = 0, btn_l = 0, btn_r = 0, btn_c = 0;
    reg [7:0] sw = 0;
    always #5 clk = ~clk;
    wire [7:0] led;
    wire adc_cs_n, adc_sclk, adc_sdata, dac_sync_n, dac_dina, dac_dinb, dac_sclk, vga_hs, vga_vs;
    wire [3:0] kypd_col, kypd_row, vga_r, vga_g, vga_b;
    reg  [15:0] pressed = 0;

    cordic_fm_top dut (
        .clk100(clk), .btn_rst(btn_rst), .btn_u(btn_u), .btn_l(btn_l), .btn_r(btn_r), .btn_c(btn_c), .sw(sw), .led(led),
        .adc_cs_n(adc_cs_n), .adc_miso(adc_sdata), .adc_sclk(adc_sclk),
        .dac_sync_n(dac_sync_n), .dac_dina(dac_dina), .dac_dinb(dac_dinb), .dac_sclk(dac_sclk),
        .kypd_col(kypd_col), .kypd_row(kypd_row),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs)
    );
    wire [31:0] conv, perr;
    model_adcs7476 adc (.cs_n(adc_cs_n), .sclk(adc_sclk), .sdata(adc_sdata), .analog_code(12'd2500), .conversions(conv), .protocol_errors(perr));
    wire [11:0] da, db; wire [1:0] pa, pb; wire [31:0] ua, ub, ea, eb;
    model_dac121s101 ma (.sync_n(dac_sync_n), .sclk(dac_sclk), .din(dac_dina), .dac_reg(da), .pd_mode(pa), .updates(ua), .protocol_errors(ea));
    model_dac121s101 mb (.sync_n(dac_sync_n), .sclk(dac_sclk), .din(dac_dinb), .dac_reg(db), .pd_mode(pb), .updates(ub), .protocol_errors(eb));
    model_kypd kp (.col(kypd_col), .row(kypd_row), .pressed(pressed));

    integer checks = 0, errors = 0;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    initial begin
        repeat (20) @(negedge clk); btn_rst = 0;
        repeat (40 * 2000) @(negedge clk);
        check(conv >= 39, "ADC conversions");
        check(ua >= 38 && ub >= 38 && ea == 0 && eb == 0, "DAC updates on both channels");
        check(led[7] == 1'b1, "heartbeat LED on in the first half second");
        check(led[1:0] == 2'b00 && led[2] == 1'b0 && led[3] == 1'b0, "mode FM, source mic, not held");
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
        // BTNU cycles the mode too (debounced 10 ms)
        btn_u = 1; repeat (1_100_000) @(negedge clk); btn_u = 0; repeat (1_100_000) @(negedge clk);
        check(led[1:0] == 2'b10, "BTNU: mode = AM");
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
