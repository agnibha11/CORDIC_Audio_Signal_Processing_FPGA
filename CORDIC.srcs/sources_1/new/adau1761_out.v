`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  adau1761_out.v -- plays one mono audio signal on both channels of the
//                    ZedBoard's on-board ADAU1761 codec (HPH OUT and LINE OUT)
//
//  This is an additional audio output; the Pmod AMP2 path is unchanged and
//  plays the same signal.
//
//    MCLK  : 10 MHz square wave (100 MHz / 10), the codec PLL's reference
//    I2C   : codec_i2c_init configures the codec once after reset
//    I2S   : i2s_tx sends the sample on both channels, FPGA is clock master
//    ADDR  : both address pins high -> I2C address 0x3B
//
//  The codec sample rate FS must match the PLL set-up in codec_i2c_init;
//  50 kHz (the design's own rate) by default, 48 kHz as a fallback (the
//  sample is then simply held from the 50 kHz stream).
// ============================================================================
module adau1761_out #(
    parameter integer CLK_HZ     = 100_000_000,
    parameter integer FS         = 50_000,
    parameter integer START_WAIT = 5_000_000,
    parameter integer PLL_WAIT   = 2_000_000,
    parameter integer CORE_WAIT  = 100_000
)(
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] sample,        // played on left and right
    output reg                ac_mclk,
    output wire               ac_bclk,
    output wire               ac_lrclk,
    output wire               ac_sdata,      // FPGA -> codec DAC data (AC-GPIO0)
    output wire               ac_adr0,
    output wire               ac_adr1,
    output wire               scl_o,         // open drain: 0 = pull low, 1 = release
    output wire               sda_o,
    input  wire               sda_in,        // raw SDA pin
    output wire               cfg_done,
    output wire               cfg_nack
);
    assign ac_adr0 = 1'b1;
    assign ac_adr1 = 1'b1;

    // MCLK = clk / 10
    reg [2:0] mdiv;
    always @(posedge clk) begin
        if (rst) begin
            mdiv <= 3'd0; ac_mclk <= 1'b0;
        end else if (mdiv == 3'd4) begin
            mdiv <= 3'd0; ac_mclk <= ~ac_mclk;
        end else
            mdiv <= mdiv + 3'd1;
    end

    // SDA read-back through two flops (only used to check acknowledges)
    reg [1:0] sda_s;
    always @(posedge clk) sda_s <= {sda_s[0], sda_in};

    codec_i2c_init #(
        .CLK_HZ(CLK_HZ), .FS(FS),
        .START_WAIT(START_WAIT), .PLL_WAIT(PLL_WAIT), .CORE_WAIT(CORE_WAIT)
    ) u_i2c (
        .clk(clk), .rst(rst),
        .scl_o(scl_o), .sda_o(sda_o), .sda_i(sda_s[1]),
        .done(cfg_done), .nack(cfg_nack)
    );

    wire frame_start;
    i2s_tx #(.CLK_HZ(CLK_HZ), .FS(FS)) u_i2s (
        .clk(clk), .rst(rst),
        .left(sample), .right(sample),
        .bclk(ac_bclk), .lrclk(ac_lrclk), .sdata(ac_sdata),
        .frame_start(frame_start)
    );
endmodule

`default_nettype wire
