"""Subject silhouette: a stand-in for Vision's foreground instance mask.

BiRefNet (Zheng et al., "Bilateral Reference for High-Resolution Dichotomous Image
Segmentation", CAAI AIR 2024; MIT license), the general-use checkpoint exported to ONNX by
onnx-community (`onnx-community/BiRefNet-ONNX`, `onnx/model.onnx`, 973 MB, MIT). The photo is
resized to 1024 x 1024 (bilinear), normalized with the ImageNet mean/std, and the last output
(logits) goes through a sigmoid; the map is resized back to the working size (bilinear) and
cached as an 8-bit PNG. Runs on CPU with onnxruntime (4 threads, sequential execution, so
two runs give the same map).

    python subject.py <pic-dir> <out.png>
"""

from __future__ import annotations

import os
import sys
import time

import numpy as np
from PIL import Image

MODEL = ("onnx-community/BiRefNet-ONNX", "onnx/model.onnx")
SIZE = 1024
MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)


def subject_map(rgb: np.ndarray) -> np.ndarray:
    """uint8 HxWx3 -> float32 HxW in [0, 1] (1 = subject)."""
    import onnxruntime as ort
    from huggingface_hub import hf_hub_download
    path = hf_hub_download(*MODEL)
    so = ort.SessionOptions()
    so.intra_op_num_threads = 4
    so.inter_op_num_threads = 1
    so.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    sess = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"])
    h, w = rgb.shape[:2]
    x = np.asarray(Image.fromarray(rgb).resize((SIZE, SIZE), Image.Resampling.BILINEAR), np.float32) / 255.0
    x = ((x - MEAN) / STD).transpose(2, 0, 1)[None].astype(np.float32)
    outs = sess.run(None, {sess.get_inputs()[0].name: x})
    logits = outs[-1][0, 0].astype(np.float32)
    prob = 1.0 / (1.0 + np.exp(-logits))
    big = Image.fromarray(prob, mode="F").resize((w, h), Image.Resampling.BILINEAR)
    return np.clip(np.asarray(big, np.float32), 0, 1)


def load_or_compute(pic_dir: str, cache_png: str) -> np.ndarray:
    if os.path.exists(cache_png):
        return np.asarray(Image.open(cache_png).convert("L"), np.float32) / 255.0
    rgb = np.asarray(Image.open(os.path.join(pic_dir, "working.ppm")).convert("RGB"))
    m = subject_map(rgb)
    os.makedirs(os.path.dirname(cache_png), exist_ok=True)
    Image.fromarray(np.round(m * 255).astype(np.uint8)).save(cache_png)
    return np.round(m * 255) / 255.0


if __name__ == "__main__":
    t0 = time.time()
    rgb = np.asarray(Image.open(os.path.join(sys.argv[1], "working.ppm")).convert("RGB"))
    m = subject_map(rgb)
    Image.fromarray(np.round(m * 255).astype(np.uint8)).save(sys.argv[2])
    print(f"{sys.argv[1]}: {time.time() - t0:.1f} s, subject share {float((m > 0.5).mean()):.3f}")
