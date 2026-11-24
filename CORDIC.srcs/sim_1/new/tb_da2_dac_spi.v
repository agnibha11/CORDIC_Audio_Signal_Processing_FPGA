`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
// ============================================================================
module tb_da2_dac_spi;
    localparam integer SCLK_DIV = 20;
    reg clk = 0, rst = 1, start = 0;
    always #5 clk = ~clk;
    reg  [11:0] da = 0, db = 0;
    wire busy, done, sync_n, dina, dinb, sclk;
    wire [11:0] ra, rb;
    wire [1:0]  pa, pb;
    wire [31:0] ua, ub, ea, eb;

    da2_dac_spi #(.SCLK_DIV(SCLK_DIV)) dut (
        .clk(clk), .rst(rst), .start(start), .data_a(da), .data_b(db), .busy(busy), .done(done),
        .dac_sync_n(sync_n), .dac_dina(dina), .dac_dinb(dinb), .dac_sclk(sclk)
    );
    model_dac121s101 m_a (.sync_n(sync_n), .sclk(sclk), .din(dina), .dac_reg(ra), .pd_mode(pa), .updates(ua), .protocol_errors(ea));
    model_dac121s101 m_b (.sync_n(sync_n), .sclk(sclk), .din(dinb), .dac_reg(rb), .pd_mode(pb), .updates(ub), .protocol_errors(eb));

    integer checks = 0, errors = 0;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    realtime t_sync_fall, t_sync_rise;
    integer nfall = 0;
    always @(negedge sync_n) begin t_sync_fall = $realtime; nfall = 0; end
    always @(posedge sync_n) t_sync_rise = $realtime;
    always @(negedge sclk) if (!sync_n) nfall = nfall + 1;

    task send;
        input [11:0] a, b;
        begin
            da = a; db = b;
            @(negedge clk); start = 1; @(negedge clk); start = 0;
            check(busy, "busy after start");
            while (!done) @(negedge clk);
            check(ra == a && rb == b, "both DAC registers updated");
            check(pa == 2'b00 && pb == 2'b00, "normal operation (PD=00)");
            check(nfall == 16, "16 falling edges");
            check(ea == 0 && eb == 0, "no protocol errors");
            check(sync_n == 1'b1 && sclk == 1'b0 && dina == 1'b0 && dinb == 1'b0, "idle levels");
            check(t_sync_rise - t_sync_fall == 33 * (SCLK_DIV / 2) * 10.0, "frame = 33 half periods");
            repeat (6) @(negedge clk);
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(negedge clk); rst = 0;
        send(12'h000, 12'hFFF); send(12'hFFF, 12'h000); send(12'h800, 12'h7FF); send(12'hA5A, 12'h5A5); send(12'h001, 12'h002);
        for (i = 0; i < 40; i = i + 1) send($urandom, $urandom);
        check(ua == 45 && ub == 45, "45 updates per channel");
        $display("frame time = %0.1f us", (t_sync_rise - t_sync_fall) / 1000.0);
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
