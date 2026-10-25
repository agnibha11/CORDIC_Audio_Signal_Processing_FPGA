`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_recip_divider.v -- restoring divider against the simulator's "/"
//  (a different algorithm: the DUT is bit-serial restoring division, the
//  reference is 64-bit integer division).  Also checks latency and den = 0.
// ============================================================================
module tb_recip_divider;
    localparam integer NS = 39, DW = 26, QW = 32;
    reg clk = 0, rst = 1, start = 0;
    always #5 clk = ~clk;
    reg  [DW-1:0] den = 0;
    wire busy, done;
    wire [QW-1:0] quot;
    recip_divider #(.NUM_SHIFT(NS), .DEN_W(DW), .Q_W(QW)) dut (.clk(clk), .rst(rst), .start(start), .den(den), .busy(busy), .done(done), .quot(quot));

    integer checks = 0, errors = 0, lat, i;
    reg [63:0] exp64;
    task check; input cond; input [8*64-1:0] msg;
        begin checks = checks + 1; if (!cond) begin errors = errors + 1; if (errors < 20) $display("FAIL @%0t: %0s", $time, msg); end end
    endtask

    task divide; input [DW-1:0] d;
        begin
            den = d;
            @(negedge clk); start = 1; @(negedge clk); start = 0; lat = 1;
            while (!done) begin @(negedge clk); lat = lat + 1; end
            if (d == 0) exp64 = 0; else begin exp64 = (64'd1 << NS) / d; if (exp64 > 64'hFFFF_FFFF) exp64 = 64'hFFFF_FFFF; end
            check(quot == exp64[QW-1:0], "quotient");
            if (quot != exp64[QW-1:0] && errors < 20) $display("   den=%0d got %0d exp %0d", d, quot, exp64);
            if (d != 0) check(lat == NS + 3, "latency");
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst = 0;
        divide(0); divide(1); divide(2); divide(3); divide(26'h3FFFFFF); divide(26'h2000000); divide(2097); divide(53961); divide(10653456);
        for (i = 0; i < 500; i = i + 1) divide($urandom);
        for (i = 0; i < 200; i = i + 1) divide($urandom % 5000 + 1);
        $display("latency = %0d clocks", lat);
        if (errors == 0) $display("ALL PASS (%0d checks)", checks); else $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
