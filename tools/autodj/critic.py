"""What can be checked about a transition without ears: its loudness arc, and whether it lands.

This is not taste. It catches let-downs and holes, so nobody has to listen to the obvious failures, and
it's the first half of an audition: render the best few options, keep the ones that pass, then rank.
"""
import numpy as np
from scipy import signal
import engine as E


def bar_loudness(audio, seconds_per_bar):
    """K-ish weighted level per bar in dB: a quick stand-in for short-term loudness."""
    sr = int(E.SR)
    mono = audio.mean(axis=1)
    sos = signal.butter(2, 60 / (sr / 2), "high", output="sos")
    x = signal.sosfilt(sos, mono)
    n = int(seconds_per_bar * sr)
    return np.array([10 * np.log10(np.mean(x[i * n:(i + 1) * n] ** 2) + 1e-9) for i in range(len(x) // n)])


def review(audio, report, pre_bars, seconds_per_bar, landing_bar=None):
    """Returns (passes, problems, numbers). `landing_bar` is the mix bar where a drop lands, if the move has one."""
    levels = bar_loudness(audio, seconds_per_bar)
    before = float(np.median(levels[: max(1, pre_bars)]))
    tail = levels[-max(2, min(8, len(levels) // 4)) :]
    after = float(np.median(tail))
    middle = levels[pre_bars: max(pre_bars + 1, len(levels) - len(tail))]
    numbers = dict(before=before, after=after, change=after - before, lowest=float(middle.min()) - before, highest=float(middle.max()) - before,
                   limiter=report["limiter_max"], lock_ms=abs(report.get("lock_error_ms") or 0))
    problems = []
    if numbers["change"] < -1.5:
        problems.append(f"new track sits {-numbers['change']:.1f} dB below the old one")
    if numbers["change"] > 3:
        problems.append(f"new track jumps {numbers['change']:.1f} dB above the old one")
    if numbers["highest"] > 3:
        problems.append(f"bump of {numbers['highest']:.1f} dB in the middle")
    if landing_bar is None and numbers["lowest"] < -5:
        problems.append(f"hole of {-numbers['lowest']:.1f} dB in the middle")
    if landing_bar is not None and landing_bar < len(levels):
        landed = float(np.median(levels[landing_bar: landing_bar + 4]))
        numbers["landing"] = landed - before
        if landed - before < -1.5:
            problems.append(f"drop lands {before - landed:.1f} dB under what came before it")
    if numbers["limiter"] > 3:
        problems.append(f"limiter pushed {numbers['limiter']:.1f} dB")
    if numbers["lock_ms"] > 0.5:
        problems.append(f"decks {numbers['lock_ms']:.1f} ms apart")
    return not problems, problems, numbers
