`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  i2s_tx.v -- I2S transmitter (FPGA is the clock master) for the ZedBoard's
//              ADAU1761 audio codec
//
//  Frame: 64 bit clocks, LRCLK low = left channel, high = right channel,
//  standard I2S timing: LRCLK and SDATA change on the falling edge of BCLK,
//  the codec samples on the rising edge, and the MSB follows the LRCLK edge
//  by one bit clock.  Each half frame carries the 16-bit sample, MSB first,
//  followed by zeros (the codec reads the first 24 bits, so the low 8 are 0).
//
//  BCLK = 64 x FS.  For FS = 50 kHz that is 3.2 MHz, which is not an integer
//  division of the 100 MHz clock, so the bit clock comes from a phase
//  accumulator (DDS): it adds 2 x 64 x FS every clock and toggles BCLK each
//  time the sum passes CLK_HZ.  A BCLK half period is therefore 15 or 16
//  clocks (150 / 160 ns), far above the codec's minimum, and the frame rate
//  is exactly FS on average.  At FS = 50 kHz one frame is exactly 2000 clocks,
//  the design's own sample period.
//
//  The left and right inputs are latched at the start of each frame (the
//  falling BCLK edge that begins the left half), so they may change at any
//  time without tearing a frame.
// ============================================================================
module i2s_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer FS     = 50_000
)(
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] left,
    input  wire signed [15:0] right,
    output reg                bclk,
    output reg                lrclk,
    output reg                sdata,
    output reg                frame_start      // one-clock pulse at each new frame
);
    localparam integer STEP = 2 * 64 * FS;      // BCLK edges per second

    reg  [27:0] acc;
    wire [28:0] acc_sum = {1'b0, acc} + STEP;
    wire        edge_now = (acc_sum >= CLK_HZ);

    reg  [5:0]  bitcnt;                          // bit position of the CURRENT bit
    reg  [15:0] lat_l, lat_r;

    wire [5:0]  n  = bitcnt + 6'd1;              // position of the bit that starts now
    wire [4:0]  j  = n[4:0];                     // position inside the half frame
    wire [15:0] ch = n[5] ? lat_r : lat_l;
    wire [4:0]  k  = 5'd16 - j;                  // sample bit index for j = 1..16

    always @(posedge clk) begin
        frame_start <= 1'b0;
        if (rst) begin
            acc    <= 28'd0;
            bclk   <= 1'b1;
            lrclk  <= 1'b1;
            sdata  <= 1'b0;
            bitcnt <= 6'd63;
            lat_l  <= 16'd0;
            lat_r  <= 16'd0;
        end else begin
            acc <= edge_now ? acc_sum - CLK_HZ : acc_sum[27:0];
            if (edge_now) begin
                if (bclk) begin                  // falling edge: start the next bit
                    bclk   <= 1'b0;
                    bitcnt <= n;
                    lrclk  <= n[5];
                    if (n == 6'd0) begin
                        lat_l       <= left;
                        lat_r       <= right;
                        frame_start <= 1'b1;
                        sdata       <= 1'b0;     // I2S: one-bit delay slot
                    end else if (j >= 5'd1 && j <= 5'd16)
                        sdata <= ch[k[3:0]];
                    else
                        sdata <= 1'b0;
                end else
                    bclk <= 1'b1;                // rising edge: codec samples
            end
        end
    end
endmodule

`default_nettype wire
