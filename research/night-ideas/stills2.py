"""Same crop, same light, four strengths, with the relief built from the template's region map
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
crop = tuple(map(float, sys.argv[3].split(",")))
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
rng = np.random.default_rng(7)
noise = ndimage.gaussian_filter(rng.standard_normal((H * 2, W * 2)).astype(np.float32), 1.0)
vx, vy = im.orientation(photo)
marks = ndimage.gaussian_filter(im.lic(noise, vx, vy, length=18.0, steps=14), 0.6)
marks /= marks.std() + 1e-6
fade = np.clip(d2 / 5.25, 0, 1)
cx, cy = int(W * 2 * crop[0]), int(H * 2 * crop[1])
box = (slice(cy, cy + 720), slice(cx, cx + 720))
variants = [("today", None), ("relief", (1.0, 0.0, 0.18)), ("subtle", (0.7, 0.18, 0.12)), ("strong", (1.6, 0.7, 0.3))]
for name, v in variants:
    if v is None:
        tile = (inked[box] * 255).astype(np.uint8)
    else:
        r, b, gloss = v
        hgt = relief(r) + b * 0.25 * marks * fade
        lit = im.light(alb[box], hgt[box], -0.35, 0.25, gloss=gloss, lines=None)
        tile = (im.to_srgb(lit) * 255).astype(np.uint8)
    Image.fromarray(tile).save(os.path.join(out, name + ".jpg"), quality=90)
