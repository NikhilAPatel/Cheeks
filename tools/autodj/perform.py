"""Plays a Score: beat-locked control moves on two decks, rendered through the app's real engine.

Everything is timed on the mix clock, in beats at the outgoing track's tempo. Mix beat 0 is where the
render starts, so a Score reads like an arrangement. The incoming deck is sample-locked to that clock
and stays there: the engine runs both decks from one sample clock, and it's checked at the end.
"""
import os
import numpy as np
import engine as E

CACHE = E.CACHE
TARGET_LUFS = -11.0  # Deck.targetLoudness
STRETCH_LAG = 0.125  # seconds, measured: what the stretcher adds to a stem-gain change
GAIN_OPENING = 0.03  # seconds for a stem's gain to be mostly open after a step


def k_weighted_lufs(mix):
    """Integrated loudness with the standard's two filters and gates, as LoudnessMeter in TrackAnalyzer.swift."""
    from scipy import signal
    fs = E.SR
    # High shelf and high pass, both designed for this rate from the BS.1770 values.
    a0db, f0, q = 3.99984, 1681.97, 0.70717
    k = np.tan(np.pi * f0 / fs); vh = 10 ** (a0db / 20); vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    b_s = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
    a_s = [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    f0, q = 38.13547087602444, 0.5003270373238773
    k = np.tan(np.pi * f0 / fs); a0 = 1 + k / q + k * k
    b_h = [1, -2, 1]; a_h = [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    x = signal.lfilter(b_h, a_h, signal.lfilter(b_s, a_s, mix, axis=0), axis=0)
    hop = int(fs * 0.1)
    energy = (x ** 2).sum(axis=1)
    blocks = np.add.reduce(energy[: len(energy) // hop * hop].reshape(-1, hop), axis=1) / hop
    short = np.convolve(blocks, np.ones(4) / 4, "valid")
    lufs = lambda e: -0.691 + 10 * np.log10(np.maximum(e, 1e-12))
    audible = short[lufs(short) > -70]
    if len(audible) == 0:
        return None
    gated = audible[lufs(audible) > lufs(audible.mean()) - 10]
    return float(lufs(gated.mean()))


class Track:
    def __init__(self, name):
        self.name = name
        self.stems = np.load(f"{CACHE}/tracks/{name}/stems.npy")
        self.map = np.load(f"{CACHE}/tracks/{name}/map.npz")
        m = self.map
        self.bpm = float(m["bpm"])
        self.beat_times = m["beat_times"]
        self.bar_beats = m["bar_beats"]
        self.bars = len(self.bar_beats)
        self.on = m["on"]
        self.kick = m["has_kick"]
        self.vocal = m["vocal_cover"]
        self.energy = m["energy"]
        self.boundaries = [int(b) for b in m["boundaries"]]
        self.lattice = int(m["lattice"])
        self.bar_chroma = m["bar_chroma"]
        self.bar_vchroma = m["bar_vchroma"]
        self.key_root = int(m["key_root"])
        self.key_mode = str(m["key_mode"])
        path = f"{CACHE}/tracks/{name}/lufs.txt"
        if os.path.exists(path):
            self.lufs = float(open(path).read())
        else:
            self.lufs = k_weighted_lufs(self.stems.sum(axis=0).astype(np.float32) / E.HEADROOM / 32768) or TARGET_LUFS
            open(path, "w").write(str(self.lufs))
        self.auto_gain = float(np.clip(TARGET_LUFS - self.lufs, -12, 9))

    def bar_frame(self, bar):
        return float(self.beat_times[0] + (self.bar_beats[0] + bar * 4) * 60 / self.bpm) * E.SR

    @property
    def beat_frames(self):
        return 60 / self.bpm * E.SR


class Score:
    """Control moves in mix beats. A ramp holds its last value afterwards."""

    def __init__(self, name):
        self.name = name
        self.events = []  # (beat, deck, action, args)
        self.ramps = []  # (start, end, deck, control, from, to, curve)
        self.notes = []

    def at(self, beat, deck, action, *args):
        self.events.append((float(beat), deck, action, args))

    def ramp(self, start, end, deck, control, v0, v1, curve="linear"):
        self.ramps.append((float(start), float(end), deck, control, float(v0), float(v1), curve))

    def set(self, beat, deck, control, value):
        self.ramp(beat, beat, deck, control, value, value)

    def note(self, beat, text):
        self.notes.append((float(beat), text))


def shape(x, curve):
    if curve == "linear":
        return x
    if curve == "in":  # slow start
        return x * x
    if curve == "out":  # fast start
        return 1 - (1 - x) * (1 - x)
    if curve == "s":
        return x * x * (3 - 2 * x)
    raise ValueError(curve)


class Performance:
    def __init__(self, a, b, a_start_bar, length_beats, b_shift=0):
        self.a, self.b = a, b
        self.a_start_bar = a_start_bar
        self.length = length_beats
        self.rate_b = a.bpm / b.bpm
        self.b_shift = b_shift

    def render(self, score):
        a, b = self.a, self.b
        da, db_ = E.Deck(a.stems), E.Deck(b.stems)
        mixer = E.Mixer(da, db_)
        decks = {"A": da, "B": db_}
        channel = {"A": 0, "B": 1}
        mixer.trim = [10 ** (a.auto_gain / 20), 10 ** (b.auto_gain / 20)]
        mixer.apply()
        for track, deck in ((a, da), (b, db_)):
            E.lib.cheeks_deck_set_grid(deck.handle, track.beat_frames, float(track.beat_times[0] + track.bar_beats[0] * 60 / track.bpm) * E.SR)
        E.lib.cheeks_deck_set_tempo(da.handle, 1.0, True, 0)
        E.lib.cheeks_deck_set_tempo(db_.handle, self.rate_b, True, self.b_shift)
        E.lib.cheeks_deck_seek(da.handle, a.bar_frame(self.a_start_bar))
        E.lib.cheeks_deck_set_playing(da.handle, True)

        frames_per_beat = a.beat_frames
        total_blocks = int(self.length * frames_per_beat / E.BLOCK) + 1
        out_l, out_r = np.zeros(total_blocks * E.BLOCK, np.float32), np.zeros(total_blocks * E.BLOCK, np.float32)
        limiter = np.zeros(total_blocks, np.float32)
        # Stems and beat FX go in ahead of the stretcher, so on a stretched deck they're heard STRETCH_LAG late.
        # A stem's gain also takes a moment to open. Send them early, or a drop's first kick is gone.
        def early(deck_name):
            stretched = deck_name == "B" and (abs(self.rate_b - 1) > 1e-9 or self.b_shift != 0)
            return (STRETCH_LAG if stretched else 0) * E.SR / frames_per_beat
        step = GAIN_OPENING * E.SR / frames_per_beat
        events = sorted(((at - early(deck) if action in ("fx", "fx_stems", "cut") else at, deck, action, args)
                         for at, deck, action, args in score.events), key=lambda e: e[0])
        ramps = []
        for start, end, deck_name, control, v0, v1, curve in score.ramps:
            if control.startswith("stem:"):
                lead = early(deck_name) + (step if end <= start else 0)
                start, end = max(0.0, start - lead), max(0.0, end - lead)
            ramps.append((start, end, deck_name, control, v0, v1, curve))
        next_event = 0
        values = {}
        filters = {"A": 0.0, "B": 0.0}
        lock = None  # (nominal frame, B's frame there) once B has started

        def set_control(deck_name, control, value):
            key = (deck_name, control)
            if values.get(key) == value:
                return
            values[key] = value
            deck = decks[deck_name]
            kind, _, what = control.partition(":")
            if kind == "stem":
                E.lib.cheeks_deck_set_stem_gain(deck.handle, int(what), float(value))
            elif kind == "eq":
                deck.set_eq(**{what: value})
            elif kind == "filter":
                E.lib.cheeks_deck_set_filter(deck.handle, float(value))
            elif kind == "fader":
                mixer.fader[channel[deck_name]] = value
                mixer.apply()
            elif kind == "color":
                E.lib.cheeks_deck_set_color(deck.handle, E.COLOR[what], float(value))
            else:
                raise ValueError(control)

        for block in range(total_blocks):
            frame = block * E.BLOCK
            beat = frame / frames_per_beat
            while next_event < len(events) and events[next_event][0] <= beat + 1e-9:
                at, deck_name, action, args = events[next_event]
                next_event += 1
                deck = decks[deck_name]
                track = a if deck_name == "A" else b
                rate = 1.0 if deck_name == "A" else self.rate_b
                late = frame - at * frames_per_beat  # how far past its exact moment this block starts
                if action == "start":
                    # Start this deck so `bar` lands exactly on mix beat `args[1]`, however the blocks fall.
                    bar, land_beat = args
                    target = track.bar_frame(bar) + (frame - land_beat * frames_per_beat) * rate
                    E.lib.cheeks_deck_seek(deck.handle, target)
                    E.lib.cheeks_deck_set_playing(deck.handle, True)
                    lock = (frame, target)
                elif action == "stop":
                    E.lib.cheeks_deck_set_playing(deck.handle, False)
                elif action == "loop":
                    # In the deck's own frames, measured from bars.
                    start, end = args
                    E.lib.cheeks_deck_set_loop(deck.handle, start, end, True)
                elif action == "loop_off":
                    E.lib.cheeks_deck_set_loop_active(deck.handle, False)
                elif action == "fx":
                    link, kind, on, beats, depth = args
                    E.lib.cheeks_deck_set_fx_link(deck.handle, link, E.FX[kind], on, beats, depth)
                elif action == "fx_stems":
                    E.lib.cheeks_deck_set_fx_stems(deck.handle, args[0])
                elif action == "cut":
                    # Cut the track's own sound at this beat of the track; FX tails ring on.
                    grid = float(track.beat_times[0] + track.bar_beats[0] * 60 / track.bpm) * E.SR
                    E.lib.cheeks_deck_cut_source_at(deck.handle, (E.lib.cheeks_deck_position(deck.handle) - grid) / track.beat_frames)
                elif action == "brake":
                    E.lib.cheeks_deck_brake(deck.handle, args[0] * frames_per_beat)
                elif action == "backspin":
                    E.lib.cheeks_deck_backspin(deck.handle, args[0] * frames_per_beat)
                else:
                    raise ValueError(action)
            for start, end, deck_name, control, v0, v1, curve in ramps:
                if beat < start:
                    continue
                if beat >= end or end <= start:
                    set_control(deck_name, control, v1)
                else:
                    set_control(deck_name, control, v0 + (v1 - v0) * shape((beat - start) / (end - start), curve))
            left, right = mixer.render_block()
            out_l[frame:frame + E.BLOCK] = left
            out_r[frame:frame + E.BLOCK] = right
            limiter[block] = mixer.limiter()

        # The incoming deck must still be exactly where the clock says: this is what keeps two kicks as one.
        pos_a, pos_b = mixer.positions()
        drift_ms = None
        if lock is not None and values.get(("B", "stopped")) is None:
            expected = lock[1] + (total_blocks * E.BLOCK - lock[0]) * self.rate_b
            drift_ms = float((pos_b - expected) / E.SR * 1000)
        report = {"lock_error_ms": drift_ms, "limiter_max": float(limiter.max()), "limiter_over1db": float(np.mean(limiter > 1)), "seconds": total_blocks * E.BLOCK / E.SR}
        mixer.close(); da.close(); db_.close()
        return np.stack([out_l, out_r], axis=1), report


def write_audio(path, audio):
    import soundfile as sf
    sf.write(path, audio, int(E.SR), subtype="PCM_16")
