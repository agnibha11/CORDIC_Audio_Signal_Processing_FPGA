#!/usr/bin/env python3
"""
Performance analysis of the CORDIC FM audio processor, computed with the
bit-accurate model (cordic_model.py) -- i.e. exactly what the hardware does.
Produces the figures referenced by the README into docs/img/:

  cordic_error_vs_iterations.png   rotation / vectoring accuracy vs N
  fm_waveforms.png                 tone, FM output, demodulated, error
  fm_spectrum_beta.png             FM spectra for several modulation indices + Carson bandwidth
  demod_snr_vs_beta.png            loop-back SNR vs beta for FM / PM / AM
  aliasing.png                     what happens when Carson's bandwidth exceeds Nyquist
  modes_waveforms.png              FM / PM / AM / bypass outputs for the same input
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
def run_chain(n, fc_idx, beta_q, fm_idx, mode, amp=16, source=1, mic=None):
    """Run the bit-exact chain for n samples. source=1 uses the internal tone."""
    consts = cm.derive_constants(fc_idx, beta_q, fm_idx, mode)
    core = cm.FMCore()
    params = dict(mode=mode, source=source, amp=amp)
    out = {k: np.zeros(n) for k in ("m", "s", "m_hat", "err", "tone")}
    for i in range(n):
        x = 0 if mic is None else int(mic[i])
        r = core.step(x, params, consts)
        for k in out:
            out[k][i] = r[k]
    return out, consts

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
def fig_waveforms():
    n = 1024
    out, c = run_chain(n, 20, 16, 4, cm.MODE_FM)       # fc 2 kHz, beta 2, fm 200 Hz
    t = np.arange(n) / FS * 1e3
    fig, ax = plt.subplots(4, 1, figsize=(10, 7), sharex=True)
    ax[0].plot(t, out["m"] / 32768, color="g"); ax[0].set_ylabel("m[n]"); ax[0].set_title("Internal 200 Hz tone (modulating signal), FS = 1.0")
    ax[1].plot(t, out["s"] / 32768, color="c"); ax[1].set_ylabel("s[n]"); ax[1].set_title("FM output, f_c = 2000 Hz, beta = 2 (peak deviation 400 Hz)")
    ax[2].plot(t, out["m"] / 32768, color="g", label="original"); ax[2].plot(t, out["m_hat"] / 32768, "--", color="orange", label="demodulated (vectoring CORDIC)")
    ax[2].legend(loc="upper right"); ax[2].set_ylabel("m, m_hat")
    ax[3].plot(t, out["err"], color="r"); ax[3].set_ylabel("error [LSB]"); ax[3].set_xlabel("time [ms]")
    ax[3].set_title("m - m_hat   (loop-back SNR = %.1f dB)" % snr_db(out["m"], out["err"]))
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "fm_waveforms.png")); plt.close(fig)
    return snr_db(out["m"], out["err"])

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
        out, c = run_chain(8192, 20, bq, 4, cm.MODE_FM)
        f, mag = spectrum(out["s"])
        beta = bq / 8; fm = 200; fc = 2000; dev = beta * fm
        a.plot(f, mag, lw=0.8)
        a.axvline(fc - (dev + fm), color="r", ls="--", lw=0.8); a.axvline(fc + (dev + fm), color="r", ls="--", lw=0.8)
        a.set_xlim(0, 6000); a.set_ylim(-110, 5)
        a.set_title("beta = %.2f  (deviation %.0f Hz) -- Carson bandwidth 2(df+fm) = %.0f Hz (red)" % (beta, dev, 2 * (dev + fm)))
        a.set_ylabel("dBFS")
    ax[-1].set_xlabel("frequency [Hz]")
    fig.suptitle("FM spectra of the bit-exact modulator output, f_c = 2 kHz, f_m = 200 Hz, Hann window")
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "fm_spectrum_beta.png")); plt.close(fig)

# ----------------------------------------------------------------------------
def fig_snr_vs_beta():
    bqs = [1, 2, 4, 8, 12, 16, 24, 32, 48, 64, 96, 127]
    res = {}
    for mode, name in ((cm.MODE_FM, "FM"), (cm.MODE_PM, "PM"), (cm.MODE_AM, "AM")):
        vals = []
        for bq in bqs:
            if mode == cm.MODE_AM and bq > 8:           # AM depth > 1 is over-modulation (envelope folds)
                vals.append(np.nan); continue
            if mode == cm.MODE_PM and bq > 25:          # PM beyond pi rad cannot be unwrapped
                vals.append(np.nan); continue
            out, c = run_chain(4096, 20, bq, 4, mode)
            vals.append(snr_db(out["m"][256:], out["err"][256:]))
        res[name] = vals
    fig, ax = plt.subplots(figsize=(7, 4))
    b = np.array(bqs) / 8
    for name, vals in res.items():
        ax.semilogx(b, vals, "o-", label=name)
    ax.set_xlabel("modulation index beta (FM: df = beta*fm, PM: rad, AM: depth)")
    ax.set_ylabel("loop-back SNR [dB]")
    ax.set_title("Demodulated-vs-original SNR, 200 Hz tone, f_c = 2 kHz (4096 samples)")
    ax.legend()
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "demod_snr_vs_beta.png")); plt.close(fig)
    return dict(zip(bqs, res["FM"])), dict(zip(bqs, res["PM"])), dict(zip(bqs, res["AM"]))

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
        a.set_title(title + "   (loop-back SNR %.1f dB)" % snr_db(out["m"][256:], out["err"][256:])); a.set_ylabel("dBFS")
    ax[-1].set_xlabel("frequency [Hz]  (Nyquist = 25 kHz)")
    fig.suptitle("Carson's rule vs the 50 kS/s sample rate")
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "aliasing.png")); plt.close(fig)

# ----------------------------------------------------------------------------
def fig_modes():
    n = 600
    names = {cm.MODE_FM: "FM (beta = 4 -> df = 800 Hz)", cm.MODE_PM: "PM (beta = 2 rad)", cm.MODE_AM: "AM (depth 1.0)", cm.MODE_BYP: "bypass"}
    fig, ax = plt.subplots(4, 1, figsize=(10, 8), sharex=True)
    t = np.arange(n) / FS * 1e3
    for a, mode in zip(ax, (cm.MODE_FM, cm.MODE_PM, cm.MODE_AM, cm.MODE_BYP)):
        bq = 8 if mode == cm.MODE_AM else 16 if mode == cm.MODE_PM else 32
        out, c = run_chain(n, 20, bq, 4, mode)
        a.plot(t, out["m"] / 32768, color="g", lw=0.8, label="m[n]")
        a.plot(t, out["s"] / 32768, color="c", lw=0.8, label="s[n]")
        a.plot(t, out["m_hat"] / 32768, "--", color="orange", lw=0.8, label="m_hat[n]")
        a.set_title(names[mode] + "   SNR %.1f dB" % snr_db(out["m"][64:], out["err"][64:])); a.set_ylabel("FS")
    ax[0].legend(loc="upper right", ncol=3); ax[-1].set_xlabel("time [ms]")
    fig.suptitle("The four modes for the same 200 Hz tone, f_c = 2 kHz")
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "modes_waveforms.png")); plt.close(fig)

# ----------------------------------------------------------------------------
if __name__ == "__main__":
    print("CORDIC error at N = 18:", fig_cordic_error())
    print("waveforms: loop-back SNR = %.1f dB" % fig_waveforms())
    fig_spectra()
    fm, pm, am = fig_snr_vs_beta()
    print("FM SNR vs beta_q:", {k: round(v, 1) for k, v in fm.items()})
    print("PM SNR vs beta_q:", {k: round(v, 1) for k, v in pm.items() if not np.isnan(v)})
    print("AM SNR vs beta_q:", {k: round(v, 1) for k, v in am.items() if not np.isnan(v)})
    fig_aliasing()
    fig_modes()
    print("figures written to", IMG)
