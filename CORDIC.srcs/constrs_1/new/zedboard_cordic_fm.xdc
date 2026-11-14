# ============================================================================
#  zedboard_cordic_fm.xdc -- ZedBoard (xc7z020clg484-1) constraints
#  Pin names and bank voltages from the Digilent ZedBoard master XDC
#  (Manuals/Zedboard-Master.xdc): banks 13 and 33 are 3.3 V, banks 34/35
#  run at VADJ which is 1.8 V by default (jumper J18).
#  If J18 is set to 2.5 V or 3.3 V, change LVCMOS18 below to LVCMOS25 / LVCMOS33.
# ============================================================================

# ---------------- clock: 100 MHz oscillator, bank 13 ----------------
set_property -dict {PACKAGE_PIN Y9 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk100]

# ---------------- push buttons, bank 34 (1.8 V) ----------------
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS18} [get_ports btn_rst]   ;# BTND
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS18} [get_ports btn_u]     ;# BTNU
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS18} [get_ports btn_l]     ;# BTNL
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS18} [get_ports btn_r]     ;# BTNR
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS18} [get_ports btn_c]     ;# BTNC

# ---------------- slide switches, bank 35 (1.8 V) ----------------
set_property -dict {PACKAGE_PIN F22 IOSTANDARD LVCMOS18} [get_ports {sw[0]}]   ;# scope time base, bit 0
set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS18} [get_ports {sw[1]}]   ;# scope time base, bit 1
set_property -dict {PACKAGE_PIN H22 IOSTANDARD LVCMOS18} [get_ports {sw[2]}]   ;# overlay = error x16
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS18} [get_ports {sw[3]}]   ;# LEDs show key code
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS18} [get_ports {sw[4]}]   ;# loudspeaker volume, bit 0 (-6 dB)
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS18} [get_ports {sw[5]}]   ;# loudspeaker volume, bit 1 (-12 dB)
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS18} [get_ports {sw[6]}]   ;# loudspeaker amplifier gain 12 dB instead of 6 dB
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS18} [get_ports {sw[7]}]   ;# loudspeaker mute

# ---------------- user LEDs, bank 33 (3.3 V) ----------------
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[7]}]

# ---------------- Pmod JA, bank 13 (3.3 V), top row: Pmod MIC ----------------
# pin1 SS, pin2 NC, pin3 MISO, pin4 SCK
set_property -dict {PACKAGE_PIN Y11  IOSTANDARD LVCMOS33} [get_ports adc_cs_n]    ;# JA1
set_property -dict {PACKAGE_PIN Y10  IOSTANDARD LVCMOS33} [get_ports adc_miso]    ;# JA3
set_property -dict {PACKAGE_PIN AA9  IOSTANDARD LVCMOS33} [get_ports adc_sclk]    ;# JA4

# ---------------- Pmod JB, bank 13 (3.3 V): Pmod KYPD ----------------
# pin1 COL4, pin2 COL3, pin3 COL2, pin4 COL1, pin7 ROW4, pin8 ROW3, pin9 ROW2, pin10 ROW1
set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS33} [get_ports {kypd_col[3]}] ;# JB1  COL4
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports {kypd_col[2]}] ;# JB2  COL3
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {kypd_col[1]}] ;# JB3  COL2
set_property -dict {PACKAGE_PIN W8  IOSTANDARD LVCMOS33} [get_ports {kypd_col[0]}] ;# JB4  COL1
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {kypd_row[3]}] ;# JB7  ROW4
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {kypd_row[2]}] ;# JB8  ROW3
set_property -dict {PACKAGE_PIN V9  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {kypd_row[1]}] ;# JB9  ROW2
set_property -dict {PACKAGE_PIN V8  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {kypd_row[0]}] ;# JB10 ROW1

# ---------------- Pmod JC, bank 13 (3.3 V), top row: Pmod AMP2 ----------------
# pin1 AIN, pin2 GAIN, pin3 NC, pin4 ~SHUTDOWN.
# JC and JD are routed as differential pairs.  Header pin numbers (ZedBoard
# schematic, sheet "PMODs and General I/O"):  pin 1 = Jx1_P, pin 2 = Jx1_N,
# pin 3 = Jx2_P, pin 4 = Jx2_N, pin 7 = Jx3_P, pin 8 = Jx3_N, pin 9 = Jx4_P, pin 10 = Jx4_N.
set_property -dict {PACKAGE_PIN AB7 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports amp_ain]   ;# JC1  (JC1_P)
set_property -dict {PACKAGE_PIN AB6 IOSTANDARD LVCMOS33} [get_ports amp_gain]                    ;# JC2  (JC1_N)
set_property -dict {PACKAGE_PIN AA4 IOSTANDARD LVCMOS33} [get_ports amp_shutdown_n]              ;# JC4  (JC2_N)

# ---------------- Pmod JD, bank 13 (3.3 V), top row: Pmod DA2 ----------------
# pin1 ~SYNC, pin2 DINA, pin3 DINB, pin4 SCLK
set_property -dict {PACKAGE_PIN V7  IOSTANDARD LVCMOS33} [get_ports dac_sync_n]   ;# JD1  (JD1_P)
set_property -dict {PACKAGE_PIN W7  IOSTANDARD LVCMOS33} [get_ports dac_dina]     ;# JD2  (JD1_N)
set_property -dict {PACKAGE_PIN V5  IOSTANDARD LVCMOS33} [get_ports dac_dinb]     ;# JD3  (JD2_P)
set_property -dict {PACKAGE_PIN V4  IOSTANDARD LVCMOS33} [get_ports dac_sclk]     ;# JD4  (JD2_N)

# ---------------- VGA, bank 33 (3.3 V) ----------------
set_property -dict {PACKAGE_PIN V20  IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN U20  IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN V19  IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN V18  IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]
set_property -dict {PACKAGE_PIN Y21  IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN Y20  IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS33} [get_ports vga_hs]
set_property -dict {PACKAGE_PIN Y19  IOSTANDARD LVCMOS33} [get_ports vga_vs]

# ---------------- timing exceptions ----------------
# Every input is resynchronised with two flops and every output is a slow
# (<= 25 MHz) registered signal whose consumers do not care about ns-level
# skew, so these ports are excluded from timing analysis.  The SPI clocks are
# ordinary data outputs (5 MHz square waves generated by counters), not
# clocks, and need no clock constraint.
set_false_path -from [get_ports {btn_rst btn_u btn_l btn_r btn_c sw[*] kypd_row[*] adc_miso}]
set_false_path -to   [get_ports {led[*] kypd_col[*] adc_cs_n adc_sclk dac_sync_n dac_dina dac_dinb dac_sclk amp_ain amp_gain amp_shutdown_n vga_r[*] vga_g[*] vga_b[*] vga_hs vga_vs}]

# place the SPI, bit-stream and VGA output registers in the IOBs for clean, skew-free edges
set_property IOB TRUE [get_ports {adc_cs_n adc_sclk dac_sync_n dac_dina dac_dinb dac_sclk amp_ain vga_r[*] vga_g[*] vga_b[*] vga_hs vga_vs}]

# PL-only design on a Zynq part: the PS7 is intentionally absent
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
