"""Port of CheeksTests/Synth.swift (synthetic test tracks) plus checks with the original array-based analysis."""
import numpy as np
from analysis_port import detect_tempo, detect_key, SR

def lcg_noise(count, seed):
    out = np.empty(count, dtype=np.float32)
    for k in range(count):
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
        v = seed - (1 << 32) if seed >= (1 << 31) else seed
        out[k] = v / 2147483647
    return out, seed

def freq(m): return 440 * 2 ** ((m - 69) / 12)

def track(bpm, fb, seconds, chords):
    n = int(seconds * SR); x = np.zeros(n); beat = 60 / bpm; seed = 12345; i = 0
    kl = int(0.15 * SR); kt = np.arange(kl) / SR
    kick = 0.9 * np.sin(2 * np.pi * (50 + 80 * np.exp(-kt * 30)) * kt) * np.exp(-kt * 18)
    hl = int(0.04 * SR); env = np.exp(-np.arange(hl) / SR * 90)
    while fb + i * beat < seconds - 0.2:
        s = int((fb + i * beat) * SR); seg = x[s:s + kl]; seg += kick[:len(seg)]
        h = int((fb + (i + 0.5) * beat) * SR)
        cnt = max(0, min(hl, n - h))
        noise, seed = lcg_noise(cnt, seed)
        x[h:h + cnt] += 0.15 * noise * env[:cnt]
        i += 1
    bar = 4 * beat; j = 0; t = np.arange(n) / SR
    while j * bar < seconds:
        c = chords[j % len(chords)]; s, e = int(j * bar * SR), min(n, int((j + 1) * bar * SR))
        v = 0.15 * np.sin(2 * np.pi * freq(c[0] - 24) * t[s:e])
        for m in c: v += 0.08 * np.sin(2 * np.pi * freq(m) * t[s:e])
        x[s:e] += v; j += 1
    return (x / np.abs(x).max() * 0.9).astype(np.float32)

AM = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
DM = [[62, 66, 69], [55, 59, 62], [57, 61, 64], [62, 66, 69]]
FM = [[53, 56, 60], [49, 53, 56], [51, 55, 58], [53, 56, 60]]
if __name__ == "__main__":
    for bpm, fb in [(128, .37), (174, .10), (92, .52), (140, 0)]:
        b, f, _ = detect_tempo(track(bpm, fb, 40, AM), SR); beat = 60 / bpm
        err = ((f - fb + beat / 2) % beat) - beat / 2
        print(f"{bpm}: got {b} err {err*1000:+.1f} ms", "OK" if abs(b - bpm) <= .05 and abs(err) < .012 else "FAIL")
    for chords, want in [(AM, "8A"), (DM, "10B"), (FM, "4A")]:
        k = detect_key(track(124, 0, 30, chords), SR); print("key", k, "OK" if k == want else f"FAIL want {want}")
