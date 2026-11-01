#!/usr/bin/env python3
"""Splits tracks into stems with the app's own Swift pipeline and model (tools/stems/swift_eval), cached for the lab.

Stems end up as int16 at the app's headroom, shape (4, frames, 2), in `Stem.allCases` order: vocals, melody, bass, drums.

    split_stems.py file.mp3 [file.mp3 ...]
"""
import json, os, shutil, subprocess, sys
import numpy as np

CACHE = os.environ.get("CHEEKS_AUTODJ_CACHE", os.path.expanduser("~/Library/Caches/cheeks-autodj"))
HARNESS = os.path.expanduser("~/Library/Caches/cheeks-stems/harness/swift_eval")
MODEL = os.path.expanduser("~/Library/Caches/cheeks-stems/compiled/Stems.mlmodelc")
SR = 44100
STEMS = ["vocals", "melody", "bass", "drums"]


def main():
    todo = [p for p in sys.argv[1:] if not os.path.exists(f"{CACHE}/tracks/{os.path.splitext(os.path.basename(p))[0]}/stems.npy")]
    work = f"{CACHE}/split-work"
    for path in todo:
        name = os.path.splitext(os.path.basename(path))[0]
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(f"{work}/in")
        subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "2", "-ar", str(SR), f"{work}/in/{name}.pcm"], check=True)
        frames = os.path.getsize(f"{work}/in/{name}.pcm") // 4
        log = subprocess.run([HARNESS, MODEL, "cpuAndGPU", f"{work}/in", f"{work}/out"], check=True, capture_output=True, text=True).stdout
        out = f"{CACHE}/tracks/{name}"
        os.makedirs(out, exist_ok=True)
        stems = np.stack([np.fromfile(f"{work}/out/{name}.{s}.pcm", dtype=np.int16).reshape(-1, 2) for s in STEMS])
        assert stems.shape == (4, frames, 2)
        np.save(f"{out}/stems.tmp.npy", stems)
        os.rename(f"{out}/stems.tmp.npy", f"{out}/stems.npy")
        json.dump({"source": os.path.abspath(path), "seconds": frames / SR}, open(f"{out}/track.json", "w"))
        print(log.strip().splitlines()[-1], flush=True)
    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
