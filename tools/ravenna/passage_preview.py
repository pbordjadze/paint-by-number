#!/usr/bin/env python3
"""A still of the era passage (App/PaintByNumber/App/EraDoor.swift, `EraPassage`), to judge its
look off the device. It mirrors `EraPassage.tiles(in:)` and the cover's drawing with Pillow, its
own random draws (not the app's), so it shows the shape and light, not the exact tiles.

    python3 tools/ravenna/passage_preview.py out.png [--width 1032 --height 1376 --at 0.67 --scale 2]
"""
import argparse, math, random
from PIL import Image, ImageDraw

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--width", type=float, default=1032)
    ap.add_argument("--height", type=float, default=1376); ap.add_argument("--at", type=float, default=0.67)
    ap.add_argument("--scale", type=float, default=2)
    a = ap.parse_args(); k = a.scale
    W, H = a.width, a.height
    img = Image.new("RGB", (int(W * k), int(H * k)), (20, 19, 17))
    d = ImageDraw.Draw(img, "RGBA")
    pitch = max(22, round(min(W, H) / 36))
    cx, cy = W / 2, H + pitch
    far = math.hypot(max(cx, W - cx), cy) + pitch
    gold, lime, lapis = (0.788, 0.635, 0.290), (0.914, 0.886, 0.827), (0.122, 0.165, 0.322)
    rnd = random.Random(547)
    for course in range(math.ceil(far / pitch)):
        radius = (course + 0.6) * pitch
        count = max(3, round(math.pi * radius / pitch)); step = math.pi / count; shift = rnd.random() * step
        tone = lime if course % 7 == 4 else lapis if course % 7 in (5, 6) else gold
        for i in range(count):
            th = shift + i * step
            r = radius + (rnd.random() - 0.5) * pitch * 0.12
            x, y = cx + r * math.cos(th), cy - r * math.sin(th)
            side = pitch * (0.8 + rnd.random() * 0.1)
            if not (-side < x < W + side and -side < y < H + side): continue
            ang = -th + (rnd.random() - 0.5) * 0.14
            light = 0.86 + rnd.random() * 0.24
            delay = min(1, radius / far + rnd.random() * 0.06)
            local = (a.at - delay * 0.75) / 0.25
            if local <= 0: continue
            e = min(1, local); sc = 1.35 - 0.35 * (1 - (1 - e) ** 3); s = side * sc
            def quad(x0, y0, x1, y1):
                pts = []
                for px, py in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
                    rx = px * math.cos(ang) - py * math.sin(ang); ry = px * math.sin(ang) + py * math.cos(ang)
                    pts.append(((x + rx) * k, (y + ry) * k))
                return pts
            col = tuple(int(min(1, c * light) * 255) for c in tone) + (int(255 * e),)
            d.polygon(quad(-s/2, -s/2, s/2, s/2), fill=col)
            d.polygon(quad(-s/2 + s*.12, -s/2 + s*.08, s/2 - s*.12, -s/2 + s*.22), fill=(255, 255, 255, int(56 * e)))
            d.polygon(quad(-s/2 + s*.1, s/2 - s*.16, s/2 - s*.1, s/2 - s*.06), fill=(0, 0, 0, int(46 * e)))
    img.save(a.out)

if __name__ == "__main__":
    main()
