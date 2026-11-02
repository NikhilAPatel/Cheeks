"""Finds where each move should happen in a pair of tracks, and scores the options.

Hard rules throw a candidate out; everything else adds up to a score. Nothing here is learned yet: the
weights are a starting point, and these features are what a learned ranker would take over.
"""
import numpy as np
from engine import VOCALS, MELODY, BASS, DRUMS

# How well two pitch classes sit together, by interval in semitones.
_K = np.array([1.0, -1.0, 0.1, 0.5, 0.5, 0.6, -0.6, 0.8, 0.5, 0.5, 0.1, -0.2])
CONSONANCE = np.stack([np.roll(_K, i) for i in range(12)])
MAX_STRETCH = 0.08  # DJs stay within 5% for 86% of tracks and 10% for 94.5% (Kim et al., ISMIR 2020)


def unit(x):
    return x / (np.linalg.norm(x) + 1e-9)


def consonance(x, y, shift=0):
    """How well two pitch-class profiles agree, with y moved up `shift` semitones. Two flat profiles score 0
    and the same strong profile against itself scores about 1, so a score means the same on any track."""
    x, y = np.maximum(x, 0), np.maximum(np.roll(y, shift), 0)
    x, y = x / (x.sum() + 1e-9) - 1 / 12, y / (y.sum() + 1e-9) - 1 / 12
    return float(x @ CONSONANCE @ y / (np.linalg.norm(x) * np.linalg.norm(y) + 1e-9)) / 1.9


def bar_consonance(xs, ys, shift=0):
    """Bar by bar, weighted to the bars where both parts are actually sounding."""
    n = min(len(xs), len(ys))
    if n == 0:
        return 0.0
    weights = np.array([min(np.linalg.norm(xs[i]), np.linalg.norm(ys[i])) for i in range(n)]) + 1e-9
    return float(np.average([consonance(xs[i], ys[i], shift) for i in range(n)], weights=weights))


class Features:
    """What the planner reads off a track's map."""

    def __init__(self, t):
        self.t = t
        self.bars = t.bars
        self.top = np.percentile(t.energy, 90)
        self.kick = t.kick.astype(float)
        self.bass = t.on[BASS].astype(float)
        self.melody = t.on[MELODY].astype(float)
        self.vocal = t.vocal
        self.lines = sorted(set(b for b in t.boundaries if 0 <= b < t.bars) | set(range(t.lattice % 8, t.bars, 8)))

    def mean(self, x, a, b):
        a, b = max(0, a), min(self.bars, b)
        return float(np.mean(x[a:b])) if b > a else 0.0

    def strength(self, bar):
        """How firmly a bar sits on the phrase structure: 16 bars, then 8, then a change in the music."""
        o = (bar - self.t.lattice) % 16
        return 1.0 if o == 0 else 0.7 if o == 8 else 0.45 if bar in self.t.boundaries else 0.25

    def is_main(self, a, b):
        return self.mean(self.kick, a, b) > 0.8 and self.mean(self.bass, a, b) > 0.6

    def level(self, a, b):
        return self.mean(self.t.energy, a, b) - self.top

    def drop_quality(self, bar):
        """A drop: the full band at full size, straight after something smaller. Nothing else is worth
        building to, and a quiet intro after a big build is a let-down however clean the cut is."""
        if not self.is_main(bar, bar + 8):
            return 0.0
        size = float(np.clip((self.level(bar, bar + 8) + 3) / 3, 0, 1))
        if size == 0 or self.mean(self.melody, bar, bar + 8) < 0.5:
            return 0.0
        if bar < 2:
            return 0.35 * size
        before = self.mean(self.kick, bar - 8, bar) * 0.5 + self.mean(self.bass, bar - 8, bar) * 0.5
        lift = np.clip((self.level(bar, bar + 8) - self.level(bar - 8, bar)) / 6, 0, 1)
        return size * (0.4 + 0.3 * (1 - before) + 0.3 * lift)

    def early(self, bar):
        """Coming in late throws most of the track away."""
        return float(np.clip(1 - bar / (self.bars * 0.5), 0, 1))

    def late(self, bar):
        return float(np.clip((bar - self.bars * 0.45) / (self.bars * 0.45), 0, 1))


def harmony_options(a, b, a_bars, b_bars):
    """The best agreement between two harmonic parts, allowing a semitone of shift. DJs rarely shift further."""
    plain = bar_consonance(a.bar_chroma[a_bars[0]:a_bars[1]], b.bar_chroma[b_bars[0]:b_bars[1]])
    best = (plain, 0)
    # A semitone has to earn its artefacts.
    for shift in (1, -1):
        c = bar_consonance(a.bar_chroma[a_bars[0]:a_bars[1]], b.bar_chroma[b_bars[0]:b_bars[1]], shift)
        if c > best[0] + 0.15 and c > 0.25:
            best = (c, shift)
    return best


def candidates(a, b, earliest=0):
    fa, fb = Features(a), Features(b)
    stretch = abs(a.bpm / b.bpm - 1)
    out = []
    if stretch > MAX_STRETCH and min(abs(a.bpm / (b.bpm * 2) - 1), abs(a.bpm * 2 / b.bpm - 1)) > MAX_STRETCH:
        cut_only = True
    else:
        cut_only = False
    # Leave from a full section: leaving from a breakdown means the track was already gone.
    exits = [x for x in fa.lines if x >= max(earliest, 24) and fa.level(x - 8, x) > -3]
    entries = fb.lines
    for x in exits:
        for e in entries:
            exit_fit = fa.strength(x) * 0.5 + fa.late(x) * 0.5
            enter_fit = fb.strength(e)

            # Cut-style moves land on B's drop; nothing overlaps, so no harmony question.
            drop = fb.drop_quality(e)
            if drop > 0 and e + 32 < b.bars:
                # What's left of A at the throw should be worth leaving: a full section, not an outro's scraps.
                body = fa.level(x - 8, x)
                full = np.clip((body + 8) / 8, 0, 1)
                for move, length, bonus, room in (("loop_drop", 16, 0.15, 16), ("echo_drop", 0, 0.05, 0), ("brake_drop", 0, -0.1, 0)):
                    at = x if move != "loop_drop" else x
                    if move == "loop_drop":
                        if x + 16 >= a.bars or not fa.is_main(x, x + 4):
                            continue
                    elif not fa.is_main(x - 4, x):
                        continue
                    score = 1.2 * exit_fit + 1.5 * drop + 1.0 * fb.early(e) + 0.5 * enter_fit + 0.6 * full + bonus - stretch * 3
                    out.append(dict(move=move, a_exit=x, b_entry=e, score=score, shift=0,
                                    why=f"drop {drop:.2f}, early {fb.early(e):.2f}, exit {exit_fit:.2f}"))
            if cut_only:
                continue

            # The blend: 16 bars of overlap, then the swap, then 16 more. The swap wants a line on both.
            for swap in (16, 8):
                sw_a, sw_b = x + swap, e + swap
                if sw_a + 16 >= a.bars + 8 or sw_b + 16 >= b.bars:
                    continue
                if not fb.is_main(sw_b, sw_b + 8):
                    continue
                # B's lead-in shouldn't carry a vocal or a bassline that's going to be muted anyway for long.
                if fa.strength(sw_a) < 0.45 or fb.strength(sw_b) < 0.45:
                    continue
                c, shift = harmony_options(a, b, (x, sw_a), (e, sw_b))
                c2, _ = harmony_options(a, b, (sw_a, sw_a + 8), (sw_b, sw_b + 8))
                harmony = 0.5 * (c + c2)
                arrives = fb.strength(sw_b) * 0.6 + fb.drop_quality(sw_b) * 0.4
                leaving = 1 - fa.mean(fa.vocal, sw_a, sw_a + 8)
                score = 1.2 * exit_fit + 1.0 * arrives + 1.0 * fb.early(e) + 0.8 * leaving + 1.2 * harmony - stretch * 3 + (0.1 if swap == 16 else 0)
                out.append(dict(move="bass_swap", a_exit=x, b_entry=e, swap=swap, tail=16, score=score, shift=shift, harmony_ok=harmony > 0.2,
                                harmony=harmony, why=f"harmony {harmony:.2f}, arrives {arrives:.2f}, leaving {leaving:.2f}, exit {exit_fit:.2f}"))

            # The tease: B's vocal over A's instrumental for 8 bars, and B's drop right after.
            if drop > 0 and e >= 8 and fb.mean(fb.vocal, e - 8, e) > 0.35 and x + 8 < a.bars and fa.is_main(x, x + 8):
                best = max((bar_consonance(a.bar_chroma[x:x + 8], b.bar_vchroma[e - 8:e], s) - (0.04 if s else 0), s) for s in (0, 1, -1))
                if best[0] > 0.2:
                    score = 1.2 * exit_fit + 1.2 * drop + 1.0 * fb.early(e) + 1.5 * best[0] + 0.5 * fb.mean(fb.vocal, e - 8, e) + 0.3
                    out.append(dict(move="vocal_tease", a_exit=x, b_entry=e, bars=8, score=score, shift=best[1], harmony=best[0],
                                    why=f"vocal fits {best[0]:.2f}, sings {fb.mean(fb.vocal, e - 8, e):.2f}, drop {drop:.2f}"))

            # The ride: A's vocal over B's instrumental for 8 bars.
            if fb.is_main(e, e + 8) and x + 8 < a.bars and fa.mean(fa.vocal, x, x + 8) > 0.35 and fb.mean(fb.vocal, e, e + 8) < 0.5:
                best = max((bar_consonance(b.bar_chroma[e:e + 8], a.bar_vchroma[x:x + 8], s) - (0.04 if s else 0), -s) for s in (0, 1, -1))
                if best[0] > 0.2:
                    score = 1.2 * exit_fit + 1.0 * fb.early(e) + 1.5 * best[0] + 0.6 * fa.mean(fa.vocal, x, x + 8) + 0.6 * drop + 0.5 * enter_fit + 0.3
                    out.append(dict(move="acapella_ride", a_exit=x, b_entry=e, bars=8, score=score, shift=best[1], harmony=best[0],
                                    why=f"vocal fits {best[0]:.2f}, sings {fa.mean(fa.vocal, x, x + 8):.2f}"))
    out.sort(key=lambda c: -c["score"])
    return out


def shortlist(a, b, earliest=0, per_move=6):
    """The best few distinct options for each move, to audition."""
    chosen, seen = {}, set()
    for c in candidates(a, b, earliest):
        key = (c["move"], c["a_exit"], c["b_entry"], c.get("swap"))
        if key in seen:
            continue
        seen.add(key)
        group = chosen.setdefault(c["move"], [])
        if len(group) < per_move:
            group.append(c)
    return chosen


def control(a, b):
    """The baseline: one long fade over A's last proper phrase, on the line, with B's full band in by the end of it.
    Starting B at bar 0 fades a club section into an intro that can have no drums for over a minute, which sounds far
    too slow at any tempo, and makes every move look better than it is."""
    fa, fb = Features(a), Features(b)
    last = [x for x in fa.lines if x + 16 <= a.bars - 2]
    full = [x for x in fb.lines if fb.is_main(x, x + 8)]
    entry = max(0, full[0] - 16) if full else 0
    return dict(move="crossfade", a_exit=last[-1] if last else max(0, a.bars - 24), b_entry=entry, bars=16, score=0, shift=0, why="the control")
