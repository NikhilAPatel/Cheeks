"""Port of the streaming TrackAnalyzer.analyze(pcm) on Int16 input, run on the Swift test synth."""
import numpy as np
from scipy.signal import lfilter
from analysis_port import biquad, MAJOR, MINOR, CAM_MAJ, CAM_MIN, SR
from swift_synth_check import track, AM, DM, FM

def to_int16(x):  # Int16(max(-1,min(1,x))*32767), truncation toward zero
    return np.trunc(np.clip(x, -1, 1) * 32767).astype(np.int16)

def cascade(kind, f, x):
    b, a = biquad(kind, f, SR)
    return lfilter(b, a, lfilter(b, a, x))

def analyze(x):
    q = to_int16(x)
    m = (q.astype(np.float32) / 32767 + q.astype(np.float32) / 32767) * 0.5  # left == right
    n = len(m); hop = 512; hops = n // hop
    lowband = cascade("lp", 150, m[: hops * hop])
    ef = (m[: hops * hop].reshape(hops, hop) ** 2).sum(1)
    el = (lowband.reshape(hops, hop) ** 2).sum(1)
    # tempo (same as Swift detectTempo(energyFull:energyLow:))
    fps = SR / hop
    lf = np.log(1 + 100 * ef); ll = np.log(1 + 100 * el)
    onset = np.maximum(0, lf - np.concatenate([[0], lf[:-1]])) + 1.5 * np.maximum(0, ll - np.concatenate([[0], ll[:-1]]))
    onset = np.maximum(0, onset - onset.mean())
    min_lag = int(fps * 60 / 175); max_lag = int(fps * 60 / 85) + 1
    best_lag = max(range(min_lag, max_lag + 1), key=lambda L: (onset[: hops - L] * onset[L:]).sum() / (hops - L))
    coarse = 60 * fps / best_lag
    best = (-1, coarse, 0.0); cand = coarse - 2
    while cand <= coarse + 2:
        period = 60 * fps / cand
        for p in range(max(1, int(period))):
            s = onset[np.round(np.arange(p, hops - 1, period)).astype(int)].sum()
            if s > best[0]: best = (s, cand, float(p))
        cand += 0.02
    bpm = round(best[1] * 100) / 100
    if abs(bpm - round(bpm)) < 0.08: bpm = float(round(bpm))
    first = best[2] / fps
    while first >= 60 / bpm: first -= 60 / bpm
    # key
    kc = n // 4
    b, a = biquad("lp", 2500, SR)
    sig = lfilter(b, a, m[: kc * 4])[::4]
    N = 1 << 13; win = np.hanning(N + 1)[:N]; rate = SR / 4
    k = np.arange(N // 2); freq = k * rate / N
    ok = (freq >= 55) & (freq <= 2000) & (k >= 1)
    pc = np.full(N // 2, -1)
    pc[ok] = np.round(69 + 12 * np.log2(freq[ok] / 440)).astype(int) % 12
    chroma = np.zeros(12); st = 0
    while st + N <= kc:
        mags = np.abs(np.fft.rfft(sig[st:st + N] * win))[: N // 2]
        for c in range(12): chroma[c] += mags[pc == c].sum()
        st += N
    sc = max(((np.corrcoef(chroma, [ (MINOR if mi else MAJOR)[(i - t) % 12] for i in range(12)])[0, 1], t, mi)
              for t in range(12) for mi in (False, True)))
    key = f"{(CAM_MIN if sc[2] else CAM_MAJ)[sc[1]]}{'A' if sc[2] else 'B'}"
    return bpm, first, key

for bpm, fb in [(128, .37), (174, .10), (92, .52), (140, 0)]:
    b, f, _ = analyze(track(bpm, fb, 40, AM)); beat = 60 / bpm
    err = ((f - fb + beat / 2) % beat) - beat / 2
    print(f"{bpm}: got {b} err {err*1000:+.1f} ms", "OK" if abs(b - bpm) <= .05 and abs(err) < .012 else "FAIL")
for chords, want in [(AM, "8A"), (DM, "10B"), (FM, "4A")]:
    k = analyze(track(124, 0, 30, chords))[2]; print("key", k, "OK" if k == want else f"FAIL want {want}")

# stems sum with headroom, from Int16 source
x = track(126, .2, 10, AM); q = to_int16(x).astype(np.float32) / 32767
bl = cascade("lp", 140, q); hl = cascade("hp", 6000, q)
mid = ((q - bl - hl) * 2) * 0.5
b1, a1 = biquad("hp", 250, SR); b2, a2 = biquad("lp", 5000, SR)
v = lfilter(b2, a2, lfilter(b2, a2, lfilter(b1, a1, lfilter(b1, a1, mid))))
mel = q - bl - hl - v
stems = [to_int16(s * 0.5).astype(np.float32) for s in (v, mel, bl, hl)]
total = sum(stems) / 32767 / 0.5
err = np.abs(total - q)[::101].max()
print("stems max |sum-orig| =", err, "OK" if err < 0.0005 else "FAIL", "| peak stem", max(np.abs(s).max() for s in (v, mel, bl, hl)))
