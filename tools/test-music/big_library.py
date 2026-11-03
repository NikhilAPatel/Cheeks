#!/usr/bin/env python3
"""Writes a library.json of made-up tracks, with no audio behind them, for seeing how the app copes with a big collection.

   big_library.py <library.json to write> <number of tracks>
"""
import json
import random
import sys
import uuid

out, count = sys.argv[1], int(sys.argv[2])
rng = random.Random(7)
kinds = ["INTRO", "CHORUS", "VERSE", "DOWN", "UP", "CHORUS", "OUTRO"]
tracks = []
for i in range(count):
    track_id = str(uuid.UUID(int=rng.getrandbits(128))).upper()
    duration = 180 + rng.random() * 240
    tracks.append({
        "id": track_id,
        "title": f"Track {i}",
        "artist": f"Artist {i % 200}",
        "fileName": f"{track_id}.mp3",
        "originalFileName": f"track{i}.mp3",
        "duration": duration,
        "bpm": 118 + rng.random() * 14,
        "firstBeat": rng.random() / 2,
        "key": f"{rng.randint(1, 12)}{rng.choice('AB')}",
        "loudness": -8 - rng.random() * 6,
        "gridSource": "drums",
        "dateAdded": 815000000 + i * 60.0,
        "playCount": rng.randint(0, 20),
        "rating": 0,
        "hotCues": {},
        "hotCueInfo": {},
        "memoryCues": [],
        "savedLoops": [],
        "phrases": [{"start": duration * n / len(kinds), "kind": kind} for n, kind in enumerate(kinds)],
    })
with open(out, "w") as file:
    json.dump({"tracks": tracks, "playlists": []}, file)
print(f"{count} tracks written")
