#!/usr/bin/env python3
"""Draws docs/img/architecture.png -- the block diagram used in the READMEs."""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "img", "architecture.png"))
fig, ax = plt.subplots(figsize=(14.5, 8.2)); ax.set_xlim(0, 145); ax.set_ylim(0, 82); ax.axis("off")

EXT = dict(fc="#fff4e0", ec="#b36b00")
def box(x, y, w, h, title, sub="", fc="#e8f0fe", ec="#1f4e9c", fs=9.5):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.3,rounding_size=1.2", fc=fc, ec=ec, lw=1.4))
    n = sub.count("\n") + 1 if sub else 0
    ax.text(x + w / 2, y + h / 2 + (1.1 * n + 0.6 if sub else 0), title, ha="center", va="center", fontsize=fs, weight="bold")
    if sub: ax.text(x + w / 2, y + h / 2 - 1.5, sub, ha="center", va="center", fontsize=7.6, color="#333", linespacing=1.25)

def arrow(x1, y1, x2, y2, label="", col="#333", ls="-", dy=1.3, dx=0, fs=7.5):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>", mutation_scale=12, lw=1.3, color=col, ls=ls))
    if label: ax.text((x1 + x2) / 2 + dx, (y1 + y2) / 2 + dy, label, ha="center", fontsize=fs, color=col)

# ---- external devices ----
box(2, 62, 17, 9, "Pmod MIC", "electret mic, compandor\nADCS7476 12-bit ADC", **EXT)
box(2, 36, 17, 9, "Pmod KYPD", "4 x 4 key matrix", **EXT)
box(126, 62, 17, 9, "Pmod DA2", "2 x DAC121S101\nA: channel  B: monitor", **EXT)
box(126, 49, 17, 9, "Pmod AMP2", "class-D amplifier\n+ loudspeaker", **EXT)
box(126, 8, 17, 9, "VGA monitor", "640 x 480 @ 60 Hz", **EXT)
box(126, 24, 17, 9, "Vivado VIO", "JTAG dashboard", **EXT)

# ---- front end ----
box(24, 62, 15, 9, "mic_adc_spi", "SPI master, 5 MHz\n50 kS/s")
box(42, 62, 15, 9, "audio_frontend", "code -> Q15\n31 Hz DC blocker")

# ---- the link ----
ax.add_patch(FancyBboxPatch((60, 45), 48, 29, boxstyle="round,pad=0.3,rounding_size=1.5", fc="#f3f8ff", ec="#1f4e9c", lw=1.8))
ax.text(84, 71.5, "fm_dsp_core  --  one radio link per sample", ha="center", fontsize=10, weight="bold")
box(62, 58, 13, 9, "TRANSMITTER", "CORDIC rotation\nFM / PM / AM", fc="#d6e6ff", fs=8.5)
box(78, 58, 12, 9, "CHANNEL", "+ Gaussian noise\n(awgn_gen)", fc="#ffe3e3", ec="#a11", fs=8.5)
box(93, 58, 13, 9, "RECEIVER", "CORDIC vectoring\nphase / envelope", fc="#d6e6ff", fs=8.5)
box(62, 47, 21, 7, "cordic_engine  (x1, time-shared)", "18 iterations, 3 jobs per sample", fc="#ffffff", fs=8)
box(86, 47, 20, 7, "audio_lpf  (x2)", "2.9 kHz, on m and on m_hat", fc="#ffffff", fs=8)
arrow(75, 62.5, 78, 62.5); arrow(90, 62.5, 93, 62.5)
arrow(68, 54, 68, 58, col="#1f4e9c"); arrow(99, 54, 99, 58, col="#1f4e9c")

# ---- control ----
box(24, 36, 15, 9, "kypd_scanner", "scan, debounce\nauto-repeat")
box(42, 36, 15, 9, "param_controller", "f_c, beta, f_m, amp,\nnoise, mode, monitor")
box(62, 34, 16, 7, "recip_divider", "G = 2^39 / D", fs=8.5)

# ---- back end ----
box(111, 62, 12, 9, "da2_dac_spi", "SPI master", fs=8.5)
box(110, 49, 9, 9, "sd_dac", "1-bit\nsigma-delta", fs=8.5)
box(62, 8, 16, 9, "fidelity_meter", "sum m^2, sum e^2\nSNR in dB")
box(82, 8, 19, 9, "capture_scope_ram", "2 x 1024 x {m, r, m_hat}\ntriggered, block RAM")
box(105, 8, 17, 9, "vga_scope_render", "2 traces + text\n3-stage pixel pipeline")
box(105, 22, 17, 5, "vga_timing", "25 MHz pixel enable", fc="#f0f0f0", ec="#666", fs=8.5)
box(108, 34, 15, 8, "monitor mux", "recovered / original\nchannel / error", fs=8.5)

# ---- arrows ----
arrow(19, 66.5, 24, 66.5, "SPI", dy=1.6); arrow(39, 66.5, 42, 66.5); arrow(57, 66.5, 62, 64.5, "m", dy=1.9)
arrow(19, 40.5, 24, 40.5); arrow(39, 40.5, 42, 40.5, "key", dy=1.6)
arrow(57, 40.5, 62, 38.5, "D", dy=1.6); arrow(70, 41, 70, 45, "G", col="#1f4e9c", dx=1.6, dy=-0.6)
arrow(55, 45, 61, 49.5, "constants", col="#1f4e9c", dx=-4.5, dy=0.6)
arrow(108, 66.5, 111, 66.5, "r", dy=1.6); arrow(123, 66.5, 126, 66.5, "SPI", dy=1.6)
arrow(114, 42, 114, 49, ""); arrow(119, 53.5, 126, 53.5, "bit stream", dy=1.5)
arrow(121.3, 42, 121.3, 62, "")
arrow(104, 45, 110, 42, "m, r, m_hat", col="#8a0000", dx=-6.5, dy=-2.8)
arrow(84, 45, 70, 17, "m, m_hat", col="#8a0000", dx=-6.0, dy=-3)
arrow(91, 45, 91.5, 17, "m, r, m_hat", col="#8a0000", dx=6.5, dy=-3)
arrow(101, 12.5, 105, 12.5, "48 bit", dy=1.6); arrow(122, 12.5, 126, 12.5)
arrow(113.5, 22, 113.5, 17)
arrow(126, 28.5, 109, 30.5, "override / read-back", col="#555", ls="--", dy=1.2, dx=-2)
ax.text(72.5, 78.5, "cordic_fm_system  (100 MHz, single clock domain, 50 kS/s)", fontsize=11.5, weight="bold", ha="center")
ax.add_patch(FancyBboxPatch((21.5, 4.5), 102.5, 72, boxstyle="round,pad=0.3", fc="none", ec="#999", lw=1, ls="--"))
ax.text(84, 43.2, "", fontsize=7)
fig.savefig(OUT, dpi=125, bbox_inches="tight"); print("wrote", OUT)
