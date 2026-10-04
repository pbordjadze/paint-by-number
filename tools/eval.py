#!/usr/bin/env python3
"""Visual + quantitative evaluation harness for the template pipeline.

    tools/eval.py run IMAGE... --out DIR [--sheet-width 2400] [--importance-dir DIR]
        [--edges-dir DIR] [--lines-dir DIR] [--eyes-dir DIR] [-- pbn generate options]
    tools/eval.py book IMAGE... --out DIR [--edges-dir DIR] [--lines-dir DIR] [--eyes-dir DIR] [--objects-dir DIR]
        [--importance-dir DIR] [--variant NAME=OPTIONS]... [--zoom 3] [--cell 560] [-- pbn generate options]

`-- --auto [--length L]` generates at the settings Auto suggests; the caption shows them.

For every image: converts to PPM, runs `pbn generate`, rasterizes the SVG outputs with
resvg, and writes a contact sheet `DIR/<name>/sheet.png` (source | painted | template)
plus `DIR/summary.json` and an overview grid `DIR/overview.png`. With --importance-dir,
`<name>.pgm` in that directory (if present) is passed to pbn as the importance map.

Layered line art: --edges-dir passes `<name>.pgm` from that directory as the edge map
(`--edges`, a contour map such as HED) and --lines-dir `<name>.pgm` as a line drawing
(`--lines`; both given, pbn combines them as the app combines its two models), and generates
layered templates (`--line-style layered`, unless the pbn options set a style: `-- --line-style
coloringBook` for coloring books); --eyes-dir passes
`<name>.json` (closed polygons normalized to the photo) as `--eyes`, and --objects-dir (`book`
only) `<name>.pgm` (a subject mask) or `<name>.json` as `--objects`. Other line-art settings
go through as pbn options (`-- --line-art samePaint=split`). The template panel draws each
layer in its group (a coloring book its drawing in heavy ink and no color edges); the caption
adds the style, cells against the classic regions and the edges per layer.

`book` judges coloring books the way their painter sees them: for every image a sheet
`DIR/<name>/book.png` with one column per variant (`--variant NAME=OPTIONS`, pbn generate
options such as `--line-art outlineThreshold=0.5`; none means the defaults alone, named
`default`) and five rows: the drawing fitted, the middle of it at --zoom, the cells of the
paint with the most of them hatched as the selected color (pbn's selected.svg), the
finished painting with the drawing over it, and the areas the drawing encloses (pbn's
areas.ppm: a color per area, light for a single cell, red rings where widening the lines
closes an opening). Under each column, the drawing metrics of `stats.json`'s `lineArt`:
cells (and against the classic regions), areas the drawing encloses (cells per area, areas
of a single cell, the largest area's share of the canvas), ink density, the share inside
cells, open stroke ends per 1000 units, interior strokes, and the share of the canvas the
lines wall off as drawn and widened by 1 to 4 pixels (a jump says how wide the openings
are). `DIR/book-summary.json` keeps every variant's stats; the table printed has a row per
image and variant. Books are generated unless the options set another style.

Requires a static release build of pbn:  tools/swift.sh build -c release --static-swift-stdlib
(or set PBN=/path/to/pbn, e.g. a saved baseline binary for before/after comparisons), node
(`cd tools && npm ci` once: resvg renders the SVGs) and Pillow.
"""
import json
import os
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from typing import NamedTuple

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBN = os.environ.get("PBN", os.path.join(ROOT, ".build", "release", "pbn"))
SVG2PNG = os.path.join(ROOT, "tools", "svg2png.mjs")


def svg_to_png(svg, png, width=None):
    cmd = ["node", SVG2PNG, svg, png] + ([str(width)] if width else [])
    subprocess.run(cmd, check=True, cwd=os.path.join(ROOT, "tools"))


def draw_palette(draw, palette, box, cols=6, names=()):
    """Numbered swatches of `palette` (hex strings) laid out in `box` = (x, y, width, height);
    `names` (one per swatch, optional; "\n" starts a second line) are written under the numbers when the
    cells are tall enough, each line shrunk to fit its cell."""
    if not palette:
        return
    x, y, width, height = box
    rows = (len(palette) + cols - 1) // cols
    cw, ch = width // cols, min(height // rows, 60)
    font = ImageFont.load_default(size=max(10, min(ch // 2, 18)))
    name_size = max(9, ch // 4)
    for i, hx in enumerate(palette):
        x0, y0 = x + (i % cols) * cw, y + (i // cols) * ch
        rgb = tuple(int(hx[k:k + 2], 16) for k in (0, 2, 4))
        draw.rectangle([x0 + 2, y0 + 2, x0 + cw - 2, y0 + ch - 2], fill=rgb)
        lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        ink = (0, 0, 0) if lum > 128 else (255, 255, 255)
        draw.text((x0 + 8, y0 + 6), str(i + 1), fill=ink, font=font)
        if ch >= 36 and i < len(names):
            lines = names[i].split("\n")
            size = name_size if len(lines) == 1 else max(8, ch // 5)
            for k, line in enumerate(lines):
                line_size = size
                name_font = ImageFont.load_default(size=line_size)
                while line_size > 7 and draw.textlength(line, font=name_font) > cw - 12:
                    line_size -= 1
                    name_font = ImageFont.load_default(size=line_size)
                y_line = y0 + ch - 4 - (len(lines) - k) * (size + 1)
                draw.text((x0 + 8, y_line), line, fill=ink, font=name_font)


def palette_names(stats):
    """Swatch labels: the nickname, then the structured name below it ("Harbor Fog" / "dark grayish blue")."""
    plain = stats.get("colorNames", [])
    nicknames = stats.get("colorNicknames", [])
    return [f"{nicknames[i]}\n{name}" if i < len(nicknames) else name for i, name in enumerate(plain)]


class Maps(NamedTuple):
    """Directories holding each picture's maps as `<name>.pgm` (eyes `<name>.json`, objects either);
    None where none is given."""
    importance: str | None = None
    edges: str | None = None
    lines: str | None = None
    eyes: str | None = None
    objects: str | None = None


def map_args(name, pbn_args, maps, style="layered"):
    """pbn options passing `name`'s maps from the directories given (a map that isn't there is
    skipped), with `--line-style STYLE` when a map is passed and the options name no style."""
    extra = []
    if maps.importance and os.path.exists(os.path.join(maps.importance, name + ".pgm")):
        extra = ["--importance", os.path.join(maps.importance, name + ".pgm")]
    drawn = False
    if maps.edges and os.path.exists(os.path.join(maps.edges, name + ".pgm")):
        extra += ["--edges", os.path.join(maps.edges, name + ".pgm")]
        drawn = True
    if maps.lines and os.path.exists(os.path.join(maps.lines, name + ".pgm")):
        extra += ["--lines", os.path.join(maps.lines, name + ".pgm")]
        drawn = True
    if drawn:
        if "--line-style" not in pbn_args:
            extra += ["--line-style", style]
        if maps.eyes and os.path.exists(os.path.join(maps.eyes, name + ".json")):
            extra += ["--eyes", os.path.join(maps.eyes, name + ".json")]
        for ext in (".pgm", ".json"):
            if maps.objects and os.path.exists(os.path.join(maps.objects, name + ext)):
                extra += ["--objects", os.path.join(maps.objects, name + ext)]
                break
    return extra


def generate(label, ppm, out, args):
    """Runs `pbn generate` on `ppm` into `out`: the stats it wrote, or None (after printing why)
    when it failed."""
    res = subprocess.run([PBN, "generate", ppm, out] + args, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[{label}] FAILED\n{res.stderr}", file=sys.stderr)
        return None
    with open(os.path.join(out, "stats.json")) as f:
        return json.load(f)


def process(image_path, out_root, pbn_args, sheet_width, maps):
    name = os.path.splitext(os.path.basename(image_path))[0]
    out = os.path.join(out_root, name)
    os.makedirs(out, exist_ok=True)
    ppm = os.path.join(out, "input.ppm")
    Image.open(image_path).convert("RGB").save(ppm)
    stats = generate(name, ppm, out, pbn_args + map_args(name, pbn_args, maps))
    if stats is None:
        return name, None
    working = Image.open(os.path.join(out, "working.ppm")).convert("RGB")
    w, h = working.size
    panel_w = sheet_width // 3
    for svg in ("painted", "template", "painted-outlined"):
        svg_to_png(os.path.join(out, f"{svg}.svg"), os.path.join(out, f"{svg}.png"), panel_w * 2)
    raster = Image.open(os.path.join(out, "raster.ppm")).convert("RGB")
    raster.save(os.path.join(out, "raster.png"))
    working.save(os.path.join(out, "working.png"))
    boundaries = None
    if os.path.exists(os.path.join(out, "boundaries.ppm")):
        boundaries = Image.open(os.path.join(out, "boundaries.ppm")).convert("RGB")
        boundaries.save(os.path.join(out, "boundaries.png"))

    panel_h = int(h * panel_w / w)
    sheet = Image.new("RGB", (panel_w * 3, 2 * panel_h + 28), "white")
    for i, img in enumerate([
        working,
        Image.open(os.path.join(out, "painted.png")).convert("RGB"),
        Image.open(os.path.join(out, "template.png")).convert("RGB"),
    ]):
        sheet.paste(img.resize((panel_w, panel_h), Image.LANCZOS), (i * panel_w, 28))
    # Second row: region raster | region boundaries | palette swatches.
    sheet.paste(raster.resize((panel_w, panel_h), Image.LANCZOS), (0, 28 + panel_h))
    if boundaries is not None:
        sheet.paste(boundaries.resize((panel_w, panel_h), Image.LANCZOS), (panel_w, 28 + panel_h))
    d = ImageDraw.Draw(sheet)
    draw_palette(d, stats.get("palette", []), (2 * panel_w, 28 + panel_h, panel_w, panel_h),
                 names=palette_names(stats))
    caption = (f"{name}  {stats['width']}x{stats['height']}  colors={stats['colors']}  regions={stats['regions']}  "
               f"dE={stats['meanDeltaE']:.4f}  rings={stats.get('bandRings', '?')}  r<2:{stats['regionsUnderRadius2']}  "
               f"belowLegible:{stats.get('labelsBelowLegibleSize', '?')}  total={stats['totalMs']:.0f}ms")
    if stats.get("lineArt"):
        line_art = stats["lineArt"]
        style = line_art.get("settings", {}).get("style", "layered")
        caption += (f"  {style}: x{line_art['cellsVsClassic']:.2f} classic, edges outline/detail/texture/color "
                    f"{'/'.join(str(n) for n in line_art['edgesPerLayer'])}, {line_art['interiorStrokes']} inside cells")
    if stats.get("auto"):
        chosen = stats["auto"]["settings"]
        caption += (f"  auto {stats['auto']['preference']}: {chosen['colorCount']} colors, detail {chosen['detail']:g}, "
                    f"smooth {chosen['smoothness']:g} (#{stats['auto']['winner']})")
    d.text((8, 6), caption, fill=(0, 0, 0), font=ImageFont.load_default(size=16))
    sheet.save(os.path.join(out, "sheet.png"))
    return name, stats


BOOK_ROWS = ["fitted", "zoomed", "selected", "finished", "areas"]


def book_metrics(stats):
    """The drawing metrics under a book column (`stats.json`'s `lineArt`), four lines."""
    la = stats.get("lineArt") or {}
    if not la:
        return [f"no line art: {stats['regions']} regions"]
    return [
        f"cells {stats['regions']} (x{la.get('cellsVsClassic', 0):.2f} classic)  colors {stats['colors']}  "
        f"dE {stats['meanDeltaE']:.4f}  {stats['totalMs']:.0f} ms",
        f"areas {la.get('enclosedAreas', '?')}: {la.get('cellsPerEnclosedArea', 0):.2f} cells/area, "
        f"{100 * la.get('singleCellAreaFraction', 0):.0f}% single, largest {100 * la.get('largestAreaFraction', 0):.0f}%, "
        f"outlines alone {la.get('outlineAreas', '?')}",
        f"ink {la.get('inkDensity', 0):.2f}/kpx, {100 * la.get('interiorFraction', 0):.0f}% inside cells, "
        f"open ends {la.get('openEndsPer1000', 0):.1f}/1000, {la.get('interiorStrokes', '?')} strokes, "
        f"selected #{la.get('selectedColor', '?')}",
        "walled off as drawn, widened 1..4 px: " + " ".join(f"{100 * v:.0f}%" for v in la.get("enclosedByWidening", []))
        + (f", openings at {la['openings']}" if la.get("openings") else ""),
    ]


def book_variant(out_root, name, variant, options, pbn_args, maps, cell, zoom):
    """Generates one variant of `name`'s book into DIR/<name>/<variant> and rasterizes its five
    views, `cell` px wide: the stats and the views by row."""
    out = os.path.join(out_root, name, variant)
    os.makedirs(out, exist_ok=True)
    args = pbn_args + options
    stats = generate(f"{name}/{variant}", os.path.join(out_root, name, "input.ppm"), out,
                     args + map_args(name, args, maps, style="coloringBook"))
    if stats is None:
        return None
    views = {}
    for row, svg in (("fitted", "template"), ("selected", "selected"), ("finished", "painted-outlined")):
        path = os.path.join(out, f"{svg}.svg")
        if os.path.exists(path):
            svg_to_png(path, os.path.join(out, f"{row}.png"), cell)
            views[row] = Image.open(os.path.join(out, f"{row}.png")).convert("RGB")
    # The middle of the drawing at `zoom`, as a panel of the fitted view's size.
    svg_to_png(os.path.join(out, "template.svg"), os.path.join(out, "zoomed-full.png"), cell * zoom)
    full = Image.open(os.path.join(out, "zoomed-full.png")).convert("RGB")
    w, h = views["fitted"].size
    x0, y0 = (full.width - w) // 2, (full.height - h) // 2
    views["zoomed"] = full.crop((x0, y0, x0 + w, y0 + h))
    views["zoomed"].save(os.path.join(out, "zoomed.png"))
    os.remove(os.path.join(out, "zoomed-full.png"))
    # The areas the drawing encloses (pbn's areas.ppm: a color per area, red rings at the
    # openings a widening of the lines closes).
    if os.path.exists(os.path.join(out, "areas.ppm")):
        views["areas"] = Image.open(os.path.join(out, "areas.ppm")).convert("RGB").resize((w, h), Image.LANCZOS)
        views["areas"].save(os.path.join(out, "areas.png"))
    return stats, views


def book(image_path, out_root, variants, pbn_args, maps, cell, zoom):
    """One image's book sheet: a column per variant, the five views down each."""
    name = os.path.splitext(os.path.basename(image_path))[0]
    os.makedirs(os.path.join(out_root, name), exist_ok=True)
    Image.open(image_path).convert("RGB").save(os.path.join(out_root, name, "input.ppm"))
    results = {variant: book_variant(out_root, name, variant, options, pbn_args, maps, cell, zoom)
               for variant, options in variants}
    done = [(v, o, results[v]) for v, o in variants if results[v]]
    if not done:
        return name, {}
    panel_h = max(views["fitted"].height for _, _, (_, views) in done)
    gap, header, footer, line = 6, 44, 84, 18
    rows = len(BOOK_ROWS)
    sheet = Image.new("RGB", (len(done) * (cell + gap) - gap, header + rows * (panel_h + gap) + footer), "white")
    d = ImageDraw.Draw(sheet)
    font, small = ImageFont.load_default(size=16), ImageFont.load_default(size=13)
    for i, (variant, options, (stats, views)) in enumerate(done):
        x = i * (cell + gap)
        d.text((x + 4, 4), f"{name} / {variant}", fill=(0, 0, 0), font=font)
        d.text((x + 4, 24), " ".join(options) or "(defaults)", fill=(70, 70, 70), font=small)
        for r, row in enumerate(BOOK_ROWS):
            y = header + r * (panel_h + gap)
            if row in views:
                sheet.paste(views[row], (x, y))
            else:
                d.rectangle([x, y, x + cell - 1, y + panel_h - 1], outline=(200, 200, 200))
            d.rectangle([x + 2, y + 2, x + 10 + 7 * len(row), y + 18], fill=(255, 255, 255))
            d.text((x + 5, y + 3), row, fill=(120, 60, 125), font=small)
        for k, text in enumerate(book_metrics(stats)):
            d.text((x + 4, header + rows * (panel_h + gap) + 2 + k * line), text, fill=(0, 0, 0), font=small)
    sheet.save(os.path.join(out_root, name, "book.png"))
    return name, {variant: stats for variant, _, (stats, _) in done}


def usage_error():
    print(__doc__, file=sys.stderr)
    sys.exit(2)


def parse_variants(values):
    """`NAME=OPTIONS` → (name, pbn options); none means the defaults alone."""
    variants = []
    for value in values:
        name, _, options = value.partition("=")
        variants.append((name.strip() or "default", shlex.split(options)))
    return variants or [("default", [])]


def book_main(argv, pbn_args):
    out_root, cell, zoom = "out", 560, 3
    dirs = {"--importance-dir": None, "--edges-dir": None, "--lines-dir": None, "--eyes-dir": None, "--objects-dir": None}
    variants, images = [], []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_root = next(it)
        elif a == "--cell":
            cell = int(next(it))
        elif a == "--zoom":
            zoom = int(next(it))
        elif a == "--variant":
            variants.append(next(it))
        elif a in dirs:
            dirs[a] = next(it)
        elif a.startswith("--"):
            usage_error()
        else:
            images.append(a)
    variants = parse_variants(variants)
    maps = Maps(dirs["--importance-dir"], dirs["--edges-dir"], dirs["--lines-dir"], dirs["--eyes-dir"],
                dirs["--objects-dir"])
    os.makedirs(out_root, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda p: book(p, out_root, variants, pbn_args, maps, cell, zoom), images))
    summary = {name: stats for name, stats in results if stats}
    json.dump(summary, open(os.path.join(out_root, "book-summary.json"), "w"), indent=2)
    width = max([len(f"{n}/{v}") for n, s in results for v in s] + [12])
    print("picture/variant".ljust(width) + "  cells  areas  cells/area  single  largest  ink   inside  open/1000  strokes")
    for name, stats in results:
        for variant, s in stats.items():
            la = s.get("lineArt") or {}
            print(f"{name}/{variant}".ljust(width) + f"  {s['regions']:5d}  {la.get('enclosedAreas', 0):5d}  "
                  f"{la.get('cellsPerEnclosedArea', 0):10.2f}  {100 * la.get('singleCellAreaFraction', 0):5.0f}%  "
                  f"{100 * la.get('largestAreaFraction', 0):6.0f}%  {la.get('inkDensity', 0):4.2f}  "
                  f"{100 * la.get('interiorFraction', 0):5.0f}%  {la.get('openEndsPer1000', 0):9.1f}  {la.get('interiorStrokes', 0):7d}")


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] not in ("run", "book"):
        print(__doc__)
        sys.exit(1)
    mode, argv = argv[0], argv[1:]
    pbn_args = []
    if "--" in argv:
        i = argv.index("--")
        argv, pbn_args = argv[:i], argv[i + 1:]
    if mode == "book":
        book_main(argv, pbn_args)
        return
    out_root = "out"
    sheet_width = 2400
    importance_dir = edges_dir = eyes_dir = lines_dir = None
    images = []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_root = next(it)
        elif a == "--sheet-width":
            sheet_width = int(next(it))
        elif a == "--importance-dir":
            importance_dir = next(it)
        elif a == "--edges-dir":
            edges_dir = next(it)
        elif a == "--lines-dir":
            lines_dir = next(it)
        elif a == "--eyes-dir":
            eyes_dir = next(it)
        elif a.startswith("--"):
            usage_error()
        else:
            images.append(a)
    maps = Maps(importance=importance_dir, edges=edges_dir, lines=lines_dir, eyes=eyes_dir)
    os.makedirs(out_root, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda p: process(p, out_root, pbn_args, sheet_width, maps), images))
    summary = {name: stats for name, stats in results if stats}
    json.dump(summary, open(os.path.join(out_root, "summary.json"), "w"), indent=2)

    # Overview grid of painted previews (4 per row).
    thumbs = []
    for name, stats in results:
        if not stats:
            continue
        img = Image.open(os.path.join(out_root, name, "painted-outlined.png")).convert("RGB")
        img.thumbnail((600, 600))
        thumbs.append(img)
    if thumbs:
        cols = 4
        rows = (len(thumbs) + cols - 1) // cols
        cell = 600
        grid = Image.new("RGB", (cols * cell, rows * cell), "white")
        for i, t in enumerate(thumbs):
            grid.paste(t, ((i % cols) * cell, (i // cols) * cell))
        grid.save(os.path.join(out_root, "overview.png"))

    keys = ["regions", "meanDeltaE", "regionsUnderRadius2", "minLabelRadius", "minLabelRoom",
            "labelsBelowLegibleSize", "valid", "totalMs"]
    for name, stats in results:
        if stats:
            print(f"{name:16s} " + "  ".join(
                f"{k}={stats.get(k):.4g}" if isinstance(stats.get(k), float) else f"{k}={stats.get(k)}" for k in keys))


if __name__ == "__main__":
    main()
