#!/usr/bin/env python3
"""The create flow's demo drawing, for pbn on Linux.

A copy of `ShellDemo.drawingPhoto()` (App/PaintByNumber/App/ShellDemo.swift) in Pillow: the
sheet with a house, a sun, a tree, a wavy ground line, a solid door, a hatched roof and a row of
small loops, laid askew on a dark table under a light that falls off to one side, so the page the
`create-drawing` scenario and `DrawingFlowTests` make can be run through `pbn drawing` here and
looked at. The geometry is the Swift's, with CoreGraphics' bottom-up y flipped; the two differ in
anti-aliasing and the JPEG, not in what is drawn. Keep the two in step.

    tools/drawings/demo_page.py out.ppm [--jpeg out.jpg]
"""
import argparse, math
from PIL import Image, ImageDraw

W, H = 1400, 1800
SHEET_W, SHEET_H = 1100, 1440
INK = (20, 18, 23)


def sheet():
    # The paper, lit from its top-right (CoreGraphics' bottom-right of the sheet after the flip).
    img = Image.new("RGB", (SHEET_W, SHEET_H))
    px = img.load()
    for y in range(SHEET_H):
        for x in range(SHEET_W):
            t = (x / SHEET_W + (SHEET_H - y) / SHEET_H) / 2  # 1 at CG (1100,1440): the light end
            t = 1 - t
            px[x, y] = (round(247 - (247 - 184) * t), round(245 - (245 - 179) * t), round(237 - (237 - 168) * t))
    d = ImageDraw.Draw(img)
    def P(x, y): return (x, SHEET_H - y)  # CoreGraphics' y, up, to Pillow's, down
    # The ground, wavy.
    pts = []
    for i in range(201):
        s = i / 200
        p0, p1, p2, p3 = (60, 420), (400, 300), (700, 520), (1040, 400)
        x = (1 - s) ** 3 * p0[0] + 3 * (1 - s) ** 2 * s * p1[0] + 3 * (1 - s) * s ** 2 * p2[0] + s ** 3 * p3[0]
        y = (1 - s) ** 3 * p0[1] + 3 * (1 - s) ** 2 * s * p1[1] + 3 * (1 - s) * s ** 2 * p2[1] + s ** 3 * p3[1]
        pts.append(P(x, y))
    d.line(pts, fill=INK, width=9, joint="curve")
    # Pillow strokes an outline inward from its box; CoreGraphics centres it on the path.
    def rect(x, y, w, h, width=9):
        e = width / 2
        d.rectangle([P(x - e, y + h + e), P(x + w + e, y - e)], outline=INK, width=width)
    def ellipse(x, y, w, h, width=9):
        e = width / 2
        d.ellipse([P(x - e, y + h + e), P(x + w + e, y - e)], outline=INK, width=width)
    rect(240, 420, 420, 330)
    d.line([P(200, 750), P(450, 1010), P(700, 750), P(200, 750)], fill=INK, width=9, joint="curve")
    for k in range(9):
        y = 770 + k * 25
        half = (y - 750) * 250 / 260
        d.line([P(450 - (250 - half), y), P(450 + (250 - half), y)], fill=INK, width=4)
    d.rectangle([P(400, 590), P(500, 420)], fill=INK)
    rect(280, 560, 90, 90)
    ellipse(800, 1080, 180, 180)
    for k in range(12):
        a = k / 12 * 2 * math.pi
        d.line([P(890 + math.cos(a) * 110, 1170 + math.sin(a) * 110), P(890 + math.cos(a) * 150, 1170 + math.sin(a) * 150)], fill=INK, width=9)
    rect(850, 420, 50, 200)
    ellipse(760, 580, 230, 260)
    for k in range(14):
        ellipse(300 + k * 36, 200, 18, 26)
    return img


def page():
    table = Image.new("RGB", (W, H), (77, 51, 36))
    s = sheet().rotate(0.05 * 180 / math.pi, resample=Image.BICUBIC, expand=True, fillcolor=None)
    # CG: translate(700, 900), rotate(0.05), translate(-550, -720): the sheet's centre at (700, 900) from the
    # bottom, turned counter-clockwise on screen (CG's bitmap is y-up, and PIL's positive angle turns the same way).
    cx, cy = 700, H - 900
    mask = Image.new("L", (SHEET_W, SHEET_H), 255).rotate(0.05 * 180 / math.pi, resample=Image.BICUBIC, expand=True)
    table.paste(s, (cx - s.width // 2, cy - s.height // 2), mask)
    return table


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out")
    ap.add_argument("--jpeg")
    a = ap.parse_args()
    img = page()
    if a.jpeg:
        img.save(a.jpeg, quality=85)
        img = Image.open(a.jpeg).convert("RGB")
    img.save(a.out)
