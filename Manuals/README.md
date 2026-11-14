# Manuals

Reference documents for the hardware this project actually uses.

| File | What it is | Used for |
|---|---|---|
| `Digilent_PmodMIC_Reference_Manual.pdf` | Pmod MIC rev. B (PB200-122): electret microphone, SA575 compandor, ADCS7476 ADC | pinout, SPI format |
| `TI_ADCS7476_12bit_1MSPS_ADC_Datasheet.pdf` | the ADC on the Pmod MIC | serial timing implemented in `mic_adc_spi.v` |
| `Digilent_PmodDA2_Reference_Manual.pdf` | Pmod DA2: two DAC121S101 | pinout, frame format |
| `TI_DAC121S101_12bit_DAC_Datasheet.pdf` | the DAC on the Pmod DA2 | serial timing implemented in `da2_dac_spi.v` |
| `Digilent_PmodAMP2_Reference_Manual.pdf` | Pmod AMP2 (PB200-233): SSM2377 class-D amplifier. The manual is written for rev. A; the rev. B board has the same J1 pinout | pinout, gain and shutdown pins |
| `ADI_SSM2377_ClassD_Amplifier_Datasheet.pdf` | the amplifier on the Pmod AMP2 | gain setting, shutdown, input range |
| `Digilent_PmodKYPD_Reference_Manual.pdf` | Pmod KYPD rev. B (PB200-195): 4 x 4 keypad | pinout, scan method |
| `Digilent_Pmod_Interface_Specification_1_2_0.pdf` | the Pmod connector standard | pin numbering, power pins |
| `ZedBoard_Hardware_Users_Guide_v2_2.pdf` | Avnet ZedBoard | Pmod / VGA / button / LED pin tables, bank voltages |
| `Zedboard-Master.xdc` | Digilent master constraint file for the ZedBoard | source of every pin in `zedboard_cordic_fm.xdc` |
| `Andraka_1998_Survey_of_CORDIC_Algorithms_for_FPGA.pdf` | R. Andraka, FPGA '98 | the CORDIC formulation used in `cordic_engine.v` |

The general Xilinx user guides that were here before (UG900, UG901, UG903, UG949, UG953, UG473,
PG105, PG159, DS187, DS190) were removed: they are not specific to this project and are available
from the AMD documentation portal (search for the document number at <https://docs.amd.com>).
The Pmod MIC3 manual was removed because the project uses the original Pmod MIC.
