#!/usr/bin/env python3
"""
Draws docs/wiring_schematic.png / .svg : every connection between the ZedBoard
and the four Pmods, pin by pin, plus the external equipment.
The pin data below is the single source for the drawing; it mirrors
CORDIC.srcs/constrs_1/new/zedboard_cordic_fm.xdc (checked by main()).
"""
import os, re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle, FancyArrowPatch, Circle

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))

# (port pin, FPGA pin, RTL port, Pmod pin name, direction: '>' FPGA drives, '<' Pmod drives, '-' unused, 'p' power)
PORTS = [
 ("JA1  (top row)", "Pmod MIC  (PB200-122 rev B)", "J1", "microphone + ADCS7476 12-bit ADC", "#1f77b4", [
    ("JA1",  "Y11",  "adc_cs_n",   "1  SS",    ">"),
    ("JA2",  "AA11", "",           "2  NC",    "-"),
    ("JA3",  "Y10",  "adc_miso",   "3  MISO",  "<"),
    ("JA4",  "AA9",  "adc_sclk",   "4  SCK",   ">"),
    ("5",    "GND",  "",           "5  GND",   "p"),
    ("6",    "3V3",  "",           "6  VCC",   "p")]),
 ("JB1  (both rows)", "Pmod KYPD  (PB200-195 rev B)", "J1", "4 x 4 key matrix, pull-ups on the rows", "#2ca02c", [
    ("JB1",  "W12",  "kypd_col[3]", "1  COL4",  ">"),
    ("JB2",  "W11",  "kypd_col[2]", "2  COL3",  ">"),
    ("JB3",  "V10",  "kypd_col[1]", "3  COL2",  ">"),
    ("JB4",  "W8",   "kypd_col[0]", "4  COL1",  ">"),
    ("5",    "GND",  "",            "5  GND",   "p"),
    ("6",    "3V3",  "",            "6  VCC",   "p"),
    ("JB7",  "V12",  "kypd_row[3]", "7  ROW4",  "<"),
    ("JB8",  "W10",  "kypd_row[2]", "8  ROW3",  "<"),
    ("JB9",  "V9",   "kypd_row[1]", "9  ROW2",  "<"),
    ("JB10", "V8",   "kypd_row[0]", "10 ROW1",  "<"),
    ("11",   "GND",  "",            "11 GND",   "p"),
    ("12",   "3V3",  "",            "12 VCC",   "p")]),
 ("JC1  (top row)", "Pmod AMP2  (PB200-233 rev B)", "J1", "SSM2377 class-D amplifier", "#d62728", [
    ("JC1",  "AB7",  "amp_ain",        "1  AIN",        ">"),
    ("JC2",  "AB6",  "amp_gain",       "2  GAIN",       ">"),
    ("JC3",  "Y4",   "",               "3  NC",         "-"),
    ("JC4",  "AA4",  "amp_shutdown_n", "4  ~SHUTDOWN",  ">"),
    ("5",    "GND",  "",               "5  GND",        "p"),
    ("6",    "3V3",  "",               "6  VCC",        "p")]),
 ("JD1  (top row)", "Pmod DA2", "J1", "2 x DAC121S101 12-bit DAC", "#9467bd", [
    ("JD1",  "V7",   "dac_sync_n", "1  ~SYNC",  ">"),
    ("JD2",  "W7",   "dac_dina",   "2  DINA",   ">"),
    ("JD3",  "V5",   "dac_dinb",   "3  DINB",   ">"),
    ("JD4",  "V4",   "dac_sclk",   "4  SCLK",   ">"),
    ("5",    "GND",  "",           "5  GND",    "p"),
    ("6",    "3V3",  "",           "6  VCC",    "p")]),
]

def check_against_xdc():
    xdc = open(os.path.join(ROOT, "CORDIC.srcs", "constrs_1", "new", "zedboard_cordic_fm.xdc")).read()
    pins = dict((m.group(2), m.group(1)) for m in re.finditer(r"PACKAGE_PIN\s+(\w+)[^\]]*\[get_ports \{?([\w\[\]]+)\}?\]", xdc))
    n = 0
    for _, _, _, _, _, rows in PORTS:
        for (_, fpga, port, _, d) in rows:
            if port:
                assert pins.get(port) == fpga, (port, fpga, pins.get(port))
                n += 1
    print("wiring table matches the XDC for", n, "signals")

def main():
    check_against_xdc()
    fig, ax = plt.subplots(figsize=(17, 13.2)); ax.set_xlim(0, 170); ax.set_ylim(12, 127); ax.axis("off")
    RH = 2.7                                           # row height
    ZX0, ZX1 = 4, 58                                   # ZedBoard box
    PX0, PX1 = 96, 128                                 # Pmod boxes
    ax.add_patch(FancyBboxPatch((ZX0, 14.5), ZX1 - ZX0, 111.5, boxstyle="round,pad=0.4,rounding_size=1.5", fc="#f4f7f4", ec="#2f5d2f", lw=2))
    ax.text((ZX0 + ZX1) / 2, 123, "Avnet ZedBoard", fontsize=15, weight="bold", ha="center")
    ax.text((ZX0 + ZX1) / 2, 120, "Zynq-7000 XC7Z020-1CLG484, FPGA part only", fontsize=9, ha="center")
    y = 115
    for (port, pmod, hdr, desc, col, rows) in PORTS:
        h = RH * len(rows)
        # ZedBoard connector block
        ax.add_patch(Rectangle((ZX1 - 22, y - h), 22, h, fc="#ffffff", ec="#333", lw=1.2))
        ax.text(ZX1 - 23.5, y - h / 2, "Pmod port\n" + port, fontsize=9.5, weight="bold", ha="right", va="center")
        # Pmod block
        ax.add_patch(FancyBboxPatch((PX0, y - h), PX1 - PX0, h, boxstyle="round,pad=0.2,rounding_size=0.8", fc="#fff8ea", ec=col, lw=2))
        ax.text(PX1 + 2, y - 1.2, pmod, fontsize=10.5, weight="bold", va="top", color=col)
        ax.text(PX1 + 2, y - 4.4, desc, fontsize=8, va="top", color="#333")
        ax.text(PX0 + 1.0, y + 0.6, "header " + hdr, fontsize=7.5, color="#555")
        for k, (ppin, fpga, sig, pname, d) in enumerate(rows):
            yy = y - RH * (k + 0.5)
            ax.plot([ZX1 - 22, ZX1], [yy - RH / 2, yy - RH / 2], color="#bbb", lw=0.5)
            ax.plot([PX0, PX1], [yy - RH / 2, yy - RH / 2], color="#ddd", lw=0.5)
            ax.text(ZX1 - 21, yy, ppin, fontsize=8.5, va="center", family="monospace")
            ax.text(ZX1 - 1, yy, fpga, fontsize=8.5, va="center", ha="right", family="monospace",
                    color="#b00" if fpga == "3V3" else "#000", weight="bold" if d != "p" else "normal")
            ax.text(PX0 + 1.2, yy, pname, fontsize=8.5, va="center", family="monospace")
            ax.add_patch(Circle((ZX1, yy), 0.45, fc="#333", ec="#333")); ax.add_patch(Circle((PX0, yy), 0.45, fc="#333", ec="#333"))
            if d == "-":
                ax.plot([ZX1, ZX1 + 5], [yy, yy], color="#aaa", lw=1, ls=":"); ax.text(ZX1 + 6, yy, "not used", fontsize=7.5, va="center", color="#888")
                continue
            c = "#000" if (d == "p" and fpga == "GND") else "#c00" if d == "p" else col
            lw = 1.0 if d == "p" else 1.8
            if d == ">":
                ax.add_patch(FancyArrowPatch((ZX1, yy), (PX0, yy), arrowstyle="-|>", mutation_scale=11, lw=lw, color=c))
            elif d == "<":
                ax.add_patch(FancyArrowPatch((PX0, yy), (ZX1, yy), arrowstyle="-|>", mutation_scale=11, lw=lw, color=c))
            else:
                ax.plot([ZX1, PX0], [yy, yy], color=c, lw=lw)
            lab = sig if sig else ("ground" if fpga == "GND" else "3.3 V supply")
            ax.text((ZX1 + PX0) / 2, yy + 0.45, lab, fontsize=8, ha="center", va="bottom", color=c, family="monospace" if sig else None)
        ybot = y - h
        # external equipment per Pmod
        if "MIC" in pmod:
            ax.text(PX1 + 2, y - 8.2, "on-board electret microphone -> SA575 compandor -> ADC\nno external connection", fontsize=8, va="top", color="#333")
        if "KYPD" in pmod:
            ax.text(PX1 + 2, y - 8.2, "key caps:   1 2 3 A\n            4 5 6 B\n            7 8 9 C\n            0 F E D\nCOL1 = column of 1-4-7-0,  ROW1 = row of 1-2-3-A\n"
                    "The board is wider than one port: use a 12-pin\n(2x6) Pmod cable, pin 1 to pin 1, if it does not\nfit next to the other Pmods.", fontsize=8, va="top", color="#333", family="monospace")
        if "AMP2" in pmod:
            ax.text(PX1 + 2, y - 8.2, "J2: 3.5 mm mono jack  -->  loudspeaker 4-8 ohm\n(or headphones / powered speakers)", fontsize=8.5, va="top", color="#333")
        if "DA2" in pmod:
            ax.text(PX1 + 2, y - 8.2, "J2 pin 1  VOUTA  -->  oscilloscope CH1  (channel signal)\nJ2 pin 3  VOUTB  -->  oscilloscope CH2  (monitor)\nJ2 pin 5  GND    -->  oscilloscope ground clips\n(optional: the VGA screen shows the same signals)", fontsize=8.5, va="top", color="#333", family="monospace")
        y = ybot - 6.5
    for ext in ("png", "svg"):
        out = os.path.join(ROOT, "docs", "wiring_schematic." + ext)
        fig.savefig(out, dpi=120, bbox_inches="tight"); print("wrote", out)

if __name__ == "__main__":
    main()
