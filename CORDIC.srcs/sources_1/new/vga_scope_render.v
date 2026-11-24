`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
//  Project Name : CORDIC Radio Link on a Chip
//  Authors      : Ayush Shinde
//  Last Updated : 24 November 2026
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
    input  wire [47:0] rd_data,          // {m, r, m_hat}
    // parameters / status for the overlay
    input  wire [6:0]  fc_idx,
    input  wire [6:0]  beta_q,
    input  wire [5:0]  fm_idx,
    input  wire [5:0]  amp,
    input  wire [4:0]  noise_idx,
    input  wire [1:0]  mode,
    input  wire        source,
    input  wire        hold,
    input  wire [1:0]  tbase,
    input  wire        coarse,
    input  wire        mute,
    input  wire [1:0]  mon_sel,
    input  wire [6:0]  snr_db,
    input  wire        clip,
    input  wire        recording,
    input  wire        key_down,
    input  wire [3:0]  key_code,
    input  wire        overlay_err,      // 0: overlay recovered signal, 1: overlay error x16
    // VGA pins (registered)
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hs,
    output reg         vga_vs
);
    localparam [9:0] A_TOP = 10'd32,  A_BOT = 10'd191, A_MID = 10'd112;
    localparam [9:0] B_TOP = 10'd208, B_BOT = 10'd367, B_MID = 10'd288;

    reg pe1, pe2;                           // pix_en delayed by 1 and 2 clocks
    always @(posedge clk) begin
        pe1 <= pix_en & ~rst;
        pe2 <= pe1 & ~rst;
    end

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

    wire [9:0] h_next = (h == 10'd799) ? 10'd0 : h + 10'd1;

    wire signed [15:0] d_m  = rd_data[47:32];
    wire signed [15:0] d_r  = rd_data[31:16];
    wire signed [15:0] d_mh = rd_data[15:0];
    wire signed [15:0] d_e  = sat16(($signed({{5{d_m[15]}}, d_m}) - $signed({{5{d_mh[15]}}, d_mh})) <<< 4);
    wire signed [15:0] d_o  = overlay_err ? d_e : d_mh;

    reg [9:0] ym_n, yo_n, ys_n;             // heights of the pixel about to be drawn
    reg [9:0] ym_p, yo_p, ys_p;             // heights of the previous pixel

    wire        conv_start = pix_en && (h == 10'd0) && (v == 10'd500);
    reg  [7:0]  fm5_r;                      // fm = idx * 50 = (idx * 5) * 10
    reg  [12:0] bf_r;                       // beta_q * fm_idx (<= 127 * 40)
    reg  [19:0] dev10_r;                    // peak deviation in units of 0.1 Hz
    reg  [4:0]  cnr_r;                      // 31 - noise_idx
    always @(posedge clk) begin
        fm5_r   <= fm_idx * 3'd5;
        bf_r    <= beta_q * fm_idx;
        dev10_r <= (bf_r * 7'd125) >> 1;
        cnr_r   <= 5'd31 - noise_idx;
    end
    wire [11:0] fc_bcd, fm_bcd;
    wire [23:0] dev_bcd;
    wire [7:0]  snr_bcd, cnr_bcd;
    bin2bcd #(.W(7),  .D(3)) u_b_fc  (.clk(clk), .rst(rst), .start(conv_start), .bin(fc_idx),  .bcd(fc_bcd));
    bin2bcd #(.W(8),  .D(3)) u_b_fm  (.clk(clk), .rst(rst), .start(conv_start), .bin(fm5_r),   .bcd(fm_bcd));
    bin2bcd #(.W(20), .D(6)) u_b_dev (.clk(clk), .rst(rst), .start(conv_start), .bin(dev10_r), .bcd(dev_bcd));
    bin2bcd #(.W(7),  .D(2)) u_b_snr (.clk(clk), .rst(rst), .start(conv_start), .bin(snr_db),  .bcd(snr_bcd));
    bin2bcd #(.W(5),  .D(2)) u_b_cnr (.clk(clk), .rst(rst), .start(conv_start), .bin(cnr_r),   .bcd(cnr_bcd));

    function [5:0] gc;
        input [7:0] a;
        begin
            if (a >= "0" && a <= "9")      gc = a - "0" + 8'd1;
            else if (a >= "A" && a <= "Z") gc = a - "A" + 8'd11;
            else if (a == ".")             gc = 6'd37;
            else                           gc = 6'd0;
        end
    endfunction
    // character `idx` (0 = leftmost) of a 4-character word
    function [5:0] w4;
        input [31:0] word;
        input [1:0]  idx;
        begin
            case (idx)
                2'd0:    w4 = gc(word[31:24]);
                2'd1:    w4 = gc(word[23:16]);
                2'd2:    w4 = gc(word[15:8]);
                default: w4 = gc(word[7:0]);
            endcase
        end
    endfunction
    function [5:0] dig;                     // digit -> glyph code ('0' = 1), blank when requested
        input [3:0] d;
        input       blank;
        begin
            dig = blank ? 6'd0 : {2'b00, d} + 6'd1;
        end
    endfunction

    wire [4:0] trow = v[8:4];
    wire [5:0] tcol = h[9:4];
    wire [5:0] rom_code;
    vga_text_rom u_rom (.row(trow), .col(tcol), .alt1(overlay_err), .code(rom_code));

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

    wire [31:0] w_mode = (mode == 2'd0) ? "FM  " : (mode == 2'd1) ? "PM  " : (mode == 2'd2) ? "AM  " : "BYP ";
    wire [31:0] w_src  = source ? "TONE" : "MIC ";
    wire [31:0] w_hold = hold   ? "HOLD" : "RUN ";
    wire [31:0] w_step = coarse ? "CRSE" : "FINE";
    wire [31:0] w_mon  = (mon_sel == 2'd0) ? "RECV" : (mon_sel == 2'd1) ? "ORIG" : (mon_sel == 2'd2) ? "CHAN" : "ERR ";
    wire [1:0]  wi     = tcol[1:0] - 2'd3;                     // tcol 31..34 -> 0..3
    wire        in_w   = (tcol >= 6'd31) && (tcol <= 6'd34);

    reg [5:0] dyn_code;
    reg       dyn_hit;
    always @(*) begin
        dyn_code = 6'd0;
        dyn_hit  = 1'b0;
        case (trow)
            5'd0: if (tcol == 6'd38) begin dyn_hit = key_down; dyn_code = {2'b00, key_code} + 6'd1; end
            5'd1: if (tcol >= 6'd36) begin dyn_hit = clip; dyn_code = w4("CLIP", tcol[1:0]); end
            5'd12: begin
                      if (tcol == 6'd28) begin
                          dyn_hit = 1'b1; dyn_code = (tbase == 2'd0) ? gc("1") : (tbase == 2'd1) ? gc("2") : gc("4");
                      end else if (tcol >= 6'd31 && tcol <= 6'd33) begin
                          dyn_hit = recording; dyn_code = w4("REC ", wi);
                      end else if (tcol >= 6'd36) begin
                          dyn_hit = mute; dyn_code = w4("MUTE", tcol[1:0]);
                      end
                  end
            5'd24: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = dig(fc_bcd[11:8], fc_bcd[11:8] == 4'd0);
                          6'd9 : dyn_code = dig(fc_bcd[7:4],  (fc_bcd[11:4] == 8'd0));
                          6'd10: dyn_code = dig(fc_bcd[3:0],  1'b0);
                          6'd11: dyn_code = gc("0");
                          6'd12: dyn_code = gc("0");
                          default: begin dyn_hit = in_w; dyn_code = w4(w_mode, wi); end
                      endcase
                  end
            5'd25: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = (b_int >= 4'd10) ? gc("1") : 6'd0;
                          6'd9 : dyn_code = dig((b_int >= 4'd10) ? b_int - 4'd10 : b_int, 1'b0);
                          6'd10: dyn_code = gc(".");
                          6'd11: dyn_code = dig(b_frac[11:8], 1'b0);
                          6'd12: dyn_code = dig(b_frac[7:4],  1'b0);
                          6'd13: dyn_code = dig(b_frac[3:0],  1'b0);
                          default: begin dyn_hit = in_w; dyn_code = w4(w_src, wi); end
                      endcase
                  end
            5'd26: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd9 : dyn_code = dig(fm_bcd[11:8], fm_bcd[11:8] == 4'd0);
                          6'd10: dyn_code = dig(fm_bcd[7:4],  (fm_bcd[11:4] == 8'd0));
                          6'd11: dyn_code = dig(fm_bcd[3:0],  1'b0);
                          6'd12: dyn_code = gc("0");
                          6'd31: dyn_code = (noise_idx == 5'd0) ? 6'd0    : dig(cnr_bcd[7:4], cnr_bcd[7:4] == 4'd0);
                          6'd32: dyn_code = (noise_idx == 5'd0) ? gc("O") : dig(cnr_bcd[3:0], 1'b0);
                          6'd33: dyn_code = (noise_idx == 5'd0) ? gc("F") : gc("D");
                          6'd34: dyn_code = (noise_idx == 5'd0) ? gc("F") : gc("B");
                          default: dyn_hit = 1'b0;
                      endcase
                  end
            5'd27: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = dig({2'b00, amp[5:4]}, 1'b0);
                          6'd9 : dyn_code = gc(".");
                          6'd10: dyn_code = dig(a_frac[7:4], 1'b0);
                          6'd11: dyn_code = dig(a_frac[3:0], 1'b0);
                          default: begin dyn_hit = in_w; dyn_code = w4(w_hold, wi); end
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
                          6'd13: dyn_code = gc(".");
                          6'd14: dyn_code = dig(dev_bcd[3:0],   1'b0);
                          default: begin dyn_hit = in_w; dyn_code = w4(w_step, wi); end
                      endcase
                  end
            5'd29: begin
                      dyn_hit = 1'b1;
                      case (tcol)
                          6'd8 : dyn_code = dig(snr_bcd[7:4], snr_bcd[7:4] == 4'd0);
                          6'd9 : dyn_code = dig(snr_bcd[3:0], 1'b0);
                          default: begin dyn_hit = in_w; dyn_code = w4(w_mon, wi); end
                      endcase
                  end
            default: ;
        endcase
    end

    wire in_a = (v >= A_TOP) && (v <= A_BOT);
    wire in_b = (v >= B_TOP) && (v <= B_BOT);
    wire [9:0] ym_q = (h == 10'd0) ? ym_n : ym_p;      // first pixel of a line has no predecessor
    wire [9:0] yo_q = (h == 10'd0) ? yo_n : yo_p;
    wire [9:0] ys_q = (h == 10'd0) ? ys_n : ys_p;

    // stage 1
    reg [5:0] code1;
    reg [2:0] frow1, fcol1;
    reg       act1, hs1, vs1, err1;
    reg       px_m1, px_o1, px_s1, px_mid1, px_grid1, px_frm1;
    // stage 2
    reg       act2, hs2, vs2, err2;
    reg       px_txt2, px_m2, px_o2, px_s2, px_mid2, px_grid2, px_frm2;

    wire [7:0] font_bits;
    vga_font u_font (.code(code1), .row(frow1), .bits(font_bits));

    reg [11:0] rgb;
    always @(*) begin
        if (!act2)         rgb = 12'h000;
        else if (px_txt2)  rgb = 12'hEEE;
        else if (px_o2)    rgb = err2 ? 12'hF22 : 12'hFD0;
        else if (px_m2)    rgb = 12'h0E2;
        else if (px_s2)    rgb = 12'h0BF;
        else if (px_mid2)  rgb = 12'h445;
        else if (px_grid2) rgb = 12'h223;
        else if (px_frm2)  rgb = 12'h667;
        else               rgb = 12'h001;
    end

    always @(posedge clk) begin
        if (rst) begin
            rd_addr <= 10'd0;
            ym_n <= A_MID; yo_n <= A_MID; ys_n <= B_MID;
            ym_p <= A_MID; yo_p <= A_MID; ys_p <= B_MID;
            code1 <= 6'd0; frow1 <= 3'd0; fcol1 <= 3'd0;
            act1 <= 1'b0; hs1 <= 1'b1; vs1 <= 1'b1; err1 <= 1'b0;
            px_m1 <= 1'b0; px_o1 <= 1'b0; px_s1 <= 1'b0; px_mid1 <= 1'b0; px_grid1 <= 1'b0; px_frm1 <= 1'b0;
            act2 <= 1'b0; hs2 <= 1'b1; vs2 <= 1'b1; err2 <= 1'b0;
            px_txt2 <= 1'b0; px_m2 <= 1'b0; px_o2 <= 1'b0; px_s2 <= 1'b0; px_mid2 <= 1'b0; px_grid2 <= 1'b0; px_frm2 <= 1'b0;
            {vga_r, vga_g, vga_b} <= 12'h000;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else begin
            if (pix_en) begin
                // fetch the sample of the next pixel
                rd_addr <= h_next >> tbase;
                // stage 1 for the current pixel
                px_m1    <= in_a && between(v, ym_q, ym_n);
                px_o1    <= in_a && between(v, yo_q, yo_n);
                px_s1    <= in_b && between(v, ys_q, ys_n);
                px_mid1  <= (in_a && v == A_MID) || (in_b && v == B_MID);
                px_grid1 <= (in_a || in_b) && (h[5:0] == 6'd0);
                px_frm1  <= (v == A_TOP) || (v == A_BOT) || (v == B_TOP) || (v == B_BOT) ||
                            ((in_a || in_b) && ((h == 10'd0) || (h == 10'd639)));
                code1    <= dyn_hit ? dyn_code : rom_code;
                frow1    <= v[3:1];
                fcol1    <= h[3:1];
                act1     <= active;
                hs1      <= hs_n;
                vs1      <= vs_n;
                err1     <= overlay_err;
                ym_p <= ym_n; yo_p <= yo_n; ys_p <= ys_n;
            end
            if (pe1) begin
                // stage 2
                px_txt2  <= font_bits[3'd7 - fcol1];
                px_m2    <= px_m1;   px_o2 <= px_o1;     px_s2 <= px_s1;
                px_mid2  <= px_mid1; px_grid2 <= px_grid1; px_frm2 <= px_frm1;
                act2     <= act1;    hs2 <= hs1;         vs2 <= vs1;   err2 <= err1;
            end
            if (pe2) begin
                // stage 3: pins
                {vga_r, vga_g, vga_b} <= rgb;
                vga_hs <= hs2;
                vga_vs <= vs2;
                // heights of the next pixel (its RAM data has just arrived)
                ym_n <= ypos(A_MID, d_m);
                yo_n <= ypos(A_MID, d_o);
                ys_n <= ypos(B_MID, d_r);
            end
        end
    end
endmodule
`default_nettype wire
