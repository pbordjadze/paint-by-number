"""A relief-only tilt sweep of the whole painting, with the relief built from the template's region map
(canvas units, scaled up smoothly): what PaintCore would have, and free of the SVG edge band's
serration. Brush marks for subtle and strong are added at the render's scale."""
import io, os, sys
import cairosvg
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
sys.path.insert(0, os.path.dirname(__file__))
import impasto as im

src, out = sys.argv[1], sys.argv[2]
frames = int(sys.argv[3])
raster = np.asarray(Image.open(os.path.join(src, "raster.ppm")).convert("RGB")).astype(np.int64)
H, W = raster.shape[:2]
key = raster[..., 0] * 65536 + raster[..., 1] * 256 + raster[..., 2]
labels = np.zeros(key.shape, np.int64)
n = 0
for k in np.unique(key):
    lab, c = ndimage.label(key == k)
    labels[lab > 0] = lab[lab > 0] + n
    n += c
edge = np.zeros(key.shape, bool)
edge[:, 1:] |= labels[:, 1:] != labels[:, :-1]
edge[1:, :] |= labels[1:, :] != labels[:-1, :]
d1 = ndimage.distance_transform_edt(~edge)


def relief(strength):
    h1 = strength * (1 - np.exp(-d1 / 1.75))
    h1 = ndimage.gaussian_filter(h1, 0.8)
    return np.asarray(Image.fromarray(h1.astype(np.float32)).resize((W * 2, H * 2), Image.BICUBIC))


png = cairosvg.svg2png(url=os.path.join(src, "painted-outlined.svg"), output_width=W * 2)
inked = np.asarray(Image.open(io.BytesIO(png)).convert("RGB"), np.float32) / 255
alb = im.to_lin(inked)
photo = im.load(os.path.join(src, "working.ppm"))
photo = np.asarray(Image.fromarray((photo * 255).astype(np.uint8)).resize((W * 2, H * 2), Image.LANCZOS), np.float32) / 255
d2 = np.asarray(Image.fromarray(d1.astype(np.float32)).resize((W * 2, H * 2), Image.BILINEAR)) * 2
hgt = relief(1.0)
os.makedirs(os.path.join(out, "whole"), exist_ok=True)
for i in range(frames):
    t = 2 * np.pi * i / frames
    img = (im.to_srgb(im.light(alb, hgt, 0.45 * np.cos(t), 0.27 * np.sin(t), gloss=0.18, lines=None)) * 255).astype(np.uint8)
    Image.fromarray(img).resize((W, H), Image.LANCZOS).save(os.path.join(out, "whole", f"f{i:03d}.png"))
