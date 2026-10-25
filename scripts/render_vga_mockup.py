#!/usr/bin/env python3
"""
Renders what the VGA screen is expected to show, using the SAME layout rules,
font glyphs and colours as vga_scope_render.v / vga_text_rom.v, with trace
data from the bit-exact model.  This is a Python rendering, not a simulation
capture: tb_cordic_fm_system.v writes the real frame (vga_frame.ppm) when run.
Output: docs/img/vga_expected.png
"""
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import cordic_model as cm
from gen_font import ORDER, rows_of
from gen_text_layout import ROWS

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "docs", "img", "vga_expected.png"))

def rgb12(v):
    return tuple(((v >> s) & 0xF) * 17 for s in (8, 4, 0))

COL = dict(bg=rgb12(0x001), txt=rgb12(0xEEE), ovl=rgb12(0xFD0), m=rgb12(0x0E2), s=rgb12(0x0BF),
           mid=rgb12(0x445), grid=rgb12(0x223), frm=rgb12(0x667))

def main(fc_idx=20, beta_q=16, fm_idx=4, amp=16, mode=0, source=1, snr=66, tbase=0):
    consts = cm.derive_constants(fc_idx, beta_q, fm_idx, mode)
    core = cm.FMCore()
    # a triggered record: run until a rising zero crossing of m, then 1024 samples
    samples = []
    prev = 0; armed = False
    for i in range(4096):
        r = core.step(0, dict(mode=mode, source=source, amp=amp), consts)
        if not samples:
            if r["m"] < -1024: armed = True
            if armed and r["m"] >= 0: samples.append(r)
        else:
            samples.append(r)
            if len(samples) == 1024: break
    img = np.zeros((480, 640, 3), dtype=np.uint8); img[:, :] = COL["bg"]
    A_TOP, A_BOT, A_MID = 32, 191, 112
    B_TOP, B_BOT, B_MID = 208, 367, 288
    def ypos(c, v): return c - (v >> 9)
    # frames, grid, centre lines
    for y in (A_TOP, A_BOT, B_TOP, B_BOT): img[y, :] = COL["frm"]
    for y in list(range(A_TOP, A_BOT + 1)) + list(range(B_TOP, B_BOT + 1)):
        img[y, 0] = COL["frm"]; img[y, 639] = COL["frm"]
        for x in range(64, 640, 64): img[y, x] = COL["grid"]
    img[A_MID, 1:639] = COL["mid"]; img[B_MID, 1:639] = COL["mid"]
    # traces (vertical joins like the RTL)
    def draw(x, yp, yc, col, top, bot):
        lo, hi = sorted((yp, yc))
        for y in range(lo, hi + 1):
            if top <= y <= bot: img[y, x] = col
    for x in range(640):
        i, ip = x >> tbase, max(x - 1, 0) >> tbase
        sc, sp = samples[i], samples[ip]
        draw(x, ypos(B_MID, sp["s"]), ypos(B_MID, sc["s"]), COL["s"], B_TOP, B_BOT)
        draw(x, ypos(A_MID, sp["m"]), ypos(A_MID, sc["m"]), COL["m"], A_TOP, A_BOT)
        draw(x, ypos(A_MID, sp["m_hat"]), ypos(A_MID, sc["m_hat"]), COL["ovl"], A_TOP, A_BOT)
    # text layer
    screen = {r: list(s) for r, s in ROWS.items()}
    def put(r, c, s):
        for k, ch in enumerate(s): screen[r][c + k] = ch
    put(24, 8, "%5d" % (fc_idx * 100)); put(24, 31, ["FM ", "PM ", "AM ", "BYP"][mode])
    put(25, 8, "%2d.%03d" % (beta_q // 8, (beta_q % 8) * 125)); put(25, 31, "TONE" if source else "MIC ")
    put(26, 8, "%5d" % (fm_idx * 50)); put(26, 31, "X%d" % (1 << tbase))
    put(27, 8, "%d.%02d" % (amp // 16, round((amp % 16) * 6.25))); put(27, 31, "RUN ")
    dev10 = (beta_q * fm_idx * 125) >> 1
    put(28, 8, "%5d.%d" % (dev10 // 10, dev10 % 10)); put(28, 31, "FINE")
    put(29, 8, "%2d" % snr); put(29, 31, "ORIG")
    put(12, 31, "REC")
    for r, chars in screen.items():
        for c, ch in enumerate(chars):
            if ch == ' ': continue
            g = rows_of(ch)
            for gy in range(8):
                for gx in range(8):
                    if g[gy] & (1 << (7 - gx)):
                        y0, x0 = r * 16 + gy * 2, c * 16 + gx * 2
                        img[y0:y0 + 2, x0:x0 + 2] = COL["txt"]
    plt.figure(figsize=(8, 6)); plt.imshow(img, interpolation="nearest"); plt.axis("off")
    plt.title("Expected VGA screen (Python rendering of the RTL layout): FM, tone source, beta = 2")
    plt.savefig(OUT, dpi=110, bbox_inches="tight"); plt.close()
    print("wrote", OUT)

if __name__ == "__main__":
    main()
