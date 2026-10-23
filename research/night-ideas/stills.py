"""Same crop, same light, four strengths: none (the app today), relief only, subtle marks, strong."""
import io, os, sys
import cairosvg
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
sys.path.insert(0, os.path.dirname(__file__))
import impasto as im

src, out = sys.argv[1], sys.argv[2]
crop = tuple(map(float, sys.argv[3].split(",")))
W = Image.open(os.path.join(src, "raster.ppm")).size[0] * 2


def render(name):
    png = cairosvg.svg2png(url=os.path.join(src, name), output_width=W)
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGB"), np.float32) / 255


flat, inked = render("painted.svg"), render("painted-outlined.svg")
H = flat.shape[0]
g = sum(np.hypot(ndimage.sobel(flat[..., c], 0), ndimage.sobel(flat[..., c], 1)) for c in range(3))
edges = ndimage.binary_dilation(g > 0.025)
photo = im.load(os.path.join(src, "working.ppm"))
photo = np.asarray(Image.fromarray((photo * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS), np.float32) / 255
cx, cy = int(W * crop[0]), int(H * crop[1])
box = (slice(cy, cy + 720), slice(cx, cx + 720))
alb = im.to_lin(inked)
variants = [("today (flat)", None), ("relief only", dict(relief=1.0, brush=0.0, gloss=0.18)),
            ("subtle marks", dict(relief=0.7, brush=0.18, gloss=0.12)), ("strong", dict(relief=1.6, brush=0.7, gloss=0.3))]
tiles = []
for name, v in variants:
    if v is None:
        tile = (inked[box] * 255).astype(np.uint8)
    else:
        hgt, _ = im.height_field(flat, edges, photo, relief=v["relief"], brush=v["brush"])
        hgt = ndimage.gaussian_filter(hgt, 1.4)
        lit = im.light(alb[box], hgt[box], -0.35, 0.25, gloss=v["gloss"], lines=None)
        tile = (im.to_srgb(lit) * 255).astype(np.uint8)
    tiles.append((name, Image.fromarray(tile)))
    Image.fromarray(tile).save(os.path.join(out, name.split(" ")[0] + ".jpg"), quality=90)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
sheet = Image.new("RGB", (720 * 2 + 16, (720 + 44) * 2 + 16), "white")
for i, (name, t) in enumerate(tiles):
    x, y = (i % 2) * 736, (i // 2) * 780
    sheet.paste(t, (x, y + 44))
    ImageDraw.Draw(sheet).text((x + 4, y + 8), name, fill=(40, 30, 50), font=font)
sheet.save(os.path.join(out, "sheet.jpg"), quality=88)
