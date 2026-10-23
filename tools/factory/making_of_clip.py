#!/usr/bin/env python3
"""A render of the making-of show, for judging its rhythm, drawn with Pillow: the show the app plays
(making_of_fields.py, whose Swift port is Sources/MakingOf's FieldShow), built from the shared modules
(the layers composited by making_of_compose.py, the template's lines and numbers, the cards and the
seed rings). The crew show it also played left with the Marginarium. Paul's decision (October 23):
the Marginarium is private for now; it leaves every build and this repository. Its archive is in the
private painting-company repository.

Usage:
  making_of_clip.py <generate-out> <snapshots> <out.mp4> [--width PX] [--fps 60] [--step SECONDS]
                    [--spec JSON] [--seed 7] [--stills DIR]

The show's spec (--spec, default App/PaintByNumber/Resources/making-of.json) sets the timing and each
step's card (its caption, with its methods' credit lines from ACKNOWLEDGEMENTS.md as a footnote,
printed letter for letter); --step overrides its step. Everything the show decides (the seeds step 3
drops, the noise that roughens each step's change, where each step's change grows from) is chosen by
the shared modules from --seed, as Sources/MakingOf chooses them; the pictures are the snapshots' own
size, which the pipeline keeps to 1024 px on the long side, and --width only scales the video (and the
stills) to that many pixels across. --no-crew, which picked this show when there were two, is
accepted and changes nothing.

Timeline: the photo alone for INTRO seconds, six steps of STEP seconds, then the template held for
the show's outro; making_of_fields.py's docstring says how each step's change grows.

--stills DIR also writes a frame every quarter second, for contact sheets. Needs numpy, Pillow,
ffmpeg, the Charter Type 1 fonts (xfonts-scalable) and making_of_layers.py's node setup (the
template's numbers are the SVG's own glyphs, rasterized by resvg).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_fields  # noqa: E402
import making_of_inputs  # noqa: E402
import making_of_layers as layers  # noqa: E402
import making_of_reveal as reveal  # noqa: E402

CARD_BAND = making_of_inputs.CARD_BAND
FONT_DIR = '/usr/share/fonts/X11/Type1'
CHARTER = os.path.join(FONT_DIR, 'c0648bt_.pfb')
CHARTER_ITALIC = os.path.join(FONT_DIR, 'c0649bt_.pfb')

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESOURCES = os.path.join(ROOT, 'App', 'PaintByNumber', 'Resources')
SPEC = os.path.join(RESOURCES, 'making-of.json')
STEPS = []          # (id, caption, [(authors, year, title)]) per step, from the spec and Acknowledgements


def credits(names):
    """Each method's credit line as ACKNOWLEDGEMENTS.md prints it: (authors, year, title). A
    card prints exactly this, so a name that isn't credited there stops the render."""
    text = open(os.path.join(ROOT, 'ACKNOWLEDGEMENTS.md'), encoding='utf-8').read()
    out = []
    for name in names:
        # the exact heading (the models have one of their own, "Informative Drawings"), and the
        # credit line inside that section, never past the next heading
        m = re.search(r'^### ' + re.escape(name) + r'\n(?:(?!### ).*\n)*?(.+), "(.+)", (\d{4})$', text, re.M)
        if not m:
            sys.exit(f'{name}: no credit in ACKNOWLEDGEMENTS.md')
        out.append((m.group(1), m.group(3), m.group(2)))
    return out


def load_spec(path):
    """Reads the show's spec; the steps' cards get their credit lines from Acknowledgements."""
    global STEPS
    spec = json.load(open(path, encoding='utf-8'))
    if spec.get('version') != 1 or len(spec['steps']) != 6:
        sys.exit(f'{path}: expected version 1 with six steps')
    STEPS = [(st['id'], st['caption'], credits(st['methods'])) for st in spec['steps']]
    return spec


def ink_line(pen, pts, value, width):
    """Draws a polyline at `value` onto `pen`, keeping whatever is darker there already."""
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = max(int(min(xs)) - width, 0), max(int(min(ys)) - width, 0)
    x1, y1 = min(int(max(xs)) + width + 1, pen.width), min(int(max(ys)) + width + 1, pen.height)
    if x0 >= x1 or y0 >= y1:
        return
    tmp = Image.new('L', (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(tmp).line([(x - x0, y - y0) for x, y in pts], fill=value, width=width, joint='curve')
    pen.paste(ImageChops.lighter(pen.crop((x0, y0, x1, y1)), tmp), (x0, y0))


def pen_coverage(lines, size, line_width):
    """The coverage (0...1, (H, W, 1)) of a frame's lines, drawn with Pillow on a canvas twice as big
    and reduced, `line_width` px across, the darker winning where lines meet."""
    W, H = size
    width = max(1, round(2 * line_width))
    pen = Image.new('L', (W * 2, H * 2), 0)
    if all(line['value'] == 1 for line in lines):
        d = ImageDraw.Draw(pen)
        for line in lines:
            d.line([(x * 2, y * 2) for x, y in line['points']], fill=255, width=width)
    else:
        for line in lines:
            ink_line(pen, [(x * 2, y * 2) for x, y in line['points']], int(255 * line['value']), width)
    return np.asarray(pen.reduce(2), dtype=np.float32)[..., None] / 255


def rasterized(svg, size):
    """The template through resvg at the picture's size: its colors (numbers included) and, without
    the numbers, how much of each pixel the lines cover (white ground), both 0...1 floats."""
    with tempfile.TemporaryDirectory() as tmp:
        layers.rasterize(svg, size[0], os.path.join(tmp, 'template.png'))
        layers.rasterize(svg, size[0], os.path.join(tmp, 'lines.png'), numbers=False)
        return layers.load(os.path.join(tmp, 'template.png'), size, 'RGB'), layers.load(os.path.join(tmp, 'lines.png'), size, 'L')


class Cards:
    """Each step's card, after Caroline: what the step does in a few plain words, and under it,
    smaller and fainter like a footnote, the credit line of each paper it stands on."""

    def __init__(self, width, footnote):
        self.width = width
        self.footnote = footnote
        self.cache = {}

    def image(self, k):
        if k in self.cache:
            return self.cache[k]
        w = self.width
        img = Image.new('L', (w, CARD_BAND), 0)
        d = ImageDraw.Draw(img)
        caption = ImageFont.truetype(CHARTER, 31)
        small = ImageFont.truetype(CHARTER, 16)
        small_italic = ImageFont.truetype(CHARTER_ITALIC, 16)
        _, text, cites = STEPS[k]
        marks = ','.join('¹²³'[i] for i in range(len(cites)))
        d.text(((w - d.textlength(text + marks, font=caption)) / 2, 54), text + marks, font=caption, fill=255)
        y = 116
        faint = int(255 * self.footnote)
        for i, (authors, year, title) in enumerate(cites):
            # the credit line letter for letter, the title in italics, wrapped to the card
            runs = [(f'{"¹²³"[i]} {authors} · {year} · ', small)] + [(word + ' ', small_italic) for word in title.split()]
            lines, cur, width_now = [], [], 0.0
            for run, font in runs:
                size = d.textlength(run, font=font)
                if cur and width_now + size > w * 0.9:
                    lines.append(cur)
                    cur, width_now = [], 0.0
                cur.append((run, font))
                width_now += size
            lines.append(cur)
            for line in lines:
                x = (w - sum(d.textlength(r, font=f) for r, f in line)) / 2
                for run, font in line:
                    d.text((x, y), run, font=font, fill=faint)
                    x += d.textlength(run, font=font)
                y += 22
            y += 6
        a = np.asarray(img, dtype=np.float32) / 255
        self.cache[k] = a
        return a


def draw_rings(draw, frame):
    """The k-means++ seeds' rings: an ink circle over a paper halo, with a dot at its middle."""
    ink = tuple(int(v) for v in layers.STYLE.ink)
    paper = tuple(int(v) for v in layers.STYLE.paper)
    for ring in frame['seed_rings']:
        x, y, r, al = ring['x'], ring['y'], ring['radius'], int(255 * ring['alpha'])
        if al <= 0:
            continue
        draw.ellipse((x - r - 2.5, y - r - 2.5, x + r + 2.5, y + r + 2.5), fill=paper + (al,))
        draw.ellipse((x - r, y - r, x + r, y + r), outline=ink + (al,), width=3)
        draw.ellipse((x - 2.6, y - 2.6, x + 2.6, y + 2.6), fill=ink + (al,))


def draw_marks(draw, frame):
    """The show's own marks (making_of_fields.py): a spark at each burning tip of the
    ink step's lines, and a faint ring opening round each number as it comes out."""
    ink = tuple(int(v) for v in layers.STYLE.ink)
    for spark in frame.get('sparks', ()):
        x, y, heat = spark['x'], spark['y'], spark['heat']
        r = 1.6 + 1.6 * heat
        draw.ellipse((x - r, y - r, x + r, y + r), fill=ink + (int(230 * heat),))
    for star in frame.get('stars', ()):
        x, y, r = star['x'], star['y'], star['radius']
        draw.ellipse((x - r, y - r, x + r, y + r), outline=ink + (int(255 * star['alpha']),), width=1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('generated')
    ap.add_argument('snapshots')
    ap.add_argument('out')
    ap.add_argument('--width', type=int, help="scale the video to this many pixels across (default the picture's own "
                    "width, the snapshots': the pipeline keeps its long side to 1024)")
    ap.add_argument('--fps', type=int, default=60)
    ap.add_argument('--no-crew', action='store_true', help='accepted and ignored: the show has no crew')
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--stills')
    ap.add_argument('--step', type=float)
    ap.add_argument('--spec', default=SPEC)
    a = ap.parse_args()
    spec = load_spec(a.spec)
    if a.step:
        spec['timing']['step'] = a.step
    svg = os.path.join(a.generated, 'template.svg')
    show = making_of_fields.FieldShow(a.snapshots, svg, spec, a.seed)
    total = show.duration
    W, H = show.size
    template, lines = rasterized(svg, show.size)
    numbers_mult = np.where(lines[..., None] > 0.85, template, 1.0)       # the numbers' glyphs, as a multiply layer
    owner = reveal.number_discs(show.built.numbers, (H, W))               # the number each pixel belongs to
    real = layers.PAPER * template                                          # the real template, which the hold ends in
    cards = Cards(W, float(spec['cards']['footnote']))
    frame_h = H + CARD_BAND
    frame_h += frame_h % 2
    out_w = a.width or W
    out_h = frame_h if out_w == W else round(frame_h * out_w / W / 2) * 2
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{out_w}x{out_h}',
           '-r', str(a.fps), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-movflags', '+faststart', a.out]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    if a.stills:
        os.makedirs(a.stills, exist_ok=True)
    for f in range(int(round(total * a.fps))):
        t = f / a.fps
        frame = show.frame(t)
        stage = frame['picture']['stage']
        pen = pen_coverage(frame['ink'], show.size, show.line_width) if frame['ink'] else None
        numbers = None
        if frame['numbers']:                  # each in its own disc; owner -1 is the 0 at the end
            numbers = (np.array(frame['numbers'] + [0.0])[owner][..., None], numbers_mult)
        pic = show.compositor.picture(t, pen, numbers, real, frame['picture']['handoff'])

        canvas = np.empty((frame_h, W, 3), dtype=np.float32)
        canvas[:H] = pic
        canvas[H:] = layers.PAPER
        if frame['card']:
            c = cards.image(frame['card']['step'])[..., None] * frame['card']['opacity']
            canvas[H:H + CARD_BAND] = canvas[H:H + CARD_BAND] * (1 - c) + layers.INK * c
        img = Image.fromarray((np.clip(canvas, 0, 1) * 255 + 0.5).astype(np.uint8))
        draw = ImageDraw.Draw(img, "RGBA")
        draw_rings(draw, frame)
        draw_marks(draw, frame)
        if (out_w, out_h) != img.size:
            img = img.resize((out_w, out_h), Image.LANCZOS)
        enc.stdin.write(img.tobytes())
        if a.stills and f % max(1, a.fps // 4) == 0:
            img.save(os.path.join(a.stills, f'{t:05.2f}.jpg'), quality=85)
    enc.stdin.close()
    if enc.wait():
        sys.exit('ffmpeg failed')


if __name__ == '__main__':
    main()
