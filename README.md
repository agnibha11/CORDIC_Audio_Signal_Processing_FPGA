# CORDIC-Based Real-Time Audio Modulation & Demodulation

Real-time FM, PM and AM modulation of microphone audio on the **Avnet ZedBoard (Zynq-7000 `xc7z020clg484-1`)**, built entirely in the programmable logic around a hand-written iterative CORDIC engine. The same engine generates the carrier and demodulates it, so the effect of the modulation on the audio is measured on chip as a signal-to-noise ratio.

Course project — Reconfigurable Computing (CS G553), Problem Statement 1: *CORDIC-Based Audio Signal Processing System with User-Controlled Frequency Modulation*.

![Architecture](docs/img/architecture.png)

---

## Features

- **Audio capture** — Pmod MIC3 (TI ADCS7476, 12-bit) at 50 kS/s through a custom SPI master, with a 31 Hz DC-blocking filter.
- **One CORDIC, three jobs per sample** — a single iterative engine (24-bit datapath, 18 iterations, rotation + vectoring modes) is time-shared to produce the internal test tone, the modulated carrier, and the demodulated signal.
- **Modulation modes** — FM, PM, AM and bypass, selected at run time.
- **Live control** — Pmod KYPD keypad sets carrier frequency (100 Hz – 10 kHz), modulation index (0 – 15.875), modulating-tone frequency (50 Hz – 2 kHz), modulating amplitude, mode and source (mic / internal tone).
- **Output** — Pmod DA2 (dual DAC121S101): channel A carries the modulated signal, channel B a selectable monitor (original, demodulated, tone or quadrature).
- **Signal storage** — triggered, double-buffered block-RAM capture of the original, modulated and demodulated signals (2 × 1024 samples).
- **VGA scope** — 640 × 480 two-channel display with the demodulated (or error ×16) trace overlaid on the original and all parameters shown as text.
- **Quality measurement** — on-chip fidelity meter computes Σm², Σ(m − m̂)², peak error and SNR in dB.
- **Vivado VIO dashboard** — read back every parameter, sample and statistic over JTAG, or override the keypad.

## Hardware

| Module | Connector | Function |
|---|---|---|
| Pmod MIC3 | JA, top row | microphone + ADC |
| Pmod DA2 | JA, bottom row | dual 12-bit DAC |
| Pmod KYPD | JB | 4 × 4 keypad |
| VGA monitor | on-board VGA | scope display |
| Speakers / oscilloscope | DA2 outputs | playback / analog view |

Single 100 MHz clock domain; all board inputs are two-flop synchronised. Pin assignments are in `CORDIC.srcs/constrs_1/new/zedboard_cordic_fm.xdc`.

## Key figures

| | |
|---|---|
| Sample rate | 50 kS/s (2000 clocks per sample at 100 MHz) |
| CORDIC | iterative, 18 iterations, 19-clock latency, 2.9 % utilisation |
| DSP sequence | 70 clocks per sample |
| Input-to-output latency | 7.2 µs, deterministic |
| Loop-back SNR (FM, β = 2) | 63.8 dB |
| Loop-back SNR (PM, β = 2 / AM, depth 1) | 87.6 dB / 76.0 dB |
| Block RAM | 3 × RAMB36 |

FM loop-back SNR rises by 6 dB for every doubling of the modulation index (43 dB at β = 0.125 to 84 dB at β = 15.875), matching the classical SNR ∝ β² law.

## Controls

```
         COL1   COL2   COL3   COL4
ROW1   [1]fc+  [2]β+  [3]fm+ [A]amp+
ROW2   [4]fc-  [5]β-  [6]fm- [B]amp-
ROW3   [7]src  [8]mode[9]tb  [C]hold
ROW4   [0]dflt [F]step[E]dacB[D]mute
```

| Control | Function |
|---|---|
| BTND | reset (restores defaults) |
| BTNU | next mode |
| BTNL / BTNR | carrier − / + |
| BTNC | scope hold / run |
| SW2 | overlay demodulated signal / error ×16 |
| SW3 | LEDs show the pressed key code |
| LD0–LD1 | mode · LD2 tone source · LD3 hold · LD4 coarse step · LD5 clip · LD6 key activity · LD7 heartbeat |

Keys are debounced and auto-repeat when held. `F` toggles fine/coarse steps; `0` restores the defaults (f_c = 2 kHz, β = 2, f_m = 200 Hz, amplitude 1, FM, microphone).

## Build and run

Requires Vivado 2025.x. Clone to a path **without spaces**.

```tcl
# Vivado Tcl console, from the repository root
source create_project.tcl            ;# creates CORDIC.xpr and generates the VIO core
source scripts/run_sims.tcl          ;# runs all test benches, prints PASS/FAIL
source scripts/build_bitstream.tcl   ;# synthesis, implementation, bitstream, reports/
```

Program the board with `CORDIC.runs/impl_1/cordic_fm_top.bit` together with the probes file `cordic_fm_top.ltx`, then press **BTND** to reset. Press `7` to switch to the internal tone for a clean test signal.

## Verification

Every block has a self-checking test bench whose golden reference uses a different algorithm from the design (double-precision maths, a floating-point modulation model, datasheet-derived device models with protocol monitors). The CORDIC is also checked bit-exact against the Python reference model used for the analysis figures.

| Test bench | Checks |
|---|---|
| `tb_cordic_engine` | 8701 |
| `tb_mic3_adc_spi` | 286 |
| `tb_da2_dac_spi` | 316 |
| `tb_kypd_scanner` | 70 |
| `tb_recip_divider` | 1417 |
| `tb_cordic_fm_system` | 845 |
| `tb_cordic_fm_top` | 8 |

All benches pass in XSim and Icarus Verilog (`iverilog -g2012`).

## Repository layout

```
CORDIC.srcs/
  sources_1/new/     RTL (Verilog-2001, `default_nettype none)
  constrs_1/new/     ZedBoard constraints
  sim_1/new/         test benches, device models, CORDIC vectors
scripts/             Python reference model, analysis, generators, Tcl flows
docs/img/            architecture and analysis figures
Manuals/             datasheets and reference guides
create_project.tcl   recreates the Vivado project
```

| Module | Role |
|---|---|
| `cordic_engine` | iterative CORDIC, rotation and vectoring |
| `fm_dsp_core` | per-sample sequencer: tone, carrier, demodulator |
| `param_controller`, `recip_divider` | user parameters and demodulator gain |
| `mic3_adc_spi`, `audio_frontend` | ADC interface, Q15 conversion, DC blocker |
| `da2_dac_spi` | dual-DAC interface |
| `kypd_scanner`, `btn_debounce` | keypad and button input |
| `capture_scope_ram` | triggered BRAM capture |
| `fidelity_meter` | SNR measurement |
| `vga_timing`, `vga_scope_render` | VGA scope and text overlay |
| `cordic_fm_top` | board wrapper, LEDs, VIO |

## References

- R. Andraka, *A survey of CORDIC algorithms for FPGA based computers*, FPGA '98
- TI ADCS7476 and DAC121S101 datasheets; Digilent Pmod MIC3, DA2 and KYPD reference manuals
- Avnet ZedBoard Hardware User's Guide v2.2
