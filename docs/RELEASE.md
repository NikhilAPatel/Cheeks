# Releasing Segue DJ

What stands between this app and the public, and who has to do what. Personal use on the owner's own phone needs only the first item.

| | What | Who | State |
|---|---|---|---|
| 1 | Pick a signing team in Xcode, and install on a phone | Owner | Done, on an iPhone 15 Pro Max. The first launch took about 20 s, which led to the fix below, not yet tried on the phone |
| 2 | The stem model's licence | Owner decides, see below | **Blocks a public release.** Set aside by the owner on 2 Nov 2026, to get the app working first. The current model stays until then |
| 3 | Speed, heat and memory on a real phone, including how long a split takes | Owner's phone, then me | Not measured. `MIX` needs a split to finish while the track before it plays |
| 4 | A real finger on small screens, and how it sounds in headphones | Owner, using `docs/TEST_PLAN.md` §2 | Not done. Everything so far is simulated touch |
| 5 | A lawyer's look at how closely the design follows one maker's gear | Owner | Not done. The name's already gone |
| 6 | Privacy manifest | | Done |
| 7 | Layouts on every iPhone | Me, then the owner's finger | Started, and rendered at small sizes |
| 8 | Auto DJ heard by the owner in the real app | Owner | Rated in the listening room only |

## The stem model's licence

**Where it stands.** The Demucs code is MIT, but the weights in `Cheeks/Stems.mlpackage` aren't clearly covered by that. They were trained partly on MUSDB18, which is for non-commercial use. The maintainer has said so directly:

- ["the pre-trained weights are mostly usable for research purpose… Making a real app of it is out of the scope of those terms"](https://github.com/facebookresearch/demucs/issues/267) (January 2022)
- ["Weights are provided for research purpose!"](https://github.com/facebookresearch/demucs/issues/508) (August 2023)

The maintainer's Hugging Face copies are confusing: [one thread says a copy carried an MIT tag](https://huggingface.co/adefossez/HTDemucs/discussions/1) and [another that a tag was removed](https://huggingface.co/adefossez/HTDemucs-ft/discussions/1). Developers have asked in both, one of them about this exact case of a paid offline iOS app, and none had an answer when this was checked in November 2026. A tag isn't a grant, so I wouldn't rely on one.

Stems aren't an optional extra here: Auto DJ reads each track's stems to plan a transition. So whatever replaces the model has to be good enough for that too.

**The ways out:**

1. **A licensed on-device model.** [AudioShake's Local Inference SDK](https://www.audioshake.ai/products/sdk) runs on iOS with no network, and its maker says it's been used in DJ apps. You have to contact them for access, so price and terms are unknown. This is the only route that's clean and likely to keep the quality. It would mean paying someone, and a new integration.
2. **Written permission for the Demucs weights.** It's free to ask, but the stated position is against it, and the people who've asked lately haven't had answers.
3. **Spleeter.** [Its paper says the pretrained models are MIT too](https://joss.theoj.org/papers/10.21105/joss.02154.pdf), and they were trained on Deezer's own data, which wasn't released. It's the cheapest clean-looking route, but it's a 2019 model, and Auto DJ loses a lot on it today. See the measurements below. A lawyer should still confirm the training data doesn't carry its own limits.
4. **Train our own.** The owner's offered GPUs, but data is the problem, not compute. [MoisesDB is non-commercial](https://arxiv.org/pdf/2307.15913), and so's MUSDB18. [Slakh2100 is CC BY](https://zenodo.org/record/4599666), but it's synthesised from MIDI and has no vocals. Without a licensed collection of real multitracks, this can't match what's in the app now.

**My recommendation:** ask AudioShake for terms first, as it's the only route likely to keep both quality and Auto DJ. Keep Spleeter as the fallback, and only start on it if the price is out of reach.

**Personal use is fine,** and nothing here stops the owner using the app on their own phone.

### Spleeter against the app's stems

Spleeter 4-stem at 16 kHz, on the owner's tracks. Nobody's heard these yet: the same moments split both ways are in the local listening room at `/stems.html`. Commercial tracks stay on this Mac.

**How close it is, on six tracks.** There's no true answer for commercial tracks, so this shows how different the two are, not which is right.

| Stem | Closeness to the app's | Bar-by-bar level agreement (r) |
|---|---|---|
| Drums | 12.5 dB | 1.00 |
| Bass | 9.4 dB | 0.92 |
| Vocals | 7.0 dB | 0.86 |
| Melody | 3.7 dB | 0.74 |

**Auto DJ through all 22 tracks, in folder order, on each model's stems:**

| | App's stems | Spleeter |
|---|---|---|
| Joins that found a move | 19 of 21 | 18 of 21 |
| Bass swaps | 3 | 0 |
| Vocal rides and teases | 2 | 0 |
| Loop builds | 6 | 10 |
| Echo throws | 8 | 8 |
| Shortest play | 35% | 20% |

So it still gets through a set, but only with the two moves that don't overlap the tracks. Only 7 of 21 joins chose the same move and bars. The planner's thresholds were tuned on Demucs stems, so some of this could come back with retuning, but I haven't tried that. The vocal and melody stems disagree the most, and those are what the blending moves rely on.

**Not measured:** Spleeter's speed and memory on a phone. On this busy Mac's CPU it ran 7 to 13 times real time, through TensorFlow. Its weights are about 150 MB, and converting them to Core ML hasn't been tried.

**A trap:** if Spleeter's model folder exists but is empty, it runs on an untrained network and says nothing. One run here did that after a failed download, and its numbers looked like a very bad model. Check the folder has a `checkpoint` before believing any result.
