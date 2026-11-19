`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  codec_i2c_init.v -- writes the ADAU1761 register set over I2C once after
//                      reset (write-only I2C master, about 100 kHz)
//
//  ADAU1761 I2C: 7-bit address 0x3B (ADDR1 = ADDR0 = 1, driven by the FPGA),
//  so the write address byte is 0x76.  Each register write is
//      START, 0x76, subaddress high, subaddress low, data byte(s), STOP
//  The PLL control register (0x4002) is six bytes long and written in one
//  burst.
//
//  Clocking set-up (FS = 50 kHz, FPGA supplies MCLK = 10 MHz):
//      core clock = 1024 x FS = 51.2 MHz, made by the codec's PLL in
//      fractional mode: 10 MHz x (R + N/M) = 10 MHz x (5 + 3/25).
//  For FS = 48 kHz the same PLL gives 49.152 MHz = 10 MHz x (4 + 572/625).
//
//  Register sequence (values from the ADAU1761 data sheet register map):
//    0  0x4000 = 0x0E  clock control: PLL is the clock source, core off
//    1  0x4002 = PLL   M, N, R, X = 1, fractional, PLL on      (wait PLL_WAIT)
//    2  0x4000 = 0x0F  core clock on                            (wait 1 ms)
//    3  0x4015 = 0x00  serial port 0: codec is slave (FPGA drives BCLK/LRCLK)
//    4  0x4016 = 0x00  serial port 1: 64 bit clocks per frame, I2S
//    5  0x4017 = 0x00  converter 0: sample rate = core / 1024
//    6  0x401C = 0x21  left playback mixer: left DAC on, mixer on
//    7  0x401E = 0x41  right playback mixer: right DAC on, mixer on
//    8  0x4020 = 0x03  left line-out mixer: left playback mixer, 0 dB
//    9  0x4021 = 0x09  right line-out mixer: right playback mixer, 0 dB
//   10  0x4023 = 0xE7  left headphone: 0 dB, unmuted, enabled
//   11  0x4024 = 0xE7  right headphone: 0 dB, unmuted, enabled
//   12  0x4025 = 0xE6  left line out: 0 dB, unmuted, line mode
//   13  0x4026 = 0xE6  right line out: 0 dB, unmuted, line mode
//   14  0x4029 = 0x03  playback power: left and right on
//   15  0x402A = 0x03  DAC control: both DACs on
//   16  0x40F2 = 0x01  serial input L0/R0 -> DACs (DSP bypassed)
//   17  0x40F9 = 0x7F  clock enable 0: all blocks
//   18  0x40FA = 0x03  clock enable 1: both clock generators
//
//  SCL and SDA are open drain: an output of 0 pulls the line low, 1 releases
//  it (the top level turns that into 0 / high impedance).  The codec never
//  stretches the clock, so SCL is not read back.  A missing acknowledge sets
//  the sticky `nack` flag (shown on LED LD7) but the sequence carries on.
// ============================================================================
module codec_i2c_init #(
    parameter integer CLK_HZ      = 100_000_000,
    parameter integer I2C_HZ      = 100_000,
    parameter integer FS          = 50_000,
    parameter integer START_WAIT  = 5_000_000,   // 50 ms after reset (codec power-up)
    parameter integer PLL_WAIT    = 2_000_000,   // 20 ms for the PLL to lock
    parameter integer CORE_WAIT   = 100_000      // 1 ms after the core clock is enabled
)(
    input  wire clk,
    input  wire rst,
    output reg  scl_o,          // 1 = released, 0 = pull low
    output reg  sda_o,
    input  wire sda_i,          // synchronised SDA (for acknowledge)
    output reg  done,
    output reg  nack
);
    localparam integer QDIV   = CLK_HZ / (4 * I2C_HZ);  // clocks per quarter bit
    localparam [7:0]   DEVADR = 8'h76;                  // 0x3B << 1, write
    localparam integer NTXN   = 19;

    // PLL bytes for the chosen sample rate
    localparam [15:0] PLL_M = (FS == 48_000) ? 16'd625 : 16'd25;
    localparam [15:0] PLL_N = (FS == 48_000) ? 16'd572 : 16'd3;
    localparam [3:0]  PLL_R = (FS == 48_000) ? 4'd4    : 4'd5;
    localparam [7:0]  PLL_B4 = {1'b0, PLL_R, 2'b00, 1'b1};  // R, X = /1, fractional

    // number of bytes after the device address
    function [3:0] txn_len;
        input [4:0] t;
        txn_len = (t == 5'd1) ? 4'd8 : 4'd3;
    endfunction

    function [7:0] txn_byte;
        input [4:0] t;
        input [2:0] i;
        reg [15:0] sub;
        reg [7:0]  dat;
        begin
            case (t)
                5'd0:  begin sub = 16'h4000; dat = 8'h0E; end
                5'd1:  begin sub = 16'h4002; dat = 8'h00; end
                5'd2:  begin sub = 16'h4000; dat = 8'h0F; end
                5'd3:  begin sub = 16'h4015; dat = 8'h00; end
                5'd4:  begin sub = 16'h4016; dat = 8'h00; end
                5'd5:  begin sub = 16'h4017; dat = 8'h00; end
                5'd6:  begin sub = 16'h401C; dat = 8'h21; end
                5'd7:  begin sub = 16'h401E; dat = 8'h41; end
                5'd8:  begin sub = 16'h4020; dat = 8'h03; end
                5'd9:  begin sub = 16'h4021; dat = 8'h09; end
                5'd10: begin sub = 16'h4023; dat = 8'hE7; end
                5'd11: begin sub = 16'h4024; dat = 8'hE7; end
                5'd12: begin sub = 16'h4025; dat = 8'hE6; end
                5'd13: begin sub = 16'h4026; dat = 8'hE6; end
                5'd14: begin sub = 16'h4029; dat = 8'h03; end
                5'd15: begin sub = 16'h402A; dat = 8'h03; end
                5'd16: begin sub = 16'h40F2; dat = 8'h01; end
                5'd17: begin sub = 16'h40F9; dat = 8'h7F; end
                default: begin sub = 16'h40FA; dat = 8'h03; end
            endcase
            if (t == 5'd1)
                case (i)
                    3'd0: txn_byte = sub[15:8];
                    3'd1: txn_byte = sub[7:0];
                    3'd2: txn_byte = PLL_M[15:8];
                    3'd3: txn_byte = PLL_M[7:0];
                    3'd4: txn_byte = PLL_N[15:8];
                    3'd5: txn_byte = PLL_N[7:0];
                    3'd6: txn_byte = PLL_B4;
                    default: txn_byte = 8'h01;      // PLL enable
                endcase
            else
                case (i)
                    3'd0: txn_byte = sub[15:8];
                    3'd1: txn_byte = sub[7:0];
                    default: txn_byte = dat;
                endcase
        end
    endfunction

    function [31:0] txn_wait;                        // pause after the STOP
        input [4:0] t;
        txn_wait = (t == 5'd1) ? PLL_WAIT : (t == 5'd2) ? CORE_WAIT : 4 * QDIV;
    endfunction

    localparam [2:0] S_WAIT = 3'd0, S_START = 3'd1, S_BIT = 3'd2, S_STOP = 3'd3, S_DONE = 3'd4;

    reg [2:0]  st;
    reg [31:0] wcnt;            // wait counter
    reg [15:0] qcnt;            // quarter-bit divider
    reg [1:0]  q;               // quarter inside the current bit / condition
    reg [4:0]  txn;
    reg [3:0]  bidx;            // byte index: 0 = device address, 1.. = txn bytes
    reg [3:0]  bitn;            // 0..7 data bits (MSB first), 8 = acknowledge
    reg [7:0]  sh;

    wire tick = (qcnt == QDIV - 1);
    wire [7:0] next_byte = txn_byte(txn, bidx[2:0]);   // byte bidx+1 of the frame

    always @(posedge clk) begin
        if (rst) begin
            st <= S_WAIT; wcnt <= START_WAIT; qcnt <= 16'd0; q <= 2'd0;
            txn <= 5'd0; bidx <= 4'd0; bitn <= 4'd0; sh <= DEVADR;
            scl_o <= 1'b1; sda_o <= 1'b1; done <= 1'b0; nack <= 1'b0;
        end else begin
            qcnt <= tick ? 16'd0 : qcnt + 16'd1;
            case (st)
                S_WAIT:
                    if (wcnt != 32'd0) wcnt <= wcnt - 32'd1;
                    else if (tick) begin st <= S_START; q <= 2'd0; end
                S_START:
                    if (tick) begin
                        q <= q + 2'd1;
                        case (q)
                            2'd0: begin scl_o <= 1'b1; sda_o <= 1'b1; end
                            2'd1: sda_o <= 1'b0;                       // START: SDA falls, SCL high
                            2'd2: scl_o <= 1'b0;
                            default: begin st <= S_BIT; bidx <= 4'd0; bitn <= 4'd0; sh <= DEVADR; end
                        endcase
                    end
                S_BIT:
                    if (tick) begin
                        q <= q + 2'd1;
                        case (q)
                            2'd0: begin scl_o <= 1'b0; sda_o <= (bitn == 4'd8) ? 1'b1 : sh[7]; end
                            2'd1: scl_o <= 1'b1;
                            2'd2: if (bitn == 4'd8 && sda_i) nack <= 1'b1;   // acknowledge must be low
                            default: begin
                                scl_o <= 1'b0;
                                if (bitn != 4'd8) begin
                                    sh   <= {sh[6:0], 1'b0};
                                    bitn <= bitn + 4'd1;
                                end else if (bidx == txn_len(txn)) begin
                                    st <= S_STOP;
                                end else begin
                                    bidx <= bidx + 4'd1;
                                    bitn <= 4'd0;
                                    sh   <= next_byte;
                                end
                            end
                        endcase
                    end
                S_STOP:
                    if (tick) begin
                        q <= q + 2'd1;
                        case (q)
                            2'd0: begin scl_o <= 1'b0; sda_o <= 1'b0; end
                            2'd1: scl_o <= 1'b1;
                            2'd2: sda_o <= 1'b1;                       // STOP: SDA rises, SCL high
                            default: begin
                                if (txn == NTXN - 1) st <= S_DONE;
                                else begin
                                    wcnt <= txn_wait(txn);
                                    txn  <= txn + 5'd1;
                                    st   <= S_WAIT;
                                end
                            end
                        endcase
                    end
                default: begin                                         // S_DONE
                    scl_o <= 1'b1; sda_o <= 1'b1; done <= 1'b1;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
