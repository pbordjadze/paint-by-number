#!/usr/bin/env python3
"""The App Store screenshots, composed from CI's screenshots of the real app.

    tools/store_screenshots.py SHOTS --out DIR [--slots DIR] [--chrome PATH]

SHOTS is an unpacked CI report (`git fetch origin +refs/ci-shots/main:refs/ci-shots/main &&
git archive refs/ci-shots/main | tar -x -C SHOTS`): it reads SHOTS/iphone/shots/iphone-<scenario>.png
and SHOTS/ipad/shots/ipad-<scenario>.png, so a scenario named in SLIDES must stay in
ci/scenarios.txt. It writes seven slides per size to DIR (outside the repo):
iphone-69-<n>-<name>.png (1320×2868), iphone-63-<n>-<name>.png (1206×2622, the size
App Store Connect requires) and ipad-13-<n>-<name>.png (2064×2752), RGB without alpha.

The first two slides show the painter's own pets, which CI can't photograph: a crop with a
`slot` reads <device>-<slot>.png from --slots (a folder outside the repo: the painter's photos
are never committed), a full-screen screenshot of the same screen as its stand-in scenario, from
an iPhone or iPad whose screen has the same proportions. Without it, the slide shows the stand-in,
marked PLACEHOLDER, and its file name ends in -placeholder. The slots (SLOTS says what each shows):
iphone-pet-preview.png and iphone-pet-progress.png, and the same two as ipad-*.png. A slide's `own`
layout (crops and photos) replaces its stand-in layout once the painter's shots fill all its slots: a
pet's portrait previews narrower than the stand-in's landscape, and their phone may be in dark mode.
Four slides
also carry a pet's own photo as a taped-on polaroid (a `photo`: --slots/photo-<n>.jpg, already
cropped to its frame's 4:5 or 5:4), each pet shown whole once; without the file the polaroid is
an empty frame marked PLACEHOLDER.

Each slide is an HTML page rendered by headless Chromium: real UI as frameless crops (Apple's
marketing guidelines don't allow drawn device frames), on the app's paper (#F4EFE6) with a
baked grain under the crops (never over the app's pixels), and midnight for the last two. The Red Fox is the coloring book's in-progress
subject because new paintings are always coloring books. Every crop is a fraction of its
source screenshot; every line of copy points at something its screen shows. The headlines are
set in Fraunces at its softest and wonkiest (fetched from Google Fonts into DIR/.fonts on
first run), a gold squiggle under one phrase and the app's gold sparkles beside them, the
cards tilted a little like a scrapbook's; the rest in the system font.

Requires Pillow and Chromium (--chrome, $CHROME, Playwright's under /opt/pw-browsers, or one
on PATH).
"""
import argparse
import glob
import math
import os
import random
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "App/PaintByNumber/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
PAPER, INK, SUB, PLUM, NAVY = "#F4EFE6", "#1F1A21", "#3A333D", "#7B3F7E", "#1B2242"
SOURCE = {"iphone": (1206, 2622), "ipad": (2064, 2752)}
CANVAS = {"iphone": (1320, 2868), "ipad": (2064, 2752)}
FONT_CSS = "https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght,SOFT,WONK@9..144,600,100,1&display=swap"
MOON = "M62 8 A44 44 0 1 0 92 78 A36 36 0 1 1 62 8Z"
SPARKLE = "M50 0Q56.65 43.35 100 50Q56.65 56.65 50 100Q43.35 56.65 0 50Q43.35 43.35 50 0Z"  # Theme.swift's Sparkle
SQUIGGLE = ("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 200 20' preserveAspectRatio='none'%3E"
            "%3Cpath d='M3 13C28 5 46 17 74 10S124 4 150 12S186 15 197 7' fill='none' stroke='%23C9A24A' stroke-width='5' "
            "stroke-linecap='round'/%3E%3C/svg%3E")


SLOTS = {
    "pet-preview": "a pet's photo on the New Painting screen (Photo | Painting)",
    "pet-progress": "a second pet's painting, about a third painted",
}


def crop(scenario, box, scale, x, y, radius=0, shadow=False, fade=0, over=False, slot=None, tilt=0, loupe=False):
    """box is (x0, x1, y0, y1) as fractions of the source; x may be "c" (centered), y "b" (bottom).
    A slot takes the painter's own screenshot of the same screen in place of the scenario; tilt is in degrees.
    A loupe is a round, gold-rimmed magnifier laid over the other crops."""
    return dict(scenario=scenario, box=box, scale=scale, x=x, y=y, radius=radius, shadow=shadow, fade=fade, over=over,
                slot=slot, tilt=tilt, loupe=loupe)


def photo(n, x, y, w, tilt, landscape=False):
    """A taped-on polaroid of the painter's photo-<n>.jpg, w px wide at (x, y)."""
    return dict(n=n, x=x, y=y, w=w, tilt=tilt, landscape=landscape)


SLIDES = {
    "iphone": [
        dict(title="Your <span class=mark>best friend</span>,<br>by numbers", size=124, sub="Pick a photo, and it becomes<br>a painting to fill by number.", crops=[
            crop("create-preview", (.106, .894, .137, .381), 1.38, "c", 1200, radius=56, shadow=True, slot="pet-preview", tilt=-2)], photos=[photo(1, 110, 1990, 560, -5)],
             own=dict(crops=[crop("create-preview", (0, 1, .063, .965), .82, 150, 770, radius=72, shadow=True, slot="pet-preview", tilt=-2)],
                      photos=[photo(1, 790, 470, 400, 7)])),
        dict(title="A portrait for<br><span class=mark>every pet</span>", crops=[
            crop("paint-book-progress", (.045, .955, .348, .622), 1.45, "c", 900, slot="pet-progress"),
            crop("paint-book-progress", (.03, .97, .838, .962), 1.0945, "c", 2300, radius=78, shadow=True, over=True,
                 slot="pet-progress")], photos=[photo(2, 830, 640, 420, 5)]),
        dict(title="Tap, tap, and<br>it’s <span class=mark>painted</span>", sub="Every paint has a name.<br>This one is Corn Husk.", crops=[
            crop("paint-book-zoomed", (0, 1, .28, .97), 1320 / 1206, 0, 888, fade=220)], photos=[photo(3, 690, 610, 560, -4, landscape=True)]),
        dict(title="Twenty <span class=mark>cozy</span><br>minutes", sub="The Great Wave: 22 colors,<br>about 20 minutes.", crops=[
            crop("create-line-art", (.106, .894, .137, .381), 1.3, "c", 960, radius=56, shadow=True, tilt=1.5),
            crop("create-line-art", (0, 1, .838, 1), 1320 / 1206, 0, "b", radius=56, shadow=True, over=True)]),
        dict(title="Van Gogh could<br>use <span class=mark>a hand</span>", sub="Paintings by Hokusai, Van Gogh,<br>Vermeer and others.", crops=[
            crop("create-samples-paintings", (.02, .98, .245, 1), 1.25, "c", 800, radius=56, shadow=True)]),
        dict(night=True, title="Soft paper for<br>the <span class=mark>night owls</span>", sub="Dark paper is easier on the eyes<br>in a dark room.", crops=[
            crop("paint-book-dark-paper", (.045, .955, .343, .627), 1.42, "c", 1100, radius=28, shadow=True),
            crop("paint-book-dark-paper", (.03, .97, .842, .957), 1.0945, "c", 2200, radius=78, shadow=True, over=True)]),
        dict(night=True, title="Written in<br>the <span class=mark>stars</span>", sub="Sun and Moon each have their own<br>music. By Moon, every fill ends in stars.", crops=[
            crop("paint-book-moon-dark", (0, 1, .06, .965), .7, 96, 720, radius=64, shadow=True, tilt=-2),
            crop("paint-book-moon-dark", (.823, .989, .629, .7053), 2.8, 680, 1230, shadow=True, loupe=True),
            crop("settings", (0, 1, .843, .9985), 1.0945, "c", 2180, radius=56, shadow=True, over=True, tilt=2)]),
        dict(night=True, hills=True, title="Right where<br>you <span class=mark>left off</span>", sub="Saved as you go, and kept<br>on your device.", crops=[
            crop("gallery", (.035, .485, .265, .535), 2.1, 104, 900, radius=72, shadow=True, over=True, tilt=-2.5)], photos=[photo(4, 850, 740, 410, 6)]),
    ],
    "ipad": [
        dict(title="Your <span class=mark>best friend</span>,<br>by numbers", size=170, sub="Pick a photo, and it becomes a painting to fill by number.", crops=[
            crop("create-preview", (.031, .968, .089, .561), 1.05, "c", 1000, radius=56, shadow=True, slot="pet-preview", tilt=-2)], photos=[photo(1, 140, 2000, 520, -5)]),
        dict(title="A portrait for<br><span class=mark>every pet</span>", crops=[
            crop("paint-book-progress", (.02, .98, .243, .72), 1.12, "c", 760, slot="pet-progress"),
            crop("paint-book-progress", (.035, .965, .925, .99), 1.0, "c", 2440, radius=70, shadow=True, over=True,
                 slot="pet-progress")], photos=[photo(2, 1500, 600, 440, 5)]),
        dict(title="Tap, tap, and<br>it’s <span class=mark>painted</span>", sub="Every paint has a name. This one is Corn Husk.", crops=[
            crop("paint-book-zoomed", (0, 1, .20, .982), 1.0, 0, 700, fade=240)], photos=[photo(3, 1340, 840, 600, -4, landscape=True)]),
        dict(title="Twenty <span class=mark>cozy</span><br>minutes", sub="The Great Wave: 22 colors, about 20 minutes.", crops=[
            crop("create-line-art", (.031, .968, .089, .561), 1.0, "c", 840, radius=56, shadow=True, tilt=1.2),
            crop("create-line-art", (0, 1, .895, 1), 1.0, 0, "b", radius=64, shadow=True, over=True)]),
        dict(title="Van Gogh could<br>use <span class=mark>a hand</span>", sub="Paintings by Hokusai, Van Gogh, Vermeer and others.", crops=[
            crop("create-samples-paintings", (.585, .985, .108, .535), 1.9, "c", 760, radius=56, shadow=True)]),
        dict(night=True, title="Soft paper for<br>the <span class=mark>night owls</span>", sub="Dark paper is easier on the eyes in a dark room.", crops=[
            crop("paint-book-dark-paper", (.02, .98, .239, .725), 1.12, "c", 860, radius=28, shadow=True),
            crop("paint-book-dark-paper", (.054, .945, .927, .983), 1.0, "c", 2440, radius=70, shadow=True, over=True)]),
        dict(night=True, title="Written in<br>the <span class=mark>stars</span>", sub="Sun and Moon each have their own music. By Moon, every fill ends in stars.", crops=[
            crop("paint-book-moon-dark", (0, 1, 0, 1), .52, 144, 860, radius=44, shadow=True, tilt=-1.5),
            crop("paint-book-moon-dark", (.845, 1, .597, .7133), 1.85, 1180, 1420, shadow=True, loupe=True),
            crop("settings", (.045, .955, .468, .628), .95, "c", 2260, radius=40, shadow=True, over=True, tilt=1.5)]),
        dict(night=True, hills=True, title="Right where<br>you <span class=mark>left off</span>", sub="Saved as you go, and kept on your device.", crops=[
            crop("gallery", (.014, .328, .145, .418), 2.1, 144, 760, radius=80, shadow=True, over=True, tilt=-2)], photos=[photo(4, 1480, 700, 480, 6)]),
    ],
}


def find_chrome(arg):
    candidates = [arg, os.environ.get("CHROME")]
    candidates += sorted(glob.glob("/opt/pw-browsers/chromium-*/chrome-linux/chrome"), reverse=True)
    candidates += [shutil.which(n) for n in ("chromium", "chromium-browser", "google-chrome")]
    candidates.append("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    for c in candidates:
        if c and os.path.exists(c):
            return c
    sys.exit("No Chromium found: pass --chrome PATH or set $CHROME")


def fetch_fonts(out):
    """Fraunces from Google Fonts, kept beside the output so later runs work offline."""
    folder = out / ".fonts"
    css = folder / "display.css"
    if css.exists():
        return css
    folder.mkdir(parents=True, exist_ok=True)
    agent = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}
    text = urllib.request.urlopen(urllib.request.Request(FONT_CSS, headers=agent)).read().decode()
    for url in sorted(set(re.findall(r"url\((https://[^)]+)\)", text))):
        name = url.rsplit("/", 1)[1]
        (folder / name).write_bytes(urllib.request.urlopen(url).read())
        text = text.replace(url, name)
    css.write_text(text)
    return css


def grain(out):
    """A seeded noise tile: the same bytes on every run."""
    path = out / ".fonts" / "grain.png"
    if not path.exists():
        r = random.Random(7)
        data = bytes(max(0, min(255, round(r.gauss(128, 46)))) for _ in range(600 * 600))
        Image.frombytes("L", (600, 600), data).save(path)
    return path


def hills(W, H, dev):
    """The icon's plum hill and paper foreground, inked by hand-wobbled lines."""
    crest = (2050, 1900) if dev == "iphone" else (2000, 1820)
    paper_top = 2450 if dev == "iphone" else 2380
    n = 60

    def line(base, seed):
        r = random.Random(seed)
        return [(W * i / n, base(i / n) + r.uniform(-3, 3)) for i in range(n + 1)]

    top = line(lambda t: crest[0] + (crest[1] - crest[0]) * t + 40 * math.sin(t * 5.5), 1)
    fg = line(lambda t: paper_top - 30 * math.sin(t * 4 + 1), 2)

    def path(pts):
        return f"M-20 {pts[0][1]:.1f} " + " ".join(f"L{x:.1f} {y:.1f}" for x, y in pts) + f" L{W + 20} {H + 20} L-20 {H + 20}Z"

    return (f"<svg class=hills viewBox='0 0 {W} {H}' width={W} height={H}>"
            f"<path d='{path(top)}' fill='{PLUM}' stroke='{INK}' stroke-width='6' stroke-linejoin='round'/>"
            f"<path d='{path(fg)}' fill='{PAPER}' stroke='{INK}' stroke-width='6' stroke-linejoin='round'/></svg>")


def photo_path(slots, p):
    path = slots / f"photo-{p['n']}.jpg" if slots else None
    return path.resolve() if path and path.exists() else None


def photo_html(slots, p):
    w, pad = p["w"], p["w"] * .045
    iw = w - 2 * pad
    ih = iw * (.8 if p["landscape"] else 1.25)
    src = photo_path(slots, p)
    inner = (f"<div class=snap style='width:{iw:.0f}px;height:{ih:.0f}px;background:url({src.as_uri()}) center/cover'></div>"
             if src else f"<div class=snap style='width:{iw:.0f}px;height:{ih:.0f}px;background:#E8E2D8'></div>"
                         f"<div class=tag style='left:{pad + 20:.0f}px;top:{pad + 20:.0f}px'>PLACEHOLDER: a pet photo</div>")
    return (f"<div class=polaroid style='left:{p['x']}px;top:{p['y']}px;padding:{pad:.0f}px {pad:.0f}px {w * .15:.0f}px;"
            f"transform:rotate({p['tilt']}deg)'>{inner}<div class=tape style='width:{w * .38:.0f}px;height:{w * .09:.0f}px;"
            f"left:{w * .31:.0f}px;top:{-w * .04:.0f}px'></div></div>")


def own_shot(slots, dev, c):
    """The painter's screenshot for this crop's slot, if --slots has it."""
    if c["slot"] and slots:
        path = slots / f"{dev}-{c['slot']}.png"
        if path.exists():
            return path.resolve()
    return None


def crop_html(shots, dev, c, W, H, slots, label=None):
    SW, SH = SOURCE[dev]
    x0, x1, y0, y1 = c["box"]
    s = c["scale"]
    w, h = (x1 - x0) * SW * s, (y1 - y0) * SH * s
    x = (W - w) / 2 if c["x"] == "c" else c["x"]
    y = H - h if c["y"] == "b" else c["y"]
    src = own_shot(slots, dev, c) or (shots / dev / "shots" / f"{dev}-{c['scenario']}.png").resolve()
    if not src.exists():
        sys.exit(f"Missing {src}: is {c['scenario']} still a CI scenario?")
    stand_in = c["slot"] and not own_shot(slots, dev, c)
    style = [f"left:{x:.1f}px", f"top:{y:.1f}px", f"width:{w:.1f}px", f"height:{h:.1f}px",
             f"background:url({src.as_uri()}) {-x0 * SW * s:.1f}px {-y0 * SH * s:.1f}px/{SW * s:.1f}px {SH * s:.1f}px no-repeat",
             f"z-index:{3 if c['over'] else 1}"]
    if c["radius"]:
        r = c["radius"]
        style.append(f"border-radius:{r}px {r}px 0 0" if c["y"] == "b" else f"border-radius:{r}px")
    if c["shadow"]:
        style.append("box-shadow:0 28px 64px rgba(31,26,33,.20),0 2px 6px rgba(31,26,33,.08)")
    if c["loupe"]:
        style += ["border-radius:50%", "border:10px solid #C9A24A", "background-origin:border-box", "z-index:3"]
    if c["fade"]:
        f = c["fade"]
        style.append(f"-webkit-mask-image:linear-gradient(to bottom,transparent 0,#000 {f}px)")
    if c["tilt"]:
        style.append(f"transform:rotate({c['tilt']}deg)")
    if stand_in:
        style.append(f"outline:6px dashed {PLUM};outline-offset:10px")
    inset = 96 if dev == "iphone" else 144  # a full-bleed crop starts off the page; its tag starts at the text margin
    tag = (f"<div class=tag style='left:{max(inset, x + 32):.1f}px;top:{y + 32:.1f}px'>PLACEHOLDER: {label}</div>"
           if stand_in and label else "")
    return f"<div class=crop style='{';'.join(style)}'></div>{tag}"


def laid_out(slide, dev, slots):
    """The slide as drawn: its `own` layout once the painter's screenshots fill its slots."""
    own = slide.get("own")
    if own and all(own_shot(slots, dev, c) for c in own["crops"] if c["slot"]):
        return {**slide, **own}
    return slide


def page(shots, dev, k, slide, fonts, noise, slots):
    W, H = CANVAS[dev]
    slide = laid_out(slide, dev, slots)
    night = slide.get("night", False)
    phone = dev == "iphone"
    margin, folio_y, folio = (96, 130, 36) if phone else (144, 120, 46)
    size = slide.get("size", 120 if phone else 160)
    fg = PAPER if night else INK
    blend, opacity = ("soft-light", .22) if night else ("overlay", .6)
    extra = ""
    if slide.get("hills"):
        m, (mx, my) = (180, (1060, 90)) if phone else (300, (1640, 120))
        extra = (hills(W, H, dev)
                 + f"<div class=glow style='left:{mx + m / 2 - 520}px;top:{my + m / 2 - 520}px'></div>"
                 + f"<svg class=moon viewBox='0 0 100 100' style='left:{mx}px;top:{my}px;width:{m}px;height:{m}px'>"
                   f"<path d='{MOON}' fill='url(#gold)'/></svg>")
    sub = f"<p>{slide['sub']}</p>" if slide.get("sub") else ""
    photos = slide.get("photos", [])
    extra += "".join(photo_html(slots, p) for p in photos)
    if not slide.get("hills") and not any(p["y"] < 900 for p in photos):  # the moon, or a photo, has that corner
        r = random.Random(k)
        for i, (x0, x1, y0, y1, s) in enumerate(((.70, .80, 230, 300, 70), (.83, .90, 360, 440, 44), (.74, .82, 520, 600, 30))):
            sz = s * (1 if phone else 1.3)
            extra += (f"<svg class=moon viewBox='0 0 100 100' style='left:{W * r.uniform(x0, x1):.0f}px;"
                      f"top:{r.uniform(y0, y1):.0f}px;width:{sz:.0f}px;height:{sz:.0f}px'><path d='{SPARKLE}' fill='url(#gold)'/></svg>")
    first_slot = next((c for c in slide["crops"] if c["slot"]), None)
    crops = "".join(crop_html(shots, dev, c, W, H, slots, SLOTS[c["slot"]] if c is first_slot else None)
                    for c in slide["crops"])
    return f"""<!doctype html><html><head><meta charset=utf-8>
<link rel=stylesheet href='{fonts.as_uri()}'>
<style>
*{{margin:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px;overflow:hidden}}
body{{position:relative;background:{NAVY if night else PAPER};font-family:-apple-system,"SF Pro Text",Inter,"Helvetica Neue",sans-serif}}
.crop,.hills,.moon,.glow,.grain,.tag,.polaroid,.tape{{position:absolute}}
.polaroid{{z-index:4;background:#FFFDF8;box-shadow:0 24px 50px rgba(31,26,33,.28),0 2px 6px rgba(31,26,33,.12)}}
.snap{{position:relative}}
.tape{{background:rgba(201,162,74,.45);transform:rotate(-4deg)}}
.tag{{z-index:6;max-width:{W - 2 * margin - 64}px;padding:16px 28px;border-radius:28px;background:{PLUM};color:{PAPER};
  font:600 {32 if phone else 40}px/1.25 -apple-system,"SF Pro Text",Inter,sans-serif}}
.hills{{left:0;top:0;z-index:2}}
.grain{{inset:0;z-index:0;mix-blend-mode:{blend};opacity:{opacity};background:url({noise.as_uri()}) 0 0/600px 600px}}
.glow{{width:1040px;height:1040px;border-radius:50%;background:radial-gradient(circle,rgba(201,162,74,.14),rgba(201,162,74,0) 62%)}}
.moon{{z-index:4}}
.folio{{position:absolute;left:{margin}px;top:{folio_y}px;display:flex;align-items:center;gap:{folio * .55:.0f}px;z-index:5;
  font:600 {folio}px Fraunces,serif;color:{fg}}}
.folio img{{width:{folio * 2}px;height:{folio * 2}px;border-radius:{folio * .45:.0f}px;box-shadow:0 0 0 1px rgba(31,26,33,.10)}}
.text{{position:absolute;left:{margin}px;right:{margin}px;top:300px;z-index:5}}
h1{{font:600 {size}px/1.02 Fraunces,serif;letter-spacing:-.015em;color:{fg}}}
.mark{{background:url("{SQUIGGLE}") 0 100%/100% .26em no-repeat;padding-bottom:.08em}}
p{{margin-top:{32 if phone else 40}px;font-size:{44 if phone else 56}px;line-height:1.3;font-weight:500;
  color:{"rgba(244,239,230,.78)" if night else SUB};max-width:{900 if phone else 1640}px}}
</style></head><body>
<svg width=0 height=0 style=position:absolute><defs><linearGradient id=gold x1=0 y1=0 x2=1 y2=1>
<stop offset=0 stop-color='#EDD089'/><stop offset=1 stop-color='#B98F32'/></linearGradient></defs></svg>
{crops}{extra}<div class=grain></div>
<div class=folio><img src='{ICON.as_uri()}'><span>Paint by Moonlight</span></div>
<div class=text><h1>{slide['title']}</h1>{sub}</div>
</body></html>"""


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("shots", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--slots", type=Path, help="the painter's own screenshots for the slots (outside the repo)")
    ap.add_argument("--chrome")
    args = ap.parse_args()
    chrome = find_chrome(args.chrome)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    fonts, noise = fetch_fonts(out), grain(out)
    pages = out / ".pages"
    pages.mkdir(exist_ok=True)
    for dev, slides in SLIDES.items():
        W, H = CANVAS[dev]
        for k, slide in enumerate(slides, 1):
            slide = laid_out(slide, dev, args.slots)
            first = slide["crops"][0]
            name = first["slot"] or first["scenario"]
            if (any(c["slot"] and not own_shot(args.slots, dev, c) for c in slide["crops"])
                    or any(not photo_path(args.slots, p) for p in slide.get("photos", []))):
                name += "-placeholder"
            html = pages / f"{dev}-{k}.html"
            html.write_text(page(args.shots, dev, k - 1, slide, fonts, noise, args.slots))
            png = out / (f"iphone-69-{k}-{name}.png" if dev == "iphone" else f"ipad-13-{k}-{name}.png")
            # The window runs taller than the slide: headless Chrome loses the bottom of an exact-size one.
            subprocess.run([chrome, "--headless", "--no-sandbox", "--hide-scrollbars", "--allow-file-access-from-files",
                            "--force-device-scale-factor=1", f"--window-size={W},{H + 400}", "--virtual-time-budget=4000",
                            f"--screenshot={png}", html.as_uri()], check=True, capture_output=True)
            image = Image.open(png).crop((0, 0, W, H)).convert("RGB")
            image.save(png)
            if dev == "iphone":
                image.resize((1206, 2622), Image.LANCZOS).save(out / f"iphone-63-{k}-{name}.png")
            print(png.name)


if __name__ == "__main__":
    main()
