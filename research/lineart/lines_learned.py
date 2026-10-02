"""Family D: learned line/edge detectors from controlnet_aux, run on CPU at working resolution.

controlnet_aux's own `__call__`s resize to a 512 px short side rounded to multiples of 64;
here each network gets the working image itself (reflect-padded to the multiple its
architecture needs, cropped back), with the input normalization its `__call__` uses, so the
raw map lines up pixel for pixel with working.ppm and raster.ppm. Output: float32 in [0, 1],
1 = line.

Models (weights from Hugging Face; first use downloads them into the HF cache):
  lineart_fine    LineartDetector  sk_model.pth   (Informative Drawings generator, "realistic")
  lineart_coarse  LineartDetector  sk_model2.pth  (same architecture, coarse style)
  lineart_anime   LineartAnimeDetector netG.pth   (Anime2Sketch-style U-Net)
  pidinet         PidiNetDetector  table5_pidinet.pth
  hed             HEDdetector      ControlNetHED.pth (lllyasviel's Apache-2.0 HED re-training)
  teed            TEEDdetector     fal-ai/teed 5_model.pth
all from lllyasviel/Annotators except TEED.

Determinism: torch.manual_seed(0), torch.use_deterministic_algorithms(True) and a fixed
thread count (4); eval mode, no dropout. On one machine two runs are byte-identical (checked
by `--check-determinism`); across CPUs with different vector units oneDNN may round
differently.

Usage: python lines_learned.py <pic-dir> <model> <out.npy> [--meta out.json]
       python lines_learned.py <pic-dir> <model> --check-determinism
"""

import json
import os
import resource
import sys
import time

import numpy as np

import lines_common as lc

MODELS = ["lineart_fine", "lineart_coarse", "pidinet", "hed", "teed", "lineart_anime"]
THREADS = 4


def _torch():
    import torch
    torch.manual_seed(0)
    torch.use_deterministic_algorithms(True)
    torch.set_num_threads(THREADS)
    return torch


def _pad(img, multiple):
    h, w = img.shape[:2]
    ph = (-h) % multiple
    pw = (-w) % multiple
    if ph == 0 and pw == 0:
        return img, (h, w)
    return np.pad(img, ((0, ph), (0, pw), (0, 0)), mode="reflect"), (h, w)


def _mark(timing):
    if timing is not None:
        timing["infer_start"] = time.time()


def _sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def run_model(rgb, model, timing=None):
    import warnings
    warnings.filterwarnings("ignore")
    torch = _torch()
    import cv2
    from einops import rearrange
    from controlnet_aux import (HEDdetector, LineartAnimeDetector, LineartDetector,
                                PidiNetDetector, TEEDdetector)

    with torch.no_grad():
        if model in ("lineart_fine", "lineart_coarse"):
            det = LineartDetector.from_pretrained("lllyasviel/Annotators")
            _mark(timing)
            net = det.model_coarse if model == "lineart_coarse" else det.model
            x, (h, w) = _pad(rgb, 8)
            t = rearrange(torch.from_numpy(x.astype(np.float32) / 255.0), "h w c -> 1 c h w")
            out = net(t)[0, 0].numpy()[:h, :w]
            return np.clip(1.0 - out, 0, 1).astype(np.float32)
        if model == "lineart_anime":
            det = LineartAnimeDetector.from_pretrained("lllyasviel/Annotators")
            _mark(timing)
            x, (h, w) = _pad(rgb, 256)
            t = rearrange(torch.from_numpy(x.astype(np.float32) / 127.5 - 1.0), "h w c -> 1 c h w")
            out = det.model(t)[0, 0].numpy()[:h, :w]
            return np.clip(1.0 - (out * 0.5 + 0.5), 0, 1).astype(np.float32)
        if model == "pidinet":
            det = PidiNetDetector.from_pretrained("lllyasviel/Annotators")
            _mark(timing)
            x, (h, w) = _pad(rgb, 16)
            x = x[:, :, ::-1].copy()  # the detector feeds BGR
            t = rearrange(torch.from_numpy(x.astype(np.float32) / 255.0), "h w c -> 1 c h w")
            out = det.netNetwork(t)[-1][0, 0].numpy()[:h, :w]
            return np.clip(out, 0, 1).astype(np.float32)
        if model == "hed":
            det = HEDdetector.from_pretrained("lllyasviel/Annotators")
            _mark(timing)
            x, (h, w) = _pad(rgb, 16)
            H, W = x.shape[:2]
            t = rearrange(torch.from_numpy(x.astype(np.float32)), "h w c -> 1 c h w")
            sides = [e.numpy().astype(np.float32)[0, 0] for e in det.netNetwork(t)]
            sides = [cv2.resize(e, (W, H), interpolation=cv2.INTER_LINEAR) for e in sides]
            edge = _sigmoid(np.mean(np.stack(sides, 2), axis=2).astype(np.float64))
            return edge[:h, :w].astype(np.float32)
        if model == "teed":
            det = TEEDdetector.from_pretrained("fal-ai/teed", "5_model.pth")
            det.model.eval()
            _mark(timing)
            x, (h, w) = _pad(rgb, 16)
            H, W = x.shape[:2]
            t = rearrange(torch.from_numpy(x.astype(np.float32)), "h w c -> 1 c h w")
            sides = [e.numpy().astype(np.float32)[0, 0] for e in det.model(t)]
            sides = [cv2.resize(e, (W, H), interpolation=cv2.INTER_LINEAR) for e in sides]
            edge = _sigmoid(np.mean(np.stack(sides, 2), axis=2).astype(np.float64))
            return edge[:h, :w].astype(np.float32)
    raise ValueError(f"unknown model {model}")


def main(argv):
    pic = lc.load_picture(argv[0])
    model = argv[1]
    if "--check-determinism" in argv:
        a = run_model(pic["working"], model)
        b = run_model(pic["working"], model)
        print(model, "identical" if np.array_equal(a, b) else
              f"DIFFERENT max |a-b| = {float(np.abs(a - b).max())}")
        return
    t0 = time.time()
    timing = {}
    out = run_model(pic["working"], model, timing)
    t1 = time.time()
    seconds = t1 - timing.get("infer_start", t0)
    np.save(argv[2], out)
    if "--meta" in argv:
        meta = {"seconds": round(seconds, 2), "load_seconds": round(t1 - t0 - seconds, 2),
                "peak_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024, 1),
                "threads": THREADS, "size": [int(out.shape[1]), int(out.shape[0])]}
        with open(argv[argv.index("--meta") + 1], "w") as f:
            json.dump(meta, f)


if __name__ == "__main__":
    main(sys.argv[1:])
