`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  recip_divider.v -- sequential restoring divider:  quot = floor(2^NUM_SHIFT / den)
//
//  The demodulator recovers a phase / frequency / envelope deviation whose
//  scale depends on the modulation index.  Multiplying that deviation by this
//  reciprocal restores the original audio amplitude for ANY parameter
//  setting, so "original" and "demodulated" can be compared directly on the
//  VGA scope and by the fidelity meter.  A division is only needed when a
//  parameter changes (microseconds, not per sample), so a 1-bit-per-clock
//  restoring divider is the right size: NUM_SHIFT+2 clocks per result.
//  den = 0 yields quot = 0 (demodulator muted).
// ============================================================================
module recip_divider #(
    parameter integer NUM_SHIFT = 39,   // numerator = 2^NUM_SHIFT
    parameter integer DEN_W     = 26,
    parameter integer Q_W       = 32
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [DEN_W-1:0] den,
    output reg              busy,
    output reg              done,       // one-cycle pulse; `quot` valid from this cycle on
    output reg  [Q_W-1:0]   quot
);
    reg [DEN_W-1:0]   d;
    reg [DEN_W:0]     rem;
    reg [NUM_SHIFT:0] q;
    reg [6:0]         bitpos;
    reg               last;

    // next partial remainder: shift in the current numerator bit (only bit NUM_SHIFT is 1)
    wire [DEN_W:0] rem_sh = {rem[DEN_W-1:0], (bitpos == NUM_SHIFT) ? 1'b1 : 1'b0};
    wire           ge     = (rem_sh >= {1'b0, d});

    always @(posedge clk) begin
        done <= 1'b0;
        last <= 1'b0;
        if (rst) begin
            busy   <= 1'b0;
            quot   <= {Q_W{1'b0}};
            rem    <= {(DEN_W+1){1'b0}};
            q      <= {(NUM_SHIFT+1){1'b0}};
            d      <= {DEN_W{1'b0}};
            bitpos <= 7'd0;
        end else if (last) begin
            // q is complete: clamp to Q_W bits and publish
            quot <= (|q[NUM_SHIFT:Q_W]) ? {Q_W{1'b1}} : q[Q_W-1:0];
            done <= 1'b1;
            busy <= 1'b0;
        end else if (!busy) begin
            if (start) begin
                if (den == {DEN_W{1'b0}}) begin
                    quot <= {Q_W{1'b0}};
                    done <= 1'b1;
                end else begin
                    d      <= den;
                    rem    <= {(DEN_W+1){1'b0}};
                    q      <= {(NUM_SHIFT+1){1'b0}};
                    bitpos <= NUM_SHIFT[6:0];
                    busy   <= 1'b1;
                end
            end
        end else begin
            rem       <= ge ? (rem_sh - {1'b0, d}) : rem_sh;
            q[bitpos] <= ge;
            if (bitpos == 7'd0)
                last <= 1'b1;
            else
                bitpos <= bitpos - 7'd1;
        end
    end
endmodule
`default_nettype wire
