# Analysis cross-checks (Python)

These are numpy/scipy ports of the app's DSP, used to verify algorithms without a Swift compiler. They're also a quick way to try out an analysis change before porting it to Swift.

- `analysis_port.py`: biquad helpers and Krumhansl key profiles, plus the original array-based tempo and key detection.
- `swift_synth_check.py`: port of `CheeksTests/Synth.swift` (deterministic synthetic tracks).
- `streaming_check.py`: port of the **current** `TrackAnalyzer.analyze(PCM16Stereo)` streaming pipeline on Int16 input, and the stem-sum check with `stemHeadroom`.

```sh
pip install numpy scipy
python3 streaming_check.py   # every line should end in OK
```

If you change `TrackAnalyzer`, `KeyDetector` or `FrequencySplitSeparator`, update the matching port and re-run it. Keep the expected values in `CheeksTests/AnalysisTests.swift` in sync.
