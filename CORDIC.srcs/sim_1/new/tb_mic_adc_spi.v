`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_mic_adc_spi.v -- ADC master against the behavioural ADCS7476 model
//  Checks: every 12-bit code is received exactly, the model sees exactly 16
//  SCLK periods per frame, no protocol violations, SCLK idles high, CS low
//  time = 33 half periods (3.3 us), and a restart while busy is ignored.
// ============================================================================
module tb_mic_adc_spi;
    localparam integer SCLK_DIV = 20;
    reg clk = 0, rst = 1, start = 0;
    always #5 clk = ~clk;

    wire busy, valid, cs_n, sclk, sdata;
    wire [11:0] data;
    reg  [11:0] analog = 12'd0;
    wire [31:0] conv, perr;

    mic_adc_spi #(.SCLK_DIV(SCLK_DIV)) dut (
        .clk(clk), .rst(rst), .start(start), .busy(busy), .valid(valid), .data(data),
        .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_miso(sdata)
    );
    model_adcs7476 adc (.cs_n(cs_n), .sclk(sclk), .sdata(sdata), .analog_code(analog),
                        .conversions(conv), .protocol_errors(perr));

    integer checks = 0, errors = 0;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    // count SCLK falling edges while CS is low, measure CS low time
    integer nfall = 0;
    realtime t_cs_fall, t_cs_rise;
    always @(negedge sclk) if (!cs_n) nfall = nfall + 1;
    always @(negedge cs_n) begin nfall = 0; t_cs_fall = $realtime; end
    always @(posedge cs_n) t_cs_rise = $realtime;

    task convert;
        input [11:0] code;
        begin
            analog = code;
            @(negedge clk); start = 1; @(negedge clk); start = 0;
            check(busy, "busy after start");
            while (!valid) @(negedge clk);
            check(data == code, "received code");
            check(nfall == 16, "16 falling edges per frame");
            check(perr == 0, "no protocol error");
            check(t_cs_rise - t_cs_fall == 33 * (SCLK_DIV / 2) * 10.0, "CS low = 33 half periods");
            check(sclk == 1'b1 && cs_n == 1'b1, "idle: SCLK high, CS high");
            repeat (10) @(negedge clk);
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(negedge clk); rst = 0;
        check(sclk == 1'b1 && cs_n == 1'b1, "reset idle state");
        convert(12'h000); convert(12'hFFF); convert(12'h800); convert(12'hA5A); convert(12'h5A5); convert(12'h001); convert(12'h800);
        for (i = 0; i < 40; i = i + 1) convert($urandom);
        check(conv == 47, "model saw 47 conversions");
        // a start while busy is ignored (no second conversion)
        analog = 12'h123;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        repeat (5) @(negedge clk); start = 1; @(negedge clk); start = 0;
        while (!valid) @(negedge clk);
        check(data == 12'h123, "code after ignored restart");
        repeat (400) @(negedge clk);
        check(conv == 48, "exactly one conversion for two starts");
        $display("conversion time = %0.1f us", (t_cs_rise - t_cs_fall) / 1000.0);
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
