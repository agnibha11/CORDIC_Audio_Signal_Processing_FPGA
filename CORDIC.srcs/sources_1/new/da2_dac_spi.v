`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  da2_dac_spi.v -- SPI master for the Pmod DA2 (two TI DAC121S101, 12-bit)
//
//  The two DACs share SYNC and SCLK and have separate data inputs DINA/DINB,
//  so both channels are updated with ONE 16-clock frame.
//
//  Frame (DAC121S101 datasheet 8.5.2):  X X PD1 PD0 D11 ... D0, MSB first.
//  PD1:PD0 = 00 selects normal operation.
//    * DIN is latched on FALLING edges of SCLK while SYNC is low.
//    * The DAC register updates on the 16th falling edge.
//    * SYNC must be high >= t_SYNC (20 ns) before the next frame.
//  To respect the DAC's setup/hold (a few ns) with margin, DIN changes only
//  on RISING edges of SCLK, i.e. half a period (100 ns) away from the
//  latching edge.  SCLK idles low here (either polarity is legal).
//
//  Timing at SCLK_DIV = 20: 33 half-periods = 3.3 us per update.
//  f_SCLK max = 30 MHz.
// ============================================================================
module da2_dac_spi #(
    parameter integer SCLK_DIV = 20
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,                // pulse: send data_a/data_b
    input  wire [11:0] data_a,               // unsigned DAC codes
    input  wire [11:0] data_b,
    output reg         busy,
    output reg         done,
    // Pmod pins
    output reg         dac_sync_n,           // DA2 pin 1 (~SYNC)
    output reg         dac_dina,             // DA2 pin 2 (DINA)
    output reg         dac_dinb,             // DA2 pin 3 (DINB)
    output wire        dac_sclk               // DA2 pin 4 (SCLK)
);

    // SCLK is held in two registers.  sclk_pad drives only the pin, so it can be
    // packed into the I/O cell (IOB TRUE in the XDC) and leaves the chip at the same
    // instant as the other SPI outputs.  sclk_nq holds the complement and is the copy
    // the state machine reads back.  Storing the complement makes the two registers
    // logically different, so synthesis cannot merge them into one (it did merge two
    // identical copies despite KEEP); DONT_TOUCH is a second guard.
    (* dont_touch = "true" *) reg sclk_pad;
    (* dont_touch = "true" *) reg sclk_nq;     // = ~sclk_pad
    assign dac_sclk = sclk_pad;

    localparam integer HALF = SCLK_DIV / 2;

    localparam [1:0] S_IDLE = 2'd0,
                     S_XFER = 2'd1,
                     S_TAIL = 2'd2;

    reg [1:0]  st;
    reg [7:0]  div;
    reg [4:0]  nfall;        // falling edges issued
    reg [15:0] sha, shb;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            st         <= S_IDLE;
            dac_sync_n <= 1'b1;
            sclk_pad <= 1'b0; sclk_nq <= 1'b1;
            dac_dina   <= 1'b0;
            dac_dinb   <= 1'b0;
            busy       <= 1'b0;
            div        <= 8'd0;
            nfall      <= 5'd0;
            sha        <= 16'd0;
            shb        <= 16'd0;
        end else begin
            case (st)
                S_IDLE: begin
                    if (start) begin
                        sha        <= {2'b00, 2'b00, data_a};
                        shb        <= {2'b00, 2'b00, data_b};
                        dac_dina   <= 1'b0;             // bit 15 of the frame (don't care = 0)
                        dac_dinb   <= 1'b0;
                        dac_sync_n <= 1'b0;
                        busy       <= 1'b1;
                        div        <= 8'd0;
                        nfall      <= 5'd0;
                        st         <= S_XFER;
                    end
                end
                S_XFER: begin
                    if (div == HALF - 1) begin
                        div <= 8'd0;
                        if (sclk_nq) begin
                            // rising edge: present the next bit (except before the first latch)
                            sclk_pad <= 1'b1; sclk_nq <= 1'b0;
                            if (nfall != 5'd0) begin
                                sha      <= {sha[14:0], 1'b0};
                                shb      <= {shb[14:0], 1'b0};
                                dac_dina <= sha[14];
                                dac_dinb <= shb[14];
                            end
                        end else begin
                            // falling edge: DAC latches DIN
                            sclk_pad <= 1'b0; sclk_nq <= 1'b1;
                            nfall    <= nfall + 5'd1;
                            if (nfall == 5'd15)
                                st <= S_TAIL;           // that was the 16th falling edge
                        end
                    end else begin
                        div <= div + 8'd1;
                    end
                end
                S_TAIL: begin
                    if (div == HALF - 1) begin
                        div        <= 8'd0;
                        dac_sync_n <= 1'b1;
                        dac_dina   <= 1'b0;
                        dac_dinb   <= 1'b0;
                        busy       <= 1'b0;
                        done       <= 1'b1;
                        st         <= S_IDLE;
                    end else begin
                        div <= div + 8'd1;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
