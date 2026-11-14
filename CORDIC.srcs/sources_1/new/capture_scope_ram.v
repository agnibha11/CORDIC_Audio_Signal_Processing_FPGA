`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  capture_scope_ram.v -- triggered, double-buffered capture of the original,
//                         channel (modulated + noise) and recovered signals
//                         in block RAM
//
//  Storage: 2 banks x 1024 samples x 48 bits ({m, r, m_hat}, Q15 each) in
//  true-dual-port BRAM (3 x RAMB36).  The capture FSM writes one bank while
//  the VGA scope reads the other; the banks swap at the next vertical
//  blanking after a record completes, so the display never tears.
//
//  Trigger: rising zero-crossing of the ORIGINAL signal with hysteresis
//  (armed below -1024, fires at >= 0) -- the scope image stands still for
//  periodic signals.  If nothing crosses for AUTO_TRIG samples the capture
//  free-runs (silence / DC still shows something).  `hold` freezes the
//  last complete record.
//
//  Port A is shared: the capture writes on it (once per 2000 clocks) and the
//  VIO dashboard reads any address through it the rest of the time, so the
//  stored samples can also be read back numerically.
// ============================================================================
module capture_scope_ram #(
    parameter integer AUTO_TRIG = 32768
)(
    input  wire               clk,
    input  wire               rst,
    // samples
    input  wire               in_valid,
    input  wire signed [15:0] m,
    input  wire signed [15:0] r,
    input  wire signed [15:0] m_hat,
    input  wire               hold,
    input  wire               vblank_start,   // pulse: safe moment to swap banks
    // VGA read port (port B)
    input  wire        [9:0]  rd_addr,
    output reg         [47:0] rd_data,        // 1-clock latency
    // VIO read-back (port A when idle)
    input  wire        [10:0] vio_addr,       // {bank, index}
    output reg         [47:0] vio_data,
    // status
    output wire               bank_disp,
    output reg                recording,
    output reg                triggered       // pulse
);
    localparam [1:0] S_ARM = 2'd0, S_REC = 2'd1, S_SWAP = 2'd2, S_HOLD = 2'd3;

    reg [1:0]  st;
    reg        bank_wr;
    reg        bank_disp_r;
    reg [9:0]  wr_idx;
    reg        below;
    reg [15:0] auto_cnt;

    assign bank_disp = bank_disp_r;

    wire trig = in_valid && ((below && !m[15]) || (auto_cnt == AUTO_TRIG - 1));

    always @(posedge clk) begin
        triggered <= 1'b0;
        if (rst) begin
            st          <= S_ARM;
            bank_wr     <= 1'b0;
            bank_disp_r <= 1'b1;
            wr_idx      <= 10'd0;
            below       <= 1'b0;
            auto_cnt    <= 16'd0;
            recording   <= 1'b0;
        end else begin
            case (st)
                S_ARM: begin
                    recording <= 1'b0;
                    if (in_valid) begin
                        if (m < -16'sd1024) below <= 1'b1;
                        auto_cnt <= auto_cnt + 16'd1;
                        if (trig) begin
                            below     <= 1'b0;
                            auto_cnt  <= 16'd0;
                            wr_idx    <= 10'd1;      // sample 0 written this cycle
                            recording <= 1'b1;
                            triggered <= 1'b1;
                            st        <= S_REC;
                        end
                    end
                end
                S_REC: begin
                    if (in_valid) begin
                        wr_idx <= wr_idx + 10'd1;
                        if (wr_idx == 10'd1023) begin
                            recording <= 1'b0;
                            st        <= S_SWAP;
                        end
                    end
                end
                S_SWAP: begin
                    if (vblank_start) begin
                        bank_disp_r <= bank_wr;
                        bank_wr     <= ~bank_wr;
                        st          <= hold ? S_HOLD : S_ARM;
                    end
                end
                S_HOLD: begin
                    if (!hold) st <= S_ARM;
                end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // true dual port RAM, 2048 x 48 (Vivado infers RAMB36)
    // ------------------------------------------------------------------
    reg [47:0] ram [0:2047];
    wire        we_a   = in_valid && ((st == S_REC) || (st == S_ARM && trig));
    wire [10:0] addr_a = we_a ? {bank_wr, (st == S_ARM) ? 10'd0 : wr_idx} : vio_addr;
    wire [10:0] addr_b = {bank_disp_r, rd_addr};

    always @(posedge clk) begin
        if (we_a)
            ram[addr_a] <= {m, r, m_hat};
        else
            vio_data <= ram[addr_a];          // read-back only in the clocks without a write
    end
    always @(posedge clk) begin
        rd_data <= ram[addr_b];
    end
endmodule
`default_nettype wire
