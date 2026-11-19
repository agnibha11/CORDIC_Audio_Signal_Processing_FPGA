# The final demonstration

A script for presenting the project in about ten minutes, with what to press, what the audience
sees and hears, and what to say. Run `TESTING.md` completely before the day; this script assumes
everything there passed.

## The story in three sentences

1. The assignment is a CORDIC-based FM modulator for microphone audio with keypad control,
   storage and display.
2. We built the whole radio link around it on one chip: transmitter, a channel whose noise we can
   set, and a receiver, using a single CORDIC engine for all three roles.
3. That lets us show and measure, live, what modulation is for: at the same channel noise FM
   gives cleaner audio than AM, it gets 6 dB better per doubling of the modulation index, and it
   collapses below a threshold. The meter on the screen agrees with the textbook formula.

Keep coming back to sentence 3. Everything in the demo is evidence for it.

## Setup, 15 minutes before

| Item | State |
|---|---|
| Pmods | DA2 in JA (top row), KYPD in JB, MIC in JC (top row), AMP2 in JD (top row) |
| Loudspeaker | in the AMP2 jack, facing the audience, at least 50 cm from the microphone, pointing away from it |
| Monitor | VGA, visible to the audience |
| Oscilloscope (optional) | CH1 on DA2 output A (channel), CH2 on output B (monitor), trigger CH2, 500 microseconds/div |
| Switches | all down, then SW4 up (volume -6 dB) as a starting point |
| Laptop | Vivado Hardware Manager open with the VIO dashboard, in case a number is asked for |
| Board | programmed; press BTND once; LD7 blinking |

Do a sound check: `7` (tone) should be clearly audible at the back of the room; adjust SW5/SW4.
Then `0`. Speak: your voice should come from the loudspeaker without howling. If it howls,
lower the volume or move the speaker.

Print the key map and tape it next to the keypad:

```
[1] fc +    [2] beta +   [3] fm +     [A] amp +
[4] fc -    [5] beta -   [6] fm -     [B] amp -
[7] source  [8] mode     [9] noise +  [C] hold
[0] default [F] step     [E] noise -  [D] monitor
```

---

## Part 1. What it is (1 minute)

**Do:** nothing yet; point at the hardware and the screen.

**Say:** "A microphone, a keypad, a DAC, an amplifier and a ZedBoard. Inside the FPGA there is a
complete radio link: a transmitter that modulates the audio, a channel, and a receiver that
recovers it. The bottom trace is the signal on the channel. The top trace shows the original
audio in green and what the receiver recovered in yellow. All sines, cosines and angles are
computed by one CORDIC that we wrote ourselves: no multiplier-based sine tables and no vendor
IP."

## Part 2. The assignment: CORDIC FM with live parameters (2 minutes)

| Do | Audience sees / hears | Say |
|---|---|---|
| `7` (tone) | top: clean 400 Hz sine; bottom: carrier whose spacing breathes; a steady tone from the speaker | "An internal test tone, also from the CORDIC. The carrier is at 4 kHz and its frequency follows the tone: that is FM." |
| `D` twice (`MON = CHAN`) | the speaker plays a harsh warble | "This is what the modulated signal itself sounds like. Nobody listens to this; it exists to cross a channel." |
| `D` twice more (`RECV`) | tone again | "And this is the receiver's output." |
| hold `2` for two seconds | `BETA` and `DEV` climb; the carrier's breathing gets wider | "Modulation index. The deviation is index times modulating frequency." |
| `1` a few times, `4` back | `FC` changes, carrier denser | "Carrier frequency." |
| `3` a few times | pitch rises | "Modulating frequency." |
| `B` a few times, `A` back | top trace shrinks and grows | "Amplitude of the modulating signal." |
| `8` three times, pausing | `PM`, `AM`, `BYP`; in AM the bottom trace shows the envelope | "And the type of modulation: phase, amplitude, or none." |
| `0` then speak | your voice on the top trace and from the speaker | "The same with the microphone. Twenty microseconds per sample; from microphone to DAC in 7.4 microseconds." |
| `C` while speaking, `C` again | the picture freezes | "Original and modulated signals are stored in block RAM, triggered like an oscilloscope. We can read the stored samples out over JTAG." |

That is the whole problem statement, shown in two minutes. Say so: "That covers the assignment.
Now for what we added."

## Part 3. The channel: FM against AM (3 minutes)

This is the centre of the demo. Go slowly.

| Do | Audience sees / hears | Say |
|---|---|---|
| `0`, `7` (tone, clean channel) | `CNR = OFF`, `SNR` about 90 | "With a perfect channel the recovered tone matches the original to 90 dB. That residue is the CORDIC's own arithmetic, with 18 iterations." |
| `F` (coarse), `9` three times | `CNR = 16DB`; bottom trace fuzzy; faint hiss; `SNR` about 24 | "Now the channel adds noise: carrier-to-noise ratio 16 dB. FM delivers 24 dB at the output." |
| `8` twice (AM) | top trace visibly rough, loud hiss; `SNR` about 14 or 15 | "Same channel, AM instead: about 10 dB worse. You can hear it." |
| `8` (bypass) | `SNR` about 25 | "No modulation at all, for reference." |
| `8` (FM again) | back to 24 | |
| `2` eight times | `BETA = 13`, `SNR` about 32, hiss nearly gone | "Here is what FM can do and AM cannot: raise the modulation index. Every doubling gains 6 dB. We pay with bandwidth: you see the carrier swinging wider." |

**Say, with the theory slide or the plot `img/snr_vs_cnr.png` on the laptop:** "These are not
hand-picked numbers. The lines are the textbook formula for our filter; the dots are our design.
They agree within 0.3 dB, and the screen in front of you shows the same values."

## Part 4. The threshold (1.5 minutes)

| Do | Audience sees / hears | Say |
|---|---|---|
| `0`, `7`, `F`, `9` x4 (C/N 11 dB) | hiss, tone clear | "FM's advantage has a price." |
| `F` (fine), `9` one at a time down to 6 dB | at about 9 dB spikes appear on the yellow trace and the speaker starts to crackle | "Below about 10 dB the noise is sometimes larger than the carrier. The phase slips a full turn and the receiver outputs a click. This is the FM threshold effect." |
| SW2 up | red error trace with tall spikes | "The red trace is the error, times sixteen." |
| SW2 down, `0` | clean again | |

## Part 5. With a voice (1.5 minutes)

| Do | Audience hears | Say |
|---|---|---|
| `0`, `F`, `9` x3, speak | voice through moderate hiss | "FM, 16 dB." |
| `8` x2, speak the same sentence | voice buried in noise | "AM, same channel." |
| `8` x2 (back to FM), `2` x8, speak | clear voice | "FM with a wide deviation." |
| `D` x3 (`ERR`), speak | only noise, no voice | "And this is only what the channel added: the difference between original and recovered. The meter measures exactly this." |
| `D`, `0` | | |

## Part 6. How it is built (1 minute, while showing the block diagram)

**Say:** "One iterative CORDIC, 24 bits, 18 iterations, used three times per sample: test tone,
carrier, and in vectoring mode as the phase and envelope detector. It is busy for 57 of every
2000 clocks, under 3 %. We chose the iterative form deliberately: a pipelined CORDIC would be
eighteen times larger to deliver thirty times more than we need. The noise is generated on chip
from a xorshift generator, twelve values summed to make it Gaussian. Everything is verified
against a bit-exact Python model: 2900 samples, five signals, zero mismatches."

---

## If something goes wrong during the demo

| Problem | Do |
|---|---|
| Howling | SW7 up (mute), then `7` (tone source) and continue with the tone |
| Keypad misbehaves | BTNU = mode, BTNL/BTNR = carrier, BTNC = hold; or VIO override (`probe_out0 = 1`) and set values on the laptop |
| No sound | SW7 down? SW5/SW4? Continue with the screen and the SNR numbers |
| Lost in the settings | `0` restores everything |
| Monitor fails | oscilloscope on the DA2 shows both signals; the SNR is on the VIO (`probe_in15`) |

## Numbers to have ready

| Quantity | Value |
|---|---|
| Sample rate | 50 kS/s, 2000 clocks of 100 MHz per sample |
| CORDIC | iterative, 24-bit data and angle, 18 iterations, 19 clocks per result |
| CORDIC accuracy | sine/cosine within 1 LSB of 16 bits; angle 4.8 microradians RMS |
| CORDIC load | 3 results per sample, 57 of 2000 clocks (2.9 %) |
| DSP sequence | 83 clocks per sample |
| Latency | 7.4 microseconds from microphone sample to DAC (channel signal); recovered audio 0.13 ms |
| Clean-channel SNR | FM 90 dB, PM 90 dB, AM 80 dB |
| Theory, output SNR minus C/N | FM (2 kHz deviation) +7.5 dB, PM (2 rad) +15.0 dB, base band +9.0 dB, AM (100 %) +3.0 dB |
| FM index law | +6.0 dB per doubling of beta |
| FM threshold | about 10 dB C/N |
| Audio filter | four cascaded 4-sample averages, -3 dB at 2.93 kHz, delay 6 samples, no multipliers |
| Noise source | xorshift32, sum of 12, 31 levels in 1 dB steps |
| Storage | 2 x 1024 samples of original, channel, recovered in block RAM |
| Verification | 12 self-checking benches; whole link bit-exact with the Python model |

## Questions you are likely to get

**Why add noise? The assignment did not ask for it.**
Item 6 asks to analyse and quantify the impact of modulation on audio quality. Without a channel
there is no impact to measure: a perfect link returns the audio unchanged whatever the
modulation. The noise is what makes the question answerable.

**Is the noise really Gaussian?**
It is the sum of 12 uniform random numbers, which matches a Gaussian closely out to about 4
standard deviations and is bounded at 6. Measured: sigma within 0.5 % of the target, 68.3 % of
samples inside one sigma. The SNR results match Gaussian-noise theory to 0.3 dB.

**Why is PM better than FM in your table?**
At the default settings, yes: PM's noise is flat while FM's grows with frequency, and with a
2 kHz deviation and a 3 kHz audio band FM has not yet "caught up". Raise the index and FM passes
it (+17.5 dB at the maximum). PM also relies on the receiver knowing the carrier phase, which a
real receiver would have to recover; FM does not.

**Why is the AM curve below its line?**
At 100 % depth the carrier disappears in the troughs of the audio; there the envelope detector
is measuring mostly noise. At 50 % depth the points sit on the line.

**Why only one CORDIC? Why not the Xilinx CORDIC IP?**
One is enough by a factor of 30, and writing it was the point of the assignment. The vendor IP
would also need two instances (its function is fixed when it is generated).

**How do you know the hardware matches the plots?**
The plots come from a Python model; a test bench proves the RTL equal to that model bit for bit;
and the SNR table in `TESTING.md` step 10 compares the board's read-outs with the model.

**What limits the 90 dB?**
The 24-bit angle and 18 iterations. It is already 18 dB beyond what the 12-bit converters can
resolve.

**What does the receiver know that a real one would not?**
The carrier frequency exactly (needed for FM and AM) and, for PM only, the carrier phase.

**Why 50 kS/s?**
An integer number of clocks per sample, time for both serial links, and a 25 kHz Nyquist limit
that leaves room for wide FM deviations.
