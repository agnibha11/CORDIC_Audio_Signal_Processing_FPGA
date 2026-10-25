#!/usr/bin/env python3
"""Draws docs/img/architecture.png -- the block diagram used in the README."""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "img", "architecture.png"))
fig, ax = plt.subplots(figsize=(13, 7.2)); ax.set_xlim(0, 130); ax.set_ylim(0, 72); ax.axis("off")

def box(x, y, w, h, title, sub="", fc="#e8f0fe", ec="#1f4e9c"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.3,rounding_size=1.2", fc=fc, ec=ec, lw=1.4))
    ax.text(x + w / 2, y + h / 2 + (2.0 if sub else 0), title, ha="center", va="center", fontsize=9.5, weight="bold")
    if sub: ax.text(x + w / 2, y + h / 2 - 2.2, sub, ha="center", va="center", fontsize=7.8, color="#333")

def arrow(x1, y1, x2, y2, label="", col="#333", ls="-"):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>", mutation_scale=12, lw=1.2, color=col, ls=ls))
    if label: ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 1.3, label, ha="center", fontsize=7.5, color=col)

# external devices
box(2, 54, 16, 9, "Pmod MIC3", "ADCS7476 12-bit SAR", fc="#fff4e0", ec="#b36b00")
box(2, 30, 16, 9, "Pmod KYPD", "4x4 matrix", fc="#fff4e0", ec="#b36b00")
box(112, 54, 16, 9, "Pmod DA2", "2 x DAC121S101", fc="#fff4e0", ec="#b36b00")
box(112, 10, 16, 9, "VGA monitor", "640x480 @ 60 Hz", fc="#fff4e0", ec="#b36b00")
box(112, 30, 16, 9, "Vivado VIO", "JTAG dashboard", fc="#fff4e0", ec="#b36b00")

# chain
box(24, 54, 17, 9, "mic3_adc_spi", "SPI master, 5 MHz")
box(45, 54, 17, 9, "audio_frontend", "offset -> Q15, DC blocker 31 Hz")
box(66, 48, 22, 15, "fm_dsp_core", "per-sample FSMD sequencer\n3 jobs on one cordic_engine\nFM / PM / AM / bypass + demod")
box(92, 54, 16, 9, "da2_dac_spi", "A: modulated  B: monitor")
box(24, 30, 17, 9, "kypd_scanner", "scan, debounce, repeat")
box(45, 30, 17, 9, "param_controller", "fc, beta, fm, amp, mode\n-> fcw, kdev, kpm, mu")
box(66, 30, 22, 9, "recip_divider", "G = 2^39 / D (demod gain)")
box(45, 10, 17, 9, "fidelity_meter", "sum m^2, sum e^2, SNR")
box(66, 10, 22, 9, "capture_scope_ram", "2 banks x 1024 x {m,s,m_hat}\ntriggered, 3 RAMB36")
box(92, 10, 16, 9, "vga_scope_render", "traces + text overlay")
box(92, 22, 16, 5, "vga_timing", "25 MHz pixel enable", fc="#f0f0f0", ec="#666")

arrow(18, 58.5, 24, 58.5, "SPI")
arrow(41, 58.5, 45, 58.5, "")
arrow(62, 58.5, 66, 58.5, "Q15")
arrow(88, 58.5, 92, 58.5, "")
arrow(108, 58.5, 112, 58.5, "SPI")
arrow(18, 34.5, 24, 34.5, "")
arrow(41, 34.5, 45, 34.5, "key")
arrow(53.5, 39, 53.5, 54, "", col="#1f4e9c")
arrow(62, 34.5, 66, 34.5, "D")
arrow(77, 39, 77, 48, "G", col="#1f4e9c")
arrow(62, 39, 70, 48, "constants", col="#1f4e9c")
arrow(90, 50, 90, 19, "", col="#8a0000")
ax.text(91.5, 44, "m, s, m_hat", fontsize=7.5, color="#8a0000")
arrow(66, 14.5, 62, 14.5, "", col="#8a0000")
arrow(88, 14.5, 92, 14.5, "48-bit")
arrow(108, 14.5, 112, 14.5, "")
arrow(100, 22, 100, 19, "")
arrow(112, 34.5, 108, 34.5, "", col="#555", ls="--")
ax.text(110, 37.5, "VIO override / read-back", fontsize=7, color="#555", ha="center")
ax.text(66, 68, "cordic_fm_system  (100 MHz, single clock domain, 50 kS/s)", fontsize=11, weight="bold", ha="center")
ax.add_patch(FancyBboxPatch((21, 6), 90, 60, boxstyle="round,pad=0.3", fc="none", ec="#999", lw=1, ls="--"))
fig.savefig(OUT, dpi=130, bbox_inches="tight"); print("wrote", OUT)
