#!/usr/bin/env python3
"""Maps a split track: its beat grid, downbeats, phrases, and what each stem is doing in every bar.

This is the knowledge a transition is planned from. It leans on the stems, because the drums stem
shows the kick far more clearly than the mix does, and an arrangement is mostly stems coming and going.

    analyze.py NAME [NAME ...]    writes tracks/NAME/map.npz and prints the arrangement
"""
import json, os, sys
import numpy as np
from scipy import signal

CACHE = os.environ.get("CHEEKS_AUTODJ_CACHE", os.path.expanduser("~/Library/Caches/cheeks-autodj"))
SR = 44100
STEMS = ["vocals", "melody", "bass", "drums"]
VOCALS, MELODY, BASS, DRUMS = 0, 1, 2, 3
HOP = 256
PITCHES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
# Krumhansl-Kessler profiles, the same as KeyDetector.swift.
MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def to_mono(stem):
    return (stem[:, 0].astype(np.float32) + stem[:, 1]) / (2 * 0.5 * 32768)


def onset_envelopes(drums):
    """Half-wave rectified change in log energy, split into the kick's band and everything above it."""
    _, _, z = signal.stft(drums, nperseg=1024, noverlap=1024 - HOP, boundary=None, padded=False)
    mag = np.abs(z).astype(np.float32)
    low_bins = int(150 / (SR / 1024))
    bands = [mag[1:low_bins + 1].sum(0), mag[low_bins + 1:].sum(0)]
    out = []
    for band in bands:
        log = np.log1p(band * 200)
        out.append(np.maximum(0, np.diff(log, prepend=log[:1])))
    return out[0], out[1]


def fold_score(onset, period):
    bins = int(round(period))
    index = np.mod(np.arange(len(onset)), period).astype(np.int64) % bins
    fold = np.bincount(index, weights=onset, minlength=bins) / np.maximum(1, np.bincount(index, minlength=bins))
    fold = np.convolve(np.r_[fold[-2:], fold, fold[:2]], np.ones(3) / 3, "same")[2:-2]
    peak = int(fold.argmax())
    return float(fold[peak] - np.median(fold)), peak


def find_grid(low, high):
    """A constant-tempo grid: most club tracks have one, and a drifting track is flagged for the planner to refuse."""
    frames_per_second = SR / HOP
    onset = low + 0.25 * high
    onset = onset / (np.percentile(onset, 99.5) + 1e-9)
    best = (-1.0, 120.0)
    # A beat folds up sharply at the true tempo and its multiples. Prefer the usual club range.
    for bpm in np.arange(70.0, 190.0, 0.1):
        score, _ = fold_score(onset, frames_per_second * 60 / bpm)
        prior = np.exp(-0.5 * (np.log2(bpm / 125.0) / 0.45) ** 2)
        score *= prior
        if score > best[0]:
            best = (score, float(bpm))
    fine = [(fold_score(onset, frames_per_second * 60 / b)[0], b) for b in np.arange(best[1] - 0.3, best[1] + 0.3, 0.005)]
    bpm = max(fine)[1]

    # Line up on the actual kicks: regress their positions against beat numbers to get tempo and phase exactly.
    period = frames_per_second * 60 / bpm
    _, phase = fold_score(onset, period)
    for _ in range(3):
        count = int((len(onset) - phase) / period)
        centres = phase + np.arange(count) * period
        reach = int(period * 0.12)
        xs, ys, weights = [], [], []
        for n, centre in enumerate(centres):
            a, b = int(centre) - reach, int(centre) + reach + 1
            if a < 0 or b >= len(low):
                continue
            window = low[a:b]
            top = int(window.argmax())
            if window[top] > np.percentile(low, 90):
                xs.append(n); ys.append(a + top); weights.append(window[top])
        if len(xs) < 16:
            break
        slope, intercept = np.polyfit(xs, ys, 1, w=np.sqrt(weights))
        period, phase = slope, intercept
    bpm = frames_per_second * 60 / period
    if abs(bpm - round(bpm)) < 0.06:
        bpm = float(round(bpm))
    first = phase * HOP / SR
    # How far the kicks stray from a straight grid, in ms: a drifting track scores badly here.
    drift = 0.0
    if len(xs) >= 16:
        residual = (np.array(ys) - (np.array(xs) * period + phase)) * HOP / SR * 1000
        drift = float(np.percentile(np.abs(residual), 90))
    return bpm, first, drift


def band_rms(mono, edges, width):
    """RMS over each [edges[i], edges[i+1]) in samples."""
    power = np.concatenate(([0.0], np.cumsum(mono.astype(np.float64) ** 2)))
    a = np.clip(edges[:-1], 0, len(mono)).astype(np.int64)
    b = np.clip(edges[1:], 0, len(mono)).astype(np.int64)
    return np.sqrt((power[b] - power[a]) / np.maximum(1, b - a))


def chroma_per_beat(mono, beat_edges):
    """Pitch-class energy in each beat from 8192-point spectra, kept to where notes are clear."""
    nfft, hop = 8192, 2048
    freqs = np.fft.rfftfreq(nfft, 1 / SR)
    keep = np.where((freqs >= 65) & (freqs <= 2100))[0]
    pitch = np.mod(np.round(12 * np.log2(freqs[keep] / 440.0)).astype(int) + 9, 12)
    window = np.hanning(nfft).astype(np.float32)
    count = max(0, (len(mono) - nfft) // hop)
    frames = np.zeros((count, 12), dtype=np.float32)
    for i in range(count):
        spectrum = np.abs(np.fft.rfft(mono[i * hop:i * hop + nfft] * window))[keep]
        frames[i] = np.bincount(pitch, weights=spectrum ** 2, minlength=12)
    times = (np.arange(count) * hop + nfft / 2)
    index = np.searchsorted(beat_edges, times) - 1
    out = np.zeros((len(beat_edges) - 1, 12), dtype=np.float32)
    valid = (index >= 0) & (index < len(out))
    np.add.at(out, index[valid], frames[valid])
    return out


def detect_key(chroma):
    total = chroma.sum(0)
    total = total / (total.sum() + 1e-9)
    best = (-2.0, 0, "minor")
    for root in range(12):
        for name, profile in (("major", MAJOR), ("minor", MINOR)):
            r = np.corrcoef(total, np.roll(profile, root))[0, 1]
            if r > best[0]:
                best = (float(r), root, name)
    return best


def novelty(features, reach):
    """Distance between the `reach` steps before and after each step."""
    n = len(features)
    out = np.zeros(n)
    for i in range(reach, n - reach):
        out[i] = np.linalg.norm(features[i:i + reach].mean(0) - features[i - reach:i].mean(0))
    return out


def find_downbeat(db, kick_db, chroma, drums, edges):
    """Which beat of four is the 1. Several weak clues add up: harmony and arrangement change on it, the
    clap sits on 2 and 4, and club tracks tend to start on a bar line."""
    n = db.shape[1]
    scores = np.zeros((4, 4))
    # Chords and bass notes change on the 1.
    unit = chroma / (np.linalg.norm(chroma, axis=1, keepdims=True) + 1e-6)
    flux = np.r_[0, 1 - np.sum(unit[1:] * unit[:-1], axis=1)]
    weight = np.r_[0, np.minimum(np.linalg.norm(chroma[1:], axis=1), np.linalg.norm(chroma[:-1], axis=1))]
    weight = weight / (np.percentile(weight, 95) + 1e-9)
    for p in range(4):
        scores[0, p] = np.sum((flux * np.minimum(weight, 1))[p::4])
    # Stems come and go on the 1. Compare the bar after each beat with the bar before it.
    feats = np.vstack([np.clip(db, -60, 0), np.clip(kick_db, -60, 0)[None]]).T
    sharp = novelty(feats, 4)
    for p in range(4):
        scores[1, p] = np.sum(sharp[p::4] ** 2)
    # The clap: brightness of the drums right on each beat is highest on 2 and 4.
    b, a = signal.butter(2, 1500 / (SR / 2), "high")
    bright = signal.lfilter(b, a, drums)
    power = np.concatenate(([0.0], np.cumsum(bright.astype(np.float64) ** 2)))
    reach = int(0.07 * SR)
    a_ = np.clip(edges[:-1] - reach // 4, 0, len(bright) - 1)
    b_ = np.clip(edges[:-1] + reach, 0, len(bright) - 1)
    clap = 10 * np.log10(power[b_] - power[a_] + 1e-9)
    per_phase = [np.median(clap[p::4]) for p in range(4)]
    for p in range(4):
        # Being on the quieter pair (1 and 3) is what counts, and it says nothing about 1 against 3.
        scores[2, p] = -(per_phase[p] + per_phase[(p + 2) % 4])
    # The first beat with a real kick on it.
    top = np.percentile(kick_db, 90)
    hits = np.where(kick_db > top - 10)[0]
    if len(hits):
        scores[3, hits[0] % 4] = 1
    # Equal votes, each scaled to its own spread.
    spread = scores.std(axis=1, keepdims=True) + 1e-9
    votes = (scores - scores.mean(axis=1, keepdims=True)) / spread
    total = votes.sum(axis=0)
    order = np.sort(total)
    return int(np.argmax(total)), float((order[-1] - order[-2]) / (np.ptp(total) + 1e-9))


def analyze(name):
    stems = np.load(f"{CACHE}/tracks/{name}/stems.npy", mmap_mode="r")
    mono = [to_mono(stems[i]) for i in range(4)]
    frames = len(mono[0])
    low, high = onset_envelopes(mono[DRUMS])
    bpm, first, drift = find_grid(low, high)
    beat = 60 / bpm
    before = int(first / beat)
    origin = first - before * beat
    count = int((frames / SR - origin) / beat)
    beat_times = origin + np.arange(count + 1) * beat
    edges = np.rint(beat_times * SR).astype(np.int64)

    # Every stem's level per beat, on one scale so their relative sizes mean something, plus the kick.
    level = np.stack([band_rms(m, edges, 0) for m in mono])
    b, a = signal.butter(2, 120 / (SR / 2), "low")
    kick_band = signal.lfilter(b, a, mono[DRUMS])
    kick = band_rms(kick_band, edges, 0)
    bass_band = signal.lfilter(b, a, mono[BASS])
    db = 20 * np.log10(level + 1e-5)
    kick_db = 20 * np.log10(kick + 1e-5)

    chroma_harm = chroma_per_beat(mono[MELODY] + mono[BASS], edges.astype(np.float64))
    chroma_voc = chroma_per_beat(mono[VOCALS], edges.astype(np.float64))
    downbeat, downbeat_conf = find_downbeat(db, kick_db, chroma_harm, mono[DRUMS], edges)

    # Bars from that downbeat on, with a part-bar ahead of the first ignored.
    bar_beats = np.arange(downbeat, len(level[0]) - 3, 4)
    bars = len(bar_beats)
    bar_level = np.stack([[20 * np.log10(np.sqrt(np.mean(level[s, b:b + 4] ** 2)) + 1e-5) for b in bar_beats] for s in range(4)])
    bar_kick = np.array([20 * np.log10(np.sqrt(np.mean(kick[b:b + 4] ** 2)) + 1e-5) for b in bar_beats])
    # How much of each bar a vocal covers: separated vocals leak, so short bursts count for little.
    # A track with no singer still leaks a quiet vocal stem, so it has to stand up against the whole mix too.
    vocal_top = np.percentile(db[VOCALS], 98)
    loudest = np.percentile(db, 97, axis=1).max()
    vocal_floor = max(vocal_top - 14, loudest - 16)
    vocal_cover = np.array([np.mean(db[VOCALS, b:b + 4] > vocal_floor) for b in bar_beats])

    # Which stems are there, relative to how loud each one gets in this track, and to the track overall.
    overall = max(np.percentile(bar_level[s], 97) for s in range(4))
    tops = np.array([np.percentile(bar_level[s], 97) for s in range(4)])
    floors = np.maximum(tops - 14, overall - 26)
    on = bar_level > floors[:, None]
    kick_top = np.percentile(bar_kick, 95)
    has_kick = bar_kick > max(kick_top - 12, overall - 30)
    energy = 10 * np.log10(np.sum(10 ** (bar_level / 10), axis=0) + 1e-9)

    # Phrases: find where the arrangement changes, then the lattice of 16 bars those changes sit on.
    bar_feats = np.vstack([np.clip(bar_level, -60, 0), np.clip(bar_kick, -60, 0)[None], np.clip(vocal_cover * -30, -30, 0)[None]]).T
    bar_change = novelty(bar_feats, 4)
    lattice_scores = [float(np.sum(bar_change[o::16] ** 2) + 0.5 * np.sum(bar_change[o::8] ** 2)) for o in range(16)]
    lattice = int(np.argmax(lattice_scores))
    # Sections start on the lattice's 4-bar lines, wherever the music changes enough there.
    threshold = max(np.percentile(bar_change, 70), 2.0)
    boundaries = [0, bars]
    for line in range(lattice % 4, bars, 4):
        reach = bar_change[max(0, line - 1):line + 2]
        if len(reach) and reach.max() >= threshold:
            boundaries.append(line)
    boundaries = sorted(set(boundaries))

    strength, root, mode = detect_key(chroma_harm)
    bar_chroma = np.stack([chroma_harm[b:b + 4].sum(0) for b in bar_beats])
    bar_vchroma = np.stack([chroma_voc[b:b + 4].sum(0) for b in bar_beats])

    out = f"{CACHE}/tracks/{name}/map.npz"
    np.savez_compressed(out, bpm=bpm, first=first, drift=drift, origin=origin, downbeat=downbeat, downbeat_conf=downbeat_conf,
                        beat_times=beat_times, bar_beats=bar_beats, bar_level=bar_level, bar_kick=bar_kick, vocal_cover=vocal_cover,
                        on=on, has_kick=has_kick, energy=energy, lattice=lattice, boundaries=np.array(boundaries),
                        bar_chroma=bar_chroma, bar_vchroma=bar_vchroma, key_root=root, key_mode=mode, key_strength=strength,
                        change=bar_change, seconds=frames / SR)
    return report(name, np.load(out))


def report(name, m):
    bars = len(m["bar_beats"])
    lines = [f"{name}: {float(m['bpm']):.2f} BPM, drift {float(m['drift']):.1f} ms, downbeat {int(m['downbeat'])} "
             f"(conf {float(m['downbeat_conf']):.2f}), key {PITCHES[int(m['key_root'])]} {m['key_mode']} ({float(m['key_strength']):.2f}), "
             f"{bars} bars, lattice {int(m['lattice'])}, {float(m['seconds']):.0f} s"]
    boundary = set(int(b) for b in m["boundaries"])
    marks = "".join("|" if i in boundary else ("'" if (i - int(m["lattice"])) % 16 == 0 else " ") for i in range(bars))
    rows = [("bound ", marks)]
    rows.append(("vocal ", "".join("#" if c > 0.6 else "+" if c > 0.2 else "." for c in m["vocal_cover"])))
    for s, label in ((MELODY, "melody"), (BASS, "bass  "), (DRUMS, "drums ")):
        rows.append((label, "".join("#" if v else "." for v in m["on"][s])))
    rows.append(("kick  ", "".join("#" if v else "." for v in m["has_kick"])))
    top = np.percentile(m["energy"], 97)
    rows.append(("energy", "".join(str(int(np.clip((e - top + 18) / 2, 0, 9))) for e in m["energy"])))
    width = 110
    for start in range(0, bars, width):
        lines.append(f"  bar {start}")
        for label, row in rows:
            lines.append(f"  {label} {row[start:start + width]}")
    return "\n".join(lines)


if __name__ == "__main__":
    for name in sys.argv[1:]:
        print(analyze(name), flush=True)
