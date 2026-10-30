#!/usr/bin/env python3
"""Simulates a phone photo of a drawing on paper, for the drawing test set.

    tools/drawings/phone_photo.py <drawing.png> <out.jpg> [--seed N] [--long 2000]

The drawing is laid on a tinted sheet over a table (wood, cloth or a desk, by the seed), seen a
little askew (a perspective of up to 4 % of the sheet's size and a few degrees of roll), under a
light that falls off across the sheet and a soft shadow along one edge, with the paper's
texture, a slight blur, sensor noise and JPEG compression. The same seed gives the same photo
(numpy's generator), so the committed photos are reproducible: `Tests/Drawings/README.md` lists
each drawing's seed. Needs numpy and Pillow.
"""
import argparse
import numpy as np
from PIL import Image, ImageFilter

TABLES = [  # (name, base colour, grain strength)
    ("oak", (168, 124, 78), 0.10),
    ("walnut", (96, 66, 44), 0.12),
    ("grey desk", (150, 152, 150), 0.03),
    ("blue cloth", (70, 88, 120), 0.06),
    ("white desk", (236, 234, 228), 0.01),
    ("black table", (38, 36, 36), 0.04),
]


def perspective_coeffs(src, dst):
    """Pillow's 8 coefficients mapping output points `dst` to input points `src`."""
    matrix = []
    for (x, y), (u, v) in zip(dst, src):
        matrix.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        matrix.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(matrix, dtype=float)
    b = np.array([c for p in src for c in p], dtype=float)
    return np.linalg.solve(a, b)


def simulate(drawing, seed, long_side):
    rng = np.random.default_rng(seed)
    d = drawing.convert("L")
    aspect = d.width / d.height
    # The sheet fills about 78 % of the frame, portrait or landscape as the drawing is.
    if aspect >= 1:
        frame_w, frame_h = long_side, int(long_side * 0.75)
    else:
        frame_w, frame_h = int(long_side * 0.75), long_side
    share = 0.70 + 0.12 * rng.random()
    sheet_w = int(frame_w * share)
    sheet_h = int(sheet_w / aspect)
    if sheet_h > frame_h * 0.9:
        sheet_h = int(frame_h * 0.9)
        sheet_w = int(sheet_h * aspect)
    d = d.resize((sheet_w, sheet_h), Image.LANCZOS)
    art = np.asarray(d, dtype=np.float32) / 255

    # The sheet's own tint and texture.
    tint = np.array([250, 247, 240], dtype=np.float32) / 255 * (0.94 + 0.06 * rng.random())
    mottle = rng.normal(0, 1, (sheet_h // 24 + 1, sheet_w // 24 + 1)).astype(np.float32)
    mottle = np.asarray(Image.fromarray(mottle).resize((sheet_w, sheet_h), Image.BILINEAR))
    texture = 1 + 0.025 * mottle + rng.normal(0, 0.012, (sheet_h, sheet_w)).astype(np.float32)
    sheet = tint[None, None, :] * texture[:, :, None]
    # Ink darkens the paper (a multiply), so pencil grey stays grey.
    sheet = sheet * art[:, :, None]

    # The table.
    table_name, base, grain = TABLES[int(rng.integers(len(TABLES)))]
    base = np.array(base, dtype=np.float32) / 255
    g = rng.normal(0, 1, (frame_h // 6 + 1, 3)).astype(np.float32)
    g = np.asarray(Image.fromarray(g).resize((frame_w, frame_h), Image.BILINEAR))
    table = base[None, None, :] * (1 + grain * g[:, :, None]) * (1 + rng.normal(0, 0.01, (frame_h, frame_w, 1)))

    # The sheet placed, askew, over it.
    ox = (frame_w - sheet_w) // 2 + int(rng.integers(-frame_w // 40, frame_w // 40 + 1))
    oy = (frame_h - sheet_h) // 2 + int(rng.integers(-frame_h // 40, frame_h // 40 + 1))
    jitter = 0.04 * min(sheet_w, sheet_h)
    roll = np.deg2rad(rng.uniform(-3, 3))
    cx, cy = ox + sheet_w / 2, oy + sheet_h / 2
    corners = []
    for (x, y) in [(ox, oy), (ox + sheet_w, oy), (ox + sheet_w, oy + sheet_h), (ox, oy + sheet_h)]:
        rx = cx + (x - cx) * np.cos(roll) - (y - cy) * np.sin(roll)
        ry = cy + (x - cx) * np.sin(roll) + (y - cy) * np.cos(roll)
        corners.append((rx + rng.uniform(-jitter, jitter), ry + rng.uniform(-jitter, jitter)))
    src = [(0, 0), (sheet_w, 0), (sheet_w, sheet_h), (0, sheet_h)]
    coeffs = perspective_coeffs(src, corners)
    sheet_img = Image.fromarray(np.clip(sheet * 255, 0, 255).astype(np.uint8))
    mask_img = Image.new("L", (sheet_w, sheet_h), 255)
    warped = sheet_img.transform((frame_w, frame_h), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    warped_mask = mask_img.transform((frame_w, frame_h), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    m = np.asarray(warped_mask, dtype=np.float32)[:, :, None] / 255
    # A soft shadow under the sheet's edges, as a sheet lifts a little off the table.
    shadow = np.asarray(warped_mask.filter(ImageFilter.GaussianBlur(frame_w / 120)), dtype=np.float32)[:, :, None] / 255
    table = table * (1 - 0.35 * shadow * (1 - m))
    frame = table * (1 - m) + (np.asarray(warped, dtype=np.float32) / 255) * m

    # Light: a linear falloff across the frame, a mild vignette, and a shadow (the hand, the
    # phone) along one side of the sheet.
    yy, xx = np.mgrid[0:frame_h, 0:frame_w].astype(np.float32)
    angle = rng.uniform(0, 2 * np.pi)
    along = ((xx - frame_w / 2) * np.cos(angle) + (yy - frame_h / 2) * np.sin(angle)) / max(frame_w, frame_h)
    light = 1 - rng.uniform(0.15, 0.35) * (along + 0.5)
    r2 = ((xx - frame_w / 2) / frame_w) ** 2 + ((yy - frame_h / 2) / frame_h) ** 2
    light *= 1 - rng.uniform(0.1, 0.3) * r2 * 2
    side = int(rng.integers(4))
    t = [xx / frame_w, 1 - xx / frame_w, yy / frame_h, 1 - yy / frame_h][side]
    shade = 1 - rng.uniform(0.12, 0.3) * np.clip((0.35 - t) / 0.25, 0, 1)
    light *= shade
    frame = frame * light[:, :, None]

    img = Image.fromarray(np.clip(frame * 255, 0, 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(rng.uniform(0.5, 1.0)))
    noisy = np.asarray(img, dtype=np.float32) + rng.normal(0, rng.uniform(1.5, 4), (frame_h, frame_w, 3))
    return Image.fromarray(np.clip(noisy, 0, 255).astype(np.uint8)), table_name, int(rng.integers(74, 90))


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("drawing")
    p.add_argument("out")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--long", type=int, default=2000, help="long side of the photo")
    a = p.parse_args()
    photo, table, quality = simulate(Image.open(a.drawing), a.seed, a.long)
    photo.save(a.out, quality=quality, subsampling=1)
    print(f"{a.out}: {photo.width}x{photo.height}, on {table}, JPEG {quality}")


if __name__ == "__main__":
    main()
