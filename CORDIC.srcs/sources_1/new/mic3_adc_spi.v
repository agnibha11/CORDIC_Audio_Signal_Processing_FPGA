`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  mic3_adc_spi.v -- SPI master for the Pmod MIC3 (TI ADCS7476, 12-bit SAR)
//
//  Protocol (ADCS7476 datasheet, section 7.3 and Pmod MIC3 reference manual):
//    * SCLK idles HIGH.  A conversion starts on the falling edge of CS; the
//      analog input is sampled at that instant (track -> hold).
//    * The ADC shifts SDATA out on FALLING edges of SCLK: four leading zeros
//      followed by DB11..DB0.  "The sample bits ... are intended to be clocked
//      in by a receiver on subsequent falling edges", i.e. each bit is captured
//      one SCLK period after it was launched.  The LSB is valid on the 16th
//      falling edge, after which SDATA goes tri-state.
//    * After 16 SCLK periods CS returns high; t_QUIET (50 ns) must elapse
//      before the next conversion -- trivially satisfied at 50 kS/s.
//
//  Timing at SCLK_DIV = 20 (5 MHz SCLK from 100 MHz): 34 half-periods =
//  3.4 us per conversion.  f_SCLK max is 20 MHz; the ADC's data access time
//  (t_DACC <= 40 ns at 3 V) comfortably fits one 200 ns period.
//
//  `data` is the raw unsigned 12-bit code (0..4095, mid-scale ~ 2048).
// ============================================================================
module mic3_adc_spi #(
    parameter integer SCLK_DIV = 20          // clk cycles per SCLK period (even)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,                // begin one conversion (pulse)
    output reg         busy,
    output reg         valid,                // one-cycle pulse: `data` updated
    output reg  [11:0] data,
    // Pmod pins
    output reg         adc_cs_n,             // MIC3 pin 1  (SS)
    output reg         adc_sclk,             // MIC3 pin 4  (SCK)
    input  wire        adc_miso              // MIC3 pin 3  (MISO), already synchronised
);
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
            adc_sclk <= 1'b1;
            busy     <= 1'b0;
            div      <= 8'd0;
            nbits    <= 5'd0;
            sh       <= 16'd0;
            data     <= 12'd0;
        end else begin
            case (st)
                S_IDLE: begin
                    adc_cs_n <= 1'b1;
                    adc_sclk <= 1'b1;
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
                        if (adc_sclk) begin
                            // falling edge: capture the bit launched one period ago
                            adc_sclk <= 1'b0;
                            sh       <= {sh[14:0], adc_miso};
                            nbits    <= nbits + 5'd1;
                        end else begin
                            adc_sclk <= 1'b1;         // rising edge
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
