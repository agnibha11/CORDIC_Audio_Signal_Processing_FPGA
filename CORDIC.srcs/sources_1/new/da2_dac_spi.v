`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
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
    output reg         dac_sclk               // DA2 pin 4 (SCLK)
);

    (* dont_touch = "true" *) reg sclk_nq;     // = ~dac_sclk

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
            dac_sclk <= 1'b0; sclk_nq <= 1'b1;
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
                            dac_sclk <= 1'b1; sclk_nq <= 1'b0;
                            if (nfall != 5'd0) begin
                                sha      <= {sha[14:0], 1'b0};
                                shb      <= {shb[14:0], 1'b0};
                                dac_dina <= sha[14];
                                dac_dinb <= shb[14];
                            end
                        end else begin
                            // falling edge: DAC latches DIN
                            dac_sclk <= 1'b0; sclk_nq <= 1'b1;
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
