"""Shared helpers for the validation scripts."""

import os
import subprocess

import numpy as np

FFMPEG = "/opt/homebrew/bin/ffmpeg"
CACHE = os.path.expanduser("~/Library/Caches/cheeks-stems")
DATA = os.path.join(CACHE, "data")
TEST_CLIP = os.path.join(DATA, "test.mp3")
MUSDB_ROOT = os.path.join(DATA, "musdb7")


def read_audio(path, seconds=None):
    """Any file ffmpeg reads, as float32 stereo [2, n] at 44.1 kHz."""
    cmd = [FFMPEG, "-v", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "2", "-ar", "44100"]
    if seconds:
        cmd += ["-t", str(seconds)]
    raw = subprocess.run(cmd + ["-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).T.copy()


def musdb_tracks(limit=None):
    """MUSDB18 7-second previews: yields (name, mix [2,n], {source: [2,n]}) in float32."""
    os.environ["PATH"] = "/opt/homebrew/bin:" + os.environ["PATH"]
    import musdb

    db = musdb.DB(root=MUSDB_ROOT, download=True, subsets=["test"])
    tracks = list(db)[: limit or None]
    for t in tracks:
        sources = {s: t.targets[s].audio.T.astype(np.float32) for s in ("drums", "bass", "other", "vocals")}
        yield t.name, t.audio.T.astype(np.float32), sources


def sdr(reference, estimate, eps=1e-8):
    """MDX / Demucs "new_sdr": 10 log10(|s|^2 / |s - s_hat|^2) over the whole clip, in dB."""
    num = np.sum(reference.astype(np.float64) ** 2) + eps
    den = np.sum((reference.astype(np.float64) - estimate.astype(np.float64)) ** 2) + eps
    return 10 * np.log10(num / den)
