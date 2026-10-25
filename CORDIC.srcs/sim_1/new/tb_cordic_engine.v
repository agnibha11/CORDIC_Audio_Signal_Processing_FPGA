`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  tb_cordic_engine.v -- self-checking test of the iterative CORDIC engine
//
//  T1  rotation over the full circle (4096 angles) against double-precision
//      $cos/$sin: |error| <= 2 LSB of the Q15 result
//  T2  bit-exact comparison with the Python reference model (cordic_vectors.mem)
//  T3  vectoring of 2000 random vectors against $atan2 / $hypot
//  T4  handshake: latency is exactly N+1 clocks, start while busy is ignored,
//      back-to-back jobs
//  Run with "run all"; the last line is "ALL PASS (n checks)".
// ============================================================================
module tb_cordic_engine;
    localparam integer W = 24, Z = 24, N = 18;
    localparam real    PI = 3.14159265358979323846;
    localparam signed [W-1:0] X0 = 318366;

    reg                 clk = 0, rst = 1, start = 0, vectoring = 0;
    reg  signed [W-1:0] x_in = 0, y_in = 0;
    reg         [Z-1:0] z_in = 0;
    wire                busy, done;
    wire signed [W-1:0] x_out, y_out;
    wire        [Z-1:0] z_out;

    cordic_engine #(.W(W), .Z(Z), .N(N)) dut (
        .clk(clk), .rst(rst), .start(start), .vectoring(vectoring),
        .x_in(x_in), .y_in(y_in), .z_in(z_in),
        .busy(busy), .done(done), .x_out(x_out), .y_out(y_out), .z_out(z_out)
    );

    always #5 clk = ~clk;

    integer checks = 0, errors = 0;
    task check;
        input cond;
        input [8*64-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                if (errors <= 20) $display("FAIL @%0t: %0s", $time, msg);
            end
        end
    endtask

    // run one job and wait for done; returns the latency in clocks
    integer lat;
    task run_job;
        input         vec;
        input  signed [W-1:0] xi, yi;
        input  [Z-1:0] zi;
        begin
            @(negedge clk);
            vectoring = vec; x_in = xi; y_in = yi; z_in = zi; start = 1;
            @(negedge clk);
            start = 0;
            lat = 1;
            while (!done) begin @(negedge clk); lat = lat + 1; end
        end
    endtask

    function signed [15:0] rnd16;
        input signed [W-1:0] v;
        reg   signed [W-1:0] t;
        begin t = v + 8; rnd16 = t[19:4]; end
    endfunction

    function real absr; input real r; begin absr = (r < 0.0) ? -r : r; end endfunction

    // ------------------------------------------------------------------
    localparam integer MAXVEC = 600;              // lines in cordic_vectors.mem
    reg  [31:0] vec [0:7*MAXVEC-1];
    integer k, nvec, i;
    real ang, ec, es, worst_rot, mag, an, ea, worst_ang, em, worst_mag;
    integer xi, yi;
    reg signed [Z-1:0] zs;

    initial begin
        $display("tb_cordic_engine: W=%0d Z=%0d N=%0d", W, Z, N);
        repeat (3) @(negedge clk);
        rst = 0;

        // ---------------- T1: rotation vs $cos/$sin ----------------
        worst_rot = 0.0;
        for (k = 0; k < 4096; k = k + 1) begin
            run_job(0, X0, 0, k << 12);
            ang = 2.0 * PI * k / 4096.0;
            ec  = absr(rnd16(x_out) - 32767.0 * $cos(ang));
            es  = absr(rnd16(y_out) - 32767.0 * $sin(ang));
            if (ec > worst_rot) worst_rot = ec;
            if (es > worst_rot) worst_rot = es;
            check(ec <= 2.0 && es <= 2.0, "T1 rotation accuracy");
        end
        $display("T1 rotation: worst |error| = %0.3f LSB (Q15) over 4096 angles", worst_rot);

        // ---------------- T2: bit-exact vs Python model ----------------
        for (i = 0; i < 7*MAXVEC; i = i + 1) vec[i] = 32'hXXXXXXXX;
        $readmemh("cordic_vectors.mem", vec);
        nvec = 0;
        while (nvec < MAXVEC && vec[7*nvec] !== 32'hXXXXXXXX) nvec = nvec + 1;
        $display("T2: %0d golden vectors", nvec);
        check(nvec > 500, "T2 vector file loaded");
        for (i = 0; i < nvec; i = i + 1) begin
            run_job(vec[7*i][0], vec[7*i+1][W-1:0], vec[7*i+2][W-1:0], vec[7*i+3][Z-1:0]);
            check(x_out == vec[7*i+4][W-1:0] && y_out == vec[7*i+5][W-1:0] && z_out == vec[7*i+6][Z-1:0],
                  "T2 bit-exact mismatch vs Python model");
            if (!(x_out == vec[7*i+4][W-1:0] && y_out == vec[7*i+5][W-1:0] && z_out == vec[7*i+6][Z-1:0]) && errors <= 20)
                $display("   vec %0d: mode %0d in(%0d,%0d,%h) got (%0d,%0d,%h) exp (%0d,%0d,%h)", i, vec[7*i][0],
                         $signed(vec[7*i+1][W-1:0]), $signed(vec[7*i+2][W-1:0]), vec[7*i+3][Z-1:0],
                         x_out, y_out, z_out, $signed(vec[7*i+4][W-1:0]), $signed(vec[7*i+5][W-1:0]), vec[7*i+6][Z-1:0]);
        end

        // ---------------- T3: vectoring vs $atan2 / $hypot ----------------
        worst_ang = 0.0; worst_mag = 0.0;
        for (k = 0; k < 2000; k = k + 1) begin
            mag = 4096.0 + ($urandom % 28672);
            an  = ($urandom % 1000000) * 2.0 * PI / 1000000.0 - PI;
            xi  = $rtoi(mag * $cos(an)); yi = $rtoi(mag * $sin(an));
            run_job(1, xi <<< 4, yi <<< 4, 0);
            zs  = z_out;
            ea  = zs * 2.0 * PI / 16777216.0 - $atan2(yi, xi);
            if (ea > PI)  ea = ea - 2.0 * PI;
            if (ea < -PI) ea = ea + 2.0 * PI;
            ea  = absr(ea);
            em  = absr(((x_out + 8) >>> 4) / 1.6467602581 - $hypot(xi, yi));   // 17-bit magnitude, K*32767 > 32767
            if (ea > worst_ang) worst_ang = ea;
            if (em > worst_mag) worst_mag = em;
            check(ea < 100.0e-6, "T3 vectoring angle");          // 100 urad; model worst case ~60 urad at |v| >= 4096
            check(em <= 2.0,     "T3 vectoring magnitude");
        end
        $display("T3 vectoring: worst angle error = %0.2f urad, worst magnitude error = %0.3f LSB", worst_ang * 1.0e6, worst_mag);

        // ---------------- T4: handshake ----------------
        run_job(0, X0, 0, 24'h200000);
        check(lat == N + 1, "T4 latency == N+1");
        $display("T4 latency = %0d clocks (expected %0d)", lat, N + 1);
        // start while busy must be ignored: issue a second start 3 cycles into a job
        @(negedge clk); vectoring = 0; x_in = X0; y_in = 0; z_in = 24'h100000; start = 1;
        @(negedge clk); start = 0;
        repeat (3) @(negedge clk);
        x_in = 0; y_in = X0; z_in = 24'h000000; start = 1;     // would give a different answer
        @(negedge clk); start = 0;
        while (!done) @(negedge clk);
        check(absr(rnd16(x_out) - 32767.0 * $cos(2.0*PI/16.0)) <= 2.0, "T4 start ignored while busy");
        // back-to-back: start on the cycle done is high
        @(negedge clk); x_in = X0; y_in = 0; z_in = 24'h000000; start = 1;
        @(negedge clk); start = 0;
        while (!done) @(negedge clk);
        x_in = X0; y_in = 0; z_in = 24'h400000; start = 1;     // +90 degrees
        @(negedge clk); start = 0;
        check(busy, "T4 busy right after back-to-back start");
        while (!done) @(negedge clk);
        check(absr(rnd16(x_out)) <= 2.0 && absr(rnd16(y_out) - 32767.0) <= 2.0, "T4 back-to-back result (+90 deg)");

        if (errors == 0) $display("ALL PASS (%0d checks)", checks);
        else             $display("FAILED: %0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
`default_nettype wire
