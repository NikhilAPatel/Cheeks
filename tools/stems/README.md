# HT-Demucs on Core ML

Builds the model behind the app's real stem separation and checks it against PyTorch. Core ML can't convert Demucs's STFT/iSTFT cleanly, so the model is only the network between them. The app does the rest in Swift (`Cheeks/Stems/`).

| File | What it is |
|---|---|
| `convert.py` | Builds and checks `Stems.mlpackage` |
| `htdemucs_core.py` | The part of `HTDemucs.forward` that gets converted |
| `pipeline.py` | The whole pipeline in numpy, the model of the Swift code |
| `validate.py` | SDR on MUSDB18 for PyTorch, Core ML and Swift |
| `gen_fixtures.py` | Writes `CheeksTests/StemFixtures.swift` from PyTorch and demucs |
| `compute_plan.py` | Which compute device runs each op (`MLComputePlan`) |
| `swift_eval/`, `build_harness.sh` | The app's Swift pipeline as a Mac command-line tool |

## Setup

Everything large stays out of the repo, in `~/Library/Caches/cheeks-stems/`. Python 3.11, plus `ffmpeg` from Homebrew for the validation.

```sh
uv venv --python 3.11 ~/Library/Caches/cheeks-stems/venv
VIRTUAL_ENV=~/Library/Caches/cheeks-stems/venv uv pip install -r tools/stems/requirements.txt
```

The commands below call this environment's `python` directly. The checkpoint downloads on first use (84 MB, pinned by SHA-256). It comes from Meta's original URL and not from the HuggingFace copy demucs would otherwise pick, though the two hold identical weights.

## Build the model

```sh
PY=~/Library/Caches/cheeks-stems/venv/bin/python
$PY tools/stems/convert.py          # fp16, to ~/Library/Caches/cheeks-stems/models/Stems.mlpackage
cp -R ~/Library/Caches/cheeks-stems/models/Stems.mlpackage Cheeks/Stems.mlpackage
```

`Cheeks/Stems.mlpackage` is git-ignored. Xcode compiles it into the app bundle as `Stems.mlmodelc`, and without it the app falls back to `FrequencySplitSeparator`. `convert.py` refuses a result too far from PyTorch. Repeat conversions give an identical program and weights.

**Interface:**
- Inputs: `mix` `[1, 2, 343980]` and `spec` `[1, 4, 2048, 336]` (L.re, L.im, R.re, R.im).
- Outputs: `spec_out` `[1, 4, 4, 2048, 336]` and `time_out` `[1, 4, 2, 343980]`.
- Sources are in the order drums, bass, other, vocals.
- The normalisation `forward` applies internally is included. Apart from that the inputs are what `_spec`/`_magnitude` produce, and the outputs still need the iSTFT.

## Validate

```sh
$PY tools/stems/validate.py ref                                  # PyTorch reference, cached
$PY tools/stems/validate.py coreml fp16_gpu ~/Library/Caches/cheeks-stems/models/Stems.mlpackage CPU_AND_GPU

sh tools/stems/build_harness.sh
xcrun coremlcompiler compile ~/Library/Caches/cheeks-stems/models/Stems.mlpackage ~/Library/Caches/cheeks-stems/compiled
$PY tools/stems/validate.py export ~/Library/Caches/cheeks-stems/pcm
~/Library/Caches/cheeks-stems/harness/swift_eval ~/Library/Caches/cheeks-stems/compiled/Stems.mlmodelc cpuAndGPU \
    ~/Library/Caches/cheeks-stems/pcm ~/Library/Caches/cheeks-stems/swiftout
$PY tools/stems/validate.py swift swift_gpu ~/Library/Caches/cheeks-stems/swiftout

$PY tools/stems/validate.py report fp16_gpu swift_gpu
```

## Measured results

Everything here was measured on an M1 Pro (10 CPU cores, 32 GB). **Nothing has been measured on a phone yet.**

### Quality

SDR in dB, the MDX definition over the whole clip, averaged over clips. The clips are the 50 MUSDB18 test previews joined five at a time into 10 clips of about 34 s, so the segment loop and overlap-add are exercised. Reference: `apply_model(shifts=0, overlap=0.25)`.

| | drums | bass | other | vocals | mean |
|---|---|---|---|---|---|
| PyTorch `apply_model` | 8.805 | 6.915 | 4.577 | 7.986 | 7.071 |
| PyTorch, with the residual added to other | 8.805 | 6.915 | 4.504 | 7.986 | 7.052 |
| Core ML + numpy, fp32, GPU | 8.805 | 6.915 | 4.577 | 7.986 | 7.071 |
| Core ML + numpy, fp16, GPU | 8.805 | 6.914 | 4.577 | 7.986 | 7.071 |
| Core ML + numpy, fp16, CPU | 8.800 | 6.915 | 4.576 | 7.987 | 7.070 |
| **Swift, fp16, GPU** (with residual) | 8.805 | 6.914 | 4.504 | 7.986 | 7.052 |
| **Swift, fp16, CPU** (with residual) | 8.799 | 6.917 | 4.504 | 7.988 | 7.052 |
| Core ML + numpy, fp16, Neural Engine | 1.173 | -0.204 | 1.816 | 4.617 | 1.850 |

- The separate 7-second previews (50 clips, each shorter than a segment) give the same picture. Swift fp16 on the GPU is within 0.001 dB per stem, and on the CPU within 0.016 dB.
- For scale, Demucs's own default of one random shift moves the mean by -0.018 dB on the same clips.
- Adding the residual costs "other" 0.07 dB on the long clips and 0.12 dB on the previews. It's what lets the stems sum back to the track: without it they match the mix at only 24 dB in the worst clip.

### Speed and memory (Swift pipeline)

Peak memory is the process's peak footprint with the audio buffers subtracted, and memory used inside the Neural Engine may not count towards it. Time per segment is the steady state, and each segment covers 5.85 s of new audio.

| Model | Units | Per segment | Load, cold | First prediction, cold | Peak memory | Quality |
|---|---|---|---|---|---|---|
| **fp16, 100 MB** | **`.cpuAndGPU`** | **0.25 s** | 0.7 s | 7.3 s | about 575 MB | good |
| **fp16** | **`.cpuOnly`** | **0.33 s** | 0.6 s | | about 270 MB | good |
| fp16 | `.cpuAndNeuralEngine` | 0.38 s | 35 s | | about 270 MB | **wrong** |
| fp16 | `.all` | 0.34 s | 27 s | | about 1.1 GB | **wrong** |
| fp32, 200 MB | `.cpuAndGPU` | 0.29 s | 0.7 s | 5.8 s | about 840 MB | good |
| fp32 | `.cpuOnly` | 0.61 s | 0.9 s | | about 520 MB | good |

- A 6-minute track takes 15.7 s on the GPU and 20.7 s on the CPU. Time per segment doesn't drift across the 62 segments, and memory beyond the Int16 buffers is the same as for a 34-second track.
- With Core ML's cache warm, loading takes under 0.2 s and the first GPU prediction 0.5 s.

### Which units actually run it (`MLComputePlan`)

| Model | `.cpuAndGPU` | `.cpuAndNeuralEngine` | `.all` |
|---|---|---|---|
| fp16 | all 1648 ops on the GPU | 61% of cost on the Neural Engine, 39% CPU, 48 device switches | 48% Neural Engine, 52% GPU, 28 switches |
| fp32 | all 1646 ops on the GPU | all on the CPU | all on the GPU |

## Decisions

**fp16.** Compared with fp32, it's half the size, uses 30% to 50% less memory and is faster, and it costs at most 0.02 dB on any stem's average. The checkpoint's weights are all exactly representable in fp16, so storing them that way loses nothing, and the difference comes only from computing in fp16. In level terms, the difference from the reference's output reaches at most -71 dBFS on the GPU and -57 dBFS on the CPU across all clips. The largest change to a single stem in a single clip was +0.5 dB, on the CPU.

**Never the Neural Engine.** With fp16 it returns audio that's badly wrong, 3 to 9 dB below the reference on every stem, with no error from Core ML. Comparing prefixes of the network shows it already diverging in the first encoder (19 dB of agreement with PyTorch, against 40 dB for fp16 on the CPU). The first transformer layer then takes the time branch down to 7 dB. fp32 can't run there at all. That's why the app asks for `.cpuAndGPU`: `.all` would silently bring the Neural Engine in. Only an M1 Pro's Neural Engine has been tried, so a phone's might behave differently; check with `validate.py` before trusting one.

**No time shifts.** Demucs's default of one random shift adds nothing measurable here, and it would make results non-deterministic.

**Melody is computed by subtraction.** It's the mix minus the other three stems, which equals "other" plus the residual, so the model's "other" output isn't used and one iSTFT per channel is saved.

## Weights licence

The demucs repository is MIT and its README states no separate terms for the weights. The `htdemucs` weights were trained on MUSDB18-HQ plus 800 further songs, and MUSDB18 itself is for non-commercial use. That's fine for a personal app. Get a real answer before distributing commercially.

## Tests

`CheeksTests/StemSeparationTests.swift` covers the STFT against PyTorch's numbers, the segment loop against real `apply_model` with a stand-in network, the fallback logic and the cache. Running the real model is opt-in, because the model isn't in git:

```sh
TEST_RUNNER_CHEEKS_STEM_MODEL=1 xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks \
    -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build \
    -only-testing:CheeksTests/StemModelTests
```

The simulator only has the CPU, and runs it at about 2 s per segment. Set `TEST_RUNNER_CHEEKS_STEM_INPUT` (raw stereo Int16) and `TEST_RUNNER_CHEEKS_STEM_OUTPUT` (a folder) to run a real clip and keep the stems.
