`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
// ============================================================================
module mic_adc_spi #(
    parameter integer SCLK_DIV = 20          // clk cycles per SCLK period (even)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,                // begin one conversion (pulse)
    output reg         busy,
    output reg         valid,                // one-cycle pulse: `data` updated
    output reg  [11:0] data,
    // Pmod pins
    output reg         adc_cs_n,             // MIC pin 1  (SS)
    output reg         adc_sclk,             // MIC pin 4  (SCK)
    input  wire        adc_miso              // MIC pin 3  (MISO), already synchronised
);

    // SCLK is held in two registers.  The port register adc_sclk drives only the pin, so
    // it is packed into the I/O cell (IOB TRUE in the XDC) and leaves the chip at the
    // same instant as the other SPI outputs.  sclk_nq holds the complement and is the
    // copy the state machine reads back.  Because the two hold different values,
    // synthesis cannot merge them.  No attribute is placed on the port register:
    // with KEEP or DONT_TOUCH on it, Vivado reported that it no longer connected
    // directly to the I/O cell and did not pack it.
    (* dont_touch = "true" *) reg sclk_nq;     // = ~adc_sclk

    localparam integer HALF = SCLK_DIV / 2;

    localparam [1:0] S_IDLE = 2'd0,
                     S_XFER = 2'd1,
                     S_TAIL = 2'd2;

    reg [1:0]  st;
    reg [7:0]  div;
    reg [4:0]  nbits;        // falling edges seen so far (bits captured)
    reg [15:0] sh;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            st       <= S_IDLE;
            adc_cs_n <= 1'b1;
            adc_sclk <= 1'b1; sclk_nq <= 1'b0;
            busy     <= 1'b0;
            div      <= 8'd0;
            nbits    <= 5'd0;
            sh       <= 16'd0;
            data     <= 12'd0;
        end else begin
            case (st)
                S_IDLE: begin
                    adc_cs_n <= 1'b1;
                    adc_sclk <= 1'b1; sclk_nq <= 1'b0;
                    if (start) begin
                        adc_cs_n <= 1'b0;             // sample instant
                        busy     <= 1'b1;
                        div      <= 8'd0;
                        nbits    <= 5'd0;
                        st       <= S_XFER;
                    end
                end
                S_XFER: begin
                    if (div == HALF - 1) begin
                        div <= 8'd0;
                        if (!sclk_nq) begin
                            // falling edge: capture the bit launched one period ago
                            adc_sclk <= 1'b0; sclk_nq <= 1'b1;
                            sh       <= {sh[14:0], adc_miso};
                            nbits    <= nbits + 5'd1;
                        end else begin
                            adc_sclk <= 1'b1; sclk_nq <= 1'b0;         // rising edge
                            if (nbits == 5'd16)
                                st <= S_TAIL;
                        end
                    end else begin
                        div <= div + 8'd1;
                    end
                end
                S_TAIL: begin
                    if (div == HALF - 1) begin
                        div      <= 8'd0;
                        adc_cs_n <= 1'b1;
                        busy     <= 1'b0;
                        valid    <= 1'b1;
                        data     <= sh[11:0];         // sh[15:12] are the leading zeros
                        st       <= S_IDLE;
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
