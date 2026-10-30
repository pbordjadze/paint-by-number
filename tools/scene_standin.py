#!/usr/bin/env python3
"""The Linux stand-in for what Vision finds of a photo on the device: a `SceneMap` for `pbn --scene`.

    tools/scene_standin.py IMAGE... --out DIR [--weights DIR] [--overrides FILE] [--preview]

Writes, per image, `DIR/<name>/scene.json`, `subject.pgm` and `saliency.pgm` (the layout
`pbn generate --scene` reads: `Sources/pbn/Inputs.swift`, `loadScene`), the maps 256 px on the
long side like the app's (`SubjectImportance.resolution`), `eyes.json` (for `pbn --eyes`, see
below), and with --preview `preview.png`: the photo with the subject mask, the faces, the animals
and the features drawn over it.

What stands in for what (the app's `SubjectVision`):

- the subjects' mask (`VNGenerateForegroundInstanceMaskRequest`): ISNet, the "general use"
  dichotomous image segmentation network of Qin et al., "Highly Accurate Dichotomous Image
  Segmentation" (ECCV 2022), Apache-2.0, as the ONNX file `isnet-general-use.onnx` that rembg
  distributes (`https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx`,
  176 MB), run with onnxruntime at 1024 × 1024; its soft output is kept (0...255);
- attention saliency (`VNGenerateAttentionBasedSaliencyImageRequest`): spectral residual saliency
  (Hou and Zhang, CVPR 2007) on the photo at 64 px, blurred, times a center prior, with the
  subject mask and the faces raised toward 1, normalized so the peak is 1: a classical stand-in,
  where the eye goes first;
- faces (`VNDetectFaceRectanglesRequest`) and their eyes, noses and mouths
  (`VNDetectFaceLandmarksRequest`): MediaPipe's face detector and face landmarker, when the
  `mediapipe` package and its models are available (`--weights`); else none. The landmarker's
  eye contours also give `eyes.json`, the closed polygons the app's `EyeFinder` makes of Vision's
  (each eye's contour, then an iris circle of 0.2 × the eye's width clipped to it), for
  `pbn --eyes`, so a coloring book outlines the eyes as it does on the device;
- animals (`VNRecognizeAnimalsRequest`, cats and dogs): MediaPipe's object detector
  (EfficientDet-Lite0, COCO), its cat and dog boxes, when available;
- the eyes and noses of cats and dogs (`VNDetectAnimalBodyPoseRequest`): nothing stands in; the
  evaluation set's come from `--overrides`.

--overrides FILE is a JSON object `{"<name>": {"faces": [[x, y, w, h]], "animals": [...],
"features": [{"kind": "eye", "x": .., "y": .., "radius": ..}]}}` whose lists replace the detectors'
for that photo: the evaluation set's features were checked by eye (`Tests/EvalSet/overrides.json`),
since a stand-in that misses an eye would judge the algorithm, not the stand-in. Normalized to the
photo, origin top-left.

How close the stand-in is to Vision is measured on the device by the app's `SceneStandInTests`,
which compare the committed scenes of `Tests/EvalSet` with Vision's own findings.

Requires numpy, Pillow and onnxruntime; mediapipe is optional. Deterministic: the networks run
on the CPU and the rest is integer or float32 arithmetic in a fixed order.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOLUTION = 256
# Vision's animal recognizer knows cats and dogs; the stand-in keeps to the same two.
ANIMALS = {"cat", "dog"}


def map_size(w, h):
    """The map size for a w × h photo (`SubjectImportance.mapSize`)."""
    aspect = w / h
    if aspect >= 1:
        return RESOLUTION, max(1, int(RESOLUTION / aspect))
    return max(1, int(RESOLUTION * aspect)), RESOLUTION


def save_pgm(path, values):
    """Writes an 8-bit PGM of a uint8 array."""
    h, w = values.shape
    with open(path, "wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode())
        f.write(np.ascontiguousarray(values, dtype=np.uint8).tobytes())


class Subject:
    """ISNet's soft foreground mask."""

    def __init__(self, weights):
        import onnxruntime as ort
        path = os.path.join(weights, "isnet-general-use.onnx")
        if not os.path.exists(path):
            sys.exit(f"{path}: ISNet's ONNX file is needed (see the docstring)")
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = max(1, os.cpu_count() or 1)
        self.session = ort.InferenceSession(path, opts, providers=["CPUExecutionProvider"])
        self.input = self.session.get_inputs()[0].name

    def mask(self, image):
        """The mask, float32 in 0...1, at the photo's size."""
        x = np.asarray(image.resize((1024, 1024), Image.BILINEAR), dtype=np.float32) / 255.0
        x = ((x - 0.5) / 1.0).transpose(2, 0, 1)[None]
        out = self.session.run(None, {self.input: x})[0][0, 0]
        lo, hi = float(out.min()), float(out.max())
        out = (out - lo) / (hi - lo) if hi > lo else np.zeros_like(out)
        return np.asarray(Image.fromarray((out * 255).astype(np.uint8)).resize(image.size, Image.BILINEAR), dtype=np.float32) / 255.0


def spectral_residual(image, side=64):
    """Spectral residual saliency (Hou and Zhang 2007) of the photo's luminance at `side` px."""
    g = np.asarray(image.convert("L").resize((side, max(1, int(side * image.height / image.width))) if image.width >= image.height
                                             else (max(1, int(side * image.width / image.height)), side), Image.BILINEAR),
                   dtype=np.float32)
    f = np.fft.fft2(g)
    amplitude = np.abs(f) + 1e-6
    log_amp = np.log(amplitude)
    # The average log spectrum over a 3 × 3 neighbourhood.
    pad = np.pad(log_amp, 1, mode="edge")
    avg = sum(pad[i:i + log_amp.shape[0], j:j + log_amp.shape[1]] for i in range(3) for j in range(3)) / 9
    residual = log_amp - avg
    s = np.abs(np.fft.ifft2(np.exp(residual + 1j * np.angle(f)))) ** 2
    s = np.asarray(Image.fromarray(s.astype(np.float32)).resize(s.shape[::-1], Image.BILINEAR))
    # Blur by a 5-tap box twice.
    for _ in range(2):
        p = np.pad(s, 2, mode="edge")
        s = sum(p[i:i + s.shape[0], j:j + s.shape[1]] for i in range(5) for j in range(5)) / 25
    return s / (s.max() + 1e-8)


def saliency_map(image, subject, faces, w, h):
    """The attention stand-in at w × h, 0...1 with the peak at 1."""
    sr = spectral_residual(image)
    sr = np.asarray(Image.fromarray(sr.astype(np.float32)).resize((w, h), Image.BILINEAR))
    ys, xs = np.mgrid[0:h, 0:w]
    u = (xs + 0.5) / w - 0.5
    v = (ys + 0.5) / h - 0.45
    center = np.exp(-(u * u + v * v) / (2 * 0.3 * 0.3))
    s = 0.3 * sr * center + 0.4 * sr + 0.3 * center * subject
    s = np.maximum(s, 0.8 * subject * center)
    for (x, y, bw, bh) in faces:
        cx, cy = (x + bw / 2) * w, (y + bh / 2) * h
        rx, ry = max(1, bw * w * 0.75), max(1, bh * h * 0.8)
        d = ((xs + 0.5 - cx) / rx) ** 2 + ((ys + 0.5 - cy) / ry) ** 2
        s = np.maximum(s, np.clip(1.2 - 0.5 * d, 0, 1))
    return s / (s.max() + 1e-8)


class Detectors:
    """MediaPipe's face detector, face landmarker and object detector, each optional."""

    def __init__(self, weights):
        self.face = self.landmarker = self.objects = None
        try:
            import mediapipe as mp
            from mediapipe.tasks import python as mp_python
            from mediapipe.tasks.python import vision
        except (ImportError, OSError) as error:
            print(f"mediapipe can't load ({error}): no faces, features or animals from detectors", file=sys.stderr)
            return
        self.mp, self.vision = mp, vision

        def model(name):
            path = os.path.join(weights, name)
            return mp_python.BaseOptions(model_asset_path=path) if os.path.exists(path) else None

        if (base := model("blaze_face_short_range.tflite")) is not None:
            self.face = vision.FaceDetector.create_from_options(vision.FaceDetectorOptions(base_options=base, min_detection_confidence=0.5))
        if (base := model("face_landmarker.task")) is not None:
            self.landmarker = vision.FaceLandmarker.create_from_options(
                vision.FaceLandmarkerOptions(base_options=base, num_faces=8, min_face_detection_confidence=0.5))
        if (base := model("efficientdet_lite0.tflite")) is not None:
            self.objects = vision.ObjectDetector.create_from_options(
                vision.ObjectDetectorOptions(base_options=base, score_threshold=0.4, max_results=12))
        for name, d in (("blaze_face_short_range.tflite", self.face), ("face_landmarker.task", self.landmarker),
                        ("efficientdet_lite0.tflite", self.objects)):
            if d is None:
                print(f"{name} not in {weights}: that detector is skipped", file=sys.stderr)

    def run(self, image):
        """(faces, animals, features, eyes), normalized to the photo; `eyes` the closed polygons
        (contours, then irises) `pbn --eyes` reads."""
        faces, animals, features, eyes = [], [], [], []
        if self.face is None and self.landmarker is None and self.objects is None:
            return faces, animals, features, eyes
        mp_image = self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=np.asarray(image.convert("RGB")))
        w, h = image.size
        if self.face is not None:
            for d in self.face.detect(mp_image).detections:
                b = d.bounding_box
                faces.append([b.origin_x / w, b.origin_y / h, b.width / w, b.height / h])
        if self.landmarker is not None:
            result = self.landmarker.detect(mp_image)
            for lm in result.face_landmarks:
                pts = np.array([[p.x, p.y] for p in lm], dtype=np.float32)
                long_side = max(w, h)

                def feature(kind, indices, scale):
                    sel = pts[indices]
                    c = sel.mean(axis=0)
                    extent = np.sqrt((((sel - c) * [w, h]) ** 2).sum(axis=1)).max()
                    features.append({"kind": kind, "x": round(float(c[0]), 4), "y": round(float(c[1]), 4),
                                     "radius": round(float(extent * scale / long_side), 4)})

                # MediaPipe face mesh indices: eye corners and lids, nose tip and alae, lip corners.
                feature("eye", [33, 133, 159, 145, 160, 144], 1.2)
                feature("eye", [362, 263, 386, 374, 385, 380], 1.2)
                feature("nose", [1, 2, 98, 327, 4], 1.0)
                feature("mouth", [61, 291, 13, 14, 0, 17], 1.0)
                # The eye contours (the mesh's eye loops, in order round the eye) and irises.
                right_loop = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
                left_loop = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398]
                for loop in (right_loop, left_loop):
                    contour = pts[loop] * [w, h]
                    span = max(np.hypot(*(a - b)) for a in contour for b in contour)
                    if span < 0.012 * long_side:
                        continue
                    iris_center = contour.mean(axis=0)
                    eyes.append(("contour", contour, span, iris_center))
                if self.face is None:
                    xs, ys = pts[:, 0], pts[:, 1]
                    faces.append([float(xs.min()), float(ys.min()), float(xs.max() - xs.min()), float(ys.max() - ys.min())])
        if self.objects is not None:
            for d in self.objects.detect(mp_image).detections:
                if d.categories and d.categories[0].category_name in ANIMALS:
                    b = d.bounding_box
                    animals.append([b.origin_x / w, b.origin_y / h, b.width / w, b.height / h])
        return faces, animals, features, eye_polygons(eyes, w, h)


def eye_polygons(eyes, w, h):
    """Contours (ordered by position), then the irises of the same eyes, normalized and quantized
    to 1/4096 as `EyeFinder.polygons` does; an iris is the circle of 0.2 × the eye's width round
    its center, clipped to the contour, kept when at least 15 % of it shows."""
    import math
    ordered = sorted(eyes, key=lambda e: (e[1].mean(axis=0)[1], e[1].mean(axis=0)[0]))

    def normalized(points):
        return [[round(min(max(x / w, 0), 1) * 4096) / 4096, round(min(max(y / h, 0), 1) * 4096) / 4096] for x, y in points]

    def inside(point, polygon):
        x, y = point
        n = len(polygon)
        hit = False
        for i in range(n):
            x0, y0 = polygon[i]
            x1, y1 = polygon[(i + 1) % n]
            if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0 + 1e-12) + x0:
                hit = not hit
        return hit

    contours, irises = [], []
    for _, contour, span, center in ordered:
        contours.append(normalized(contour))
        radius = 0.2 * span
        circle = [(center[0] + radius * math.cos(2 * math.pi * i / 32), center[1] + radius * math.sin(2 * math.pi * i / 32)) for i in range(32)]
        visible = [p for p in circle if inside(p, contour)]
        if len(visible) >= 0.15 * 32 and len(visible) >= 3:
            irises.append(normalized(visible))
    return contours + irises


def preview(image, subject, faces, animals, features, path):
    im = image.convert("RGB").copy()
    overlay = Image.new("RGB", im.size, (255, 80, 0))
    alpha = Image.fromarray((subject * 110).astype(np.uint8)).resize(im.size)
    im = Image.composite(overlay, im, alpha)
    d = ImageDraw.Draw(im)
    w, h = im.size
    for (x, y, bw, bh) in faces:
        d.rectangle([x * w, y * h, (x + bw) * w, (y + bh) * h], outline=(255, 255, 0), width=3)
    for (x, y, bw, bh) in animals:
        d.rectangle([x * w, y * h, (x + bw) * w, (y + bh) * h], outline=(0, 255, 255), width=3)
    for f in features:
        r = f["radius"] * max(w, h)
        color = {"eye": (0, 255, 0), "nose": (255, 0, 255), "mouth": (255, 0, 0)}[f["kind"]]
        d.ellipse([f["x"] * w - r, f["y"] * h - r, f["x"] * w + r, f["y"] * h + r], outline=color, width=2)
    im.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("images", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--weights", default=os.environ.get("SCENE_WEIGHTS", os.path.join(ROOT, ".claude", "weights")))
    ap.add_argument("--overrides")
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()
    overrides = {}
    if args.overrides:
        with open(args.overrides) as f:
            overrides = json.load(f)
    subject_net = Subject(args.weights)
    detectors = Detectors(args.weights)
    for path in args.images:
        name = os.path.splitext(os.path.basename(path))[0]
        image = Image.open(path).convert("RGB")
        out = os.path.join(args.out, name)
        os.makedirs(out, exist_ok=True)
        full = subject_net.mask(image)
        faces, animals, features, eyes = detectors.run(image)
        over = overrides.get(name, {})
        faces = over.get("faces", faces)
        animals = over.get("animals", animals)
        features = over.get("features", features)
        if "faces" in over and not over["faces"]:
            eyes = []
        w, h = map_size(*image.size)
        subject = np.asarray(Image.fromarray((full * 255).astype(np.uint8)).resize((w, h), Image.BOX), dtype=np.float32) / 255
        sal = saliency_map(image, subject, faces, w, h)
        save_pgm(os.path.join(out, "subject.pgm"), np.rint(subject * 255).astype(np.uint8))
        save_pgm(os.path.join(out, "saliency.pgm"), np.rint(sal * 255).astype(np.uint8))
        scene = {"subject": "subject.pgm", "saliency": "saliency.pgm",
                 "faces": [[round(v, 4) for v in r] for r in faces], "animals": [[round(v, 4) for v in r] for r in animals],
                 "features": features}
        with open(os.path.join(out, "scene.json"), "w") as f:
            json.dump(scene, f, indent=1)
        with open(os.path.join(out, "eyes.json"), "w") as f:
            json.dump(eyes, f)
        if args.preview:
            preview(image, full, faces, animals, features, os.path.join(out, "preview.png"))
        print(f"{name:24s} subject {subject.mean():.2f} of the frame, faces {len(faces)}, animals {len(animals)}, features {len(features)}")


if __name__ == "__main__":
    main()
