"""Eyes: a stand-in for Vision's face landmarks (people) and animal body pose eye joints.

Open-vocabulary detection with OWLv2 (Minderer et al., "Scaling Open-Vocabulary Object
Detection", NeurIPS 2023; `google/owlv2-base-patch16-ensemble`, Apache-2.0) queried with
"an eye" / "the eye of an animal". OWLv2 sees a 960 x 960 square, so the photo is searched in
overlapping square tiles around the subject (the BiRefNet mask's bounding box, see
subject.py) as well as whole, and boxes are kept when they score above SCORE, lie inside the
subject, and are small (an eye is a few percent of the subject's size). Overlapping boxes are
merged (non-maximum suppression). Deterministic: eval mode, fixed thread count.

People: OWLv2 misses downcast eyes (the Milkmaid's score 0.15 and 0.09), so faces found by
OpenCV's YuNet (MIT, the importance proxy's face detector) add a box around each of its two
eye landmarks (EYE_BOX x the face width), the stand-in for Vision's face landmarks.

    python eyes.py <pic-dir> <subject.png> <out.json>
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image

MODEL = "google/owlv2-base-patch16-ensemble"
QUERIES = ["an eye", "the eye of an animal"]
SCORE = 0.25
MAX_FRAC = 0.12     # an eye box is at most this fraction of the subject's bounding-box diagonal
EYE_BOX = (0.24, 0.16)   # YuNet eye boxes: width, height as fractions of the face width


def _detect(model, proc, img: Image.Image):
    import torch
    inputs = proc(text=[QUERIES], images=img, return_tensors="pt")
    with torch.no_grad():
        out = model(**inputs)
    # boxes are relative to the padded square the processor makes (the long side)
    side = max(img.size)
    res = proc.image_processor.post_process_object_detection(out, threshold=0.05, target_sizes=[(side, side)])[0]
    return [(float(s), [float(v) for v in b]) for s, b in zip(res["scores"], res["boxes"])]


def face_eyes(rgb: np.ndarray, min_frac: float = 0.06, score: float = 0.8) -> list:
    """Boxes around YuNet's eye landmarks, (score, [x0, y0, x1, y1])."""
    import cv2
    from huggingface_hub import hf_hub_download
    import lines_common as lc
    h, w = rgb.shape[:2]
    det = cv2.FaceDetectorYN.create(hf_hub_download(*lc.YUNET), "", (w, h), score, 0.3, 5000)
    _, faces = det.detect(np.ascontiguousarray(rgb[:, :, ::-1]))
    out = []
    for f in (faces if faces is not None else []):
        fw, fh = float(f[2]), float(f[3])
        if min(fw, fh) < min_frac * min(h, w):
            continue
        bw, bh = EYE_BOX[0] * fw, EYE_BOX[1] * fw
        for ex, ey in ((f[4], f[5]), (f[6], f[7])):
            out.append((round(float(f[14]), 3), [round(float(ex) - bw / 2, 1), round(float(ey) - bh / 2, 1),
                                                  round(float(ex) + bw / 2, 1), round(float(ey) + bh / 2, 1)]))
    return out


def find_eyes(rgb: np.ndarray, subject: np.ndarray) -> list:
    import torch
    from transformers import Owlv2ForObjectDetection, Owlv2Processor
    torch.set_num_threads(4)
    torch.manual_seed(0)
    proc = Owlv2Processor.from_pretrained(MODEL)
    model = Owlv2ForObjectDetection.from_pretrained(MODEL).eval()
    h, w = rgb.shape[:2]
    m = subject > 0.5
    if m.sum() < 0.002 * h * w:
        return []
    ys, xs = np.nonzero(m)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    diag = float(np.hypot(x1 - x0, y1 - y0))
    # tiles: the subject's box as a square, plus its halves (eyes are small for the model at 960)
    tiles = []
    side = int(max(x1 - x0, y1 - y0))
    for k in (1, 2):
        s = max(side // k, 200)
        step = max(s // 2, 1) if k > 1 else s
        for ty in range(int(y0), max(int(y1) - s, int(y0)) + 1, step):
            for tx in range(int(x0), max(int(x1) - s, int(x0)) + 1, step):
                tiles.append((tx, ty, min(tx + s, w), min(ty + s, h)))
    cands = []
    for tx0, ty0, tx1, ty1 in tiles:
        img = Image.fromarray(rgb[ty0:ty1, tx0:tx1])
        for s, (bx0, by0, bx1, by1) in _detect(model, proc, img):
            cands.append((s, [bx0 + tx0, by0 + ty0, bx1 + tx0, by1 + ty0]))
    keep = face_eyes(rgb)
    for s, b in sorted(cands, key=lambda t: -t[0]):
        bw, bh = b[2] - b[0], b[3] - b[1]
        if s < SCORE or np.hypot(bw, bh) > MAX_FRAC * diag or min(bw, bh) < 3:
            continue
        cx, cy = int((b[0] + b[2]) / 2), int((b[1] + b[3]) / 2)
        if not (0 <= cx < w and 0 <= cy < h) or subject[cy, cx] < 0.5:
            continue
        if any(_iou(b, k[1]) > 0.2 or _inside(b, k[1]) for k in keep):
            continue
        keep.append((round(s, 3), [round(v, 1) for v in b]))
    return keep


def _iou(a, b):
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    ua = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / ua if ua > 0 else 0.0


def _inside(a, b):
    cx, cy = (a[0] + a[2]) / 2, (a[1] + a[3]) / 2
    return b[0] <= cx <= b[2] and b[1] <= cy <= b[3]


def load_or_compute(pic_dir: str, subject: np.ndarray, cache_json: str) -> list:
    if os.path.exists(cache_json):
        return json.load(open(cache_json))["eyes"]
    rgb = np.asarray(Image.open(os.path.join(pic_dir, "working.ppm")).convert("RGB"))
    eyes = find_eyes(rgb, subject)
    json.dump({"model": MODEL, "queries": QUERIES, "eyes": eyes}, open(cache_json, "w"), indent=1)
    return eyes


if __name__ == "__main__":
    rgb = np.asarray(Image.open(os.path.join(sys.argv[1], "working.ppm")).convert("RGB"))
    sub = np.asarray(Image.open(sys.argv[2]).convert("L"), np.float32) / 255.0
    eyes = find_eyes(rgb, sub)
    json.dump({"model": MODEL, "queries": QUERIES, "eyes": eyes}, open(sys.argv[3], "w"), indent=1)
    print(sys.argv[1], eyes)
