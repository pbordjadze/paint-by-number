#!/usr/bin/env python3
"""A still of the way back from Paint by Mosaic (App/PaintByNumber/App/EraDoor.swift, `EraWayBack`
and `EraPassage.drawWayBack`), to judge its look off the device, as `passage_preview.py` does the
way in's. It mirrors the timings, the night, the crescent and the tiles' fall with Pillow, with
its own random draws (not the app's), plain four-point stars and no glow round the crescent, so it shows the shape and the
light, not the exact tiles. `--at` is seconds from the passage's start (the demos hold 1.495 and
2.35); the gallery beneath is a flat paper.

    python3 tools/ravenna/way_back_preview.py out.png [--at 1.495 --width 1032 --height 1376 --scale 1]
"""
import argparse, math, random
from PIL import Image, ImageDraw

WAIT, COVER, FALL, STILL, TOTAL = 0.45, 0.55, 0.9, 0.45, 2.95
SWAP = WAIT + COVER * 0.75; LAID = WAIT + COVER; FALLEN = LAID + FALL; CLEARS = FALLEN + STILL; CLEAR = TOTAL - CLEARS
GOLD = (201, 162, 74)

def ease(x):
    t = min(1, max(0, x)); return t * t * (3 - 2 * t)

def crescent(x, y, side):
    s = side / 52; ox, oy = x + side / 2, y + side / 2; ix, iy = ox + 6.41 * s, oy - 2.89 * s
    pts = []
    for cx, cy, r, a0, a1 in ((ox, oy, 26 * s, -81.75, -326.7), (ix, iy, 23 * s, 48.24, 263.31)):
        for k in range(41):
            a = math.radians(a0 + (a1 - a0) * k / 40); pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--width", type=float, default=1032)
    ap.add_argument("--height", type=float, default=1376); ap.add_argument("--at", type=float, default=LAID + FALL * 0.55)
    ap.add_argument("--scale", type=float, default=1)
    a = ap.parse_args(); k = a.scale; t = a.at
    W, H = a.width, a.height; size = (int(W * k), int(H * k))
    img = Image.new("RGBA", size, (242, 241, 244, 255))
    pitch = max(22, round(min(W, H) / 36))
    cx, cy = W / 2, H + pitch
    far = math.hypot(max(cx, W - cx), cy) + pitch
    if t <= WAIT: img.save(a.out); return

    # The night, the tiles' bed while they are laid.
    night = 1 - ease((t - CLEARS) / CLEAR / 0.8)
    sky = Image.new("RGBA", size); sd = ImageDraw.Draw(sky)
    top, bottom = (12, 11, 25), (30, 22, 62)
    for row in range(size[1]):
        f = row / max(1, size[1] - 1)
        sd.line([(0, row), (size[0], row)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * f) for i in range(3)) + (int(255 * night),))
    spread = 1 if t >= SWAP else min(1, max(0, (t - WAIT) / COVER / 0.75))
    mask = Image.new("L", size, 0)
    front = far * spread
    ImageDraw.Draw(mask).ellipse([(cx - front) * k, (cy - front) * k, (cx + front) * k, (cy + front) * k], fill=255)
    img.paste(Image.alpha_composite(img, sky), (0, 0), mask)
    img = img.convert("RGB"); d = ImageDraw.Draw(img, "RGBA")

    gold = 1 - ease(((t - CLEARS) / CLEAR - 0.3) / 0.7)
    up = ease(((t - LAID) / FALL - 0.3) / 0.2) * gold
    if up > 0:
        side = min(160, max(64, min(W, H) * 0.2))
        moon = [(x * k, y * k) for x, y in crescent(W / 2 - side / 2, H * 0.36 - side / 2, side)]
        d.polygon(moon, fill=GOLD + (int(255 * 0.92 * up),))
        d.line(moon + moon[:1], fill=GOLD + (int(255 * up),), width=max(1, round(min(4, max(2, side * 0.04)) * k)), joint="curve")
        places = [(0.77, 0.13, 0.22), (0.24, 0.17, 0.30), (0.85, 0.40, 0.26), (0.15, 0.47, 0.20), (0.68, 0.60, 0.24)]
        for i, (px, py, ps) in enumerate(places):
            s = t - (FALLEN - 0.25 + 0.11 * i)
            if s <= 0: continue
            sc = 0.3 + 0.82 * ease(s / 0.14) if s < 0.14 else 1.12 - 0.12 * ease((s - 0.14) / 0.10)
            r = side * ps * sc / 2; x, y = W * px, H * py; q = r * 0.133
            star = [(x, y - r), (x + q, y - q), (x + r, y), (x + q, y + q), (x, y + r), (x - q, y + q), (x - r, y), (x - q, y - q)]
            d.polygon([(u * k, v * k) for u, v in star], fill=GOLD + (int(255 * min(1, s / 0.12) * gold),))

    if t < FALLEN:
        tones = ((0.788, 0.635, 0.290), (0.914, 0.886, 0.827), (0.122, 0.165, 0.322))
        rnd = random.Random(547)
        for course in range(math.ceil(far / pitch)):
            radius = (course + 0.6) * pitch
            count = max(3, round(math.pi * radius / pitch)); step = math.pi / count; shift = rnd.random() * step
            tone = tones[1] if course % 7 == 4 else tones[2] if course % 7 in (5, 6) else tones[0]
            for i in range(count):
                th = shift + i * step
                r = radius + (rnd.random() - 0.5) * pitch * 0.12
                x, y = cx + r * math.cos(th), cy - r * math.sin(th)
                side = pitch * (0.8 + rnd.random() * 0.1)
                ang = -th + (rnd.random() - 0.5) * 0.14
                light = 0.86 + rnd.random() * 0.24
                delay = min(1, radius / far + rnd.random() * 0.06)
                lean = rnd.random() - 0.5
                if not (-side < x < W + side and -side < y < H + side): continue
                if t < LAID:
                    local = ((t - WAIT) / COVER - delay * 0.75) / 0.25
                    if local <= 0: continue
                    e = min(1, local); op = e; sc = 1.35 - 0.35 * (1 - (1 - e) ** 3)
                else:
                    local = ((t - LAID) / FALL - (1 - delay) * 0.7) / 0.3
                    if local >= 1: continue
                    e = max(0, local); op = 1 - e * e; sc = 1 - 0.12 * e
                    y += pitch * 5 * e * e * (1 + lean); ang += 2.4 * lean * e
                s = side * sc
                def quad(x0, y0, x1, y1):
                    pts = []
                    for px, py in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
                        rx = px * math.cos(ang) - py * math.sin(ang); ry = px * math.sin(ang) + py * math.cos(ang)
                        pts.append(((x + rx) * k, (y + ry) * k))
                    return pts
                d.polygon(quad(-s/2, -s/2, s/2, s/2), fill=tuple(int(min(1, c * light) * 255) for c in tone) + (int(255 * op),))
                d.polygon(quad(-s/2 + s*.12, -s/2 + s*.08, s/2 - s*.12, -s/2 + s*.22), fill=(255, 255, 255, int(56 * op)))
                d.polygon(quad(-s/2 + s*.1, s/2 - s*.16, s/2 - s*.1, s/2 - s*.06), fill=(0, 0, 0, int(46 * op)))
    img.save(a.out)

if __name__ == "__main__":
    main()
