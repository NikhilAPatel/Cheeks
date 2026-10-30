"""The separation pipeline in numpy, the model of what Cheeks/Stems/ does in Swift.

Runs on top of either the Core ML model or PyTorch, and is checked against demucs itself by
validate.py and gen_fixtures.py. Reading order mirrors DemucsSTFT and CoreMLStemSeparator.
"""

import numpy as np

SEGMENT = 343980  # int(44100 * 7.8)
STRIDE = 257985  # int(0.75 * SEGMENT)
N_FFT = 4096
HOP = 1024
# Periodic Hann, as torch.hann_window.
WINDOW = (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(N_FFT) / N_FFT)).astype(np.float32)
# Sum of the squared window at hop N/4: every output sample is covered by all four frames. _ispec
# adds two silent frames each side, so this holds right up to the segment edges.
ENVELOPE = 1.5
SOURCES = ("drums", "bass", "other", "vocals")


def spec(x):
    """HTDemucs._spec + _magnitude: float32 [2, n] -> complex-as-channels [4, 2048, ceil(n/1024)]."""
    n = x.shape[-1]
    frames = int(np.ceil(n / HOP))
    left = HOP // 2 * 3
    padded = np.pad(x, ((0, 0), (left, left + frames * HOP - n)), mode="reflect")
    # _spec's own padding means the frames it keeps never reach stft's centre padding.
    out = np.empty((4, N_FFT // 2, frames), dtype=np.float32)
    for k in range(frames):
        z = np.fft.rfft(padded[:, k * HOP : k * HOP + N_FFT] * WINDOW, axis=-1)[:, :-1] / np.sqrt(N_FFT)
        out[0, :, k], out[1, :, k] = z[0].real, z[0].imag
        out[2, :, k], out[3, :, k] = z[1].real, z[1].imag
    return out


def ispec(z, n):
    """HTDemucs._ispec for one complex-as-channels spectrogram [2*C, 2048, T]: -> [C, n]."""
    channels = z.shape[0] // 2
    frames = z.shape[-1]
    left = HOP // 2 * 3
    y = np.zeros((channels, frames * HOP + 2 * left + N_FFT), dtype=np.float64)
    for c in range(channels):
        spectrum = np.zeros((N_FFT // 2 + 1, frames), dtype=np.complex128)
        spectrum[:-1] = z[2 * c] + 1j * z[2 * c + 1]
        time = np.fft.irfft(spectrum, n=N_FFT, axis=0) * WINDOW[:, None] * np.sqrt(N_FFT)
        for k in range(frames):
            y[c, k * HOP : k * HOP + N_FFT] += time[:, k]
    return (y[:, left : left + n] / ENVELOPE).astype(np.float32)


def triangular_weight():
    half = SEGMENT // 2
    w = np.concatenate([np.arange(1, half + 1), np.arange(SEGMENT - half, 0, -1)]).astype(np.float32)
    return w / w.max()


def chunk_at(mix, offset):
    """TensorChunk(mix, offset, SEGMENT).padded(SEGMENT) -> (chunk [2, SEGMENT], trim, length).

    A short final chunk reaches back into earlier audio by half the shortfall and pads the rest
    with zeros. The prediction is then cut back to `length` starting at `trim`.
    """
    total = mix.shape[-1]
    length = min(total - offset, SEGMENT)
    delta = SEGMENT - length
    start = offset - delta // 2
    end = start + SEGMENT
    first, last = max(0, start), min(total, end)
    chunk = np.zeros((2, SEGMENT), dtype=np.float32)
    chunk[:, first - start : last - start] = mix[:, first:last]
    return chunk, delta // 2, length


def separate(mix, predict_segment):
    """apply_model(shifts=0, split=True, overlap=0.25) wrapped in the track normalisation of
    demucs.api.Separator, streaming: [2, n] -> [4, 2, n] in `SOURCES` order.
    """
    n = mix.shape[-1]
    ref = mix.mean(0, dtype=np.float64)
    mean = ref.mean()
    std = ref.std(ddof=1) + 1e-8
    normalised = ((mix - mean) / std).astype(np.float32)

    weight = triangular_weight()
    out = np.zeros((4, 2, n), dtype=np.float32)
    total = np.zeros(n, dtype=np.float32)
    for offset in range(0, n, STRIDE):
        chunk, trim, length = chunk_at(normalised, offset)
        y = predict_segment(chunk)[..., trim : trim + length]
        out[..., offset : offset + length] += weight[:length] * y
        total[offset : offset + length] += weight[:length]
    return out / total * std + mean


def coreml_predictor(model):
    """A predict_segment on top of a Core ML model."""

    def predict(chunk):
        s = spec(chunk)
        result = model.predict({"mix": chunk[None], "spec": s[None]})
        time_out = result["time_out"][0]
        spec_out = result["spec_out"][0]
        y = np.empty_like(time_out)
        for source in range(4):
            y[source] = time_out[source] + ispec(spec_out[source], SEGMENT)
        return y

    return predict


def to_int16(x):
    """PCM16Stereo.toInt16."""
    return np.trunc(np.clip(x, -1, 1) * 32767).astype(np.int16)


def from_int16(x):
    return x.astype(np.float32) / 32767
