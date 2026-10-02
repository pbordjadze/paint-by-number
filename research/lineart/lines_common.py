"""Shared helpers for the line-art families: picture IO, OKLab, the importance proxy.

A picture directory is the output of `pbn generate <pic> <dir> --auto --length relaxed`:
`working.ppm` (the photo at pbn's working resolution) and `raster.ppm` (pbn's color
segmentation, same size) are what the line scripts read.
"""

import os

import numpy as np
from PIL import Image
from scipy import ndimage

PAPER = (0xF4, 0xEF, 0xE6)  # the canvas `paper` token
INK = (0x1E, 0x1A, 0x22)    # CanvasPalette.light ink, sRGB (0.118, 0.102, 0.133)


def load_rgb(path):
    """uint8 HxWx3."""
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)


def load_picture(pic_dir):
    pic = {"dir": pic_dir, "name": os.path.basename(os.path.normpath(pic_dir))}
    pic["working"] = load_rgb(os.path.join(pic_dir, "working.ppm"))
    raster = os.path.join(pic_dir, "raster.ppm")
    if os.path.exists(raster):
        pic["raster"] = load_rgb(raster)
    return pic


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def rgb8_to_oklab(rgb):
    """uint8 (...,3) sRGB -> float32 OKLab (L in [0,1]); distances there ~ deltaE."""
    lin = srgb_to_linear(np.asarray(rgb, dtype=np.float64) / 255.0)
    lms = np.cbrt(lin @ _M1.T)
    return (lms @ _M2.T).astype(np.float32)


def oklab_to_rgb8(lab):
    lab = np.asarray(lab, dtype=np.float64)
    lms = lab @ np.linalg.inv(_M2).T
    lin = (lms ** 3) @ np.linalg.inv(_M1).T
    return np.round(linear_to_srgb(lin) * 255).astype(np.uint8)


def oklab_gradient(lab, sigma=1.0):
    """Per-pixel OKLab gradient magnitude (Gaussian derivatives), ~deltaE per pixel."""
    g2 = np.zeros(lab.shape[:2], np.float64)
    for c in range(3):
        ch = lab[..., c].astype(np.float64)
        gx = ndimage.gaussian_filter(ch, sigma, order=(0, 1), mode="nearest")
        gy = ndimage.gaussian_filter(ch, sigma, order=(1, 0), mode="nearest")
        g2 += gx * gx + gy * gy
    return np.sqrt(g2).astype(np.float32)


YUNET = ("opencv/face_detection_yunet", "face_detection_yunet_2023mar.onnx")  # MIT, Shiqi Yu


def detect_faces(rgb, min_frac=0.06, score=0.8):
    """Face boxes [(x, y, w, h)] from OpenCV's YuNet (weights from Hugging Face), faces at
    least `min_frac` of the short side; [] when the detector or its weights are unavailable."""
    try:
        import cv2
        from huggingface_hub import hf_hub_download
        path = hf_hub_download(*YUNET)
        h, w = rgb.shape[:2]
        det = cv2.FaceDetectorYN.create(path, "", (w, h), score, 0.3, 5000)
        _, faces = det.detect(np.ascontiguousarray(rgb[:, :, ::-1]))
    except Exception:
        return []
    if faces is None:
        return []
    out = []
    for f in faces:
        x, y, fw, fh = (float(v) for v in f[:4])
        if min(fw, fh) >= min_frac * min(h, w):
            out.append((x, y, fw, fh))
    return sorted(out)


def importance_map(rgb, faces=None):
    """Deterministic stand-in for the app's Vision importance map, in [0, 1].

    pbn exports no importance map, so this blends classic cues (the app's own map comes from
    Vision saliency plus faces):
    - spectral-residual saliency (Hou & Zhang, CVPR 2007) on the OKLab lightness and the
      two chroma channels at 64 px on the long side: log-amplitude spectrum minus its 3x3
      box mean, back with the original phase, squared, Gaussian sigma 2.5 (at 64 px), each
      channel normalized to its max and averaged;
    - a center prior: a Gaussian centered on the frame, sigma 0.35 of each dimension
      (photographers center subjects; Vision's attention maps are center-biased too).
    importance = 0.65 * saliency + 0.35 * center, then stretched so the 99th percentile is
    1 and floored at 0.1 (nothing is worthless). Smooth at the working size (bicubic up).
    Faces (YuNet, `detect_faces`) then get importance 1 over an ellipse 1.2 x the box width
    and 1.3 x its height, fading out over a quarter of the box: the app's Vision pass gives
    faces the same priority, and spectral residual alone misses them (a face is smooth).
    """
    h, w = rgb.shape[:2]
    scale = 64.0 / max(h, w)
    sh, sw = max(8, int(round(h * scale))), max(8, int(round(w * scale)))
    small = np.asarray(Image.fromarray(rgb).resize((sw, sh), Image.Resampling.BOX), dtype=np.uint8)
    lab = rgb8_to_oklab(small).astype(np.float64)
    sal = np.zeros((sh, sw))
    for c, weight in ((0, 1.0), (1, 0.5), (2, 0.5)):
        f = np.fft.fft2(lab[..., c] - lab[..., c].mean())
        amp = np.abs(f)
        log_amp = np.log(amp + 1e-9)
        phase = np.angle(f)
        residual = log_amp - ndimage.uniform_filter(log_amp, 3, mode="wrap")
        s = np.abs(np.fft.ifft2(np.exp(residual + 1j * phase))) ** 2
        s = ndimage.gaussian_filter(s, 2.5, mode="nearest")
        if s.max() > 0:
            sal += weight * s / s.max()
    sal /= sal.max() if sal.max() > 0 else 1
    yy, xx = np.mgrid[0:sh, 0:sw]
    center = np.exp(-(((xx + 0.5) / sw - 0.5) ** 2 / (2 * 0.35 ** 2)
                      + ((yy + 0.5) / sh - 0.5) ** 2 / (2 * 0.35 ** 2)))
    imp = 0.65 * sal + 0.35 * center
    imp = imp / max(np.percentile(imp, 99), 1e-9)
    imp = np.clip(imp, 0.1, 1.0)
    big = Image.fromarray(imp.astype(np.float32), mode="F").resize((w, h), Image.Resampling.BICUBIC)
    out = np.clip(np.asarray(big, dtype=np.float32), 0.1, 1.0)
    if faces is None:
        faces = detect_faces(rgb)
    if faces:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        for x, y, fw, fh in faces:
            cx, cy, ax, ay = x + fw / 2, y + fh / 2, 0.6 * fw, 0.65 * fh
            r = np.sqrt(((xx - cx) / ax) ** 2 + ((yy - cy) / ay) ** 2)
            bump = np.clip((1.25 - r) / 0.25, 0, 1)
            out = np.maximum(out, bump.astype(np.float32))
    return out


def save_gray(path, x):
    """float map in [0,1] -> 8-bit PNG (1 = white)."""
    Image.fromarray(np.round(np.clip(x, 0, 1) * 255).astype(np.uint8)).save(path, optimize=False)


def save_raw_png(path, response):
    """A raw line response (1 = ink) as dark lines on white, the way people look at it."""
    save_gray(path, 1.0 - response)
