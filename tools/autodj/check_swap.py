#!/usr/bin/env python3
"""Measures a rendered bass swap around its handover, beat by beat, so the beat of air can be checked without ears.

    check_swap.py FOLDER_OF_RENDERS
"""
import glob, json, os, sys
import numpy as np
from scipy.io import wavfile


def beats_around(path):
    notes = json.load(open(path[:-4] + ".json"))
    rate, audio = wavfile.read(path)
    mono = audio.astype(np.float64).mean(axis=1) / 32768
    beat = 60 / notes["bpm_a"]
    swap_beat = notes["start_beat"] + notes["swap"] * 4
    out = []
    for offset in range(-8, 5):
        a = int((swap_beat + offset) * beat * rate)
        b = int((swap_beat + offset + 1) * beat * rate)
        level = np.sqrt(np.mean(mono[a:b] ** 2) + 1e-12)
        out.append((offset, 20 * np.log10(level)))
    return notes, out


for path in sorted(glob.glob(sys.argv[1] + "/*bassSwap.wav")):
    notes, rows = beats_around(path)
    print(os.path.basename(path)[:50], "exit", notes["exit"], "entry", notes["entry"], "swap", notes["swap"], "harmony", notes["harmony"])
    print("   " + " ".join(f"{o:+d}:{v:5.1f}" for o, v in rows))
    air = dict(rows)[-1]
    before = np.median([v for o, v in rows if -8 <= o < -4])
    after = np.median([v for o, v in rows if 0 <= o < 4])
    print(f"   air {air:.1f} dB: {before - air:.1f} below the bars before it, {after - air:.1f} below the landing, landing {after - before:+.1f} dB against before")
