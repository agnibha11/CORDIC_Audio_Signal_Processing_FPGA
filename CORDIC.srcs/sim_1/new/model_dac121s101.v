`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
// ============================================================================
module model_dac121s101 (
    input  wire        sync_n,
    input  wire        sclk,
    input  wire        din,
    output reg  [11:0] dac_reg,
    output reg  [1:0]  pd_mode,
    output reg  [31:0] updates,
    output reg  [31:0] protocol_errors
);
    reg  [15:0] sh;
    reg  [4:0]  nfall;
    reg         started;
    realtime    t_din_change;

    initial begin
        dac_reg = 0; pd_mode = 0; updates = 0; protocol_errors = 0; sh = 0; nfall = 0; t_din_change = 0; started = 0;
    end

    always @(din) t_din_change = $realtime;

    always @(negedge sync_n) begin
        nfall   = 0;
        sh      = 0;
        started = 1;
    end

    always @(negedge sclk) begin
        if (!sync_n) begin
            // setup check: DIN must have been stable >= 4.5 ns before this edge
            if ($realtime - t_din_change < 4.5) protocol_errors = protocol_errors + 1;
            sh    = {sh[14:0], din};
            nfall = nfall + 1;
            if (nfall == 16) begin
                pd_mode = sh[13:12];
                if (sh[13:12] == 2'b00) dac_reg = sh[11:0];
                updates = updates + 1;
            end
        end
    end

    always @(posedge sync_n) begin
        if (started && nfall != 16) protocol_errors = protocol_errors + 1;
        started = 0;
    end
endmodule
`default_nettype wire
