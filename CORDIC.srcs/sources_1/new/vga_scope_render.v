`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  vga_scope_render.v -- two-channel oscilloscope display with a text overlay
//
//  640 x 480 layout (16 px text rows):
//    row 0      title, last key pressed
//    row 1      legend for trace A
//    rows 2-11  TRACE A : original m[n] (green) with the demodulated m_hat[n]
//               (yellow) or the error (m - m_hat) x16 (red) drawn on top
//    row 12     legend for trace B
//    rows 13-22 TRACE B : modulated output s[n] (cyan)
//    rows 24-29 live parameter read-outs and key hints
//  Each trace is +/-64 px for full scale (value >>> 9).  Consecutive samples
//  are joined by vertical segments so a 10 kHz carrier still reads as a
//  waveform.  The sample for the next pixel is prefetched from the capture
//  RAM one pixel ahead (4 clocks), which covers the BRAM read latency.
// ============================================================================
module vga_scope_render (
    input  wire        clk,
    input  wire        rst,
    // timing
    input  wire        pix_en,
    input  wire [9:0]  h,
    input  wire [9:0]  v,
    input  wire        active,
    input  wire        hs_n,
    input  wire        vs_n,
    // capture RAM read port (port B)
    output reg  [9:0]  rd_addr,
    input  wire [47:0] rd_data,          // {m, s, m_hat}
    // parameters / status for the overlay
    input  wire [6:0]  fc_idx,
    input  wire [6:0]  beta_q,
    input  wire [5:0]  fm_idx,
    input  wire [5:0]  amp,
    input  wire [1:0]  mode,
    input  wire        source,
    input  wire        hold,
    input  wire [1:0]  tbase,
    input  wire        coarse,
    input  wire        mute,
    input  wire [1:0]  dacb_sel,
    input  wire [6:0]  snr_db,
    input  wire        clip,
    input  wire        recording,
    input  wire        key_down,
    input  wire [3:0]  key_code,
    input  wire        overlay_err,      // 0: overlay demodulated, 1: overlay error x16
    // VGA pins (registered)
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hs,
    output reg         vga_vs
);
    // ------------------------------------------------------------------
    // geometry
    // ------------------------------------------------------------------
    localparam [9:0] A_TOP = 10'd32,  A_BOT = 10'd191, A_MID = 10'd112;
    localparam [9:0] B_TOP = 10'd208, B_BOT = 10'd367, B_MID = 10'd288;

    // ------------------------------------------------------------------
    // sample prefetch
    // ------------------------------------------------------------------
    wire [9:0] h_next = (h == 10'd799) ? 10'd0 : h + 10'd1;
    reg  [47:0] s_last;
    wire [47:0] s_cur  = rd_data;
    wire [47:0] s_prev = (h == 10'd0) ? rd_data : s_last;

    always @(posedge clk) begin
        if (rst) begin
            rd_addr <= 10'd0;
            s_last  <= 48'd0;
        end else if (pix_en) begin
            rd_addr <= h_next >> tbase;
            s_last  <= rd_data;
        end
    end

    // ------------------------------------------------------------------
    // trace geometry
    // ------------------------------------------------------------------
    function [9:0] ypos;                    // centre - value/512
        input [9:0]         centre;
        input signed [15:0] val;
        reg   signed [10:0] y;
        begin
            y    = $signed({1'b0, centre}) - $signed({{4{val[15]}}, val[15:9]});
            ypos = y[9:0];
        end
    endfunction

    function between;
        input [9:0] y, a, b;
        begin
            between = (a <= b) ? ((y >= a) && (y <= b)) : ((y >= b) && (y <= a));
        end
    endfunction

    function signed [15:0] sat16;
        input signed [20:0] x;
        begin
            if (x > 21'sd32767)       sat16 = 16'sd32767;
            else if (x < -21'sd32768) sat16 = -16'sd32768;
            else                      sat16 = x[15:0];
        end
    endfunction

    wire signed [15:0] m_c  = s_cur[47:32],  m_p  = s_prev[47:32];
    wire signed [15:0] s_c  = s_cur[31:16],  s_p  = s_prev[31:16];
    wire signed [15:0] mh_c = s_cur[15:0],   mh_p = s_prev[15:0];
    wire signed [15:0] e_c  = sat16(($signed({{5{m_c[15]}}, m_c}) - $signed({{5{mh_c[15]}}, mh_c})) <<< 4);
    wire signed [15:0] e_p  = sat16(($signed({{5{m_p[15]}}, m_p}) - $signed({{5{mh_p[15]}}, mh_p})) <<< 4);
    wire signed [15:0] o_c  = overlay_err ? e_c : mh_c;
    wire signed [15:0] o_p  = overlay_err ? e_p : mh_p;

    wire in_a = (v >= A_TOP) && (v <= A_BOT);
    wire in_b = (v >= B_TOP) && (v <= B_BOT);
    wire vis  = active;

    wire px_m   = vis && in_a && between(v, ypos(A_MID, m_p),  ypos(A_MID, m_c));
    wire px_o   = vis && in_a && between(v, ypos(A_MID, o_p),  ypos(A_MID, o_c));
    wire px_s   = vis && in_b && between(v, ypos(B_MID, s_p),  ypos(B_MID, s_c));
    wire px_mid = vis && ((in_a && v == A_MID) || (in_b && v == B_MID));
    wire px_grid= vis && (in_a || in_b) && (h[5:0] == 6'd0);
    wire px_frm = vis && ((v == A_TOP) || (v == A_BOT) || (v == B_TOP) || (v == B_BOT) ||
                          ((in_a || in_b) && ((h == 10'd0) || (h == 10'd639))));

    // ------------------------------------------------------------------
    // text layer
    // ------------------------------------------------------------------
    wire [4:0] trow = v[8:4];
    wire [5:0] tcol = h[9:4];
    wire [5:0] rom_code;
    vga_text_rom u_rom (.row(trow), .col(tcol), .alt1(overlay_err), .code(rom_code));

    // --- binary to BCD helpers (double dabble) ---
    function [11:0] bcd3;                   // 0..255 -> 3 digits
        input [7:0] b;
        integer k;
        reg [19:0] t;
        begin
            t = {12'd0, b};
            for (k = 0; k < 8; k = k + 1) begin
                if (t[11:8]  >= 5) t[11:8]  = t[11:8]  + 4'd3;
                if (t[15:12] >= 5) t[15:12] = t[15:12] + 4'd3;
                if (t[19:16] >= 5) t[19:16] = t[19:16] + 4'd3;
                t = t << 1;
            end
            bcd3 = t[19:8];
        end
    endfunction

    function [23:0] bcd6;                   // 0..999999 -> 6 digits
        input [19:0] b;
        integer k;
        reg [43:0] t;
        begin
            t = {24'd0, b};
            for (k = 0; k < 20; k = k + 1) begin
                if (t[23:20] >= 5) t[23:20] = t[23:20] + 4'd3;
                if (t[27:24] >= 5) t[27:24] = t[27:24] + 4'd3;
                if (t[31:28] >= 5) t[31:28] = t[31:28] + 4'd3;
                if (t[35:32] >= 5) t[35:32] = t[35:32] + 4'd3;
                if (t[39:36] >= 5) t[39:36] = t[39:36] + 4'd3;
                if (t[43:40] >= 5) t[43:40] = t[43:40] + 4'd3;
                t = t << 1;
            end
            bcd6 = t[43:20];
        end
    endfunction

    function [5:0] dig;                     // digit -> glyph code ('0' = 1), blank when requested
        input [3:0] d;
        input       blank;
        begin
            dig = blank ? 6'd0 : {2'b00, d} + 6'd1;
        end
    endfunction

    // --- the values to display ---
    wire [11:0] fc_bcd  = bcd3(fc_idx);                                  // fc = idx * 100
    wire [7:0]  fm5     = fm_idx * 3'd5;                                 // fm = idx * 50 = (idx*5) * 10
    wire [11:0] fm_bcd  = bcd3(fm5);
    wire [3:0]  b_int   = beta_q[6:3];
    wire [11:0] b_frac  = (beta_q[2:0] == 3'd0) ? 12'h000 : (beta_q[2:0] == 3'd1) ? 12'h125 :
                          (beta_q[2:0] == 3'd2) ? 12'h250 : (beta_q[2:0] == 3'd3) ? 12'h375 :
                          (beta_q[2:0] == 3'd4) ? 12'h500 : (beta_q[2:0] == 3'd5) ? 12'h625 :
                          (beta_q[2:0] == 3'd6) ? 12'h750 : 12'h875;
    wire [7:0]  a_frac  = (amp[3:0] == 4'd0)  ? 8'h00 : (amp[3:0] == 4'd1)  ? 8'h06 : (amp[3:0] == 4'd2)  ? 8'h13 :
                          (amp[3:0] == 4'd3)  ? 8'h19 : (amp[3:0] == 4'd4)  ? 8'h25 : (amp[3:0] == 4'd5)  ? 8'h31 :
                          (amp[3:0] == 4'd6)  ? 8'h38 : (amp[3:0] == 4'd7)  ? 8'h44 : (amp[3:0] == 4'd8)  ? 8'h50 :
                          (amp[3:0] == 4'd9)  ? 8'h56 : (amp[3:0] == 4'd10) ? 8'h63 : (amp[3:0] == 4'd11) ? 8'h69 :
                          (amp[3:0] == 4'd12) ? 8'h75 : (amp[3:0] == 4'd13) ? 8'h81 : (amp[3:0] == 4'd14) ? 8'h88 : 8'h94;
    wire [19:0] dev10   = (beta_q * fm_idx * 8'd125) >> 1;               // peak deviation * 10 Hz
    wire [23:0] dev_bcd = bcd6(dev10);
    wire [11:0] snr_bcd = bcd3({1'b0, snr_db});

    // --- dynamic character at (trow, tcol) ---
    reg [5:0] dyn_code;
    reg       dyn_hit;
    always @(*) begin
        dyn_code = 6'd0;
        dyn_hit  = 1'b0;
        case (trow)
            5'd0: if (tcol == 6'd38) begin dyn_hit = key_down; dyn_code = {2'b00, key_code} + 6'd1; end
            5'd1: if (tcol >= 6'd36) begin
                      dyn_hit = clip;
                      case (tcol) 6'd36: dyn_code = 6'd13; 6'd37: dyn_code = 6'd22; 6'd38: dyn_code = 6'd19; default: dyn_code = 6'd26; endcase // CLIP
                  end
            5'd12: begin
                      if (tcol >= 6'd31 && tcol <= 6'd33) begin
                          dyn_hit = recording;
                          case (tcol) 6'd31: dyn_code = 6'd28; 6'd32: dyn_code = 6'd15; default: dyn_code = 6'd13; endcase // REC
                      end else if (tcol >= 6'd36) begin
                          dyn_hit = mute;
                          case (tcol) 6'd36: dyn_code = 6'd23; 6'd37: dyn_code = 6'd31; 6'd38: dyn_code = 6'd30; default: dyn_code = 6'd15; endcase // MUTE
                      end
                  end
            5'd24: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = dig(fc_bcd[11:8], fc_bcd[11:8] == 4'd0);
                          6'd9 : dyn_code = dig(fc_bcd[7:4],  (fc_bcd[11:4] == 8'd0));
                          6'd10: dyn_code = dig(fc_bcd[3:0],  1'b0);
                          6'd11: dyn_code = 6'd1;
                          6'd12: dyn_code = 6'd1;
                          6'd31: dyn_code = (mode == 2'd3) ? 6'd12 : (mode == 2'd1) ? 6'd26 : (mode == 2'd2) ? 6'd11 : 6'd16; // B/P/A/F
                          6'd32: dyn_code = (mode == 2'd3) ? 6'd35 : 6'd23;                                               // Y/M
                          6'd33: dyn_code = (mode == 2'd3) ? 6'd26 : 6'd0;                                                // P
                          default: dyn_hit = 1'b0;
                      endcase
                  end
            5'd25: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = (b_int >= 4'd10) ? 6'd2 : 6'd0;
                          6'd9 : dyn_code = dig((b_int >= 4'd10) ? b_int - 4'd10 : b_int, 1'b0);
                          6'd10: dyn_code = 6'd37;                                                                        // '.'
                          6'd11: dyn_code = dig(b_frac[11:8], 1'b0);
                          6'd12: dyn_code = dig(b_frac[7:4],  1'b0);
                          6'd13: dyn_code = dig(b_frac[3:0],  1'b0);
                          6'd31: dyn_code = source ? 6'd30 : 6'd23;   // T / M
                          6'd32: dyn_code = source ? 6'd25 : 6'd19;   // O / I
                          6'd33: dyn_code = source ? 6'd24 : 6'd13;   // N / C
                          6'd34: dyn_code = source ? 6'd15 : 6'd0;    // E
                          default: dyn_hit = 1'b0;
                      endcase
                  end
            5'd26: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd9 : dyn_code = dig(fm_bcd[11:8], fm_bcd[11:8] == 4'd0);
                          6'd10: dyn_code = dig(fm_bcd[7:4],  (fm_bcd[11:4] == 8'd0));
                          6'd11: dyn_code = dig(fm_bcd[3:0],  1'b0);
                          6'd12: dyn_code = 6'd1;
                          6'd31: dyn_code = 6'd34;                                               // X
                          6'd32: dyn_code = (tbase == 2'd0) ? 6'd2 : (tbase == 2'd1) ? 6'd3 : 6'd5; // 1/2/4
                          default: dyn_hit = 1'b0;
                      endcase
                  end
            5'd27: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = dig({2'b00, amp[5:4]}, 1'b0);
                          6'd9 : dyn_code = 6'd37;
                          6'd10: dyn_code = dig(a_frac[7:4], 1'b0);
                          6'd11: dyn_code = dig(a_frac[3:0], 1'b0);
                          6'd31: dyn_code = hold ? 6'd18 : 6'd28;     // H / R
                          6'd32: dyn_code = hold ? 6'd25 : 6'd31;     // O / U
                          6'd33: dyn_code = hold ? 6'd22 : 6'd24;     // L / N
                          6'd34: dyn_code = hold ? 6'd14 : 6'd0;      // D
                          default: dyn_hit = 1'b0;
                      endcase
                  end
            5'd28: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = dig(dev_bcd[23:20], dev_bcd[23:20] == 4'd0);
                          6'd9 : dyn_code = dig(dev_bcd[19:16], dev_bcd[23:16] == 8'd0);
                          6'd10: dyn_code = dig(dev_bcd[15:12], dev_bcd[23:12] == 12'd0);
                          6'd11: dyn_code = dig(dev_bcd[11:8],  dev_bcd[23:8]  == 16'd0);
                          6'd12: dyn_code = dig(dev_bcd[7:4],   1'b0);
                          6'd13: dyn_code = 6'd37;
                          6'd14: dyn_code = dig(dev_bcd[3:0],   1'b0);
                          6'd31: dyn_code = coarse ? 6'd34 : 6'd16;   // X / F
                          6'd32: dyn_code = coarse ? 6'd2  : 6'd19;   // 1 / I
                          6'd33: dyn_code = coarse ? 6'd1  : 6'd24;   // 0 / N
                          6'd34: dyn_code = coarse ? 6'd0  : 6'd15;   //   / E
                          default: dyn_hit = 1'b0;
                      endcase
                  end
            5'd29: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = dig(snr_bcd[7:4], snr_bcd[7:4] == 4'd0);
                          6'd9 : dyn_code = dig(snr_bcd[3:0], 1'b0);
                          6'd31: dyn_code = (dacb_sel == 2'd0) ? 6'd25 : (dacb_sel == 2'd1) ? 6'd14 : (dacb_sel == 2'd2) ? 6'd30 : 6'd27; // O/D/T/Q
                          6'd32: dyn_code = (dacb_sel == 2'd0) ? 6'd28 : (dacb_sel == 2'd1) ? 6'd15 : (dacb_sel == 2'd2) ? 6'd25 : 6'd31; // R/E/O/U
                          6'd33: dyn_code = (dacb_sel == 2'd0) ? 6'd19 : (dacb_sel == 2'd1) ? 6'd23 : (dacb_sel == 2'd2) ? 6'd24 : 6'd11; // I/M/N/A
                          6'd34: dyn_code = (dacb_sel == 2'd0) ? 6'd17 : (dacb_sel == 2'd1) ? 6'd25 : (dacb_sel == 2'd2) ? 6'd15 : 6'd14; // G/O/E/D
                          default: dyn_hit = 1'b0;
                      endcase
                  end
            default: ;
        endcase
    end

    wire [5:0] code = dyn_hit ? dyn_code : rom_code;
    wire [7:0] font_bits;
    vga_font u_font (.code(code), .row(v[3:1]), .bits(font_bits));
    wire px_txt = vis && (v < 10'd480) && font_bits[3'd7 - h[3:1]];

    // ------------------------------------------------------------------
    // colour priority and output registers
    // ------------------------------------------------------------------
    reg [11:0] rgb;
    always @(*) begin
        if (!vis)          rgb = 12'h000;
        else if (px_txt)   rgb = 12'hEEE;
        else if (px_o)     rgb = overlay_err ? 12'hF22 : 12'hFD0;
        else if (px_m)     rgb = 12'h0E2;
        else if (px_s)     rgb = 12'h0BF;
        else if (px_mid)   rgb = 12'h445;
        else if (px_grid)  rgb = 12'h223;
        else if (px_frm)   rgb = 12'h667;
        else               rgb = 12'h001;
    end

    always @(posedge clk) begin
        if (rst) begin
            {vga_r, vga_g, vga_b} <= 12'h000;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else if (pix_en) begin
            {vga_r, vga_g, vga_b} <= rgb;
            vga_hs <= hs_n;
            vga_vs <= vs_n;
        end
    end
endmodule
`default_nettype wire
