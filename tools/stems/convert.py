#!/usr/bin/env python3
"""Converts HT-Demucs to Core ML: the network only, with the STFT/iSTFT left to Swift.

    python convert.py [--precision fp16|fp32] [--out PATH]

The result is checked against PyTorch before it's accepted. See README.md for the environment
and for why these settings. Nothing is installed by this script.
"""

import argparse
import os
import sys
import time

import coremltools as ct
import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from htdemucs_core import (  # noqa: E402
    CACHE_ROOT,
    SEGMENT_SAMPLES,
    SPEC_BINS,
    SPEC_FRAMES,
    HTDemucsCore,
    load_htdemucs,
    reference_outputs,
)

# Lowest agreement with PyTorch, on the CPU, for a model to be accepted. In dB, on a noise input.
MINIMUM_SNR = {"fp16": 20, "fp32": 70}


def snr(reference, estimate):
    reference = reference.astype(np.float64)
    return 10 * np.log10(np.sum(reference**2) / np.sum((reference - estimate.astype(np.float64)) ** 2))


def trace(model, mix, spec):
    # MultiheadAttention's fast path traces to _native_multi_head_attention, which coremltools
    # doesn't know. The slow path computes the same thing out of ordinary ops.
    torch.backends.mha.set_fastpath_enabled(False)
    core = HTDemucsCore(model).eval()
    with torch.no_grad():
        return torch.jit.trace(core, (mix, spec), check_trace=False)


def convert(traced, precision):
    return ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="mix", shape=(1, 2, SEGMENT_SAMPLES), dtype=np.float32),
            ct.TensorType(name="spec", shape=(1, 4, SPEC_BINS, SPEC_FRAMES), dtype=np.float32),
        ],
        outputs=[
            ct.TensorType(name="spec_out", dtype=np.float32),
            ct.TensorType(name="time_out", dtype=np.float32),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_ONLY,
        compute_precision={
            "fp32": ct.precision.FLOAT32,
            "fp16": ct.precision.FLOAT16,
        }[precision],
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--precision", choices=["fp32", "fp16"], default="fp16")
    parser.add_argument("--out", default=os.path.join(CACHE_ROOT, "models", "Stems.mlpackage"))
    args = parser.parse_args()

    model = load_htdemucs()
    print("sources", model.sources, "segment", model.segment, "samplerate", model.samplerate)
    assert model.sources == ["drums", "bass", "other", "vocals"]
    assert model.samplerate == 44100 and int(model.segment * model.samplerate) == SEGMENT_SAMPLES
    assert model.nfft == 4096 and model.hop_length == 1024

    # An input for the trace and for checking the result. reference_outputs also asserts that the
    # wrapper reproduces HTDemucs.forward, so this catches a demucs version that has moved on.
    torch.manual_seed(0)
    mix = 0.1 * torch.randn(1, 2, SEGMENT_SAMPLES)
    spec, spec_out, time_out, _ = reference_outputs(model, mix)
    assert spec.shape == (1, 4, SPEC_BINS, SPEC_FRAMES), spec.shape
    assert spec_out.shape == (1, 4, 4, SPEC_BINS, SPEC_FRAMES), spec_out.shape
    assert time_out.shape == (1, 4, 2, SEGMENT_SAMPLES), time_out.shape

    t = time.time()
    traced = trace(model, mix, spec)
    print(f"traced in {time.time() - t:.1f}s")

    t = time.time()
    mlmodel = convert(traced, args.precision)
    print(f"converted in {time.time() - t:.1f}s")

    result = mlmodel.predict({"mix": mix.numpy(), "spec": spec.numpy()})
    agreement = min(snr(spec_out.numpy(), result["spec_out"]), snr(time_out.numpy(), result["time_out"]))
    print(f"agreement with PyTorch on the CPU: {agreement:.1f} dB")
    if agreement < MINIMUM_SNR[args.precision]:
        raise SystemExit(f"the converted model is too far from PyTorch (minimum {MINIMUM_SNR[args.precision]} dB)")

    mlmodel.author = "Rouard, Fan, Defossez (HT-Demucs, Meta). Network section only, see tools/stems."
    mlmodel.license = "MIT (facebookresearch/demucs)"
    mlmodel.short_description = (
        "HT-Demucs network between the spectrogram and the masking. "
        "Sources: drums, bass, other, vocals."
    )
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    mlmodel.save(args.out)
    print("saved", args.out)


if __name__ == "__main__":
    main()
