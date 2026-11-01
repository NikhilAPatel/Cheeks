#!/usr/bin/env python3
"""Plans transitions between two tracks, renders the options, and keeps the first of each move that passes.

    audition.py OUT_DIR TRACK_A TRACK_B
"""
import json, os, sys
import numpy as np
import critic as C, engine as E, perform as P, plan as L, recipes as R

PITCH = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]


def perform(a, b, candidate, pre=8, post=8):
    c = dict(candidate)
    pre = min(pre, c["a_exit"])
    c.update(pre=pre, post=post)
    score, length = R.MOVES[c["move"]](a, b, c)
    audio, report = P.Performance(a, b, c["a_exit"] - pre, length, b_shift=c.get("shift", 0)).render(score)
    drop_at = {"loop_drop": pre + 16, "echo_drop": pre, "brake_drop": pre, "vocal_tease": pre + c.get("bars", 8), "acapella_ride": pre}.get(c["move"])
    passes, problems, numbers = C.review(audio, report, pre, 60 / a.bpm * 4, drop_at)
    meta = dict(c, **report, passes=passes, problems=problems, numbers=numbers, title=score.name, a=a.name, b=b.name, a_bpm=a.bpm, b_bpm=b.bpm,
                key_a=f"{PITCH[a.key_root]} {a.key_mode}", key_b=f"{PITCH[b.key_root]} {b.key_mode}",
                notes=[(t * 60 / a.bpm, text) for t, text in sorted(score.notes)])
    return audio, meta


def audition(a, b, out_dir, verbose=True):
    """Each move's first passing option, best first. Everything tried is reported."""
    kept = []
    for move, options in L.shortlist(a, b).items():
        for tried, option in enumerate(options):
            audio, meta = perform(a, b, option)
            line = f"  {move:14s} {option['score']:.2f} A {option['a_exit']:3d} B {option['b_entry']:3d} {option.get('why', '')[:60]:60s} {meta['numbers']['change']:+.1f} dB"
            if meta["passes"]:
                meta["tried"] = tried + 1
                meta["name"] = f"{a.name}__{b.name}__{move}"
                P.write_audio(f"{out_dir}/{meta['name']}.wav", audio)
                json.dump(meta, open(f"{out_dir}/{meta['name']}.json", "w"), indent=1, default=float)
                kept.append(meta)
                if verbose:
                    print(line + " kept", flush=True)
                break
            if verbose:
                print(line + " | " + "; ".join(meta["problems"])[:70], flush=True)
    audio, meta = perform(a, b, L.control(a, b))
    meta["name"] = f"{a.name}__{b.name}__crossfade"
    P.write_audio(f"{out_dir}/{meta['name']}.wav", audio)
    json.dump(meta, open(f"{out_dir}/{meta['name']}.json", "w"), indent=1, default=float)
    return kept, meta


if __name__ == "__main__":
    out_dir, a_name, b_name = sys.argv[1:4]
    os.makedirs(out_dir, exist_ok=True)
    a, b = P.Track(a_name), P.Track(b_name)
    print(f"{a.name} {a.bpm:.1f} {PITCH[a.key_root]} {a.key_mode} -> {b.name} {b.bpm:.1f} {PITCH[b.key_root]} {b.key_mode}", flush=True)
    kept, control = audition(a, b, out_dir)
    print(f"  kept {len(kept)}: " + ", ".join(m["move"] for m in kept))
