`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_adau1761_out.v -- self-checking bench for the on-board codec output
//
//  * an I2C slave model at address 0x3B acknowledges every byte and logs the
//    transactions; the log must equal the expected 19-register sequence,
//    including the six-byte PLL burst, for FS = 50 kHz and FS = 48 kHz
//  * no missing acknowledge, `cfg_done` set at the end
//  * MCLK = 10 MHz
//  * I2S (FS = 50 kHz): every frame is exactly 2000 clocks and 64 bit clocks,
//    LRCLK low = left; both channels decode to the sample latched at the
//    frame start (I2S one-bit delay, MSB first)
//  * I2S (FS = 48 kHz): 48 frames per millisecond on average
//  Start-up waits are shortened by parameters.
// ============================================================================
module tb_adau1761_out;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    reg signed [15:0] sample = 16'sd0;

    // ---------------- DUT, FS = 50 kHz ----------------
    wire mclk, bclk, lrclk, sdat, adr0, adr1, scl_o, sda_o, done, nack;
    tri1 scl, sda;                                  // pull-ups
    assign scl = scl_o ? 1'bz : 1'b0;
    reg  slave_ack = 1'b0;
    assign sda = (!sda_o || slave_ack) ? 1'b0 : 1'bz;
    adau1761_out #(.FS(50_000), .START_WAIT(1000), .PLL_WAIT(2000), .CORE_WAIT(500)) dut (
        .clk(clk), .rst(rst), .sample(sample),
        .ac_mclk(mclk), .ac_bclk(bclk), .ac_lrclk(lrclk), .ac_sdata(sdat),
        .ac_adr0(adr0), .ac_adr1(adr1), .scl_o(scl_o), .sda_o(sda_o), .sda_in(sda),
        .cfg_done(done), .cfg_nack(nack));

    // ---------------- DUT, FS = 48 kHz ----------------
    wire mclk2, bclk2, lrclk2, sdat2, a0b, a1b, scl2_o, sda2_o, done2, nack2;
    tri1 scl2, sda2;
    assign scl2 = scl2_o ? 1'bz : 1'b0;
    reg  slave_ack2 = 1'b0;
    assign sda2 = (!sda2_o || slave_ack2) ? 1'b0 : 1'bz;
    adau1761_out #(.FS(48_000), .START_WAIT(1000), .PLL_WAIT(2000), .CORE_WAIT(500)) dut48 (
        .clk(clk), .rst(rst), .sample(sample),
        .ac_mclk(mclk2), .ac_bclk(bclk2), .ac_lrclk(lrclk2), .ac_sdata(sdat2),
        .ac_adr0(a0b), .ac_adr1(a1b), .scl_o(scl2_o), .sda_o(sda2_o), .sda_in(sda2),
        .cfg_done(done2), .cfg_nack(nack2));

    integer checks = 0, errors = 0;
    task check; input cond; input [8*72-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    // ---------------- I2C slave models (log bytes per transaction) ----------------
    reg [7:0] log1 [0:255]; integer n1 = 0; integer t1 = 0; reg [7:0] sh1; integer b1 = 0; reg in1 = 0;
    reg [7:0] log2 [0:255]; integer n2 = 0; integer t2 = 0; reg [7:0] sh2; integer b2 = 0; reg in2 = 0;
    always @(negedge sda) if (scl === 1'b1) begin in1 = 1; b1 = 0; end                 // START
    always @(posedge sda) if (scl === 1'b1 && in1) begin in1 = 0; t1 = t1 + 1; log1[n1] = 8'hFF; n1 = n1 + 1; end  // STOP marker
    always @(posedge scl) if (in1 && b1 < 8) begin sh1 = {sh1[6:0], sda === 1'b1}; b1 = b1 + 1; end
    always @(negedge scl) if (in1) begin
        if (b1 == 8) begin slave_ack = 1'b1; b1 = 9; log1[n1] = sh1; n1 = n1 + 1; end
        else if (b1 == 9) begin slave_ack = 1'b0; b1 = 0; end
    end
    always @(negedge sda2) if (scl2 === 1'b1) begin in2 = 1; b2 = 0; end
    always @(posedge sda2) if (scl2 === 1'b1 && in2) begin in2 = 0; t2 = t2 + 1; log2[n2] = 8'hFF; n2 = n2 + 1; end
    always @(posedge scl2) if (in2 && b2 < 8) begin sh2 = {sh2[6:0], sda2 === 1'b1}; b2 = b2 + 1; end
    always @(negedge scl2) if (in2) begin
        if (b2 == 8) begin slave_ack2 = 1'b1; b2 = 9; log2[n2] = sh2; n2 = n2 + 1; end
        else if (b2 == 9) begin slave_ack2 = 1'b0; b2 = 0; end
    end

    // expected byte stream (0xFF = STOP marker; no register byte equals 0xFF)
    reg [7:0] exp50 [0:255]; reg [7:0] exp48 [0:255]; integer ne;
    task add_reg; input [15:0] a; input [7:0] d;
        begin
            exp50[ne] = 8'h76; exp48[ne] = 8'h76; ne = ne + 1;
            exp50[ne] = a[15:8]; exp48[ne] = a[15:8]; ne = ne + 1;
            exp50[ne] = a[7:0];  exp48[ne] = a[7:0];  ne = ne + 1;
            exp50[ne] = d; exp48[ne] = d; ne = ne + 1;
            exp50[ne] = 8'hFF; exp48[ne] = 8'hFF; ne = ne + 1;
        end
    endtask
    task add_pll;
        begin
            exp50[ne] = 8'h76; exp48[ne] = 8'h76; ne = ne + 1;
            exp50[ne] = 8'h40; exp48[ne] = 8'h40; ne = ne + 1;
            exp50[ne] = 8'h02; exp48[ne] = 8'h02; ne = ne + 1;
            exp50[ne] = 8'h00; exp48[ne] = 8'h02; ne = ne + 1;      // M = 25 / 625
            exp50[ne] = 8'h19; exp48[ne] = 8'h71; ne = ne + 1;
            exp50[ne] = 8'h00; exp48[ne] = 8'h02; ne = ne + 1;      // N = 3 / 572
            exp50[ne] = 8'h03; exp48[ne] = 8'h3C; ne = ne + 1;
            exp50[ne] = 8'h29; exp48[ne] = 8'h21; ne = ne + 1;      // R = 5 / 4, X = 1, fractional
            exp50[ne] = 8'h01; exp48[ne] = 8'h01; ne = ne + 1;      // PLL enable
            exp50[ne] = 8'hFF; exp48[ne] = 8'hFF; ne = ne + 1;
        end
    endtask

    // ---------------- MCLK period ----------------
    realtime m_last = 0, m_per = 0;
    always @(posedge mclk) begin m_per = $realtime - m_last; m_last = $realtime; end

    // ---------------- I2S receiver (FS = 50 kHz) ----------------
    integer frames = 0, bits_in_frame = 0, fr_bad_len = 0, fr_bad_bits = 0, fr_bad_data = 0;
    time    lr_fall_t = 0;
    reg [63:0] fshift;
    reg signed [15:0] latched;          // sample at the frame start (shadow of the DUT latch)
    always @(posedge clk) if (dut.u_i2s.edge_now && dut.u_i2s.bclk && dut.u_i2s.n == 6'd0) latched <= sample;
    reg prev_lr = 1;
    reg signed [15:0] frame_val;
    always @(posedge bclk) begin
        // rising edge: sample SDATA; frame boundary = first rising edge after LRCLK fell
        if (prev_lr == 1'b1 && lrclk == 1'b0) begin
            if (frames > 1) begin
                if (bits_in_frame != 64) fr_bad_bits = fr_bad_bits + 1;
                // left word: bits 1..16 of the left half; right word: bits 33..48
                if (fshift[62:47] !== frame_val || fshift[30:15] !== frame_val) fr_bad_data = fr_bad_data + 1;
            end
            if (lr_fall_t != 0 && frames > 1 && ($time - lr_fall_t) != 20000) fr_bad_len = fr_bad_len + 1;
            lr_fall_t = $time;
            frames = frames + 1;
            bits_in_frame = 0;
            frame_val = latched;
        end
        fshift = {fshift[62:0], sdat};
        bits_in_frame = bits_in_frame + 1;
        prev_lr = lrclk;
    end

    integer frames48 = 0; reg prev48 = 1;
    always @(posedge bclk2) begin
        if (prev48 == 1'b1 && lrclk2 == 1'b0) frames48 = frames48 + 1;
        prev48 = lrclk2;
    end

    integer i, mism1, mism2, f0, f48a, scnt = 0;
    always @(negedge clk) if (!rst) begin
        scnt = scnt + 1;
        if (scnt == 3000) begin scnt = 0; sample = $random; end
    end
    initial begin
        ne = 0;
        add_reg(16'h4000, 8'h0E); add_pll; add_reg(16'h4000, 8'h0F);
        add_reg(16'h4015, 8'h00); add_reg(16'h4016, 8'h00); add_reg(16'h4017, 8'h00);
        add_reg(16'h401C, 8'h21); add_reg(16'h401E, 8'h41); add_reg(16'h4020, 8'h03); add_reg(16'h4021, 8'h09);
        add_reg(16'h4023, 8'hE7); add_reg(16'h4024, 8'hE7); add_reg(16'h4025, 8'hE6); add_reg(16'h4026, 8'hE6);
        add_reg(16'h4029, 8'h03); add_reg(16'h402A, 8'h03); add_reg(16'h40F2, 8'h01);
        add_reg(16'h40F9, 8'h7F); add_reg(16'h40FA, 8'h03);

        repeat (5) @(negedge clk); rst = 0;
        check(adr0 === 1'b1 && adr1 === 1'b1, "codec address pins high (I2C address 0x3B)");
        check(scl === 1'b1 && sda === 1'b1, "I2C bus idle after reset");

        // audio: a new value every 3000 clocks (not frame-aligned on purpose)
        wait (done === 1'b1 && done2 === 1'b1);
        repeat (100) @(negedge clk);

        check(t1 == 19, "50 kHz: 19 I2C transactions");
        check(n1 == ne, "50 kHz: byte count matches the register list");
        mism1 = 0; for (i = 0; i < ne; i = i + 1) if (log1[i] !== exp50[i]) mism1 = mism1 + 1;
        check(mism1 == 0, "50 kHz: every I2C byte matches (address, subaddress, data, PLL burst)");
        check(nack === 1'b0 && done === 1'b1, "50 kHz: all bytes acknowledged, configuration done");
        check(t2 == 19 && n2 == ne, "48 kHz: 19 transactions, byte count");
        mism2 = 0; for (i = 0; i < ne; i = i + 1) if (log2[i] !== exp48[i]) mism2 = mism2 + 1;
        check(mism2 == 0, "48 kHz: every I2C byte matches (PLL M = 625, N = 572, R = 4)");
        check(nack2 === 1'b0 && done2 === 1'b1, "48 kHz: all acknowledged, done");
        check(m_per > 99.9 && m_per < 100.1, "MCLK period 100 ns (10 MHz)");

        f0 = frames; f48a = frames48;
        repeat (100_000) @(negedge clk);                 // 1 ms
        check(frames - f0 == 50, "50 kHz: 50 frames per millisecond");
        check(frames48 - f48a >= 47 && frames48 - f48a <= 49, "48 kHz: 48 frames per millisecond");
        repeat (200_000) @(negedge clk);
        check(frames > 100, "I2S running");
        check(fr_bad_len == 0, "every 50 kHz frame is exactly 2000 clocks");
        check(fr_bad_bits == 0, "every frame has 64 bit clocks");
        check(fr_bad_data == 0, "left and right words equal the sample latched at the frame start");

        if (errors == 0) $display("ALL PASS (%0d checks)", checks);
        else             $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule

`default_nettype wire
