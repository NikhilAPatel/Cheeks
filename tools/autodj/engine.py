"""The app's real audio engine, driven from Python through its C API (Cheeks/DSP/CheeksDSP.h).

What renders here is what the app would play: same stems, stretcher, FX, EQ and limiter. Build it
first with build_engine.sh. Controls are applied between 256-frame blocks, as the core's own block is.
"""
import ctypes as C
import os
import numpy as np

CACHE = os.environ.get("CHEEKS_AUTODJ_CACHE", os.path.expanduser("~/Library/Caches/cheeks-autodj"))
SR = 44100.0
BLOCK = 256
HEADROOM = 0.5
VOCALS, MELODY, BASS, DRUMS = 0, 1, 2, 3

FX = {"none": 0, "echo": 1, "pingpong": 2, "reverb": 3, "flanger": 4, "phaser": 5, "filter": 6, "gate": 7, "crush": 8, "spiral": 9}
COLOR = {"filter": 0, "dub": 1, "space": 2, "noise": 3, "crush": 4, "pitch": 5}

lib = C.CDLL(f"{CACHE}/libcheeksdsp.dylib")
_d = C.c_void_p
_sigs = {
    "cheeks_deck_create": (_d, [C.c_double]),
    "cheeks_deck_destroy": (None, [_d]),
    "cheeks_deck_set_sources": (None, [_d, C.POINTER(C.POINTER(C.c_int16)), C.c_int, C.c_int64, C.c_float]),
    "cheeks_deck_set_playing": (None, [_d, C.c_bool]),
    "cheeks_deck_position": (C.c_double, [_d]),
    "cheeks_deck_seek": (None, [_d, C.c_double]),
    "cheeks_deck_jump": (None, [_d, C.c_double]),
    "cheeks_deck_set_tempo": (None, [_d, C.c_double, C.c_bool, C.c_int]),
    "cheeks_deck_is_stretching": (C.c_bool, [_d]),
    "cheeks_deck_brake": (None, [_d, C.c_double]),
    "cheeks_deck_backspin": (None, [_d, C.c_double]),
    "cheeks_deck_set_loop": (None, [_d, C.c_double, C.c_double, C.c_bool]),
    "cheeks_deck_set_loop_active": (None, [_d, C.c_bool]),
    "cheeks_deck_set_stem_gain": (None, [_d, C.c_int, C.c_float]),
    "cheeks_deck_set_grid": (None, [_d, C.c_double, C.c_double]),
    "cheeks_deck_set_fx_link": (None, [_d, C.c_int, C.c_int, C.c_bool, C.c_double, C.c_float]),
    "cheeks_deck_set_fx_stems": (None, [_d, C.c_int]),
    "cheeks_deck_cut_source_at": (None, [_d, C.c_double]),
    "cheeks_deck_restore_source": (None, [_d]),
    "cheeks_deck_set_eq": (None, [_d, C.c_float, C.c_float, C.c_float]),
    "cheeks_deck_set_filter": (None, [_d, C.c_float]),
    "cheeks_deck_set_color": (None, [_d, C.c_int, C.c_float]),
    "cheeks_engine_create": (_d, [C.c_double, C.POINTER(_d), C.c_int]),
    "cheeks_engine_destroy": (None, [_d]),
    "cheeks_engine_render": (None, [_d, C.POINTER(C.c_float), C.POINTER(C.c_float), C.c_int]),
    "cheeks_engine_set_channel": (None, [_d, C.c_int, C.c_float, C.c_float, C.c_float]),
    "cheeks_engine_set_master": (None, [_d, C.c_float, C.c_float, C.c_float, C.c_bool]),
    "cheeks_engine_positions": (None, [_d, C.POINTER(C.c_double), C.c_int]),
    "cheeks_engine_limiter_reduction": (C.c_float, [_d]),
}
for name, (res, args) in _sigs.items():
    fn = getattr(lib, name)
    fn.restype, fn.argtypes = res, args


def knob_to_gain(v):
    """EQ knob to linear gain, as Deck.applyEQ: fully left removes the band, centre is flat, fully right is +6 dB."""
    return 0.0 if v <= -0.97 else 10 ** ((v * 26 if v < 0 else v * 6) / 20)


class Deck:
    def __init__(self, stems):
        self.handle = lib.cheeks_deck_create(SR)
        self.stems = stems
        self._buffers = [np.ascontiguousarray(stems[i]) for i in range(4)]
        slots = (C.POINTER(C.c_int16) * 4)(*[b.ctypes.data_as(C.POINTER(C.c_int16)) for b in self._buffers])
        lib.cheeks_deck_set_sources(self.handle, slots, 4, stems.shape[1], 1 / HEADROOM / 32768)
        self.eq = [0.0, 0.0, 0.0]

    def set_eq(self, low=None, mid=None, high=None):
        for i, v in enumerate((low, mid, high)):
            if v is not None:
                self.eq[i] = v
        lib.cheeks_deck_set_eq(self.handle, *[knob_to_gain(v) for v in self.eq])

    def close(self):
        lib.cheeks_deck_destroy(self.handle)


class Mixer:
    """Two decks and a master bus at the app's defaults: fader 0.85, master 0.9."""

    def __init__(self, a, b):
        self.decks = [a, b]
        handles = (_d * 2)(a.handle, b.handle)
        self.handle = lib.cheeks_engine_create(SR, handles, 2)
        self.trim = [1.0, 1.0]
        self.fader = [0.85, 0.85]
        lib.cheeks_engine_set_master(self.handle, 0.9, 0.8, 1.0, False)
        self.apply()
        self.left = np.zeros(BLOCK, dtype=np.float32)
        self.right = np.zeros(BLOCK, dtype=np.float32)

    def apply(self):
        for ch in range(2):
            lib.cheeks_engine_set_channel(self.handle, ch, self.trim[ch], self.fader[ch] ** 2, 0.0)

    def render_block(self):
        lib.cheeks_engine_render(self.handle, self.left.ctypes.data_as(C.POINTER(C.c_float)),
                                 self.right.ctypes.data_as(C.POINTER(C.c_float)), BLOCK)
        return self.left, self.right

    def positions(self):
        out = (C.c_double * 2)()
        lib.cheeks_engine_positions(self.handle, out, 2)
        return out[0], out[1]

    def limiter(self):
        return lib.cheeks_engine_limiter_reduction(self.handle)

    def close(self):
        lib.cheeks_engine_destroy(self.handle)
