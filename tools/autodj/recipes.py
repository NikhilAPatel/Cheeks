"""Transition moves, written as Scores.

Rules every move keeps: one bassline at a time, and it changes hands on a downbeat. One kick at a time,
since two rarely sit together. Two vocals never overlap. Harmony only overlaps when the planner says the
two parts agree. Moves that don't overlap anything work between any two tracks.

Times are in mix beats. `T` is where the move starts (or, for a drop, where the new track lands).
"""
from engine import VOCALS, MELODY, BASS, DRUMS
from perform import Score

ALL = (VOCALS, MELODY, BASS, DRUMS)


def stem(s):
    return f"stem:{s}"


def prime_b(score, b, entry_bar, land_beat, lead=8):
    """Starts the incoming deck silently ahead of its landing, so the stretcher's settled when it's heard."""
    for s in ALL:
        score.set(0, "B", stem(s), 0)
    lead_bars = min(lead // 4, entry_bar)
    score.at(max(0, land_beat - lead_bars * 4), "B", "start", entry_bar, land_beat)


def crossfade(a, b, plan):
    """The control: what a basic automix does. Beat-matched, on a phrase line, and one long fade."""
    bars = plan.get("bars", 16)
    T, end = plan["pre"] * 4, (plan["pre"] + bars) * 4
    s = Score("Crossfade")
    s.set(0, "B", "fader:", 0)
    s.at(T - min(2, plan["b_entry"]) * 4, "B", "start", plan["b_entry"], T)
    s.ramp(T, end, "B", "fader:", 0, 0.85, "out")
    s.ramp(T, end, "A", "fader:", 0.85, 0, "in")
    s.at(end, "A", "stop")
    s.note(T, "Fade starts")
    return s, end + plan["post"] * 4


def bass_swap(a, b, plan):
    """The club blend. The new track's hats and percussion creep in, the basslines trade on a downbeat
    at the top of a phrase, then the old track's top end leaves."""
    swap, tail = plan.get("swap", 16), plan.get("tail", 16)
    T = plan["pre"] * 4
    S = T + swap * 4
    half = S + tail * 2
    E = S + tail * 4
    s = Score("Bass swap")
    prime_b(s, b, plan["b_entry"], T)
    s.set(0, "B", "eq:low", -1)
    s.note(T, "New hats creep in")
    s.ramp(T, T + swap * 2, "B", stem(DRUMS), 0, 0.9, "in")
    if plan.get("harmony_ok"):
        s.note(T + swap * 2, "New melody slides under")
        s.ramp(T + swap * 2, S, "B", stem(MELODY), 0, 0.65, "in")
        s.ramp(T + swap * 2, S, "A", stem(MELODY), 1, 0.75)
    # The old bass drops out for the last two beats, which is what makes the swap land.
    s.ramp(S - 2, S - 1.75, "A", stem(BASS), 1, 0)
    s.note(S, "Basslines swap")
    s.set(S, "A", "eq:low", -1)
    s.set(S, "B", "eq:low", 0)
    s.set(S, "B", stem(BASS), 1)
    s.set(S, "B", stem(DRUMS), 1)
    if plan.get("harmony_ok"):
        s.ramp(S, half, "B", stem(MELODY), 0.65, 1)
        s.ramp(S, half, "A", stem(MELODY), 0.75, 0, "s")
    else:
        s.note(S, "Melodies swap")
        s.set(S, "B", stem(MELODY), 1)
        s.set(S, "A", stem(MELODY), 0)
    s.ramp(S, half, "A", stem(VOCALS), 1, 0, "s")
    s.ramp(S, E, "A", "filter:", 0, 0.35)
    s.ramp(half, half + 4, "B", stem(VOCALS), 0, 1)
    s.ramp(half, E, "A", stem(DRUMS), 1, 0)
    s.at(E, "A", "stop")
    return s, E + plan["post"] * 4


def loop_drop(a, b, plan):
    """The build. The old track folds into smaller and smaller loops while it thins and rises, breathes
    for one beat, and the new track's drop lands. It needs nothing to agree, so it works between anything."""
    L = plan["a_exit"]
    T0 = plan["pre"] * 4
    bar = a.beat_frames * 4
    start = a.bar_frame(L)
    s = Score("Loop build into a drop")
    # 4 bars as played, then the loop: 4, 2+2, 1+1, 1/2+1/2, 1/4 x 4.
    D = T0 + 16 * 4
    prime_b(s, b, plan["b_entry"], D)
    s.note(T0 + 16, "Loop: 4 bars")
    s.at(T0 + 0.02, "A", "loop", start, start + 4 * bar)
    s.at(T0 + 32.02, "A", "loop", start, start + 2 * bar)
    s.note(T0 + 32, "Loop: 2 bars")
    s.at(T0 + 48.02, "A", "loop", start, start + bar)
    s.note(T0 + 48, "Loop: 1 bar")
    s.at(T0 + 56.02, "A", "loop", start, start + bar / 2)
    s.note(T0 + 56, "Loop: half a bar")
    s.at(T0 + 60.02, "A", "loop", start, start + bar / 4)
    s.note(T0 + 60, "Loop: one beat")
    s.ramp(T0 + 32, D - 1, "A", stem(BASS), 1, 0, "out")
    s.ramp(T0 + 16, D - 1, "A", "filter:", 0, 0.55, "in")
    s.set(T0 + 48, "A", "eq:low", -1)
    s.at(T0 + 48, "A", "fx", 0, "reverb", True, 2.0, 0.55)
    s.ramp(T0 + 32, D - 1, "A", "color:noise", 0, 0.6, "in")
    s.note(D - 1, "One beat of air")
    s.at(D - 1, "A", "cut")
    s.set(D - 1, "A", "color:noise", 0)
    s.note(D, "New track drops")
    for st in ALL:
        s.set(D, "B", stem(st), 1)
    s.ramp(D, D + 16, "A", "fader:", 0.85, 0, "s")
    s.at(D + 16, "A", "stop")
    return s, D + plan["post"] * 4


def echo_drop(a, b, plan):
    """The throw. The last beats go into an echo, the track cuts, and the new one lands under the repeats."""
    T = plan["pre"] * 4
    s = Score("Echo throw into a drop")
    prime_b(s, b, plan["b_entry"], T)
    s.note(T - 2, "Echo opens")
    s.at(T - 2, "A", "fx", 0, "echo", True, 0.75, 0.8)
    s.at(T, "A", "cut")
    s.note(T, "New track lands")
    for st in ALL:
        s.set(T, "B", stem(st), 1)
    s.ramp(T + 8, T + 32, "A", "fader:", 0.85, 0, "linear")
    s.at(T + 32, "A", "stop")
    return s, T + plan["post"] * 4


def brake_drop(a, b, plan):
    """The stop. The platter dies over a bar and the new track slams in. Tempo and key don't matter at all."""
    T = plan["pre"] * 4
    s = Score("Brake into a drop")
    prime_b(s, b, plan["b_entry"], T)
    s.note(T - 4, "Brake")
    s.at(T - 4, "A", "brake", 4.0)
    s.note(T, "New track slams in")
    for st in ALL:
        s.set(T, "B", stem(st), 1)
    s.at(T + 4, "A", "stop")
    return s, T + plan["post"] * 4


def vocal_tease(a, b, plan):
    """The tease. The new track's vocal rides over the old track's instrumental for a phrase, so the crowd
    hears what's coming before the new track's beat arrives. Needs the vocal to agree with the old harmony."""
    bars = plan.get("bars", 8)
    T = plan["pre"] * 4
    D = T + bars * 4
    s = Score("Vocal tease")
    prime_b(s, b, plan["b_entry"] - bars, T)
    s.note(T, "New vocal over the old beat")
    s.ramp(T - 2, T, "A", stem(VOCALS), 1, 0)
    s.ramp(T - 2, T + 1, "B", stem(VOCALS), 0, 1)
    s.set(D - 2, "A", stem(BASS), 0)
    s.note(D, "New track drops under its own vocal")
    for st in (MELODY, BASS, DRUMS):
        s.set(D, "B", stem(st), 1)
    for st in (MELODY, DRUMS):
        s.set(D, "A", stem(st), 0)
    s.at(D + 4, "A", "stop")
    return s, D + plan["post"] * 4


def acapella_ride(a, b, plan):
    """The ride. On a downbeat the whole track changes underneath the singer: the old vocal carries on over
    the new track's instrumental, then gets thrown into an echo. This is the mashup moment."""
    bars = plan.get("bars", 8)
    T = plan["pre"] * 4
    E = T + bars * 4
    s = Score("Vocal rides onto the new track")
    prime_b(s, b, plan["b_entry"], T)
    s.note(T, "Track changes under the vocal")
    s.ramp(T - 1, T - 0.75, "A", stem(BASS), 1, 0)
    for st in (MELODY, DRUMS):
        s.set(T, "A", stem(st), 0)
    for st in (MELODY, BASS, DRUMS):
        s.set(T, "B", stem(st), 1)
    s.at(E - 2, "A", "fx", 0, "echo", True, 0.75, 0.8)
    s.note(E - 2, "Vocal thrown to the echo")
    s.at(E, "A", "cut")
    s.ramp(E, E + 2, "B", stem(VOCALS), 0, 1)
    s.ramp(E + 8, E + 24, "A", "fader:", 0.85, 0)
    s.at(E + 24, "A", "stop")
    return s, E + plan["post"] * 4


MOVES = {
    "crossfade": crossfade,
    "bass_swap": bass_swap,
    "loop_drop": loop_drop,
    "echo_drop": echo_drop,
    "brake_drop": brake_drop,
    "vocal_tease": vocal_tease,
    "acapella_ride": acapella_ride,
}
