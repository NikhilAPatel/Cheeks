#!/usr/bin/env python3
"""How fast a track feels, which BPM doesn't say: two tracks at 124 can feel a long way apart.

Reads what each stem does on a 16th-note grid in the track's main sections, from stems.npy and map.npz.

    feel.py [NAME ...]    prints a table, and writes tracks/NAME/feel.json
"""
import json, os, sys
import numpy as np
from scipy import signal

CACHE = os.environ.get("CHEEKS_AUTODJ_CACHE", os.path.expanduser("~/Library/Caches/cheeks-autodj"))
SR = 44100
HOP = 256
VOCALS, MELODY, BASS, DRUMS = 0, 1, 2, 3


def to_mono(stem):
    return (stem[:, 0].astype(np.float32) + stem[:, 1]) / (2 * 0.5 * 32768)


def flux(mono, low, high):
    """How sharply a band's level rises, on a log scale, so a quiet hi-hat counts as well as a loud one."""
    _, _, z = signal.stft(mono, nperseg=1024, noverlap=1024 - HOP, boundary=None, padded=False)
    bins = SR / 1024
    a, b = max(1, int(low / bins)), int(high / bins) + 1
    band = np.abs(z[a:b]).astype(np.float32).sum(0)
    log = np.log1p(band * 200)
    return np.maximum(0, np.diff(log, prepend=log[:1]))


def main_bars(m):
    """The bars the track is mostly heard by: kick and bass in, near full size."""
    energy, kick, bass = m["energy"], m["has_kick"], m["on"][BASS]
    top = np.percentile(energy, 90)
    bars = np.where(kick & bass & (energy > top - 3))[0]
    if len(bars) < 8:
        bars = np.where(energy > np.percentile(energy, 75))[0]
    return bars


def slot_values(onset, starts, sixteenth):
    """The strongest rise in each 16th, allowing for one played late, as swing does."""
    frame = SR / HOP
    out = np.zeros(len(starts))
    late = np.zeros(len(starts))
    for i, t in enumerate(starts):
        a = int((t - 0.2 * sixteenth) * frame)
        b = int((t + 0.6 * sixteenth) * frame) + 1
        if a < 0 or b >= len(onset):
            continue
        window = onset[a:b]
        top = int(window.argmax())
        out[i] = window[top]
        late[i] = (a + top) / frame - t
    return out, late


def pattern(values, per_bar=16):
    """How often each 16th of the bar is hit, as a 16-long profile, and how many of the bar's 16ths are hit."""
    usable = len(values) // per_bar * per_bar
    rows = values[:usable].reshape(-1, per_bar)
    top = np.percentile(values, 97) + 1e-6
    hits = rows > 0.3 * top
    return hits.mean(0), float(hits.sum(1).mean())


def feel(name):
    folder = f"{CACHE}/tracks/{name}"
    stems = np.load(f"{folder}/stems.npy", mmap_mode="r")
    m = np.load(f"{folder}/map.npz")
    beats, bar_beats = m["beat_times"], m["bar_beats"]
    bars = main_bars(m)
    bars = bars[bars < len(bar_beats)]
    sixteenth = 60 / float(m["bpm"]) / 4

    # The 16ths of those bars.
    starts = []
    for bar in bars:
        first = bar_beats[bar]
        if first + 4 < len(beats):
            starts.extend(beats[first] + np.arange(16) * sixteenth)
    starts = np.array(starts)

    drums = to_mono(stems[DRUMS])
    bass = to_mono(stems[BASS])
    top = to_mono(stems[MELODY]) + to_mono(stems[VOCALS])

    hat_values, hat_late = slot_values(flux(drums, 2500, 16000), starts, sixteenth)
    kick_values, _ = slot_values(flux(drums, 30, 150), starts, sixteenth)
    bass_values, _ = slot_values(flux(bass, 30, 400), starts, sixteenth)
    top_values, _ = slot_values(flux(top, 300, 6000), starts, sixteenth)

    hat_shape, hats = pattern(hat_values)
    kick_shape, kicks = pattern(kick_values)
    bass_shape, notes = pattern(bass_values)
    top_shape, tops = pattern(top_values)

    # Swing: how late the second and fourth 16th of each beat come, as a share of a 16th, where they're played.
    off = np.arange(len(starts)) % 4 % 2 == 1
    strong = hat_values > 0.3 * (np.percentile(hat_values, 97) + 1e-6)
    late = hat_late[off & strong]
    swing = float(np.median(late) / sixteenth) if len(late) > 8 else 0.0

    # How long the bass stays up between notes: a held sub feels slower than a plucked one at the same note count.
    power = np.concatenate(([0.0], np.cumsum(bass.astype(np.float64) ** 2)))
    edges = (starts * SR).astype(np.int64)
    edges = edges[edges + int(sixteenth * SR) < len(bass)]
    slot_level = np.sqrt((power[edges + int(sixteenth * SR)] - power[edges]) / max(1, int(sixteenth * SR)))
    sustain = float(np.mean(slot_level > 0.5 * (np.percentile(slot_level, 97) + 1e-9)))

    bpm = float(m["bpm"])
    beat_rate = bpm / 60
    result = dict(name=name, bpm=bpm, main_bars=int(len(bars)), kicks_per_bar=kicks, hats_per_beat=hats / 4, bass_per_beat=notes / 4,
                  top_per_beat=tops / 4, bass_sustain=sustain, swing=swing,
                  hat_rate=hats / 4 * beat_rate, bass_rate=notes / 4 * beat_rate, top_rate=tops / 4 * beat_rate,
                  bass_shape=[round(float(v), 3) for v in bass_shape], kick_shape=[round(float(v), 3) for v in kick_shape],
                  hat_shape=[round(float(v), 3) for v in hat_shape], top_shape=[round(float(v), 3) for v in top_shape])
    with open(f"{folder}/feel.json", "w") as f:
        json.dump(result, f, indent=1)
    return result


def draw(shape):
    return "".join("#" if v > 0.6 else "+" if v > 0.25 else "." for v in shape)


if __name__ == "__main__":
    names = sys.argv[1:] or sorted(os.listdir(f"{CACHE}/tracks"))
    rows = [feel(n) for n in names if os.path.exists(f"{CACHE}/tracks/{n}/map.npz")]
    rows.sort(key=lambda r: r["bass_rate"] + r["hat_rate"] * 0.5 + r["top_rate"] * 0.5)
    print(f"{'track':22}{'bpm':>6} {'bars':>4} {'kick':>5} {'hat/b':>6} {'bass/b':>6} {'top/b':>6} {'held':>5} {'swing':>6}  kick             bass             hats")
    for r in rows:
        print(f"{r['name']:22}{r['bpm']:6.1f} {r['main_bars']:4d} {r['kicks_per_bar']:5.1f} {r['hats_per_beat']:6.2f} {r['bass_per_beat']:6.2f} "
              f"{r['top_per_beat']:6.2f} {r['bass_sustain']:5.2f} {r['swing']:6.2f}  {draw(r['kick_shape'])} {draw(r['bass_shape'])} {draw(r['hat_shape'])}")
