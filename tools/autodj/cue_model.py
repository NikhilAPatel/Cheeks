#!/usr/bin/env python3
"""A second opinion on where DJs mix: CUE-DETR (ETH Zurich, ISMIR 2024, MIT licence), trained on 21k cue points
placed by four professional DJs. Same preprocessing as their cue_points.py, in batches, on the GPU.

    cue_model.py NAME [NAME ...]    writes tracks/NAME/cues.json
"""
import json, os, sys
import librosa
import numpy as np
import torch
from matplotlib import cm
from scipy.signal import find_peaks
from transformers import DetrForObjectDetection, DetrImageProcessor

CACHE = os.environ.get("CHEEKS_AUTODJ_CACHE", os.path.expanduser("~/Library/Caches/cheeks-autodj"))
OVERLAP, WIN, PADDING = 0.75, 355, 266
SENSITIVITY, RADIUS = 0.9, 16


def windows(path):
    y, _ = librosa.load(path)
    db = librosa.power_to_db(librosa.feature.melspectrogram(y=y, sr=22050, n_fft=2048), ref=np.max)[::-1]
    mapper = cm.ScalarMappable(cmap="viridis")
    mapper.set_clim(db.min(), db.max())
    image = mapper.to_rgba(db, bytes=True)[:, :, :3]
    step = WIN * (1 - OVERLAP)
    for i in range(int((image.shape[1] + PADDING) // step)):
        left = int(i * step) - PADDING
        right = left + WIN
        if left < 0:
            part = np.pad(image[:, :right], ((0, 0), (-left, 0), (0, 0)), mode="linear_ramp")
        elif right > image.shape[1]:
            part = image[:, left:]
            part = np.pad(part, ((0, 0), (0, right - left - part.shape[1]), (0, 0)), mode="linear_ramp")
        else:
            part = image[:, left:right]
        yield left, part


def main():
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    processor = DetrImageProcessor.from_pretrained("facebook/detr-resnet-50")
    model = DetrForObjectDetection.from_pretrained("disco-eth/cue-detr").to(device).eval()
    for name in sys.argv[1:]:
        out = f"{CACHE}/tracks/{name}/cues.json"
        if os.path.exists(out):
            continue
        positions, scores, batch, lefts = [], [], [], []

        def flush():
            encoding = processor.preprocess(batch, do_resize=False, return_tensors="pt")
            with torch.no_grad():
                outputs = model(encoding["pixel_values"].to(device))
            outputs.logits, outputs.pred_boxes = outputs.logits.cpu(), outputs.pred_boxes.cpu()
            for p, left in zip(processor.post_process_object_detection(outputs, 0, [(128, WIN)] * len(batch)), lefts):
                scores.extend(p["scores"].tolist())
                positions.extend((((p["boxes"][:, 0] + p["boxes"][:, 2]) // 2) + left).long().tolist())
            batch.clear(); lefts.clear()

        for left, part in windows(f"{CACHE}/music/{name}.mp3"):
            batch.append(part); lefts.append(left)
            if len(batch) == 16:
                flush()
        if batch:
            flush()
        scaled = (np.array(scores) - min(scores)) / (max(scores) - min(scores))
        order = np.argsort(positions, kind="stable")
        positions, scaled = np.array(positions)[order], scaled[order]
        peaks, _ = find_peaks(scaled, height=SENSITIVITY, distance=RADIUS)
        times = librosa.frames_to_time(positions[peaks]).tolist()
        json.dump({"times": times, "scores": scaled[peaks].tolist()}, open(out, "w"))
        print(name, len(times), [round(t, 1) for t in times], flush=True)


if __name__ == "__main__":
    main()
