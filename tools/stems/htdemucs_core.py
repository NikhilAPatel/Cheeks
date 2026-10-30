"""The part of HTDemucs.forward that Core ML can run, plus the checkpoint loader.

HTDemucs.forward is, in order:

    z = _spec(mix)                     # STFT            -> outside the model (Swift, vDSP)
    x = _magnitude(z)                  # complex-as-channels
    x, xt = normalise, encode, transform, decode, denormalise   # <- this module
    zout = _mask(z, x)                 # with cac=True this just reinterprets x as complex
    x = _ispec(zout)                   # iSTFT           -> outside the model (Swift, vDSP)
    return xt + x

`HTDemucsCore.forward` is a line-for-line copy of the middle section. Anything that differs
from demucs/htdemucs.py is called out in a comment.
"""

import math
import os
from pathlib import Path

import torch
from demucs.transformer import create_2d_sin_embedding
from einops import rearrange
from torch import nn

SEGMENT_SAMPLES = 343980  # int(44100 * 7.8)
SPEC_BINS = 2048  # n_fft / 2; _spec drops the Nyquist bin
SPEC_FRAMES = 336  # ceil(SEGMENT_SAMPLES / hop)

CACHE_ROOT = os.path.expanduser("~/Library/Caches/cheeks-stems")
CHECKPOINT = "955717e8-8726e21a.th"
CHECKPOINT_URL = "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/" + CHECKPOINT
CHECKPOINT_SHA256 = "8726e21a"


def load_htdemucs():
    """The `htdemucs` model, from Meta's original checkpoint, cached under CACHE_ROOT.

    demucs.pretrained.get_model("htdemucs") prefers the HuggingFace copy and writes to ~/.cache.
    Those weights are identical (checked parameter by parameter), but going by signature against
    a local folder keeps everything in one place and pins the file by its SHA-256.
    """
    from demucs.pretrained import get_model

    folder = Path(CACHE_ROOT) / "checkpoints"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / CHECKPOINT
    if not path.exists():
        torch.hub.download_url_to_file(CHECKPOINT_URL, str(path), hash_prefix=CHECKPOINT_SHA256)
    model = get_model(CHECKPOINT.split("-")[0], repo=folder)
    model.eval()
    return model


class HTDemucsCore(nn.Module):
    """(mix [1,2,343980], spec [1,4,2048,336]) -> (spec_out [1,4,4,2048,336], time_out [1,4,2,343980])

    `spec` channels are L.re, L.im, R.re, R.im, as `_magnitude` lays them out. `spec_out` has the
    same channel layout per source; sources are in `model.sources` order.
    """

    def __init__(self, model):
        super().__init__()
        assert model.cac, "only the complex-as-channels variant is supported"
        assert model.use_train_segment
        assert model.crosstransformer.emb == "sin" and model.crosstransformer.sin_random_shift == 0
        self.m = model

        # forward() rebuilds these from the shapes on every call. They're constants, so bake them
        # in: then no arange/scatter/pow runs at inference time, and they are computed in fp32
        # however the model is compiled.
        t = model.crosstransformer
        bottom = model.bottom_channels
        bins = SPEC_BINS // 4 ** len(model.encoder)
        frames = SPEC_FRAMES
        with torch.no_grad():
            pos_2d = create_2d_sin_embedding(bottom, bins, frames, "cpu", t.max_period)
            self.register_buffer("pos_2d", rearrange(pos_2d, "b c fr t1 -> b (t1 fr) c"))
            frames_t = math.ceil(SEGMENT_SAMPLES / 4 ** len(model.tencoder))
            pos_t = t._get_pos_embedding(frames_t, 1, bottom, "cpu")
            self.register_buffer("pos_t", rearrange(pos_t, "t2 b c -> b t2 c"))

    def _transform(self, x, xt):
        # CrossTransformerEncoder.forward with the positional embeddings precomputed.
        t = self.m.crosstransformer
        B, C, Fr, T1 = x.shape
        x = rearrange(x, "b c fr t1 -> b (t1 fr) c")
        x = t.norm_in(x)
        x = x + t.weight_pos_embed * self.pos_2d

        xt = rearrange(xt, "b c t2 -> b t2 c")
        xt = t.norm_in_t(xt)
        xt = xt + t.weight_pos_embed * self.pos_t

        for idx in range(t.num_layers):
            if idx % 2 == t.classic_parity:
                x = t.layers[idx](x)
                xt = t.layers_t[idx](xt)
            else:
                old_x = x
                x = t.layers[idx](x, xt)
                xt = t.layers_t[idx](xt, old_x)

        x = rearrange(x, "b (t1 fr) c -> b c fr t1", t1=T1)
        xt = rearrange(xt, "b t2 c -> b c t2")
        return x, xt

    def forward(self, mix, spec):
        m = self.m
        length = mix.shape[-1]
        x = spec
        xt = mix
        B, C, Fq, T = x.shape

        # Same as x.mean/x.std(dim=(1,2,3), keepdim=True) and the time-branch equivalents, with the
        # std spelled out: torch.std is unbiased (N - 1), and the literal keeps the conversion
        # independent of how coremltools maps the `std` op.
        n_spec = C * Fq * T
        mean = x.mean(dim=(1, 2, 3), keepdim=True)
        std = (((x - mean) ** 2).mean(dim=(1, 2, 3), keepdim=True) * (n_spec / (n_spec - 1))).sqrt()
        x = (x - mean) / (1e-5 + std)

        n_time = mix.shape[1] * length
        meant = xt.mean(dim=(1, 2), keepdim=True)
        stdt = (((xt - meant) ** 2).mean(dim=(1, 2), keepdim=True) * (n_time / (n_time - 1))).sqrt()
        xt = (xt - meant) / (1e-5 + stdt)

        saved = []
        saved_t = []
        lengths = []
        lengths_t = []
        for idx, encode in enumerate(m.encoder):
            lengths.append(x.shape[-1])
            inject = None
            if idx < len(m.tencoder):
                lengths_t.append(xt.shape[-1])
                tenc = m.tencoder[idx]
                xt = tenc(xt)
                if not tenc.empty:
                    saved_t.append(xt)
                else:
                    inject = xt
            x = encode(x, inject)
            if idx == 0 and m.freq_emb is not None:
                frs = torch.arange(x.shape[-2], device=x.device)
                emb = m.freq_emb(frs).t()[None, :, :, None].expand_as(x)
                x = x + m.freq_emb_scale * emb
            saved.append(x)

        if m.crosstransformer:
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_upsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_upsampler_t(xt)

            x, xt = self._transform(x, xt)

            if m.bottom_channels:
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_downsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_downsampler_t(xt)

        for idx, decode in enumerate(m.decoder):
            skip = saved.pop(-1)
            x, pre = decode(x, skip, lengths.pop(-1))
            offset = m.depth - len(m.tdecoder)
            if idx >= offset:
                tdec = m.tdecoder[idx - offset]
                length_t = lengths_t.pop(-1)
                if tdec.empty:
                    assert pre.shape[2] == 1, pre.shape
                    pre = pre[:, :, 0]
                    xt, _ = tdec(pre, None, length_t)
                else:
                    skip = saved_t.pop(-1)
                    xt, _ = tdec(xt, skip, length_t)

        assert len(saved) == 0 and len(lengths_t) == 0 and len(saved_t) == 0

        S = len(m.sources)
        x = x.view(B, S, -1, Fq, T)
        x = x * std[:, None] + mean[:, None]
        xt = xt.view(B, S, -1, length)
        xt = xt * stdt[:, None] + meant[:, None]
        return x, xt


def reference_outputs(model, mix):
    """What the wrapper gives for `mix`, checked against HTDemucs.forward itself.

    Returns (spec, spec_out, time_out, stems).
    """
    with torch.no_grad():
        z = model._spec(mix)
        spec = model._magnitude(z)
        spec_out, time_out = HTDemucsCore(model)(mix, spec)
        zout = model._mask(z, spec_out)
        stems = time_out + model._ispec(zout, mix.shape[-1])
        expected = model(mix)
    difference = (stems - expected).abs().max().item()
    # Float rounding only: the positional embeddings take a slightly different path.
    assert difference < 1e-4 * max(1, expected.abs().max().item()), difference
    return spec, spec_out, time_out, stems
