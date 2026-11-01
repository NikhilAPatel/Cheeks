#!/usr/bin/env python3
"""Encodes chosen renders for the Listening Room and writes its list of takes.

    make_page.py RENDERS OUT VERSION
"""
import json, os, random, subprocess, sys

PAIRS = [
    ("jam181344", "jam1280420", ["crossfade", "bass_swap", "loop_drop", "vocal_tease", "echo_drop"]),
    ("jam1280420", "jam728914", ["crossfade", "bass_swap", "acapella_ride", "loop_drop", "brake_drop"]),
    ("jam1308620", "jam1197771", ["crossfade", "loop_drop", "bass_swap", "acapella_ride"]),
    ("jam1280420", "jam1072904", ["crossfade", "bass_swap", "acapella_ride", "loop_drop", "echo_drop"]),
]
BLURB = {
    "crossfade": "The control: beat-matched and on a phrase line, with one long fade. This is what a basic automix does.",
    "bass_swap": "The club blend: the new track's hats creep in, the basslines trade on a downbeat, then the old track's top end leaves.",
    "loop_drop": "The build: the old track folds into shorter and shorter loops while it thins and rises, breathes for one beat, then the new track drops.",
    "vocal_tease": "The tease: the new track's vocal rides over the old track's beat for 8 bars before its own beat arrives.",
    "acapella_ride": "The ride: on a downbeat the whole track changes under the singer, and the old vocal is thrown into an echo 8 bars later.",
    "echo_drop": "The throw: the last beats go into an echo, the track cuts, and the new one lands under the repeats.",
    "brake_drop": "The stop: the platter dies over a bar and the new track slams in.",
}


def main():
    renders, out, version = sys.argv[1:4]
    os.makedirs(f"{out}/clips", exist_ok=True)
    os.makedirs(f"{out}/strips", exist_ok=True)
    rng = random.Random(11)
    pairs = []
    for a, b, moves in PAIRS:
        takes = []
        order = moves[:]
        rng.shuffle(order)
        for i, move in enumerate(order):
            name = f"{a}__{b}__{move}"
            m = json.load(open(f"{renders}/{name}.json"))
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", f"{renders}/{name}.wav", "-codec:a", "libmp3lame", "-q:a", "3", f"{out}/clips/{name}.mp3"], check=True)
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", f"{renders}/{name}.png", "-vf", "scale=1200:-1", "-q:v", "6", f"{out}/strips/{name}.jpg"], check=True)
            first = m["notes"][0][0] if m["notes"] else 0
            takes.append(dict(id=f"{name}__{version}", file=name, label=f"Take {i + 1}", move=m["title"], blurb=BLURB[move], seconds=m["seconds"], notes=m["notes"],
                              start=max(0, first - 60 / m["a_bpm"] * 16), a_exit=m["a_exit"], b_entry=m["b_entry"], tried=m.get("tried", 1)))
        m = json.load(open(f"{renders}/{a}__{b}__{moves[0]}.json"))
        pairs.append(dict(a=a[3:], b=b[3:], a_bpm=m["a_bpm"], b_bpm=m["b_bpm"], key_a=m["key_a"], key_b=m["key_b"], takes=takes))
    json.dump(pairs, open(f"{out}/pairs.json", "w"), separators=(",", ":"))
    print(sum(len(p["takes"]) for p in pairs), "takes", round(sum(t["seconds"] for p in pairs for t in p["takes"]) / 60, 1), "min")


if __name__ == "__main__":
    main()
