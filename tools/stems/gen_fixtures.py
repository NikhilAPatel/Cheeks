#!/usr/bin/env python3
"""Generates CheeksTests/StemFixtures.swift: reference numbers from PyTorch and demucs itself.

The signal and the fake network are simple enough to be written identically in Swift, so only the
expected outputs need committing. The numpy pipeline in pipeline.py is checked here as well.

    python gen_fixtures.py        # rewrites the file and prints the numpy-vs-demucs errors
"""

import os
import sys

import numpy as np
import torch
from torch import nn

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pipeline as P  # noqa: E402
from demucs.apply import apply_model  # noqa: E402
from htdemucs_core import SEGMENT_SAMPLES, load_htdemucs  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "CheeksTests", "StemFixtures.swift")

# Gains per source in the fake network, Demucs order.
TIME_GAIN = [0.11, 0.23, 0.31, 0.41]
SPEC_GAIN = [0.19, 0.07, 0.13, 0.17]


def test_signal(n):
    """Deterministic stereo signal: two sines and a little LCG noise per channel. [2, n] float32."""
    state = 12345
    noise = np.empty(n, dtype=np.float64)
    for i in range(n):
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        noise[i] = state / 2**32 * 2 - 1
    t = np.arange(n, dtype=np.float64)
    left = 0.4 * np.sin(2 * np.pi * 440 * t / 44100) + 0.2 * np.sin(2 * np.pi * 1000.5 * t / 44100 + 0.3) + 0.1 * noise
    right = 0.3 * np.sin(2 * np.pi * 220 * t / 44100) + 0.1 * np.sin(2 * np.pi * 3000.25 * t / 44100) - 0.05 * noise
    # Slow level change so that segments differ from one another.
    envelope = 0.6 + 0.4 * np.sin(2 * np.pi * 0.13 * t / 44100)
    return (np.stack([left, right]) * envelope).astype(np.float32)


def test_spectrogram(frames):
    """Deterministic [4, 2048, frames] with energy at DC, including an imaginary part there."""
    b = np.arange(2048, dtype=np.float64)[:, None]
    f = np.arange(frames, dtype=np.float64)[None, :]
    out = np.stack(
        [
            0.5 * np.cos(0.01 * b + 0.2 * f) / (1 + 0.01 * b),
            0.5 * np.sin(0.013 * b - 0.1 * f) / (1 + 0.01 * b),
            0.3 * np.cos(0.002 * b * f / 10 + 1) / (1 + 0.02 * b),
            0.3 * np.sin(0.005 * b + 0.3 * f + 1) / (1 + 0.02 * b),
        ]
    )
    return (100 * out).astype(np.float32)


class FakeNetwork(nn.Module):
    """Stands in for HTDemucs in apply_model. The time branch scales with the chunk's own level, so
    that segments disagree and the overlap-add weighting shows in the result; the spectral branch
    goes through the real _spec and _ispec.
    """

    sources = ["drums", "bass", "other", "vocals"]
    samplerate = 44100
    segment = SEGMENT_SAMPLES / 44100

    def __init__(self, demucs):
        super().__init__()
        self.demucs = demucs

    def valid_length(self, length):
        return SEGMENT_SAMPLES

    def forward(self, mix):
        assert mix.shape[-1] == SEGMENT_SAMPLES
        level = 1 + mix.abs().mean()
        z = self.demucs._spec(mix)
        out = []
        for s in range(4):
            time = TIME_GAIN[s] * mix * level
            out.append(time + self.demucs._ispec(SPEC_GAIN[s] * z[:, None], SEGMENT_SAMPLES)[:, 0])
        return torch.stack(out, dim=1)


def fake_numpy(chunk):
    level = 1 + np.abs(chunk).mean(dtype=np.float32)
    s = P.spec(chunk)
    y = np.empty((4, 2, SEGMENT_SAMPLES), dtype=np.float32)
    for source in range(4):
        y[source] = TIME_GAIN[source] * chunk * level + P.ispec(SPEC_GAIN[source] * s, SEGMENT_SAMPLES)
    return y


def demucs_separate(fake, mix):
    # The normalisation is that of demucs.api.Separator.separate_tensor.
    wav = torch.from_numpy(mix)
    ref = wav.mean(0)
    mean, std = ref.mean(), ref.std() + 1e-8
    with torch.no_grad():
        out = apply_model(fake, ((wav - mean) / std)[None], shifts=0, split=True, overlap=0.25, device="cpu")
    return (out * std + mean)[0].numpy(), float(mean), float(std)


def as_swift(values, per_line=8):
    values = [f"{float(v):.8e}" for v in np.ravel(values)]
    lines = [", ".join(values[i : i + per_line]) for i in range(0, len(values), per_line)]
    return "[\n        " + ",\n        ".join(lines) + ",\n    ]"


def main():
    demucs = load_htdemucs()
    fake = FakeNetwork(demucs)
    sections = []

    # 1. _spec of a whole segment.
    x = test_signal(SEGMENT_SAMPLES)
    with torch.no_grad():
        spec_ref = demucs._magnitude(demucs._spec(torch.from_numpy(x)[None]))[0].numpy()
    print("numpy spec vs demucs: max err", np.abs(P.spec(x) - spec_ref).max(), "peak", np.abs(spec_ref).max())
    bins = [0, 1, 10, 41, 42, 500, 2047]
    frames = [0, 1, 2, 167, 334, 335]
    points = [(c, b, f) for c in range(4) for b in bins for f in frames]
    sections.append(("specPoints", "[(channel: Int, bin: Int, frame: Int)]",
                     "[\n        " + ", ".join(f"({c}, {b}, {f})" for c, b, f in points) + ",\n    ]"))
    sections.append(("specValues", "[Float]", as_swift([spec_ref[p] for p in points])))
    sections.append(("specFrameEnergy", "[Float]", as_swift((spec_ref.astype(np.float64) ** 2).sum(axis=(0, 1)))))

    # 2. _ispec of an arbitrary spectrogram, nonzero imaginary DC included.
    z = test_spectrogram(336)
    cplx = torch.from_numpy(z)[None].view(1, 1, -1, 2, 2048, 336).permute(0, 1, 2, 4, 5, 3)
    cplx = torch.view_as_complex(cplx.contiguous())
    with torch.no_grad():
        y_ref = demucs._ispec(cplx, SEGMENT_SAMPLES)[0, 0].numpy()
    print("numpy ispec vs demucs: max err", np.abs(P.ispec(z, SEGMENT_SAMPLES) - y_ref).max(), "peak", np.abs(y_ref).max())
    indices = [0, 1, 511, 512, 1535, 1536, 4000, 100000, 343979, 343978, 343000, 342444]
    sections.append(("ispecIndices", "[Int]", "[" + ", ".join(map(str, indices)) + "]"))
    sections.append(("ispecValues", "[Float]", as_swift(y_ref[:, indices])))
    sections.append(("ispecEnergy", "[Float]", as_swift((y_ref.astype(np.float64) ** 2).sum(axis=1))))

    # 3. apply_model with the fake network, in Int16 as the app has it. Long enough for four
    #    segments with a short last one, and one track shorter than a segment.
    for label, seconds in (("long", 20), ("short", 3)):
        n = int(seconds * 44100)
        mix_int = P.to_int16(test_signal(n))
        mix = P.from_int16(mix_int)
        stems, mean, std = demucs_separate(fake, mix)
        numpy_stems = P.separate(mix, fake_numpy)
        print(f"numpy pipeline vs apply_model ({label}): max err", np.abs(numpy_stems - stems).max(),
              "peak", np.abs(stems).max())
        positions = sorted({0, 1, 1000, 1537, 100_000, 257_984, 257_985, 300_000, 343_979, 343_980, 515_969, 515_970,
                            600_000, 773_954, 773_955, 800_000, n - 2, n - 1} & set(range(n)))
        sections.append((f"{label}Frames", "Int", str(n)))
        sections.append((f"{label}Mean", "Float", f"{mean:.8e}"))
        sections.append((f"{label}Std", "Float", f"{std:.8e}"))
        sections.append((f"{label}Positions", "[Int]", "[" + ", ".join(map(str, positions)) + "]"))
        # Demucs order, at positions: L and R per source.
        sections.append((f"{label}Values", "[Float]", as_swift(stems[:, :, positions])))

    body = "\n\n".join(f"    static let {name}: {kind} = {value}" for name, kind, value in sections)
    source = f"""// Generated by tools/stems/gen_fixtures.py from PyTorch and demucs. Don't edit by hand.

enum StemFixtures {{
{body}
}}
"""
    with open(OUT, "w") as f:
        f.write(source)
    print("wrote", os.path.normpath(OUT), len(source), "bytes")


if __name__ == "__main__":
    main()
