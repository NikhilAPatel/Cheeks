"""numpy port of the original (array-based) tempo and key detection, plus shared helpers.

The Swift code now streams over Int16 audio (see streaming_check.py); the math is identical."""
import numpy as np
from scipy.signal import lfilter

SR = 44100.0

def biquad(kind, f, sr, q=0.7071):
    w = 2 * np.pi * f / sr
    alpha = np.sin(w) / (2 * q); c = np.cos(w)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    else:
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    a = [1 + alpha, -2 * c, 1 - alpha]
    return np.array(b) / a[0], np.array(a) / a[0]

def cascade(kind, f, sr, x):
    b, a = biquad(kind, f, sr)
    return lfilter(b, a, lfilter(b, a, x)).astype(np.float32)

def detect_tempo(mono, sr):
    hop = 512
    fps = sr / hop
    low = cascade("lp", 150, sr, mono)
    frames = len(mono) // hop
    e_full = (mono[: frames * hop].reshape(frames, hop) ** 2).sum(1)
    e_low = (low[: frames * hop].reshape(frames, hop) ** 2).sum(1)
    lf = np.log(1 + 100 * e_full); ll = np.log(1 + 100 * e_low)
    prev_f = np.concatenate([[0], lf[:-1]]); prev_l = np.concatenate([[0], ll[:-1]])
    onset = np.maximum(0, lf - prev_f) + 1.5 * np.maximum(0, ll - prev_l)
    onset = np.maximum(0, onset - onset.mean())

    min_lag = int(fps * 60 / 175); max_lag = int(fps * 60 / 85) + 1
    best_lag, best_score = min_lag, -1
    for lag in range(min_lag, max_lag + 1):
        s = (onset[: frames - lag] * onset[lag:]).sum() / (frames - lag)
        if s > best_score:
            best_score, best_lag = s, lag
    coarse = 60 * fps / best_lag

    best = (-1, coarse, 0.0)
    cand = coarse - 2
    while cand <= coarse + 2:
        period = 60 * fps / cand
        for p in range(max(1, int(period))):
            pos = np.arange(p, frames - 1, period)
            s = onset[np.round(pos).astype(int)].sum()
            if s > best[0]:
                best = (s, cand, float(p))
        cand += 0.02
    bpm = round(best[1] * 100) / 100
    if abs(bpm - round(bpm)) < 0.08:
        bpm = float(round(bpm))
    beat = 60 / bpm
    first = best[2] / fps
    while first >= beat:
        first -= beat
    return bpm, first, coarse

MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
CAM_MAJ = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
CAM_MIN = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]

def detect_key(mono, sr):
    factor = 4
    rate = sr / factor
    count = len(mono) // factor
    b, a = biquad("lp", 2500, sr)
    sig = lfilter(b, a, mono[: count * factor])[::factor]
    n = 1 << 13
    win = np.hanning(n + 1)[:n]  # vDSP_HANN_NORM is the periodic-style window
    k = np.arange(n // 2)
    freq = k * rate / n
    pc = np.full(n // 2, -1)
    ok = (freq >= 55) & (freq <= 2000) & (k >= 1)
    midi = 69 + 12 * np.log2(np.where(ok, freq, 440) / 440)
    pc[ok] = (np.round(midi[ok]).astype(int) % 12 + 12) % 12
    chroma = np.zeros(12)
    start = 0
    while start + n <= count:
        mags = np.abs(np.fft.rfft(sig[start:start + n] * win))[: n // 2]
        for c in range(12):
            chroma[c] += mags[pc == c].sum()
        start += n
    best = (-np.inf, 0, False)
    for tonic in range(12):
        for minor in (False, True):
            prof = MINOR if minor else MAJOR
            rot = np.array([prof[(i - tonic) % 12] for i in range(12)])
            s = np.corrcoef(chroma, rot)[0, 1]
            if s > best[0]:
                best = (s, tonic, minor)
    _, t, m = best
    return f"{(CAM_MIN if m else CAM_MAJ)[t]}{'A' if m else 'B'}"

# ---------- synthetic tracks ----------
rng = np.random.default_rng(1)

def note_freq(midi):
    return 440 * 2 ** ((midi - 69) / 12)

def make_track(bpm, first_beat, seconds, chords, swing_hats=True):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    beat = 60 / bpm
    kick_len = int(0.15 * SR)
    kt = np.arange(kick_len) / SR
    kick = np.sin(2 * np.pi * (50 + 80 * np.exp(-kt * 30)) * kt) * np.exp(-kt * 18)
    hat = rng.standard_normal(int(0.04 * SR)) * np.exp(-np.arange(int(0.04 * SR)) / SR * 90)
    hat = lfilter(*biquad("hp", 7000, SR), hat)
    i = 0
    while first_beat + i * beat < seconds - 0.2:
        s = int((first_beat + i * beat) * SR)
        out[s:s + kick_len] += 0.9 * kick[: len(out[s:s + kick_len])]
        if swing_hats:
            h = int((first_beat + (i + 0.5) * beat) * SR)
            out[h:h + len(hat)] += 0.3 * hat[: len(out[h:h + len(hat)])]
        i += 1
    # chords, one per bar
    bar = 4 * beat
    for j in range(int(seconds / bar) + 1):
        chord = chords[j % len(chords)]
        s, e = int(j * bar * SR), min(n, int((j + 1) * bar * SR))
        tt = t[s:e]
        for m in chord:
            out[s:e] += 0.08 * np.sin(2 * np.pi * note_freq(m) * tt)
        out[s:e] += 0.15 * np.sin(2 * np.pi * note_freq(chord[0] - 24) * tt)  # bass
    return (out / np.abs(out).max() * 0.9).astype(np.float32)

A_MINOR = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]   # Am F C G
D_MAJOR = [[62, 66, 69], [55, 59, 62], [57, 61, 64], [62, 66, 69]]   # D G A D
F_MINOR = [[53, 56, 60], [49, 53, 56], [51, 55, 58], [53, 56, 60]]   # Fm Db Eb Fm

if __name__ == "__main__":
    cases = [
        (128, 0.37, A_MINOR, "8A"),
        (174, 0.10, D_MAJOR, "10B"),
        (92, 0.52, F_MINOR, "4A"),
        (123.5, 0.21, A_MINOR, "8A"),
        (140, 0.0, F_MINOR, "4A"),
    ]
    for bpm, fb, chords, want_key in cases:
        x = make_track(bpm, fb, 45, chords)
        got_bpm, got_fb, coarse = detect_tempo(x, SR)
        beat = 60 / bpm
        phase_err = ((got_fb - fb + beat / 2) % beat) - beat / 2
        key = detect_key(x, SR)
        print(f"true {bpm:6.2f} bpm fb {fb:.3f} key {want_key:>3} | got {got_bpm:6.2f} (coarse {coarse:6.2f}) "
              f"fb {got_fb:.3f} phase err {phase_err*1000:+6.1f} ms | key {key}")
