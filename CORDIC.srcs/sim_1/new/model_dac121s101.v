`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  model_dac121s101.v -- behavioural model of one DAC121S101 (Pmod DA2 channel)
//
//  Shifts DIN in on every FALLING SCLK edge while SYNC is low.  On the 16th
//  falling edge the frame is decoded: the DAC register takes D11..D0 if
//  PD1:PD0 = 00, otherwise the power-down mode is recorded.  Setup/hold of
//  DIN around the latching edge are checked against the datasheet limits
//  (tDS = 4.5 ns, tDHD = 4.5 ns worst case) and counted as protocol errors,
//  as are frames shorter than 16 clocks.
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
