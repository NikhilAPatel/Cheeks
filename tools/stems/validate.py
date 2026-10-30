#!/usr/bin/env python3
"""SDR on real music, with ground truth, for every way of running the model.

Clips (MUSDB18 7-second previews, test subset, 50 songs):
  short    each preview on its own. Shorter than one segment, so it exercises the padding path.
  long     previews joined five at a time (about 34 s). This is the one that exercises the
           segment loop and the overlap-add.

    python validate.py ref                         # PyTorch apply_model, cached under eval/
    python validate.py coreml NAME MODEL UNITS     # Core ML + the numpy pipeline
    python validate.py export DIR                  # raw PCM for the Swift harness
    python validate.py swift NAME DIR              # score the harness's output
    python validate.py report [NAME ...]

The reference and every candidate get the same input, the mix after quantising to Int16 (what the
app holds in memory).
"""

import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import pipeline as P  # noqa: E402

EVAL = os.path.join(common.CACHE, "eval")
GROUP = 5


def clips():
    """Yields (clip name, mix [2,n] from Int16, truth [4,2,n] in SOURCES order)."""
    tracks = list(common.musdb_tracks())
    for name, mix, sources in tracks:
        yield "short/" + name, P.from_int16(P.to_int16(mix)), np.stack([sources[s] for s in P.SOURCES])
    for g in range(0, len(tracks), GROUP):
        group = tracks[g : g + GROUP]
        mix = np.concatenate([t[1] for t in group], axis=-1)
        truth = np.concatenate([np.stack([t[2][s] for s in P.SOURCES]) for t in group], axis=-1)
        yield f"long/{g // GROUP:02d}", P.from_int16(P.to_int16(mix)), truth


def results_path(name):
    return os.path.join(EVAL, name)


def save(name, clip, stems):
    path = os.path.join(results_path(name), clip.replace("/", "__") + ".npy")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    np.save(path, stems.astype(np.float32))


def load(name, clip):
    return np.load(os.path.join(results_path(name), clip.replace("/", "__") + ".npy"), mmap_mode="r")


def add_residual(stems, mix):
    out = np.array(stems)
    out[P.SOURCES.index("other")] += mix - stems.sum(0)
    return out


def run_ref(shifts=0):
    import torch
    from demucs.apply import apply_model
    from htdemucs_core import load_htdemucs

    model = load_htdemucs()
    name = "ref" if shifts == 0 else f"ref_shift{shifts}"
    for clip, mix, _ in clips():
        wav = torch.from_numpy(mix)
        ref = wav.mean(0)
        mean, std = ref.mean(), ref.std() + 1e-8
        t = time.time()
        with torch.no_grad():
            torch.manual_seed(0)
            out = apply_model(model, ((wav - mean) / std)[None], shifts=shifts, split=True, overlap=0.25, device="cpu")
        stems = (out * std + mean)[0].numpy()
        save(name, clip, stems)
        print(clip, f"{time.time() - t:.1f}s", flush=True)


def run_coreml(name, package, unit_name):
    import coremltools as ct

    t = time.time()
    model = ct.models.MLModel(package, compute_units=getattr(ct.ComputeUnit, unit_name))
    print("load", round(time.time() - t, 1), flush=True)
    predict = P.coreml_predictor(model)
    segments = 0

    def counted(chunk):
        nonlocal segments
        segments += 1
        return predict(chunk)

    t = time.time()
    for clip, mix, _ in clips():
        save(name, clip, P.separate(mix, counted))
    elapsed = time.time() - t
    print(f"{segments} segments in {elapsed:.1f}s, {elapsed / segments:.3f}s each (numpy STFT included)")


def run_export(folder):
    os.makedirs(folder, exist_ok=True)
    for clip, mix, _ in clips():
        P.to_int16(mix).T.tofile(os.path.join(folder, clip.replace("/", "__") + ".pcm"))


def run_swift(name, folder):
    for clip, mix, _ in clips():
        base = os.path.join(folder, clip.replace("/", "__"))
        stems = []
        for source in ("drums", "bass", "melody", "vocals"):
            raw = np.fromfile(f"{base}.{source}.pcm", dtype=np.int16).reshape(-1, 2).T
            stems.append(raw.astype(np.float32) / 32767 / 0.5)  # PCM16Stereo.stemHeadroom
        stems = np.stack(stems)
        assert stems.shape[-1] == mix.shape[-1], (clip, stems.shape, mix.shape)
        save(name, clip, stems)


def report(names):
    """Swift results have the residual in melody by construction, so they're compared with the
    reference after adding the residual to its `other`. Everything else is compared as it comes."""
    groups = ("short", "long")
    rows = {}
    for clip, mix, truth in clips():
        group = clip.split("/")[0]
        reference = np.asarray(load("ref", clip))
        reference_residual = add_residual(reference, mix)
        for name in ["ref", "ref+residual"] + names:
            stems = reference_residual if name == "ref+residual" else np.asarray(load(name, clip))
            baseline = reference_residual if name.startswith("swift") else reference
            row = rows.setdefault((name, group), {"sdr": [], "base": [], "null": [], "sum": []})
            row["sdr"].append([common.sdr(truth[s], stems[s]) for s in range(4)])
            row["base"].append([common.sdr(truth[s], baseline[s]) for s in range(4)])
            # How far from the reference output, in dB. Very high means numerically the same.
            row["null"].append([common.sdr(baseline[s], stems[s]) for s in range(4)])
            row["sum"].append(common.sdr(mix, stems.sum(0)))

    header = "".join(f"{s:>9s}" for s in P.SOURCES) + f"{'mean':>9s}"
    for group in groups:
        print(f"\n== {group} ({len(rows[('ref', group)]['sdr'])} clips). SDR against ground truth, dB, mean over clips")
        print(f"{'':28s}{header}")
        for name in ["ref", "ref+residual"] + names:
            m = np.mean(rows[(name, group)]["sdr"], axis=0)
            print(f"{name:28s}" + "".join(f"{v:9.3f}" for v in m) + f"{m.mean():9.3f}")
        print("Difference from its reference, dB")
        for name in names:
            per_clip = np.array(rows[(name, group)]["sdr"]) - np.array(rows[(name, group)]["base"])
            d = per_clip.mean(axis=0)
            print(f"{name:28s}" + "".join(f"{v:+9.3f}" for v in d) + f"{d.mean():+9.3f}"
                  f"   worst single stem in a clip {np.abs(per_clip).max():.3f}")
        print("Agreement with the reference's output (SDR with the reference as truth), dB, worst clip")
        for name in names:
            n = np.array(rows[(name, group)]["null"])
            print(f"{name:28s}" + "".join(f"{v:9.1f}" for v in n.min(axis=0)))
        print("Sum of the stems against the mix, dB, worst clip")
        for name in ["ref", "ref+residual"] + names:
            print(f"{name:28s}{min(rows[(name, group)]['sum']):9.1f}")


def main():
    command = sys.argv[1]
    if command == "ref":
        run_ref(int(sys.argv[2]) if len(sys.argv) > 2 else 0)
    elif command == "coreml":
        run_coreml(sys.argv[2], os.path.expanduser(sys.argv[3]), sys.argv[4])
    elif command == "export":
        run_export(sys.argv[2])
    elif command == "swift":
        run_swift(sys.argv[2], sys.argv[3])
    elif command == "report":
        report(sys.argv[2:])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
