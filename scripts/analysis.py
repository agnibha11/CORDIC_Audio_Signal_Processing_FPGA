#!/usr/bin/env python3
"""
Performance analysis of the CORDIC radio link, computed with the bit-accurate
model (cordic_model.py).  tb_fm_dsp_core proves the RTL equal to this model
bit for bit, so these figures are what the hardware computes.
Figures written to docs/img/:

  snr_vs_cnr.png                   output SNR vs channel C/N for FM / PM / AM / base band + theory
  snr_vs_beta.png                  FM: output SNR vs modulation index at a fixed C/N (6 dB per octave)
  link_waveforms.png               original, noisy channel signal, recovered audio, error
  fm_threshold.png                 FM receiver output above and below the threshold (clicks)
  channel_blocks.png               noise histogram vs Gaussian, audio filter response
  cordic_error_vs_iterations.png   rotation / vectoring accuracy vs N
  fm_spectrum_beta.png             FM spectra for several modulation indices + Carson bandwidth
  aliasing.png                     what happens when Carson's bandwidth exceeds Nyquist
  modes_waveforms.png              FM / PM / AM / bypass transmitter outputs for the same input
"""
import os, math, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import cordic_model as cm

HERE = os.path.dirname(os.path.abspath(__file__))
IMG  = os.path.normpath(os.path.join(HERE, "..", "docs", "img"))
os.makedirs(IMG, exist_ok=True)
FS = cm.FS

plt.rcParams.update({"figure.dpi": 120, "font.size": 9, "axes.grid": True, "grid.alpha": 0.3})

# ----------------------------------------------------------------------------
def run_chain(n, fc_idx, beta_q, fm_idx, mode, amp=16, source=1, mic=None, noise=0):
    """Run the bit-exact chain for n samples. source=1 uses the internal tone.
    Returned "m" is the reference (audio-filtered) modulating signal."""
    consts = cm.derive_constants(fc_idx, beta_q, fm_idx, mode)
    core = cm.FMCore()
    params = dict(mode=mode, source=source, amp=amp, noise=noise)
    out = {k: np.zeros(n) for k in ("m_ref", "s", "r", "m_hat", "m_hat_raw", "err", "tone", "ni")}
    for i in range(n):
        x = 0 if mic is None else int(mic[i])
        r = core.step(x, params, consts)
        for k in out:
            out[k][i] = r[k]
    out["m"] = out["m_ref"]
    return out, consts

# ----------------------------------------------------------------------------
# Small-noise ("above threshold") theory of the link.
#   C/N = A^2 / (2 sigma^2): carrier power over the noise power of one quadrature.
#   Phase noise of the received carrier: variance 1 / (2 C/N) per sample, white.
#   The audio filter H(f) decides how much of the detector noise reaches the output:
#     Bn = integral |H|^2 df            (flat detector noise: PM, AM, base band)
#     F2 = integral f_d^2 |H|^2 df      (FM: the discriminator differentiates, noise ~ f^2;
#                                        f_d = (Fs/pi) sin(pi f / Fs) is the exact
#                                        response of the first difference)
# ----------------------------------------------------------------------------
_f  = np.arange(0.5, FS / 2, 1.0)
_H2 = np.array([cm.lpf_response(x) for x in _f]) ** 2
BN  = float(np.sum(_H2))
F2  = float(np.sum((FS / math.pi * np.sin(math.pi * _f / FS)) ** 2 * _H2))

def theory_gain_db(mode, beta_q, fm_idx, amp=16):
    """Output SNR minus C/N in dB, for a sinusoidal modulating tone."""
    fm = fm_idx * 50.0
    sig = 0.5 * (amp / 16.0) ** 2 * cm.lpf_response(fm) ** 2        # tone power after the audio filter
    if mode == cm.MODE_FM:
        df = beta_q / 8.0 * fm
        noise = F2 / (FS * df * df)
    elif mode == cm.MODE_PM:
        kp = min(beta_q, cm.PM_BETA_MAX) / 8.0
        noise = BN / (FS * kp * kp)
    elif mode == cm.MODE_AM:
        mu = min(beta_q, cm.AM_BETA_MAX) / 8.0
        noise = 4.0 * BN / (FS * mu * mu)
    else:
        noise = BN / FS
    return 10 * math.log10(sig / noise)

def link_snr(mode, beta_q, fm_idx, noise, fc_idx=40, n=16000, skip=400):
    out, _ = run_chain(n, fc_idx, beta_q, fm_idx, mode, noise=noise)
    return snr_db(out["m_ref"][skip:], out["err"][skip:])

def snr_db(sig, err):
    ps = np.sum(sig.astype(float) ** 2); pe = np.sum(err.astype(float) ** 2)
    return 10 * math.log10(ps / pe) if pe > 0 else 150.0

# ----------------------------------------------------------------------------
def fig_cordic_error():
    Ns = list(range(8, 25))
    rot_max, rot_rms, vec_max, vec_rms = [], [], [], []
    rng = np.random.default_rng(1)
    angs = rng.integers(0, 1 << 24, 1500)
    for N in Ns:
        tbl = cm.atan_table(cm.Z, N)
        K = cm.cordic_gain(N)
        X0 = int(round((32767 << cm.G) / K))
        e = []
        for z in angs:
            x, y, _ = cm.cordic(X0, 0, int(z), False, n=N, table=tbl)
            a = 2 * math.pi * z / 2 ** 24
            e.append(cm.round_shift(x, cm.G) - 32767 * math.cos(a))
            e.append(cm.round_shift(y, cm.G) - 32767 * math.sin(a))
        e = np.array(e); rot_max.append(np.abs(e).max()); rot_rms.append(np.sqrt(np.mean(e ** 2)))
        ea = []
        for _ in range(800):
            a = rng.uniform(-math.pi, math.pi); mag = 32767
            xi = int(round(mag * math.cos(a))); yi = int(round(mag * math.sin(a)))
            _, _, th = cm.cordic(xi << cm.G, yi << cm.G, 0, True, n=N, table=tbl)
            d = cm.to_signed(th, cm.Z) * 2 * math.pi / 2 ** 24 - math.atan2(yi, xi)
            d = (d + math.pi) % (2 * math.pi) - math.pi
            ea.append(d * 1e6)
        ea = np.array(ea); vec_max.append(np.abs(ea).max()); vec_rms.append(np.sqrt(np.mean(ea ** 2)))
    fig, ax = plt.subplots(1, 2, figsize=(10, 3.6))
    ax[0].semilogy(Ns, rot_max, "o-", label="max |error|")
    ax[0].semilogy(Ns, rot_rms, "s-", label="RMS error")
    ax[0].axvline(18, color="k", ls="--", lw=0.8); ax[0].text(18.2, max(rot_max) * 0.5, "N = 18 (this design)")
    ax[0].set_xlabel("iterations N"); ax[0].set_ylabel("error [LSB of Q15]"); ax[0].set_title("Rotation mode: cos/sin error (W = 24)")
    ax[0].legend()
    ax[1].semilogy(Ns, vec_max, "o-", label="max |angle error|")
    ax[1].semilogy(Ns, vec_rms, "s-", label="RMS angle error")
    ax[1].axvline(18, color="k", ls="--", lw=0.8)
    ax[1].set_xlabel("iterations N"); ax[1].set_ylabel("angle error [urad]"); ax[1].set_title("Vectoring mode: atan2 error (full-scale input)")
    ax[1].legend()
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "cordic_error_vs_iterations.png")); plt.close(fig)
    i = Ns.index(18)
    return dict(rot_max=rot_max[i], rot_rms=rot_rms[i], vec_max=vec_max[i], vec_rms=vec_rms[i])

# ----------------------------------------------------------------------------
def fig_snr_vs_cnr():
    """The headline result: output SNR against channel C/N."""
    idxs = list(range(31, 0, -2))                  # C/N 0 .. 30 dB
    cnr  = [31 - k for k in idxs]
    cases = [("FM  deviation 6.35 kHz (beta 15.9, maximum)", cm.MODE_FM, 127, 8, "#d62728", "o"),
             ("FM  deviation 2 kHz (beta 5, default)", cm.MODE_FM, 40, 8, "#ff7f0e", "o"),
             ("PM  2 rad", cm.MODE_PM, 40, 8, "#9467bd", "s"),
             ("base band (no modulation)", cm.MODE_BYP, 40, 8, "#555555", "x"),
             ("AM  100 %", cm.MODE_AM, 40, 8, "#1f77b4", "^")]
    fig, ax = plt.subplots(figsize=(8.2, 5.4))
    table = {}
    for name, mode, bq, fm, col, mk in cases:
        bq_eff = min(bq, 127)
        meas = [link_snr(mode, bq_eff, fm, k) for k in idxs]
        g = theory_gain_db(mode, bq_eff, fm)
        ax.plot(cnr, [c + g for c in cnr], "-", color=col, lw=1.0, alpha=0.6)
        ax.plot(cnr, meas, mk, color=col, ms=5, label="%s   (theory: C/N %+.1f dB)" % (name, g))
        table[name] = (g, dict(zip(cnr, meas)))
    ax.set_xlabel("channel carrier-to-noise ratio C/N [dB]   (keys 9 / E)")
    ax.set_ylabel("output SNR after the audio filter [dB]   (VGA read-out)")
    ax.set_title("Markers: bit-exact model of the hardware (16 000 samples each).  Lines: small-noise theory.\n400 Hz tone, f_c = 4 kHz")
    ax.set_xlim(-1, 31); ax.set_ylim(-8, 60); ax.legend(loc="upper left", fontsize=8)
    ax.annotate("FM threshold:\nbelow about 10 dB the noise\nflips the phase (clicks)", xy=(8, 17), xytext=(15.5, 1.5),
                arrowprops=dict(arrowstyle="->", color="#333"), fontsize=8)
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "snr_vs_cnr.png")); plt.close(fig)
    return table

def fig_snr_vs_beta():
    bqs = [4, 8, 16, 24, 40, 64, 96, 127]
    fig, ax = plt.subplots(figsize=(7.4, 4.4))
    res = {}
    for noise, col in ((6, "#d62728"), (16, "#ff7f0e"), (0, "#2ca02c")):
        meas = [link_snr(cm.MODE_FM, bq, 8, noise) for bq in bqs]
        lab = "clean channel (CORDIC floor)" if noise == 0 else "C/N = %d dB" % (31 - noise)
        ax.semilogx(np.array(bqs) / 8, meas, "o", color=col, label=lab)
        if noise:
            ax.semilogx(np.array(bqs) / 8, [31 - noise + theory_gain_db(cm.MODE_FM, bq, 8) for bq in bqs], "-", color=col, lw=1, alpha=0.6)
        res[noise] = dict(zip(bqs, meas))
    ax.set_xlabel("modulation index beta   (deviation = beta x 400 Hz, keys 2 / 5)")
    ax.set_ylabel("output SNR [dB]")
    ax.set_title("FM trades bandwidth for SNR: +6 dB per doubling of beta (lines = theory)")
    ax.legend(fontsize=8)
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "snr_vs_beta.png")); plt.close(fig)
    return res

def fig_link_waveforms():
    n = 900
    out, c = run_chain(n + 400, 40, 40, 8, cm.MODE_FM, noise=16)
    sl = slice(400, 400 + n); t = np.arange(n) / FS * 1e3
    fig, ax = plt.subplots(4, 1, figsize=(10, 7.4), sharex=True)
    ax[0].plot(t, out["m_ref"][sl] / 32768, color="g"); ax[0].set_ylabel("m"); ax[0].set_title("Original: 400 Hz tone after the audio filter (full scale = 1.0)")
    ax[1].plot(t, np.clip(out["r"][sl] / 32768, -1, 1), color="c", lw=0.7); ax[1].set_ylabel("r")
    ax[1].set_title("Channel signal on DAC-A: FM carrier, f_c = 4 kHz, deviation 2 kHz, plus noise at C/N = 15 dB")
    ax[2].plot(t, out["m_ref"][sl] / 32768, color="g", label="original"); ax[2].plot(t, out["m_hat"][sl] / 32768, color="orange", lw=1.0, label="recovered (vectoring CORDIC + audio filter)")
    ax[2].legend(loc="upper right", fontsize=8); ax[2].set_ylabel("m, m_hat")
    ax[3].plot(t, out["err"][sl] / 32768, color="r", lw=0.8); ax[3].set_ylabel("error"); ax[3].set_xlabel("time [ms]")
    ax[3].set_title("m - m_hat   (output SNR = %.1f dB, theory %.1f dB)" % (snr_db(out["m_ref"][400:], out["err"][400:]), 15 + theory_gain_db(cm.MODE_FM, 40, 8)))
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "link_waveforms.png")); plt.close(fig)

def fig_threshold():
    n = 2000
    fig, ax = plt.subplots(3, 1, figsize=(10, 6.2), sharex=True)
    t = np.arange(n) / FS * 1e3
    for a, noise in zip(ax, (16, 23, 27)):
        out, c = run_chain(n + 400, 40, 40, 8, cm.MODE_FM, noise=noise)
        a.plot(t, out["m_ref"][400:] / 32768, color="g", lw=0.8)
        a.plot(t, out["m_hat"][400:] / 32768, color="orange", lw=0.8)
        a.set_ylim(-2.2, 2.2); a.set_ylabel("m, m_hat")
        a.set_title("C/N = %d dB: output SNR %.1f dB" % (31 - noise, snr_db(out["m_ref"][400:], out["err"][400:])))
    ax[-1].set_xlabel("time [ms]")
    fig.suptitle("FM threshold effect: above ~10 dB the noise is a smooth hiss; below it, noise peaks exceed the carrier,\nthe phase slips a full turn and the discriminator emits impulses (heard as clicks)", fontsize=9)
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "fm_threshold.png")); plt.close(fig)

def fig_channel_blocks():
    gen = cm.Awgn()
    x = np.array([gen.step(31)[0] for _ in range(60000)], float) / cm.NOISE_GAIN[31]
    fig, ax = plt.subplots(1, 2, figsize=(10.5, 3.8))
    ax[0].hist(x, bins=121, range=(-5, 5), density=True, color="#9ecae1", label="awgn_gen, 60 000 samples")
    g = np.linspace(-5, 5, 400); ax[0].plot(g, np.exp(-g * g / 2) / math.sqrt(2 * math.pi), "k", lw=1, label="Gaussian, sigma = 1")
    ax[0].set_yscale("log"); ax[0].set_ylim(1e-5, 1); ax[0].set_xlabel("noise sample / sigma"); ax[0].set_ylabel("probability density")
    ax[0].set_title("Channel noise: sum of 12 xorshift32 words"); ax[0].legend(fontsize=8)
    f = np.arange(10.0, FS / 2, 10.0)
    ax[1].plot(f / 1e3, 20 * np.log10(np.maximum([cm.lpf_response(v) for v in f], 1e-6)))
    ax[1].axhline(-3, color="r", ls="--", lw=0.8); ax[1].set_ylim(-90, 3)
    f3 = f[np.argmax(np.array([cm.lpf_response(v) for v in f]) < 10 ** (-3 / 20))]
    ax[1].set_xlabel("frequency [kHz]"); ax[1].set_ylabel("|H| [dB]")
    ax[1].set_title("Audio filter: four cascaded 4-sample averages (-3 dB at %.2f kHz)" % (f3 / 1e3))
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "channel_blocks.png")); plt.close(fig)
    return dict(sigma=float(x.std()), mean=float(x.mean()), f3=float(f3), kurt=float(np.mean(x ** 4) / np.mean(x ** 2) ** 2))

# ----------------------------------------------------------------------------
def spectrum(x, nfft=8192):
    w = np.hanning(len(x))
    X = np.fft.rfft(x * w, nfft)
    f = np.fft.rfftfreq(nfft, 1 / FS)
    mag = 20 * np.log10(np.abs(X) / (np.sum(w) / 2) / 32768 + 1e-12)
    return f, mag

def fig_spectra():
    betas = [2, 8, 24, 48]          # beta_q -> 0.25, 1, 3, 6
    fig, ax = plt.subplots(len(betas), 1, figsize=(10, 8), sharex=True)
    for a, bq in zip(ax, betas):
        out, c = run_chain(8192, 40, bq, 8, cm.MODE_FM)
        f, mag = spectrum(out["s"])
        beta = bq / 8; fm = 400; fc = 4000; dev = beta * fm
        a.plot(f, mag, lw=0.8)
        a.axvline(fc - (dev + fm), color="r", ls="--", lw=0.8); a.axvline(fc + (dev + fm), color="r", ls="--", lw=0.8)
        a.set_xlim(0, 10000); a.set_ylim(-110, 5)
        a.set_title("beta = %.2f  (deviation %.0f Hz) -- Carson bandwidth 2(df+fm) = %.0f Hz (red)" % (beta, dev, 2 * (dev + fm)))
        a.set_ylabel("dBFS")
    ax[-1].set_xlabel("frequency [Hz]")
    fig.suptitle("FM spectra of the bit-exact transmitter output, f_c = 4 kHz, f_m = 400 Hz, Hann window")
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "fm_spectrum_beta.png")); plt.close(fig)

# ----------------------------------------------------------------------------
def fig_aliasing():
    cases = [(60, 16, 20, "f_c = 6 kHz, beta = 2, f_m = 1 kHz: Carson BW 6 kHz, top edge 9 kHz < 25 kHz"),
             (90, 96, 20, "f_c = 9 kHz, beta = 12, f_m = 1 kHz: deviation 12 kHz, top edge 22 kHz (just inside)"),
             (100, 127, 40, "f_c = 10 kHz, beta = 15.9, f_m = 2 kHz: deviation 31.8 kHz -> folds over Nyquist")]
    fig, ax = plt.subplots(len(cases), 1, figsize=(10, 7), sharex=True)
    for a, (fc, bq, fm, title) in zip(ax, cases):
        out, c = run_chain(8192, fc, bq, fm, cm.MODE_FM)
        f, mag = spectrum(out["s"])
        a.plot(f, mag, lw=0.8); a.set_ylim(-100, 5); a.set_xlim(0, FS / 2)
        a.axvline(fc * 100, color="k", ls=":", lw=0.8)
        a.set_title(title + "   (clean-channel SNR %.1f dB)" % snr_db(out["m"][256:], out["err"][256:])); a.set_ylabel("dBFS")
    ax[-1].set_xlabel("frequency [Hz]  (Nyquist = 25 kHz)")
    fig.suptitle("Carson's rule vs the 50 kS/s sample rate (real part of the transmitted signal, as seen on DAC-A)")
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "aliasing.png")); plt.close(fig)

# ----------------------------------------------------------------------------
def fig_modes():
    n = 500
    names = {cm.MODE_FM: "FM (beta = 5 -> deviation 2 kHz)", cm.MODE_PM: "PM (2 rad)", cm.MODE_AM: "AM (100 %)", cm.MODE_BYP: "bypass (base band)"}
    fig, ax = plt.subplots(4, 1, figsize=(10, 8), sharex=True)
    t = np.arange(n) / FS * 1e3
    res = {}
    for a, mode in zip(ax, (cm.MODE_FM, cm.MODE_PM, cm.MODE_AM, cm.MODE_BYP)):
        out, c = run_chain(n + 4096, 40, 40, 8, mode)
        sl = slice(4096, 4096 + n)
        a.plot(t, out["s"][sl] / 32768, color="c", lw=0.8, label="transmitted s[n]")
        a.plot(t, out["m"][sl] / 32768, color="g", lw=1.0, label="original m[n]")
        a.plot(t, out["m_hat"][sl] / 32768, "--", color="orange", lw=1.0, label="recovered m_hat[n]")
        res[mode] = snr_db(out["m"][400:], out["err"][400:])
        a.set_title(names[mode] + "   clean-channel SNR %.1f dB" % res[mode]); a.set_ylabel("FS")
    ax[0].legend(loc="upper right", ncol=3, fontsize=8); ax[-1].set_xlabel("time [ms]")
    fig.suptitle("The four modes for the same 400 Hz tone, f_c = 4 kHz, clean channel")
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "modes_waveforms.png")); plt.close(fig)
    return res

# ----------------------------------------------------------------------------
if __name__ == "__main__":
    print("audio filter: Bn = %.1f Hz, F2^(1/3) = %.1f Hz" % (BN, (3 * F2) ** (1 / 3)))
    print("theory, default tone: FM %+.2f dB, PM %+.2f dB, AM %+.2f dB, base band %+.2f dB above C/N" %
          tuple(theory_gain_db(m, 40, 8) for m in (cm.MODE_FM, cm.MODE_PM, cm.MODE_AM, cm.MODE_BYP)))
    print("channel blocks:", fig_channel_blocks())
    print("CORDIC error at N = 18:", fig_cordic_error())
    print("clean-channel SNR per mode:", {k: round(v, 1) for k, v in fig_modes().items()})
    fig_link_waveforms(); fig_threshold(); fig_spectra(); fig_aliasing()
    tab = fig_snr_vs_cnr()
    for name, (g, d) in tab.items():
        print("%-40s theory C/N %+5.1f dB | " % (name, g) + "  ".join("%d:%.1f" % (c, v) for c, v in sorted(d.items()) if c % 5 == 0))
    res = fig_snr_vs_beta()
    for noise, d in res.items():
        print("FM SNR vs beta_q, noise_idx %d:" % noise, {k: round(v, 1) for k, v in d.items()})
    print("figures written to", IMG)
