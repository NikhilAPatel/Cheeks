#!/usr/bin/env python3
"""Checks the app's TrackMapper against the lab's analyze.py and the kicks themselves, on the lab's tracks."""
import json, os
import numpy as np
from scipy import signal

C = os.path.expanduser("~/Library/Caches/cheeks-autodj")
SR = 44100
sos = signal.butter(4, 150 / (SR / 2), "low", output="sos")
print("track        bpm lab/app      steady  bars  1 agrees lattice  on%: vocal/melody/bass/drums kick   kick attack vs app grid  secs")
rows = []
for line in open(f"{C}/app_map.jsonl"):
    a = json.loads(line)
    n = a["name"]
    z = np.load(f"{C}/tracks/{n}/map.npz")
    lab_beat = 60 / float(z["bpm"])
    lab_first = float(z["beat_times"][0] + z["bar_beats"][0] * lab_beat)
    same_tempo = abs(a["bpm"] / float(z["bpm"]) - 1) < 0.002
    bar = 4 * lab_beat
    # Is the app's bar line one of the lab's? A beat off shows up as a quarter of a bar.
    off = ((a["first_bar"] - lab_first + bar / 2) % bar) - bar / 2
    downbeat_ok = same_tempo and abs(off) < 0.06
    lab_on = z["on"]
    bars = min(a["bars"], lab_on.shape[1])
    shift = int(round((a["first_bar"] - lab_first) / bar))
    def agree(x, y):
        x = np.array(x[max(0, -shift):]); y = np.array(y[max(0, shift):])
        k = min(len(x), len(y))
        return float(np.mean(x[:k] == y[:k])) if k else 0
    ons = [agree(a["on"][s], lab_on[s].astype(int).tolist()) for s in (1, 2, 3)]
    voc = agree([int(v > .5) for v in a["vocal"]], [int(v > .5) for v in z["vocal_cover"]])
    kick = agree(a["kick"], z["has_kick"].astype(int).tolist())
    lat_ok = same_tempo and (a["lattice"] + shift - int(z["lattice"])) % 8 == 0
    s = np.load(f"{C}/tracks/{n}/stems.npy", mmap_mode="r")[3]
    x = signal.sosfilt(sos, (s[:, 0].astype(np.float32) + s[:, 1]) / 32768)
    env = np.abs(x)
    beat = 60 / a["bpm"]
    r = int(0.2 * beat * SR)
    offs = []
    t = a["first"]
    while int(t * SR) + r < len(env):
        c = int(t * SR)
        if c - r >= 0:
            w = env[c - r:c + r]
            if w.max() > 0.03:
                offs.append((np.argmax(w >= w.max() / 2) + c - r - c) / SR * 1000)
        t += beat
    attack = float(np.median(offs)) if offs else float("nan")
    rows.append((a["steady"], same_tempo, downbeat_ok, lat_ok, attack, ons, voc, kick))
    print(f"{n:12s} {float(z['bpm']):7.2f}/{a['bpm']:7.2f} {str(a['steady']):6s} {a['bars']:4d}  {'yes' if downbeat_ok else 'NO ':3s}   {'yes' if lat_ok else 'no ':3s}    {voc:.2f} {ons[0]:.2f} {ons[1]:.2f} {ons[2]:.2f}  {kick:.2f}   {attack:6.1f} ms   {a['seconds']:.1f}")
steady = [r for r in rows if r[0]]
print(f"steady {len(steady)} of {len(rows)}; on those: same tempo {sum(r[1] for r in steady)}, same 1 {sum(r[2] for r in steady)}, same 8-bar lines {sum(r[3] for r in steady)}, attack median {np.median([r[4] for r in steady]):.1f} ms, spread {np.std([r[4] for r in steady]):.1f} ms")
