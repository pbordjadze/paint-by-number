"""Tilt-sweep frames from the template's vectors (smooth edges, ink lines as the app draws a book).

    python3 clip2.py <pbn out dir> <out dir> [frames] [cropx,cropy] [--still]
"""
import io, os, sys
import cairosvg
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, os.path.dirname(__file__))
import impasto as im

src, out = sys.argv[1], sys.argv[2]
frames = int(sys.argv[3]) if len(sys.argv) > 3 else 60
crop = tuple(map(float, sys.argv[4].split(","))) if len(sys.argv) > 4 else (0.3, 0.1)
BRUSH = float(sys.argv[5]) if len(sys.argv) > 5 else 0.35
W0 = Image.open(os.path.join(src, "raster.ppm")).size[0]
W = W0 * 2


def render(name):
    png = cairosvg.svg2png(url=os.path.join(src, name), output_width=W)
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGB"), np.float32) / 255


flat = render("painted.svg")
inked = render("painted-outlined.svg")
H = flat.shape[0]
# Area edges: where the flat paint changes colour (antialiased, so a one-to-two pixel band).
g = np.zeros(flat.shape[:2], np.float32)
for c in range(3):
    g += np.hypot(ndimage.sobel(flat[..., c], 0), ndimage.sobel(flat[..., c], 1))
edges = ndimage.binary_dilation(g > 0.025)
photo = im.load(os.path.join(src, "working.ppm"))
photo = np.asarray(Image.fromarray((photo * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS), np.float32) / 255
hgt, _ = im.height_field(flat, edges, photo, brush=BRUSH)
hgt = ndimage.gaussian_filter(hgt, 1.4)
alb = im.to_lin(inked)
cx, cy = int(W * crop[0]), int(H * crop[1])
os.makedirs(os.path.join(out, "whole"), exist_ok=True)
os.makedirs(os.path.join(out, "detail"), exist_ok=True)
Image.fromarray((inked * 255).astype(np.uint8)).resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(out, "flat.jpg"), quality=88)
for i in range(frames):
    t = 2 * np.pi * i / frames
    img = (im.to_srgb(im.light(alb, hgt, 0.45 * np.cos(t), 0.27 * np.sin(t), lines=None)) * 255).astype(np.uint8)
    pic = Image.fromarray(img)
    pic.resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(out, "whole", f"f{i:03d}.png"))
    pic.crop((cx, cy, cx + 720, cy + 720)).save(os.path.join(out, "detail", f"f{i:03d}.png"))
