# Step-by-step test procedure

This procedure takes the design from "passes simulation" to "works on the bench". It is
ordered so that every step depends only on things already proven, and so that a fault points at
one module or one connector.

The design has not been on hardware before. Expect that the first pass through this document
finds something; the troubleshooting table at the end and the notes in each step say where to
look. Expected values marked *(model)* come from the bit-exact Python model, values marked
*(sim)* from the RTL simulation.

Keep a copy of the table in step 12 and fill it in as you go: it is the measurement record for
the report.

---

## Step 0. Before touching the hardware: simulation regression

Either in Vivado (`source scripts/run_sims.tcl`, about 30 minutes) or with Icarus Verilog
(handbook section 12.2). All twelve benches must end with `ALL PASS`.

| Bench | Expected last line |
|---|---|
| `tb_cordic_engine` | `ALL PASS (8701 checks)` |
| `tb_awgn_gen` | `ALL PASS (967 checks)` |
| `tb_audio_lpf` | `ALL PASS (3056 checks)` |
| `tb_sd_dac` | `ALL PASS (11 checks)` |
| `tb_bin2bcd` | `ALL PASS (2256 checks)` |
| `tb_mic_adc_spi` | `ALL PASS (286 checks)` |
| `tb_da2_dac_spi` | `ALL PASS (316 checks)` |
| `tb_kypd_scanner` | `ALL PASS (70 checks)` |
| `tb_recip_divider` | `ALL PASS (1417 checks)` |
| `tb_fm_dsp_core` | `ALL PASS (14502 checks)` |
| `tb_cordic_fm_top` | `ALL PASS (16 checks)` |
| `tb_cordic_fm_system` | `ALL PASS (859 checks)` |

## Step 1. Build

1. Clone the repository to a path **without spaces**.
2. Vivado Tcl console: `cd` to the folder, `source create_project.tcl`, then
   `source scripts/build_bitstream.tcl`.
3. Open `reports/timing_summary.rpt`.

| Check | Pass condition | If not |
|---|---|---|
| Bitstream written | `vivado/CORDIC.runs/impl_1/cordic_fm_top.bit` and `.ltx` exist | read the first error in the Vivado log |
| Setup timing | WNS (worst negative slack) is 0 or positive | the report names the failing path; note source and destination register and add a pipeline register there, or ask for help with the path name |
| Hold timing | WHS is 0 or positive | normally fixed automatically by the router |
| DRC | no errors; warnings about the unused processor (`ZPS7-1`) and inside `dbg_hub` are expected | read the DRC message |
| Unconstrained ports | none | every top-level port must appear in the XDC |

Record WNS, the LUT / flip-flop / DSP / block-RAM counts (from `reports/utilization.rpt`) in
the table of step 12. These are the first real numbers for resources and timing.

**Do not continue with negative slack**: a design that fails timing may work, half-work or fail
differently on each power-up, and every later step would be unreliable.

## Step 2. Board alone: no Pmods plugged in

Connect only: 12 V supply, micro-USB to J17 (PROG), VGA monitor. All switches down.

1. Power on. Hardware Manager, open target, **Program Device** with both the `.bit` and the
   `.ltx` file.
2. Do **not** press any button yet.

| Check | Expected | Meaning if wrong |
|---|---|---|
| Blue DONE LED | on | bitstream not loaded: cable, power, wrong device |
| LD7 | blinks once per second | clock or reset problem |
| LD0 to LD6 | all off | mode FM, microphone, no hold, no noise |
| VGA picture | title row, two framed panes, six text rows | no picture: monitor does not accept 640 x 480 at 59.5 Hz, or VGA pins |
| Text | `FC = 4000 HZ`, `BETA = 5.000`, `FM = 400 HZ`, `AMP = 1.00`, `DEV = 2000.0 HZ`, `MODE = FM`, `SRC = MIC`, `CNR = OFF`, `HOLD = RUN`, `STEP = FINE`, `MON = RECV` | all zeros or garbage: the power-on reset did not work; press BTND; if that fixes it, report it |

3. Buttons:

| Action | Expected |
|---|---|
| BTNU | `MODE` goes FM, PM, AM, BYP, FM; LD1:LD0 count 00, 01, 10, 11 |
| BTNR, BTNL | `FC` up / down by 100 Hz |
| BTNC | `HOLD = HOLD`, LD3 on; again: `RUN` |
| BTND | everything back to the defaults |

4. Switches: SW0 up: `TB=X2`; SW1 up: `TB=X4`; SW2 up: row 1 changes to `ERRORX16=RED`; SW7 up:
   `MUTE` appears. Put all switches down again.

## Step 3. The whole signal chain, still without Pmods (VIO)

The internal tone exercises transmitter, channel, receiver, filter, meter, capture and display
with no external hardware. Without a keypad it is selected through the VIO dashboard.

1. In Hardware Manager open the VIO dashboard (`hw_vio_1`), press `+`, add all probes.
   Radix: `probe_in9`, `in10`, `in11` signed decimal; the rest unsigned decimal.
2. Set `probe_out1 = 40`, `out2 = 40`, `out3 = 8`, `out4 = 16`, `out5 = 0`, `out6 = 1`
   (source = tone), `out7 = 0`, `out9 = 0`, then `probe_out0 = 1` (override).

| Check | Expected |
|---|---|
| Screen | `SRC = TONE`; top pane: five and a bit cycles of a clean sine, stable (not drifting sideways); bottom pane: a dense carrier at half height whose spacing visibly tightens and widens |
| `SNR` | about 90 *(model: 90.3 dB)* |
| `probe_in18` (G), `probe_in19` (D) | 819 200 and 671 088 for the default settings *(model)* |
| `probe_in8` (ADC code) | no meaning yet: the MIC is not plugged in |

3. Channel noise: set `probe_out9` and compare the `SNR` read-out. The read-out updates every
   0.66 s and may flicker by 1.

| `probe_out9` | `CNR` shows | SNR expected *(model)* | Top pane |
|---|---|---|---|
| 0 | OFF | 90 | yellow exactly covers green |
| 1 | 30DB | 37 or 38 | still covers |
| 11 | 20DB | 27 or 28 | slight roughness |
| 16 | 15DB | 22 or 23 | yellow wobbles around green |
| 21 | 10DB | 17 or 18 | clearly noisy |
| 26 | 5DB | 10 to 12 | spikes (FM threshold) |
| 31 | 0DB | 1 to 3 | no resemblance |

LD4 is on whenever the noise is on. If these values are right, the arithmetic of the whole link
is right on silicon, because the model is bit-exact.

4. Modes at `probe_out9 = 16` (C/N 15 dB): set `probe_out5` to 1, 2, 3.

| `probe_out5` | Mode | SNR expected *(model)* |
|---|---|---|
| 0 | FM | 23 |
| 1 | PM | 30 |
| 2 | AM | 13 or 14 |
| 3 | BYP | 24 |

5. Set `probe_out9 = 0`, `probe_out5 = 0`. Leave the override on for now.

## Step 4. Pmod port pins with a multimeter (optional, before plugging any Pmod)

Purpose: confirm that the FPGA signals are on the header pins the wiring table says. The JC and
JD pin order is confirmed on the ZedBoard schematic (`WIRING.md` section 4), so this step is an
extra safety check, mainly for JC, where a swap would make the FPGA drive the microphone's output
pin. DC voltage range, black lead on pin 5 (GND) of the same row. The
signals toggle fast; a multimeter shows their average.

| Port pin | Signal | Expected reading | Then |
|---|---|---|---|
| any port, pin 6 | 3V3 | 3.3 V | |
| JA2 | `amp_gain` | 3.3 V | SW6 up: 0 V |
| JA4 | `amp_shutdown_n` | 3.3 V | SW7 up: 0 V |
| JA1 | `amp_ain` | about 1.65 V (a 50 % bit stream) | steady |
| JB1 to JB4 | `kypd_col` | about 2.5 V each (low one quarter of the time) | |
| JB7 to JB10 | `kypd_row` (inputs, pull-up) | about 3.3 V | |
| JC1 | `adc_cs_n` | about 2.75 V | |
| JC4 | `adc_sclk` | about 3.0 V (idles high) | |
| JC2, JC3 | not used / `adc_miso` (input) | no defined reading | |
| JD1 | `dac_sync_n` | about 2.75 V (high except 3.3 of every 20 microseconds) | |
| JD4 | `dac_sclk` | about 0.25 V | |
| JD2, JD3 | `dac_dina`, `dac_dinb` | between 0 and about 0.3 V, varying | |

If JC2 reads 2.75 V instead of JC1, or JC3 reads 3.0 V instead of JC4, the P/N order of the pairs
on JC is the other way round on your board: apply the fix in `WIRING.md` section 4, rebuild,
repeat this step. **Do not plug the MIC in before JC1 and JC4 read as in the table.**

Put SW6 and SW7 down again.

## Step 5. Pmod DA2 on JD, oscilloscope

Power off, plug the DA2 into the **top row of JD**, power on, program, repeat the VIO settings of
step 3. Scope CH1 on DA2 J2 pin 1 (VOUTA), CH2 on J2 pin 3 (VOUTB), grounds on J2 pin 5.
Both channels DC-coupled, 500 mV/div, 500 microseconds/div, trigger on CH2.

| Check | Expected |
|---|---|
| CH2 (monitor = recovered tone) | sine, 400 Hz (period 2.5 ms), from about 0 V to 3.3 V, centred on 1.65 V |
| CH1 (channel signal) | FM carrier centred on 1.65 V, about 1.65 V peak to peak (half scale), visibly denser where CH2 is high |
| Set `probe_out2 = 0` (beta 0) | CH1 becomes a plain 4 kHz sine (period 250 microseconds); frequency read-out 4.000 kHz within the crystal tolerance |
| Set `probe_out1 = 100` | CH1 is 10 kHz: only 5 samples per cycle, the DAC steps are visible. That is correct |
| Back to `out1 = 40`, `out2 = 40`; `probe_out9 = 16` | CH1 carrier with noise on it; CH2 sine with roughness |
| DAC steps | each step lasts 20 microseconds (50 kS/s) |

A flat line at 1.65 V on both: the DAC is receiving frames of mid-scale, check the VIO source
setting. 0 V or 3.3 V stuck: wiring or orientation.

## Step 6. Pmod KYPD on JB

Power off, plug the keypad into JB (directly or with a 12-pin cable), power on, program.
In the VIO set `probe_out0 = 0` (override off): the keypad is now in control.
Put **SW3 up**: the LEDs now show the key code, LD7 lights while a key is held.

Press every key once and compare LD3..LD0 (1 = on):

| Key | LD3 LD2 LD1 LD0 | | Key | LD3 LD2 LD1 LD0 |
|---|---|---|---|---|
| 0 | 0000 | | 8 | 1000 |
| 1 | 0001 | | 9 | 1001 |
| 2 | 0010 | | A | 1010 |
| 3 | 0011 | | B | 1011 |
| 4 | 0100 | | C | 1100 |
| 5 | 0101 | | D | 1101 |
| 6 | 0110 | | E | 1110 |
| 7 | 0111 | | F | 1111 |

The key also appears after `K=` at the top right of the screen while held.

| Symptom | Cause |
|---|---|
| no key does anything | header not seated, cable reversed end to end, or rows/columns exchanged (pins 1-4 with 7-10) |
| keys work but give the wrong codes in a regular pattern (for example 1 reads as A, 4 as B) | the column order is reversed: header mirrored. Either turn the connector or reverse the order of the four `kypd_col` pin assignments in the XDC |
| rows exchanged (1 reads as 0, 4 as 7) | reverse the order of the four `kypd_row` assignments |
| a key registers twice | should not happen (5 ms debounce); report it with the key |

SW3 down. Press `0`. Then check each function key against the screen:

| Key | Expected on screen |
|---|---|
| `1`, `4` | `FC` 4100, back to 4000 |
| `2`, `5` | `BETA` 5.125, back to 5.000; `DEV` follows |
| `3`, `6` | `FM` 450, back to 400 |
| `A`, `B` | `AMP` 1.06, back to 1.00 |
| `7` | `SRC = TONE`, LD2 on |
| `8` | `MODE` cycles |
| `9` | `CNR = 30DB`, LD4 on; again 29DB |
| `E` | back towards `OFF` |
| `F` | `STEP = CRSE`; now `1` adds 1000 Hz, `2` adds 1.0, `9` subtracts 5 dB |
| `C` | `HOLD = HOLD`, picture frozen |
| `D` | `MON` cycles RECV, ORIG, CHAN, ERR |
| hold `1` | after half a second `FC` counts up continuously, stops at 10000 |
| `0` | all defaults |

## Step 7. Pmod AMP2 on JA, loudspeaker

Before plugging in: **SW7 up (mute), SW5 and SW4 up (quietest)**. Power off, plug the AMP2 into
the top row of JA, loudspeaker into its jack, power on, program.

1. Press `7` (tone). SW7 down.

| Check | Expected |
|---|---|
| Sound | a steady 400 Hz tone, quiet |
| SW4 down, then SW5 down | louder in three steps of 6 dB |
| SW6 up | louder again (12 dB amplifier gain); may distort at full volume with a full-scale tone: put it down again |
| SW7 up | silence, `MUTE` on screen |
| `3` several times | pitch rises in 50 Hz steps |
| `D` once (`MON = ORIG`) | same tone |
| `D` again (`CHAN`) | the FM carrier itself: a harsh buzz around 4 kHz |
| `D` again (`ERR`) | near silence with the channel clean |
| `D` again | back to `RECV` |

2. Noise by ear, tone source, `MON = RECV`: press `F` (coarse), then `9` repeatedly.

| `CNR` | Expected sound |
|---|---|
| 30, 25 | tone with faint hiss |
| 20, 15 | tone with clear hiss |
| 10 | strong hiss, occasional click |
| 5 | crackling, the tone is still recognisable |
| 0 | noise |

No sound at all: SW7; jack; step 4 readings on JA; speaker impedance (4 to 8 ohm, or powered
speakers). A loud hum or whistle that depends on where the speaker is: acoustic feedback, see step 8.

## Step 8. Pmod MIC on JC

SW7 up (mute) first. Power off, plug the MIC into the **top row of JC**, power on, program.
Press `0` (source = microphone).

| Check | Expected |
|---|---|
| VIO `probe_in8` in a quiet room | hovering around mid-scale (roughly 1800 to 2300; the exact resting value depends on the board). Stuck at 0 or 4095: orientation or wiring |
| Top pane, quiet room | a thin noisy line at the centre (the compressor on the Pmod raises room noise) |
| Speak or whistle at 20 cm | the top pane shows the waveform; a whistle gives a clean sine and a stable picture |
| Bottom pane | the carrier's spacing follows the voice |
| `CLIP` / LD5 | only on very loud sounds |
| `SNR` | meaningful only while there is sound; high (above 60) with the channel clean |

Now SW7 down, volume low, loudspeaker pointing away from the microphone:

| Check | Expected |
|---|---|
| `MON = RECV` | your voice from the loudspeaker (delayed by a fraction of a millisecond, not noticeable) |
| Howling | acoustic feedback: lower the volume (SW5, SW4), move the speaker away, or use headphones |
| `8` three times (bypass) | the same voice; this is the reference: FM with a clean channel must sound the same |

## Step 9. Functional tests with the microphone

Press `0` before each.

| Test | Keys | Expected |
|---|---|---|
| FM in noise | `F`, `9` x3 (C/N 16 dB) | voice clearly audible through steady hiss |
| More deviation helps | then `2` x8 (beta 13) | hiss drops markedly; `SNR` rises by about 8 dB compared with beta 5 |
| AM at the same noise | `0`, `F`, `9` x3, `8` x2 | much noisier than FM was |
| PM | `8` instead (once) | cleaner than AM |
| Threshold | FM, keep pressing `9` | below about 10 dB the hiss turns into crackling and the voice breaks up |
| Hear only the damage | `D` three times (`ERR`) | noise only, no voice: this is what the channel added |
| Hear the channel | `D` twice (`CHAN`) | the modulated carrier with noise |
| Error on screen | SW2 up | red trace = difference x16, grows with the noise |
| Freeze a word | `C` while speaking | picture stops; `C` again resumes |
| Time base | SW0 / SW1 | X2, X4 zoom |

## Step 10. Quantitative check against the model

Tone source (`0`, `7`). For each row set the mode with `8` and the noise with `F`, `9` / `E`.
Wait three updates of the `SNR` read-out and note the value. For the exact value read
`probe_in12` (S) and `probe_in13` (E) and compute `10 log10(S / E)`.

| Mode | C/N | Expected *(model)* | Measured (screen) | Measured (VIO sums) |
|---|---|---|---|---|
| FM | off | 90.3 | | |
| FM | 30 | 37.5 | | |
| FM | 20 | 27.7 | | |
| FM | 15 | 22.8 | | |
| FM | 10 | 17.8 | | |
| FM | 5 | 10.8 | | |
| PM | 20 | 35.1 | | |
| AM | 20 | 19.4 | | |
| BYP | 20 | 29.1 | | |

FM at C/N 20 dB against the index (keys `2` / `5`):

| beta | `DEV` | Expected *(model)* | Measured |
|---|---|---|---|
| 1.000 | 400 | 14.1 | |
| 2.000 | 800 | 20.0 | |
| 5.000 | 2000 | 27.7 | |
| 10.000 | 4000 | 33.7 | |
| 15.875 | 6350 | 37.6 | |

Pass condition: within 1.5 dB (the on-screen estimate is rounded to whole dB and a 0.66 s window
of noise has a statistical spread of a few tenths of a dB). Because the hardware is
deterministic and bit-exact with the model, large deviations mean a real fault.

## Step 11. Stored-signal read-back (item 4 of the statement)

1. Tone source, press `C` (hold).
2. VIO: read `probe_in17`; bit 3 is the bank being displayed.
3. Set `probe_out8 = bank * 1024 + i` for a few `i` and read `probe_in16` (48 bits: `m_ref` in
   bits 47:32, `r` in 31:16, `m_hat` in 15:0, each a signed 16-bit number).

| Check | Expected |
|---|---|
| `i = 0` | `m_ref` is zero or slightly positive (the record starts at a rising zero crossing) |
| `i = 31` | about +32 600 (a quarter of a 400 Hz cycle is 31.25 samples) |
| `i = 62, 63` | near zero, falling |
| `m_hat` with the channel clean | within 2 counts of `m_ref` |

## Step 12. Record sheet

| Quantity | Value | Source |
|---|---|---|
| Vivado version | | |
| WNS / WHS | | `reports/timing_summary.rpt` |
| Slice LUTs / registers | | `reports/utilization.rpt` |
| DSP48E1 / RAMB36 | | same |
| Hierarchical: `u_sys` vs `u_vio` + `dbg_hub` | | `reports/utilization_hier.rpt` |
| Total on-chip power | | `reports/power.rpt` |
| Carrier frequency at `FC = 4000` | | scope, step 5 |
| Tone frequency at `FM = 400` | | scope, step 5 |
| DAC step time | | scope, step 5 |
| SNR tables | | step 10 |
| Lowest C/N with intelligible speech, FM beta 5 / AM | | step 9, by ear |

## Troubleshooting

| Symptom | Look at |
|---|---|
| VIO probes have no names | the `.ltx` file was not given when programming |
| VIO core has the wrong number of probes after pulling new code | stale project: close it, delete the `vivado/` folder, `source create_project.tcl`, rebuild |
| Picture rolls or monitor says "out of range" | the monitor does not accept 59.5 Hz at 640 x 480; try another monitor |
| Everything works but the screen text is shifted by half a character | not a fault: the picture is delayed by half a pixel by design |
| Top pane flat, `SRC = MIC` | step 8: ADC code; is the MIC in JC top row |
| `SNR = 0` with the tone and a clean channel | receiver gain is 0: `probe_in18`; mode is bypass or beta is 0 |
| SNR values consistently off by several dB | timing failure (step 1) is the first suspect |
| Loudspeaker distorted | lower SW5/SW4 volume; SW6 down |
| Keypad dead after working | SW3 test (step 6); cable |
| Buttons do nothing, switches reversed | J18 (VADJ) not at 1V8: the XDC declares LVCMOS18 for banks 34/35 |
