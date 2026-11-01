#!/usr/bin/env python3
"""Shows a render without listening to it: level per bar in three bands, and a spectrogram picture.

    inspect_render.py file.wav [bpm]
"""
import json, os, struct, sys, zlib
import numpy as np
import soundfile as sf
from scipy import signal


def png(path, image):
    """image is (h, w, 3) uint8."""
    h, w, _ = image.shape
    raw = b"".join(b"\0" + image[y].tobytes() for y in range(h))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def main():
    path = sys.argv[1]
    meta = json.load(open(path[:-4] + ".json")) if os.path.exists(path[:-4] + ".json") else {}
    bpm = float(sys.argv[2]) if len(sys.argv) > 2 else meta.get("a_bpm", 125)
    audio, sr = sf.read(path, dtype="float32")
    mono = audio.mean(axis=1)
    bar = int(60 / bpm * 4 * sr)
    bands = []
    for lo, hi in ((20, 150), (150, 2500), (2500, 16000)):
        sos = signal.butter(4, [lo / (sr / 2), hi / (sr / 2)], "band", output="sos")
        bands.append(signal.sosfilt(sos, mono))
    print(f"{meta.get('title', path)}: {len(mono) / sr:.1f} s, peak {20 * np.log10(np.abs(audio).max() + 1e-9):.1f} dB, A bar {meta.get('a_exit')} B bar {meta.get('b_entry')}")
    notes = meta.get("notes", [])
    print("bar  low  mid high  total")
    for i in range(len(mono) // bar):
        chunk = [20 * np.log10(np.sqrt(np.mean(b[i * bar:(i + 1) * bar] ** 2)) + 1e-6) for b in bands]
        total = 20 * np.log10(np.sqrt(np.mean(mono[i * bar:(i + 1) * bar] ** 2)) + 1e-6)
        here = [t for s, t in notes if i * bar <= s * sr < (i + 1) * bar]
        print(f"{i:3d} {chunk[0]:4.0f} {chunk[1]:4.0f} {chunk[2]:4.0f}  {total:5.1f}  {'#' * int(max(0, total + 40) / 2):20s} {'; '.join(here)}")
    f, t, z = signal.stft(mono, sr, nperseg=4096, noverlap=4096 - 1024)
    mag = 20 * np.log10(np.abs(z) + 1e-6)
    # Log-frequency rows, 240 of them.
    rows = np.geomspace(30, 16000, 240)
    idx = np.searchsorted(f, rows).clip(0, len(f) - 1)
    img = mag[idx][::-1]
    cols = min(1400, img.shape[1])
    step = img.shape[1] / cols
    img = img[:, (np.arange(cols) * step).astype(int)]
    v = np.clip((img + 80) / 70, 0, 1)
    rgb = np.stack([v ** 0.6, v ** 1.4, v ** 3 * 0.8 + 0.1], axis=2)
    out = (rgb * 255).astype(np.uint8)
    per_col = (len(mono) / sr) / cols
    for s, text in notes:
        out[:, min(cols - 1, int(s / per_col))] = (255, 255, 255)
    for i in range(len(mono) // bar):
        out[-6:, min(cols - 1, int(i * bar / sr / per_col))] = (255, 255, 0) if i % 4 == 0 else (120, 120, 0)
    png(path[:-4] + ".png", out)


if __name__ == "__main__":
    main()
