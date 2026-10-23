#!/usr/bin/env python3
"""A render of the making-of show, for judging its rhythm, drawn with Pillow: the crew show
(making_of_show.py, built from the shared modules: the layers composited by making_of_compose.py, the
template's lines and numbers, the cards, the seed rings and the Lamp's guardians, making_of_pets.py,
as the crew), or with --no-crew the show the app plays (making_of_fields.py, whose Swift port is
Sources/MakingOf's FieldShow).

Usage:
  making_of_clip.py <generate-out> <snapshots> <out.mp4> [--width PX] [--fps 60] [--crew N] [--no-crew]
                    [--step SECONDS] [--pets RESOURCES] [--spec JSON] [--seed 7]
                    [--stills DIR] [--pet-height SHARE] [--motion DIR] [--plan-json PATH]

--pets is the folder of the guardians' sheets, by default the app's Resources. The show's spec (--spec,
default App/PaintByNumber/Resources/making-of.json) sets the timing, each step's card (its caption,
with its methods' credit lines from ACKNOWLEDGEMENTS.md as a footnote, printed letter for letter)
and the crew's motion; --step, --crew (the first N guardians of its order) and --pet-height override it.
Everything the show decides (where the crew pops in and works, the seeds step 3 drops, the noise that
roughens each step's reveal, the lines' start jitters) is chosen by the shared modules from --seed, as
Sources/MakingOf chooses the shared parts; the pictures are the snapshots' own size, which the
pipeline keeps to 1024 px on the long side, and --width only scales the video (and the stills) to
that many pixels across.
--no-crew plays the show with no crew instead (making_of_fields.py): each step's change grows from
seeds over the picture itself, with sparks along the burning lines and a ring as each number comes out.
--motion DIR writes a motion report of the guardians and stops. --plan-json PATH writes the crew's
plan and stops: {"spec", "inputs", "plan", "states"}, the inputs rounded to 0.01 px and 0.0001 s before
the plan is made from them, and every guardian's state at 30 per second. That file is
tools/tests/fixtures/plan-parrots.json, which test_making_of_pets.py replays; regenerate it after
changing making_of_pets.py, making_of_inputs.py or the spec, from the generated parrots (the
recipe was in Sources/MakingOf/MakingOf.swift's header: `git show d3e3a954:Sources/MakingOf/MakingOf.swift`).

Timeline: the photo alone for INTRO seconds, six steps of STEP seconds, then the template held
for OUTRO. In each step the crew's stops are where its change spreads from, so it always grows from
where somebody is working, at a pace that fills the step:

  1 sketch             relative total variation: around each stop the photo's texture smears away
                       first, then graphite goes down on the structure that survives, strongest
                       first, and the photo washes to paper behind it
  2 shading            a soft-edged bloom outward from each stop
  3 paints             k-means++: real seeds (pixels drawn by their squared distance to the seeds so
                       far) drop one by one as dots, and each paint's areas flow out from its seed
  4 merged             whole regions (connected areas of one paint) pop in as the bloom reaches them
  5 ink                the template's lines as stair-stepped pixel outlines, the way Potrace starts,
                       drawn along their paths (guardians walk some), while the grey lifts halfway
  6 template           Potrace's fit: the outlines relax into the template's smooth curves, rippling
                       out from the stops; areas clear to paper, and numbers come last

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
import making_of_pets  # noqa: E402
import making_of_reveal as reveal  # noqa: E402
import making_of_show  # noqa: E402

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
    """Reads the show's spec and applies it to the crew's constants; the steps' cards get their
    credit lines from Acknowledgements."""
    global STEPS
    spec = json.load(open(path, encoding='utf-8'))
    if spec.get('version') != 1 or len(spec['steps']) != 6:
        sys.exit(f'{path}: expected version 1 with six steps')
    STEPS = [(st['id'], st['caption'], credits(st['methods'])) for st in spec['steps']]
    making_of_pets.configure(spec)
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


def motion_report(pets, total, size, h, out):
    """How the guardians move, by numbers and by eye: per guardian its fastest speed and hardest
    acceleration (in its heights per second), and a spacing chart, its feet every 1/30 s, darker
    later; even spacing is steady speed, bunching is slowing down."""
    os.makedirs(out, exist_ok=True)
    dt = 1 / 120
    lines = []
    for n, p in enumerate(pets):
        xs, ys, lifts = [], [], []
        for i in range(int(total / dt)):
            st = p.state(i * dt)
            xs.append(st[0])
            ys.append(st[1])
            lifts.append(st[2])
        xs, ys, lifts = np.array(xs), np.array(ys), np.array(lifts)
        v = np.hypot(np.diff(xs), np.diff(ys)) / dt / h
        acc = np.abs(np.diff(v)) / dt
        lift_v = np.abs(np.diff(lifts)) / dt / h
        jobs = len(p.stops) - 1
        moving = v > 0.2
        work = slice(0, int(min(st[0] for st in p.stops if st[4] == -4) / dt))   # before the goodbye
        lines.append(f'{n:2d} jobs {jobs:2d}  ground: top {v.max():4.2f} h/s, mean moving {v[moving].mean() if moving.any() else 0:4.2f},'
                     f' moving {moving.mean() * 100:3.0f}% of the time, hardest accel {np.percentile(acc, 99.5):5.1f} h/s2'
                     f'  lift: top {lifts.max() / h:4.2f} h, fastest {lift_v.max():4.2f} h/s'
                     f'  before the goodbye: top {v[work].max():4.2f} h/s, hardest accel {np.percentile(acc[work], 99.5):5.1f} h/s2')
        ys = ys - lifts
        if n < 4:
            img = Image.new('RGB', size, (247, 244, 238))
            d = ImageDraw.Draw(img)
            for i in range(0, len(xs), 4):
                c = int(200 * (1 - i / len(xs)))
                d.ellipse((xs[i] - 2, ys[i] - 2, xs[i] + 2, ys[i] + 2), fill=(c, c, c))
            img.save(os.path.join(out, f'spacing-{n}.png'))
    for n, p in enumerate(pets[:2]):
        for sgm, stop in zip(p.segments, p.stops[1:]):
            lines.append(f'pet {n} walks {sgm["leave"]:.2f}-{sgm["arrive"]:.2f} s, {sgm["d"] / h:.1f} h, to ({stop[2]:.0f}, {stop[3]:.0f}), step {stop[4]}'
                         + (' and draws a line' if stop[5] is not None else ''))
    for k in range(6):
        xs = [st[2] for p in pets for st in p.stops if st[4] == k]
        if xs:
            third = [sum(1 for x in xs if j * size[0] / 3 <= x < (j + 1) * size[0] / 3) for j in range(3)]
            lines.append(f'step {k + 1}: {len(xs)} jobs, left/middle/right thirds {third[0]}/{third[1]}/{third[2]}')
    # crowding: how often two guardians' boxes (0.7 h wide, h tall) overlap, standing or walking
    frames, touching, worst = 0, 0, 0
    for i in range(0, int(total * 30)):
        t = i / 30
        boxes = []
        for p in pets:
            st = p.state(t)
            if st[8] > 0.5:
                boxes.append((st[0] - 0.35 * h, st[1] - st[2] - h, st[0] + 0.35 * h, st[1] - st[2]))
        n = sum(1 for a_ in range(len(boxes)) for b_ in range(a_ + 1, len(boxes))
                if boxes[a_][0] < boxes[b_][2] and boxes[b_][0] < boxes[a_][2] and boxes[a_][1] < boxes[b_][3] and boxes[b_][1] < boxes[a_][3])
        frames += 1
        touching += n > 0
        worst = max(worst, n)
    lines.append(f'pets overlapping in {touching / frames * 100:.0f}% of frames, at most {worst} pairs at once')
    traces = sum(1 for p in pets for st in p.stops if st[5] is not None)
    lines.append(f'lines drawn by walking: {traces}; out of the frame by {min(p.stops[-1][0] for p in pets):.2f}-{max(p.stops[-1][0] for p in pets):.2f} s')
    open(os.path.join(out, 'motion.txt'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))


def write_plan(path, spec, inputs, planned, total):
    """The plan file: the spec and the inputs the plan was made from, the plan, and every guardian's
    state 30 times a second to the show's end."""
    doc = {'spec': spec, 'inputs': inputs, 'plan': making_of_pets.plan_data(planned),
           'states': making_of_pets.states_data(planned.pets, total)}
    with open(path, 'w', encoding='utf-8') as f:     # one line per part
        f.write('{\n' + ',\n'.join(f'"{k}":' + json.dumps(v, separators=(',', ':')) for k, v in doc.items()) + '\n}\n')


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
    """The show with no crew's own marks (making_of_fields.py): a spark at each burning tip of the
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
    ap.add_argument('--crew', type=int)
    ap.add_argument('--no-crew', action='store_true', help='the show with no crew (making_of_fields.py)')
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--stills')
    ap.add_argument('--step', type=float)
    ap.add_argument('--spec', default=SPEC)
    ap.add_argument('--pets', default=RESOURCES)
    ap.add_argument('--pet-height', type=float, help="a guardian's height as a share of the picture's shorter side (the spec's crew height)")
    ap.add_argument('--motion', help='write a motion report and spacing charts of the guardians to this folder, and stop')
    ap.add_argument('--plan-json', help="write the crew's plan (inputs, plan, states) to this file, and stop")
    a = ap.parse_args()
    spec = load_spec(a.spec)
    if a.step:
        spec['timing']['step'] = a.step
    ids = making_of_pets.ORDER[:a.crew or len(spec['crew']['pets'])]
    svg = os.path.join(a.generated, 'template.svg')
    intro, step, outro = (float(spec['timing'][k]) for k in ('intro', 'step', 'outro'))
    total = intro + 6 * step + outro

    if a.no_crew and (a.plan_json or a.motion):
        sys.exit('--plan-json and --motion are the crew\'s')
    if a.plan_json or a.motion:
        pictures, template, built = making_of_show.crew_inputs(a.snapshots, svg, spec, a.seed, ids, a.pet_height)
        planned = making_of_pets.plan(built.inputs)
        if a.plan_json:
            write_plan(a.plan_json, spec, built.inputs, planned, total)
        else:
            motion_report(planned.pets, total, pictures.size, built.inputs['petHeight'], a.motion)
        return

    if a.no_crew:
        sprites, show = {}, making_of_fields.FieldShow(a.snapshots, svg, spec, a.seed)
        total = show.duration
    else:
        sprites = making_of_pets.load(a.pets, ids)
        show = making_of_show.Show(a.snapshots, svg, spec, a.seed, ids, a.pet_height, {i: s.metrics for i, s in sprites.items()})
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
        if frame['sprites']:
            rgba = img.convert('RGBA')
            for d in frame['sprites']:
                making_of_pets.draw_sprite(rgba, sprites[d['id']], d)
            img = rgba.convert('RGB')
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
