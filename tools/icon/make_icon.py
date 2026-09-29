#!/usr/bin/env python3
"""Renders the app icon (light, dark, tinted) — a half-painted paint-by-numbers landscape.

    python3 tools/icon/make_icon.py <out_dir> [rounded-font.ttf]

The number glyphs use a rounded typeface (e.g. Nunito ExtraBold, OFL: `npm pack
@expo-google-fonts/nunito`) to echo SF Rounded used in the app.
"""
import math
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

S = 4096  # supersampled canvas; downscaled to 1024


def wave(y0, amp, freq, phase, tilt=0.0, steps=400):
    pts = []
    for i in range(steps + 1):
        x = S * i / steps
        y = y0 + amp * math.sin(freq * 2 * math.pi * i / steps + phase) + tilt * (i / steps - 0.5) * S
        pts.append((x, y))
    return pts


def region(top, bottom=None):
    """Polygon between a top curve and either another curve or the bottom edge."""
    if bottom is None:
        return top + [(S, S * 2), (0, S * 2)]
    return top + list(reversed(bottom))


def render(variant):
    light = variant == "light"
    tinted = variant == "tinted"
    paper = (255, 253, 248) if light else (46, 44, 50)
    line = (196, 192, 186) if light else (104, 100, 110)
    ink = (150, 146, 140) if light else (150, 146, 156)
    pal = {
        "sky": (255, 221, 199) if light else (52, 47, 84),
        "sun": (255, 182, 72),
        "far": (126, 138, 246) if light else (104, 110, 222),
        "mid": paper,  # left unpainted, shows its number
        "near": (46, 188, 128),
        "front": (255, 98, 104),
    }
    if tinted:
        paper, line, ink = (0, 0, 0), (90, 90, 90), (160, 160, 160)
        pal = {"sky": (40, 40, 40), "sun": (235, 235, 235), "far": (120, 120, 120), "mid": (0, 0, 0),
               "near": (185, 185, 185), "front": (255, 255, 255)}

    img = Image.new("RGB", (S, S), pal["sky"])
    d = ImageDraw.Draw(img)

    far = wave(S * 0.47, S * 0.040, 0.85, 0.3, tilt=-0.06)
    mid = wave(S * 0.62, S * 0.040, 0.75, 2.9, tilt=0.05)
    near = wave(S * 0.765, S * 0.030, 1.05, 4.4, tilt=-0.04)
    front = wave(S * 0.875, S * 0.022, 0.9, 1.3, tilt=0.03)
    for upper, lower in ((far, mid), (mid, near), (near, front)):
        gap = min(b[1] - a[1] for a, b in zip(upper, lower))
        assert gap > S * 0.025, gap

    w = int(S * 0.0075)

    # An unpainted cloud (union of discs) with its outline and number.
    cloud = Image.new("L", (S, S), 0)
    cd = ImageDraw.Draw(cloud)
    for cx, cy, r in ((0.20, 0.235, 0.075), (0.30, 0.19, 0.095), (0.405, 0.235, 0.07), (0.30, 0.255, 0.07)):
        cd.ellipse([S * (cx - r), S * (cy - r), S * (cx + r), S * (cy + r)], fill=255)
    cd.rectangle([S * 0.20, S * 0.235, S * 0.405, S * 0.31], fill=255)
    cloud = cloud.filter(ImageFilter.GaussianBlur(S * 0.004)).point(lambda v: 255 if v > 127 else 0)
    grown = cloud.filter(ImageFilter.MaxFilter(w // 2 * 2 + 1))
    shrunk = cloud.filter(ImageFilter.MinFilter(w // 2 * 2 + 1))
    img.paste(Image.new("RGB", (S, S), paper), (0, 0), cloud)
    img.paste(Image.new("RGB", (S, S), line), (0, 0), ImageChops.subtract(grown, shrunk))

    sun_c, sun_r = (S * 0.66, S * 0.34), S * 0.125
    sun_box = [sun_c[0] - sun_r, sun_c[1] - sun_r, sun_c[0] + sun_r, sun_c[1] + sun_r]
    d.ellipse(sun_box, fill=pal["sun"], outline=line, width=w)
    # Each band covers the one behind it; outlines are drawn on each band's top edge.
    d.polygon(region(far), fill=pal["far"])
    d.line(far, fill=line, width=w, joint="curve")
    d.polygon(region(mid), fill=pal["mid"])
    d.line(mid, fill=line, width=w, joint="curve")
    d.polygon(region(near), fill=pal["near"])

    # The front band is mid-fill: paint spreading radially from a "tap".
    front_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(front_mask).polygon(region(front), fill=255)
    tap, reach = (S * 0.22, S * 0.97), S * 0.50
    reveal = Image.new("L", (S, S), 0)
    ImageDraw.Draw(reveal).ellipse([tap[0] - reach, tap[1] - reach, tap[0] + reach, tap[1] + reach], fill=255)
    reveal = reveal.filter(ImageFilter.GaussianBlur(S * 0.004))
    painted = ImageChops.multiply(front_mask, reveal)
    unpainted = ImageChops.subtract(front_mask, painted)
    img.paste(Image.new("RGB", (S, S), paper), (0, 0), unpainted)
    img.paste(Image.new("RGB", (S, S), pal["front"]), (0, 0), painted)
    # Wet sheen along the leading edge.
    ring = Image.new("L", (S, S), 0)
    rw = S * 0.02
    ImageDraw.Draw(ring).ellipse([tap[0] - reach + rw, tap[1] - reach + rw, tap[0] + reach - rw, tap[1] + reach - rw],
                                 outline=80, width=int(rw))
    ring = ImageChops.multiply(ring.filter(ImageFilter.GaussianBlur(S * 0.006)), front_mask)
    img.paste(Image.new("RGB", (S, S), (255, 255, 255)), (0, 0), ring)

    for curve in (near, front):
        d.line(curve, fill=line, width=w, joint="curve")

    # Unpainted regions show their numbers.
    def font(size):
        try:
            return ImageFont.truetype(FONT, int(size))
        except OSError:
            return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", int(size))
    mx = 0.30
    my = (mid[int(mx * 400)][1] + near[int(mx * 400)][1]) / 2
    d.text((S * mx, my), "3", font=font(S * 0.12), fill=ink, anchor="mm")
    d.text((S * 0.30, S * 0.245), "1", font=font(S * 0.075), fill=ink, anchor="mm")
    fx = 0.82
    fy = (front[int(fx * 400)][1] + S) / 2 - S * 0.01
    d.text((S * fx, fy), "5", font=font(S * 0.065), fill=ink, anchor="mm")

    return img.resize((1024, 1024), Image.LANCZOS)


FONT = sys.argv[2] if len(sys.argv) > 2 else "Nunito_800ExtraBold.ttf"

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    for variant, name in (("light", "AppIcon.png"), ("dark", "AppIcon-Dark.png"), ("tinted", "AppIcon-Tinted.png")):
        render(variant).save(f"{out}/{name}")
