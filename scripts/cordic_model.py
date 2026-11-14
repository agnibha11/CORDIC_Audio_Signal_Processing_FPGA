#!/usr/bin/env python3
"""
Bit-accurate Python reference model of the CORDIC radio link
(transmitter -> noisy channel -> receiver).

Every arithmetic step here mirrors the Verilog RTL exactly (two's-complement
widths, arithmetic right shifts = floor, modular phase accumulators), so the
model can generate golden vectors for the testbenches and drive the analysis
plots without an HDL simulator in the loop.

Fixed-point conventions (see README, section "Numerics"):
  * audio samples          : 16-bit signed, Q15, full scale = +/-32767
  * phase accumulators     : 32-bit unsigned, 1 turn = 2^32  (BAM)
  * CORDIC data path       : W = 24 bits  (Q15 payload << 4, 4 guard, 4 headroom... see below)
  * CORDIC angle path      : Z = 24 bits, 1 turn = 2^24 (two's complement, +/- half turn)
  * CORDIC iterations      : N = 18
"""
import math

# ----------------------------------------------------------------------------
# System constants (must match cordic_fm_pkg values in the RTL)
# ----------------------------------------------------------------------------
CLK_HZ          = 100_000_000
CLK_PER_SAMPLE  = 2000
FS              = CLK_HZ / CLK_PER_SAMPLE          # 50 000 Hz

W  = 24      # CORDIC data width
Z  = 24      # CORDIC angle width
N  = 18      # CORDIC iterations
G  = 4       # guard bits: engine value = Q15 value << G

FCW_PER_100HZ = 8589935      # round(100 * 2^32 / FS)      -> carrier step (fc_idx * 100 Hz)
FCW_PER_50HZ  = 4294967      # round( 50 * 2^32 / FS)      -> tone step    (fm_idx *  50 Hz)
KPM_UNIT      = 85445659     # round(2^32 / (16*pi))       -> phase deviation per beta_q (0.125 rad)
MU_SHIFT      = 12           # mu_q = beta_q << 12         -> AM depth, Q15 (beta_q/8 * 32768)
AM_D_UNIT     = 215845       # round(64 * K * 16384 / 8)   -> AM demod divisor per beta_q, then >> 6
DIV_NUM_SHIFT = 39           # reciprocal G = floor(2^39 / D)
DEMOD_SHIFT   = 24           # m_hat = (r * G) >> 24

BETA_FRAC_BITS = 3           # beta_q is Q4.3
GAIN_FRAC_BITS = 4           # amp   is Q2.4 (16 = unity)

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def to_signed(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v

def sat(v, bits):
    hi = (1 << (bits - 1)) - 1
    lo = -(1 << (bits - 1))
    return hi if v > hi else lo if v < lo else v

def wrap(v, bits):
    return v & ((1 << bits) - 1)

def round_shift(v, s):
    """Round-half-up arithmetic shift, exactly as the RTL does: (v + 2^(s-1)) >>> s."""
    return (v + (1 << (s - 1))) >> s

# ----------------------------------------------------------------------------
# CORDIC constants
# ----------------------------------------------------------------------------
def atan_table(z_bits=Z, n=N):
    """atan(2^-i) expressed in BAM units of 2^z_bits per turn, rounded to nearest."""
    return [int(round(math.atan(2.0 ** -i) / (2 * math.pi) * (1 << z_bits))) for i in range(n)]

def cordic_gain(n=N):
    k = 1.0
    for i in range(n):
        k *= math.sqrt(1.0 + 2.0 ** (-2 * i))
    return k

K_GAIN = cordic_gain()
# start vector for rotation mode: amplitude after N rotations = X0 * K = 32767 << G
X0 = int(round((32767 << G) / K_GAIN))
# AM demod offset: vectoring magnitude of a carrier with envelope 16384 (= 0.5) is K*16384 (Q15 units)
AM_OFFSET = int(round(K_GAIN * 16384))
ATAN = atan_table()

def _ashr(v, s):
    return v >> s          # Python >> on ints is an arithmetic (floor) shift

def cordic(x_in, y_in, z_in, vectoring, w=W, z_bits=Z, n=N, table=None):
    """Bit-exact model of cordic_engine.v.
    x_in, y_in : signed ints that fit in w bits
    z_in       : angle, any int, interpreted modulo 2^z_bits (BAM)
    returns (x_out, y_out, z_out) with z_out in [0, 2^z_bits)
    """
    table = table or ATAN
    q90 = 1 << (z_bits - 2)
    zm  = wrap(z_in, z_bits)
    if not vectoring:
        quad = zm >> (z_bits - 2)
        if quad == 1:          # [ 90, 180): pre-rotate +90
            x, y, z = -y_in, x_in, to_signed(zm - q90, z_bits)
        elif quad == 2:        # [-180,-90): pre-rotate -90
            x, y, z = y_in, -x_in, to_signed(zm + q90, z_bits)
        else:
            x, y, z = x_in, y_in, to_signed(zm, z_bits)
    else:
        if x_in < 0:
            if y_in >= 0:
                x, y, z = y_in, -x_in, q90
            else:
                x, y, z = -y_in, x_in, -q90
        else:
            x, y, z = x_in, y_in, 0
    for i in range(n):
        if vectoring:
            d = 1 if y < 0 else -1
        else:
            d = 1 if z >= 0 else -1
        xs, ys = _ashr(x, i), _ashr(y, i)
        x, y = x - d * ys, y + d * xs
        z = to_signed(z - d * table[i], z_bits)
        assert -(1 << (w - 1)) <= x < (1 << (w - 1)), "x overflow"
        assert -(1 << (w - 1)) <= y < (1 << (w - 1)), "y overflow"
    return x, y, wrap(z, z_bits)

def cordic_sincos_q15(phase32):
    """cos/sin of a 32-bit BAM phase as Q15, exactly as the modulator computes them."""
    x, y, _ = cordic(X0, 0, phase32 >> (32 - Z), False)
    return round_shift(x, G), round_shift(y, G)

# ----------------------------------------------------------------------------
# Parameter -> DSP constant derivation (param_controller.v)
# ----------------------------------------------------------------------------
MODE_FM, MODE_PM, MODE_AM, MODE_BYP = 0, 1, 2, 3
PM_BETA_MAX = 16             # PM phase deviation is min(beta, 2.0) rad  (beta_q <= 16) -> 1.14 rad of margin to the +/-pi wrap
AM_BETA_MAX = 8              # AM depth is min(beta, 1.0)                (beta_q <= 8)  -> never over-modulates

def derive_constants(fc_idx, beta_q, fm_idx, mode):
    fcw_c = wrap(fc_idx * FCW_PER_100HZ, 32)
    fcw_m = wrap(fm_idx * FCW_PER_50HZ, 32)
    kdev  = (beta_q * fcw_m) >> BETA_FRAC_BITS          # 32-bit unsigned (< 2^32 for all legal settings)
    b_pm  = min(beta_q, PM_BETA_MAX)
    b_am  = min(beta_q, AM_BETA_MAX)
    kpm   = b_pm * KPM_UNIT                              # < 2^31
    mu_q  = b_am << MU_SHIFT                             # Q15 depth, <= 32768
    d_am  = (b_am * AM_D_UNIT) >> 6
    if mode == MODE_FM:
        d = kdev >> (32 - Z)
    elif mode == MODE_PM:
        d = kpm >> (32 - Z)
    elif mode == MODE_AM:
        d = d_am
    else:
        d = 0
    g = 0 if d == 0 else min((1 << DIV_NUM_SHIFT) // d, (1 << 32) - 1)
    return dict(fcw_c=fcw_c, fcw_m=fcw_m, kdev=kdev, kpm=kpm, mu_q=mu_q, d_am=d_am, div=d, g=g)

# ----------------------------------------------------------------------------
# Channel noise generator (awgn_gen.v)
#   xorshift32 PRNG -> 12 signed 16-bit words summed (Irwin-Hall, sigma = 2^16)
#   -> scaled by a per-level gain so that sigma equals the requested value.
#   noise_idx 0 = channel noise off;  1..31 -> C/N = 31 - noise_idx  dB
#   C/N is carrier power (A^2/2, A = 32767) over the noise power of one
#   quadrature component (sigma^2), i.e. measured over the whole 0..Fs/2 band.
# ----------------------------------------------------------------------------
XS_SEED    = 0x2545F491
NOISE_SUMS = 12
def cnr_db_of(noise_idx):
    return None if noise_idx == 0 else 31 - noise_idx
NOISE_GAIN = [0] + [int(round(32767.0 / math.sqrt(2.0) / 10 ** ((31 - k) / 20.0))) for k in range(1, 32)]

def xorshift32(x):
    x ^= (x << 13) & 0xFFFFFFFF
    x ^= x >> 17
    x ^= (x << 5) & 0xFFFFFFFF
    return x

class Awgn:
    def __init__(self):
        self.x = XS_SEED
    def _sum(self):
        acc = 0
        for _ in range(NOISE_SUMS):
            self.x = xorshift32(self.x)
            acc += to_signed(self.x >> 16, 16)
        return acc                                   # 20-bit signed, sigma = 2^16
    def step(self, noise_idx):
        g = NOISE_GAIN[noise_idx]
        si = self._sum(); sq = self._sum()
        return _ashr(si * g, 16), _ashr(sq * g, 16)  # 19-bit signed each

# ----------------------------------------------------------------------------
# Audio low-pass filter (audio_lpf.v): cascade of moving-sum (boxcar) stages.
# Multiplier-free, linear phase, exact integer arithmetic.
# ----------------------------------------------------------------------------
RAW_BITS  = 20                                       # width of the unfiltered receiver output
LPF_LENS  = (4, 4, 4, 4)                             # stage lengths (powers of two)
LPF_SHIFT = sum(int(math.log2(L)) for L in LPF_LENS) # total gain = 2^LPF_SHIFT
LPF_DELAY = sum(L - 1 for L in LPF_LENS) / 2.0       # group delay in samples

class BoxLPF:
    def __init__(self, lens=LPF_LENS):
        self.lens = lens
        self.dl  = [[0] * L for L in lens]
        self.acc = [0] * len(lens)
    def step(self, x):
        v = x
        for k in range(len(self.lens)):
            self.acc[k] += v - self.dl[k][-1]
            self.dl[k] = [v] + self.dl[k][:-1]
            v = self.acc[k]
        return round_shift(v, LPF_SHIFT)             # fits 16 bits: |mean| <= 32768 -> saturate for the +32768 corner

def lpf_response(f, fs=FS, lens=LPF_LENS):
    """|H(f)| of the boxcar cascade (float)."""
    h = 1.0
    for L in lens:
        x = math.pi * f / fs
        h *= 1.0 if abs(math.sin(x)) < 1e-12 else abs(math.sin(L * x) / (L * math.sin(x)))
    return h

# ----------------------------------------------------------------------------
# Audio front end (audio_frontend.v): ADC code -> Q15, DC blocker
# ----------------------------------------------------------------------------
class AudioFrontEnd:
    DC_SHIFT = 8          # pole at 1 - 2^-8  -> fc = FS/(2*pi*256) ~ 31 Hz
    def __init__(self):
        self.x_prev = 0
        self.acc = 0      # Q15.8, 28-bit signed
    def step(self, adc_code):
        x = sat((adc_code - 2048) << 4, 16)
        diff = x - self.x_prev
        self.x_prev = x
        # acc <= acc - (acc >>> 8) + (diff << 8)
        self.acc = sat(self.acc - _ashr(self.acc, self.DC_SHIFT) + (diff << self.DC_SHIFT), 28)
        y = sat(_ashr(self.acc, self.DC_SHIFT), 16)
        clip = (adc_code < 64) or (adc_code > 4031)
        return y, clip

# ----------------------------------------------------------------------------
# Per-sample DSP sequence (fm_dsp_core.v): transmitter -> channel -> receiver
# ----------------------------------------------------------------------------
class FMCore:
    def __init__(self):
        self.phi_m = 0
        self.phi_c = 0
        self.theta_hat_prev = 0
        self.awgn = Awgn()
        self.lpf_ref = BoxLPF()
        self.lpf_rx  = BoxLPF()

    def step(self, x_mic, params, consts):
        """params: dict(mode, source, amp, noise) ; consts from derive_constants()."""
        mode, source, amp = params['mode'], params['source'], params['amp']
        noise_idx = params.get('noise', 0)
        ni, nq = self.awgn.step(noise_idx)
        # --- job 1: internal tone ------------------------------------------------
        _, ty, _ = cordic(X0, 0, self.phi_m >> (32 - Z), False)
        tone = round_shift(ty, G)
        self.phi_m = wrap(self.phi_m + consts['fcw_m'], 32)
        # --- modulating signal ---------------------------------------------------
        src = tone if source else x_mic
        m = sat(_ashr(src * amp, GAIN_FRAC_BITS), 16)
        # --- phase update ------------------------------------------------------
        p_fm = consts['kdev'] * m
        p_pm = consts['kpm'] * m
        p_am = consts['mu_q'] * m
        self.phi_c = wrap(self.phi_c + consts['fcw_c'], 32)
        if mode == MODE_FM:
            self.phi_c = wrap(self.phi_c + _ashr(p_fm, 15), 32)
            theta = self.phi_c
        elif mode == MODE_PM:
            theta = wrap(self.phi_c + _ashr(p_pm, 15), 32)
        else:
            theta = self.phi_c
        env = sat(16384 + _ashr(p_am, 16), 16)
        # --- job 2: carrier (transmitter) ---------------------------------------
        cx, cy, _ = cordic(X0, 0, theta >> (32 - Z), False)
        I, Q = round_shift(cx, G), round_shift(cy, G)
        I_am = _ashr(I * env, 15)
        Q_am = _ashr(Q * env, 15)
        if mode == MODE_AM:
            tx_i, tx_q = I_am, Q_am
        else:
            tx_i, tx_q = I, Q
        s = m if mode == MODE_BYP else tx_i
        # --- channel: additive white Gaussian noise on both quadratures ----------
        rx_i = (m if mode == MODE_BYP else tx_i) + ni
        rx_q = tx_q + nq
        r = sat(_ashr(rx_i, 1), 16)                      # DAC-A / scope tap: half scale, 6 dB of headroom for the noise
        # --- job 3: receiver (vectoring) ------------------------------------------
        mx, my, th = cordic(rx_i << G, rx_q << G, 0, True)
        mag = round_shift(mx, G)
        if mode == MODE_FM:
            raw = to_signed((th - self.theta_hat_prev) - (consts['fcw_c'] >> (32 - Z)), Z)
        elif mode == MODE_PM:
            raw = to_signed(th - (self.phi_c >> (32 - Z)), Z)
        elif mode == MODE_AM:
            raw = mag - AM_OFFSET
        else:
            raw = 0
        self.theta_hat_prev = th
        # 20-bit result (16x full scale of headroom): wide-band noise must not be
        # clipped BEFORE the audio filter, or the clipping products fold into the audio band
        if mode == MODE_BYP:
            m_hat_raw = rx_i
        else:
            m_hat_raw = sat(_ashr(raw * consts['g'], DEMOD_SHIFT), RAW_BITS)
        # --- audio filters: identical filter on the reference and on the receiver -
        m_ref = sat(self.lpf_ref.step(m), 16)
        m_hat = sat(self.lpf_rx.step(m_hat_raw), 16)
        return dict(tone=tone, m=m, s=s, I=I, Q=Q, env=env, theta=theta, ni=ni, nq=nq, r=r,
                    theta_hat=th, mag=mag, raw=raw, m_hat_raw=m_hat_raw,
                    m_ref=m_ref, m_hat=m_hat, err=m_ref - m_hat)

# ----------------------------------------------------------------------------
# self-check when run directly
# ----------------------------------------------------------------------------
if __name__ == "__main__":
    print(f"K = {K_GAIN:.10f}   X0 = {X0}   AM_OFFSET = {AM_OFFSET}")
    print("ATAN table (Z=%d):" % Z, ATAN)
    worst = 0.0
    for k in range(0, 1 << 16, 7):
        ph = k << 16
        c, s = cordic_sincos_q15(ph)
        ang = 2 * math.pi * ph / 2**32
        worst = max(worst, abs(c - 32767 * math.cos(ang)), abs(s - 32767 * math.sin(ang)))
    print(f"rotation: worst |err| vs 32767*cos/sin over 9363 angles = {worst:.3f} LSB(Q15)")
    import random
    random.seed(1)
    worst_a = 0.0; worst_m = 0.0
    for _ in range(5000):
        a = random.uniform(-math.pi, math.pi); mag = random.uniform(1000, 32767)
        xi = int(round(mag * math.cos(a))); yi = int(round(mag * math.sin(a)))
        mx, my, th = cordic(xi << G, yi << G, 0, True)
        th_rad = to_signed(th, Z) * 2 * math.pi / 2**Z
        d = (th_rad - math.atan2(yi, xi) + math.pi) % (2 * math.pi) - math.pi
        worst_a = max(worst_a, abs(d))
        worst_m = max(worst_m, abs(round_shift(mx, G) / K_GAIN - math.hypot(xi, yi)))
    print(f"vectoring: worst angle err = {worst_a*1e6:.2f} urad, worst magnitude err = {worst_m:.3f} LSB")
