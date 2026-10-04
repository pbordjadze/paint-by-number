#!/usr/bin/env python3
"""Quality regression gate for the template pipeline (run by CI on every push).

    tools/regression.py [--update] [--sheets DIR] [--json FILE] [--out DIR]
    tools/regression.py --self-test

Generates the photos of SAMPLE_NAMES (App/PaintByNumber/Resources/Samples/<name>.jpg) in each
regime of REGIMES with the release pbn, twice, and checks the results against the committed
baseline tools/baseline/regression.json:

  hard invariants  pbn succeeds; `pbn check` validates the template; the two runs give
                   byte-identical templates; no region under radius 2; palette distance
                   at least the floor the segmentation enforces; no label below legible
                   size (only when pbn reports `labelsBelowLegibleSize`)
  tolerance bands  mean ΔE at most baseline × 1.05; region count within ±15 %; template
                   bytes within ±20 %
  informational    p95 ΔE, band rings (`bandRings`: regions a smooth gradient is posterized
                   into; ±1 noise on the decoded input moves it by up to half, too much for a
                   band), colors, regions under radius 3, min inscribed radius, timings,
                   whether the template is byte-identical to the baseline's

in the book regime (BOOK_REGIME: the coloring book at the app's default settings, from the
committed maps of tools/baseline/lines: `<name>-contours.png`, HED, and `<name>-drawing.png`,
the line-drawing model, both at the photo's size, combined by pbn as the app combines them),
with the same invariants and bands (regions are the book's cells) and, informational, the
drawing metrics of `stats.json`'s `lineArt`: areas the drawing encloses, the largest area's
share of the canvas (the background, unless a silhouette is open), ink density, open stroke
ends per 1000 units and interior strokes;

and in the auto regime (AUTO_REGIME: `pbn generate --auto`, the settings Auto suggests at
Relaxed) against tools/baseline/auto.json:

  hard invariants  the ones above; the chosen colors, detail and smoothness lie inside the
                   preference's bands pbn reports; the winner is one of the candidates
  informational    the choice versus the baseline's (choices move when the pipeline does),
                   regions, ΔE, bytes, estimated painting time against the time band, timings

Prints a table with deltas and exits 1 on any failure (2 on a usage or setup error).
--update rewrites both baselines from this run (only if every hard invariant holds): do it
when a pipeline or Auto change is intended, look at the sheets, and commit the baselines with
the change. --sheets DIR writes DIR/<regime>/<sample>.jpg (source | painted | region outlines,
palette). --json FILE writes every metric and verdict. --out DIR keeps pbn's output.

Requires the release pbn (tools/swift.sh build -c release --static-swift-stdlib, or set
PBN=/path/to/pbn) and Pillow (JPEG decoding, sheets). --self-test needs neither: it checks
the comparison rules on synthetic metrics.
"""
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBN = os.environ.get("PBN", os.path.join(ROOT, ".build", "release", "pbn"))
SAMPLES = os.path.join(ROOT, "App", "PaintByNumber", "Resources", "Samples")
# The app's six former samples (`Sample.retired`), pinned by name: the curated picture library
# beside them changes with curation, which must neither move the baselines nor multiply CI's
# time. The benchmark step in .github/workflows/ci.yml lists the same files.
SAMPLE_NAMES = ["barn", "espresso", "hibiscus", "lighthouse", "parrots", "regatta"]
BASELINE = os.path.join(ROOT, "tools", "baseline", "regression.json")
AUTO_BASELINE = os.path.join(ROOT, "tools", "baseline", "auto.json")
# The samples' edge maps for the book regime, as the app's two models make them.
LINES = os.path.join(ROOT, "tools", "baseline", "lines")

# The app's default, its most intricate and its boldest settings.
REGIMES = [
    {"colors": 24, "detail": 0.5},
    {"colors": 150, "detail": 1.0},
    {"colors": 12, "detail": 0.0},
]

# The coloring book at the app's defaults, from the committed maps.
BOOK_REGIME = {"book": "coloringBook", "colors": 24, "detail": 0.5}

# Auto: every sample at the settings it suggests for this painting length.
AUTO_REGIME = {"auto": "relaxed"}

# The drawing metrics of a book (`stats.json`'s `lineArt`), lifted beside the other metrics.
BOOK_METRICS = ["enclosedAreas", "largestAreaFraction", "inkDensity", "openEndsPer1000", "interiorStrokes"]

# Metrics kept in the baseline: the banded ones plus informational ones worth a delta.
BASELINE_KEYS = ["regions", "meanDeltaE", "p95DeltaE", "encodedBytes", "colors", "regionsUnderRadius3",
                 "minInscribedRadius", "minPaletteDistance", "totalMs", "bandRings"] + BOOK_METRICS

# Tolerance bands versus the baseline: (metric, lowest ratio, highest ratio); None = unbounded.
BANDS = [
    ("meanDeltaE", None, 1.05),
    ("regions", 0.85, 1.15),
    ("encodedBytes", 0.80, 1.20),
]

# Slack for the palette floor: pbn reports Float32 distances, the floor here is a double.
FLOAT_SLACK = 1e-6


def regime_name(regime):
    if "auto" in regime:
        return f"auto-{regime['auto']}"
    book = "book-" if "book" in regime else ""
    return f"{book}c{regime['colors']}-d{regime['detail']:g}"


def chosen(result):
    """Auto's chosen settings from pbn's stats (an empty dict when absent or malformed)."""
    auto = result.get("auto")
    settings = auto.get("settings") if isinstance(auto, dict) else None
    return settings if isinstance(settings, dict) else {}


def palette_floor(regime, result):
    """Minimum OKLab distance between paints. pbn reports the pipeline's own floor
    (GenerationSettings.minPaletteDistance) as minPaletteDistanceFloor; the formula mirrors it
    for a pbn that predates that field."""
    reported = number(result.get("minPaletteDistanceFloor"))
    if reported is not None:
        return reported
    colors = regime.get("colors") or number(chosen(result).get("colorCount")) or 24
    return 0.04 * min(1.0, math.sqrt(24 / colors))


def number(value):
    """The value if it is a real number (not a bool), else None: unknown or malformed
    fields count as absent."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value if math.isfinite(value) else None


# ---------------------------------------------------------------------------- rules

def invariant_failures(regime, result):
    """Hard-invariant failures of one generated case. `result` holds pbn's metrics plus the
    run's own findings (`error`, `validation`, `deterministic`)."""
    if result.get("error"):
        return [f"pbn: {result['error']}"]
    failures = []
    validation = result.get("validation") or ""
    if not validation.startswith("valid"):
        failures.append(f"template invalid: {validation or 'not checked'}")
    if result.get("deterministic") is not True:
        failures.append("non-deterministic: two runs gave different templates")
    under2 = number(result.get("regionsUnderRadius2"))
    if under2 is None:
        failures.append("pbn did not report regionsUnderRadius2")
    elif under2 != 0:
        radius = number(result.get("minInscribedRadius"))
        failures.append(f"{under2:g} region(s) under radius 2"
                        + (f" (min inscribed radius {radius:.3f})" if radius is not None else ""))
    distance = number(result.get("minPaletteDistance"))
    floor = palette_floor(regime, result)
    if distance is None:
        failures.append("pbn did not report minPaletteDistance")
    elif distance < floor - FLOAT_SLACK:
        failures.append(f"palette distance {distance:.4f} below the floor {floor:.4f}")
    illegible = number(result.get("labelsBelowLegibleSize"))
    if illegible is not None and illegible != 0:
        failures.append(f"{illegible:g} label(s) below legible size")
    return failures


def band_failures(result, base):
    """Tolerance-band failures of one case against its baseline entry (None if missing)."""
    if result.get("error"):
        return []
    if base is None:
        return ["no baseline entry (run tools/regression.py --update)"]
    failures = []
    for key, low, high in BANDS:
        cur, ref = number(result.get(key)), number(base.get(key))
        if cur is None:
            failures.append(f"pbn did not report {key}")
        elif ref is None:
            failures.append(f"baseline has no {key} (run tools/regression.py --update)")
        elif (low is not None and cur < ref * low) or (high is not None and cur > ref * high):
            allowed = (f"at most {pct(high * ref, ref)}" if low is None
                       else f"{pct(low * ref, ref)} to {pct(high * ref, ref)}")
            failures.append(f"{key} {cur:.6g} is {pct(cur, ref)} vs baseline {ref:.6g} (allowed: {allowed})")
    return failures


def check_case(regime, result, base):
    if "auto" in regime:
        return invariant_failures(regime, result) + choice_failures(regime, result) + auto_baseline_failures(result, base)
    return invariant_failures(regime, result) + band_failures(result, base)


def bounds(value):
    """A [low, high] pair of numbers, else None."""
    if isinstance(value, list) and len(value) == 2 and all(number(v) is not None for v in value):
        return value
    return None


def choice_failures(regime, result):
    """Auto's hard invariant: the suggested settings lie inside the bands of the preference
    asked for (as pbn reports them), and they are the winning candidate's."""
    if result.get("error"):
        return []
    auto = result.get("auto")
    if not isinstance(auto, dict):
        return ["pbn did not report an auto decision"]
    if auto.get("preference") != regime["auto"]:
        return [f"decision for {auto.get('preference')!r}, asked for {regime['auto']!r}"]
    settings, bands = chosen(result), auto.get("bands") if isinstance(auto.get("bands"), dict) else {}
    failures = []
    for key, band in (("colorCount", "colors"), ("detail", "detail"), ("smoothness", "smoothness")):
        value, limits = number(settings.get(key)), bounds(bands.get(band))
        if value is None or limits is None:
            failures.append(f"pbn did not report the chosen {key} and its band")
        elif not limits[0] - FLOAT_SLACK <= value <= limits[1] + FLOAT_SLACK:
            failures.append(f"chosen {key} {value:g} outside the {regime['auto']} band {limits[0]:g}..{limits[1]:g}")
    winner, candidates = auto.get("winner"), auto.get("candidates")
    if not isinstance(candidates, list) or isinstance(winner, bool) or not isinstance(winner, int) \
            or not 0 <= winner < len(candidates):
        failures.append(f"winner {winner!r} is not one of the candidates")
    elif not isinstance(candidates[winner], dict) or candidates[winner].get("settings") != settings:
        failures.append("the chosen settings are not the winning candidate's")
    return failures


def auto_baseline_failures(result, base):
    """The auto regime compares with its baseline for information only; it just has to exist."""
    if result.get("error") or base is not None:
        return []
    return ["no auto baseline entry (run tools/regression.py --update)"]


def choice_text(settings):
    if not settings:
        return "-"
    parts = [number(settings.get(k)) for k in ("colorCount", "detail", "smoothness")]
    if any(p is None for p in parts):
        return "?"
    return f"{parts[0]:.0f}c d{parts[1]:g} s{parts[2]:g}"


def stale_entries(baseline_cases, run_keys):
    """Baseline entries this run no longer produces (a sample or regime was removed)."""
    return sorted(set(baseline_cases) - set(run_keys))


# ---------------------------------------------------------------------------- report

def pct(cur, ref):
    if cur == ref:
        return "="
    if ref == 0:
        return "new"
    return f"{(cur - ref) / ref * 100:+.1f}%"


def cell(value, ref=None, fmt="{:g}"):
    value = number(value)
    if value is None:
        return "-"
    text = fmt.format(value)
    ref = number(ref)
    return text if ref is None else f"{text} {pct(value, ref)}"


# ASCII only: the sheets' font has no Δ or ≥.
COLUMNS = ["sample", "regions", "mean dE", "p95 dE", "rings", "bytes", "r<2", "r<3", "min r", "paint gap",
           "colors", "ms", "template", "verdict"]


AUTO_COLUMNS = ["sample", "choice", "baseline", "regions", "mean dE", "p95 dE", "bytes", "est min", "r<2",
                "paint gap", "ms", "template", "verdict"]


BOOK_COLUMNS = ["sample", "cells", "mean dE", "areas", "largest", "ink", "open ends", "strokes", "bytes", "r<2",
                "paint gap", "ms", "template", "verdict"]


def columns(regime):
    return AUTO_COLUMNS if "auto" in regime else BOOK_COLUMNS if "book" in regime else COLUMNS


def book_row(name, regime, result, base, failures):
    base = base or {}
    if result.get("error"):
        return [name] + ["-"] * (len(BOOK_COLUMNS) - 2) + ["FAIL"]
    sha = result.get("templateSHA1")
    template = "new" if not base.get("templateSHA1") else ("same" if sha == base.get("templateSHA1") else "changed")
    return [
        name,
        cell(result.get("regions"), base.get("regions"), "{:.0f}"),
        cell(result.get("meanDeltaE"), base.get("meanDeltaE"), "{:.4f}"),
        cell(result.get("enclosedAreas"), base.get("enclosedAreas"), "{:.0f}"),
        cell(result.get("largestAreaFraction"), base.get("largestAreaFraction"), "{:.3f}"),
        cell(result.get("inkDensity"), base.get("inkDensity"), "{:.2f}"),
        cell(result.get("openEndsPer1000"), base.get("openEndsPer1000"), "{:.1f}"),
        cell(result.get("interiorStrokes"), base.get("interiorStrokes"), "{:.0f}"),
        cell(result.get("encodedBytes"), base.get("encodedBytes"), "{:.0f}"),
        cell(result.get("regionsUnderRadius2"), fmt="{:.0f}"),
        f"{cell(result.get('minPaletteDistance'), base.get('minPaletteDistance'), '{:.4f}')}"
        f" >= {palette_floor(regime, result):.4f}",
        cell(result.get("totalMs"), base.get("totalMs"), "{:.0f}"),
        template,
        "FAIL" if failures else "ok",
    ]


def make_row(name, regime, result, base, failures):
    maker = auto_row if "auto" in regime else book_row if "book" in regime else row
    return maker(name, regime, result, base, failures)


def auto_row(name, regime, result, base, failures):
    base = base or {}
    if result.get("error"):
        return [name] + ["-"] * (len(AUTO_COLUMNS) - 2) + ["FAIL"]
    choice = choice_text(chosen(result))
    if not base:
        was = "new"
    else:
        was = "same" if choice == choice_text(base.get("settings") or {}) else "was " + choice_text(base.get("settings"))
    sha = result.get("templateSHA1")
    template = "new" if not base.get("templateSHA1") else ("same" if sha == base.get("templateSHA1") else "changed")
    auto = result.get("auto") if isinstance(result.get("auto"), dict) else {}
    minutes = bounds((auto.get("bands") or {}).get("minutes") if isinstance(auto.get("bands"), dict) else None)
    regions = number(result.get("regions"))
    estimate = "-"
    if regions is not None:
        # PaintingTime.estimate: 3 s per region.
        estimate = f"{regions * 3 / 60:.0f}"
        if minutes is not None:
            estimate += " <" if regions * 3 / 60 < minutes[0] else (" >" if regions * 3 / 60 > minutes[1] else "")
    return [
        name, choice, was,
        cell(result.get("regions"), base.get("regions"), "{:.0f}"),
        cell(result.get("meanDeltaE"), base.get("meanDeltaE"), "{:.4f}"),
        cell(result.get("p95DeltaE"), base.get("p95DeltaE"), "{:.4f}"),
        cell(result.get("encodedBytes"), base.get("encodedBytes"), "{:.0f}"),
        estimate,
        cell(result.get("regionsUnderRadius2"), fmt="{:.0f}"),
        f"{cell(result.get('minPaletteDistance'), base.get('minPaletteDistance'), '{:.4f}')}"
        f" >= {palette_floor(regime, result):.4f}",
        cell(result.get("totalMs"), base.get("totalMs"), "{:.0f}"),
        template,
        "FAIL" if failures else "ok",
    ]


def row(name, regime, result, base, failures):
    base = base or {}
    if result.get("error"):
        return [name] + ["-"] * (len(COLUMNS) - 2) + ["FAIL"]
    sha = result.get("templateSHA1")
    template = "new" if not base.get("templateSHA1") else ("same" if sha == base.get("templateSHA1") else "changed")
    return [
        name,
        cell(result.get("regions"), base.get("regions"), "{:.0f}"),
        cell(result.get("meanDeltaE"), base.get("meanDeltaE"), "{:.4f}"),
        cell(result.get("p95DeltaE"), base.get("p95DeltaE"), "{:.4f}"),
        cell(result.get("bandRings"), base.get("bandRings"), "{:.0f}"),
        cell(result.get("encodedBytes"), base.get("encodedBytes"), "{:.0f}"),
        cell(result.get("regionsUnderRadius2"), fmt="{:.0f}"),
        cell(result.get("regionsUnderRadius3"), base.get("regionsUnderRadius3"), "{:.0f}"),
        cell(result.get("minInscribedRadius"), base.get("minInscribedRadius"), "{:.3f}"),
        f"{cell(result.get('minPaletteDistance'), base.get('minPaletteDistance'), '{:.4f}')}"
        f" >= {palette_floor(regime, result):.4f}",
        cell(result.get("colors"), base.get("colors"), "{:.0f}"),
        cell(result.get("totalMs"), base.get("totalMs"), "{:.0f}"),
        template,
        "FAIL" if failures else "ok",
    ]


def table(rows, columns=COLUMNS):
    widths = [max(len(r[i]) for r in [columns] + rows) for i in range(len(columns))]
    line = lambda r: "  ".join(c.ljust(w) if i == 0 else c.rjust(w) for i, (c, w) in enumerate(zip(r, widths)))
    return "\n".join([line(columns), line(["-" * w for w in widths])] + [line(r) for r in rows])


def totals(results, base_cases, keys):
    """Corpus means of a regime versus the baseline, for the line under its table."""
    parts = []
    for metric, label, fmt in (("meanDeltaE", "mean dE", "{:.4f}"), ("regions", "regions", "{:.0f}"),
                               ("encodedBytes", "bytes", "{:.0f}"), ("totalMs", "ms", "{:.0f}")):
        cur = [number(results[k].get(metric)) for k in keys]
        ref = [number((base_cases.get(k) or {}).get(metric)) for k in keys]
        if any(v is None for v in cur):
            continue
        mean = sum(cur) / len(cur)
        text = f"{label} {fmt.format(mean)}"
        if all(v is not None for v in ref):
            text += f" ({pct(mean, sum(ref) / len(ref))})"
        parts.append(text)
    return "corpus mean: " + "  ".join(parts)


# ---------------------------------------------------------------------------- running

def run_case(ppm, regime, out, maps=None):
    """Generates `ppm` twice in `regime` (into out/ and out/repeat/), validates the
    template and returns the metrics with the run's findings. `maps`: the sample's contour
    and drawing PGMs, for the book regime."""
    if "auto" in regime:
        args = ["--auto", "--length", regime["auto"]]
    else:
        args = ["--colors", str(regime["colors"]), "--detail", str(regime["detail"])]
    if "book" in regime:
        if not maps:
            return {"error": "no edge maps for the book regime"}
        args += ["--line-style", regime["book"], "--edges", maps[0], "--lines", maps[1]]
    templates = []
    for target in (out, os.path.join(out, "repeat")):
        res = subprocess.run([PBN, "generate", ppm, target] + args, capture_output=True, text=True)
        if res.returncode != 0:
            # pbn's last stderr line already says what failed ("generation failed: ...").
            return {"error": (res.stderr.strip() or f"exited {res.returncode}").splitlines()[-1]}
        with open(os.path.join(target, "template.pbnt"), "rb") as f:
            templates.append(f.read())
    with open(os.path.join(out, "stats.json")) as f:
        result = json.load(f)
    line_art = result.get("lineArt")
    if isinstance(line_art, dict):
        for key in BOOK_METRICS:
            result[key] = line_art.get(key)
    shutil.rmtree(os.path.join(out, "repeat"))
    check = subprocess.run([PBN, "check", os.path.join(out, "template.pbnt")], capture_output=True, text=True)
    # `pbn check` prints the file's versions first and its verdict ("valid …"/"INVALID …") last.
    verdict = [l for l in check.stdout.splitlines() if l.startswith(("valid", "INVALID"))]
    result["validation"] = (verdict[-1] if verdict else check.stdout.strip() or check.stderr.strip())[:400]
    result["deterministic"] = templates[0] == templates[1]
    result["templateSHA1"] = hashlib.sha1(templates[0]).hexdigest()
    return result


def baseline_entry(result):
    entry = {}
    for key in BASELINE_KEYS:
        value = number(result.get(key))
        if value is not None:
            entry[key] = round(value, 1) if key == "totalMs" else value
    entry["templateSHA1"] = result["templateSHA1"]
    return entry


def auto_baseline_entry(result):
    entry = baseline_entry(result)
    entry["settings"] = {k: chosen(result).get(k) for k in ("colorCount", "detail", "smoothness")}
    entry["winner"] = result["auto"].get("winner")
    return entry


def write_sheet(path, title, lines, failures, out):
    """Contact sheet: source | painted | region outlines, the palette underneath."""
    from PIL import Image, ImageDraw, ImageFont
    from eval import draw_palette  # tools/eval.py, next to this script

    with open(os.path.join(out, "stats.json")) as f:
        palette = json.load(f).get("palette", [])
    panels = [Image.open(os.path.join(out, name)).convert("RGB")
              for name in ("working.ppm", "raster.ppm", "boundaries.ppm")]
    panel_w = 520  # 1560-px sheets: legible unzoomed, small enough for every CI report
    panel_h = round(panels[0].height * panel_w / panels[0].width)
    cols = 6 if len(palette) <= 36 else 15
    swatch_rows = (len(palette) + cols - 1) // cols
    header = 26 * (1 + len(lines) + len(failures)) + 8
    sheet = Image.new("RGB", (3 * panel_w, header + panel_h + 30 * swatch_rows + 8), "white")
    for i, img in enumerate(panels):
        sheet.paste(img.resize((panel_w, panel_h), Image.LANCZOS), (i * panel_w, header))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=18)
    for i, (text, color) in enumerate([(title, (0, 0, 0))] + [(t, (60, 60, 60)) for t in lines]
                                      + [(t, (190, 0, 0)) for t in failures]):
        d.text((10, 6 + 26 * i), text, fill=color, font=font)
    draw_palette(d, palette, (0, header + panel_h + 4, 3 * panel_w, 30 * swatch_rows), cols=cols)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # JPEG: photo panels as PNG would add ~14 MB to every CI report.
    sheet.save(path, quality=88)


def main(argv):
    update = "--update" in argv
    options = {}
    it = iter(argv)
    for a in it:
        if a in ("--sheets", "--json", "--out"):
            options[a] = next(it, None)
            if options[a] is None:
                print(f"{a} needs a path", file=sys.stderr)
                sys.exit(2)
        elif a != "--update":
            print(__doc__, file=sys.stderr)
            sys.exit(2)
    if not os.access(PBN, os.X_OK):
        print(f"{PBN} not found: build it with tools/swift.sh build -c release --static-swift-stdlib "
              "(or set PBN)", file=sys.stderr)
        sys.exit(2)
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is required (pip install pillow, or apt install python3-pil)", file=sys.stderr)
        sys.exit(2)

    samples = [name + ".jpg" for name in SAMPLE_NAMES]
    missing = [s for s in samples if not os.path.isfile(os.path.join(SAMPLES, s))]
    if missing:
        print(f"missing from {SAMPLES}: {', '.join(missing)}", file=sys.stderr)
        sys.exit(2)
    map_files = {name: [f"{name}-{kind}.png" for kind in ("contours", "drawing")] for name in SAMPLE_NAMES}
    missing = [f for files in map_files.values() for f in files if not os.path.isfile(os.path.join(LINES, f))]
    if missing:
        print(f"missing from {LINES}: {', '.join(missing)}", file=sys.stderr)
        sys.exit(2)
    try:
        with open(BASELINE) as f:
            baseline = json.load(f)
    except (OSError, ValueError) as error:
        print(f"no usable baseline ({error}); every case will fail until --update", file=sys.stderr)
        baseline = {}
    base_cases = baseline.get("cases") if isinstance(baseline.get("cases"), dict) else {}
    try:
        with open(AUTO_BASELINE) as f:
            auto_baseline = json.load(f)
    except (OSError, ValueError) as error:
        print(f"no usable auto baseline ({error}); every auto case will fail until --update", file=sys.stderr)
        auto_baseline = {}
    if isinstance(auto_baseline.get("cases"), dict):
        base_cases.update(auto_baseline["cases"])
    regimes = REGIMES + [BOOK_REGIME, AUTO_REGIME]

    work = options.get("--out") or tempfile.mkdtemp(prefix="pbn-regression-")
    try:
        inputs, maps = {}, {}
        for sample in samples:
            name = os.path.splitext(sample)[0]
            inputs[name] = os.path.join(work, "input", name + ".ppm")
            os.makedirs(os.path.dirname(inputs[name]), exist_ok=True)
            Image.open(os.path.join(SAMPLES, sample)).convert("RGB").save(inputs[name])
            maps[name] = []
            for file in map_files[name]:
                pgm = os.path.join(work, "input", os.path.splitext(file)[0] + ".pgm")
                Image.open(os.path.join(LINES, file)).convert("L").save(pgm)
                maps[name].append(pgm)
        cases = [(regime, name) for regime in regimes for name in inputs]
        key = lambda regime, name: f"{regime_name(regime)}/{name}"
        # Two at a time: pbn is itself parallel, and concurrent runs vary the scheduling
        # the determinism check sees.
        with ThreadPoolExecutor(max_workers=2) as pool:
            outputs = list(pool.map(
                lambda c: run_case(inputs[c[1]], c[0], os.path.join(work, regime_name(c[0]), c[1]), maps[c[1]]), cases))
        results = {key(r, n): out for (r, n), out in zip(cases, outputs)}

        report, all_failures, verdicts = [], [], {}
        for regime in regimes:
            keys = [key(regime, name) for name in inputs]
            auto = "auto" in regime
            rows = []
            for k in keys:
                # A new baseline only has to satisfy the invariants.
                if update:
                    failures = invariant_failures(regime, results[k]) + (choice_failures(regime, results[k]) if auto else [])
                else:
                    failures = check_case(regime, results[k], base_cases.get(k))
                verdicts[k] = failures
                all_failures += [f"{k}: {f}" for f in failures]
                rows.append(make_row(k.split("/")[1], regime, results[k], base_cases.get(k), failures))
            title = (f"{regime_name(regime)}: the settings Auto suggests at {regime['auto'].capitalize()} (choices are "
                     "informational; est min < or > the time band)" if auto
                     else f"{regime_name(regime)}: the coloring book at {regime['colors']} colors, detail "
                          f"{regime['detail']:g}, from the maps in tools/baseline/lines (areas, largest, ink, open ends "
                          "and strokes are informational)" if "book" in regime
                     else f"{regime_name(regime)}: {regime['colors']} colors, detail {regime['detail']:g}")
            report += [title, table(rows, columns(regime))]
            if not any(results[k].get("error") for k in keys):
                report.append(totals(results, base_cases, keys))
            report.append("")
        if not update:
            for k in stale_entries(base_cases, results):
                all_failures.append(f"{k}: baseline entry no longer generated (run tools/regression.py --update)")
        report += [f"FAIL {f}" for f in all_failures]
        passed = "pass the hard invariants" if update else "pass"
        # The last line is the verdict (CI copies it into STATUS.md).
        report.append(f"{len(results)} cases: {len(all_failures)} failure(s)" if all_failures
                      else f"{len(results)} cases: all {passed}")
        print("\n".join(report))

        if options.get("--sheets"):
            for (regime, name) in cases:
                k = key(regime, name)
                out = os.path.join(work, regime_name(regime), name)
                if results[k].get("error"):
                    continue
                names = columns(regime)
                cells = dict(zip(names, make_row(name, regime, results[k], base_cases.get(k), verdicts[k])))
                lines = ["  ".join(f"{c} {cells[c]}" for c in names[1:7]),
                         "  ".join(f"{c} {cells[c]}" for c in names[7:-1])]
                write_sheet(os.path.join(options["--sheets"], regime_name(regime), name + ".jpg"),
                            f"{k}  ({results[k]['width']}x{results[k]['height']})  {cells['verdict']}",
                            lines, verdicts[k], out)
        if options.get("--json"):
            os.makedirs(os.path.dirname(os.path.abspath(options["--json"])), exist_ok=True)
            with open(options["--json"], "w") as f:
                json.dump({"baseline": os.path.relpath(BASELINE, ROOT), "autoBaseline": os.path.relpath(AUTO_BASELINE, ROOT),
                       "failures": all_failures,
                           "cases": {k: {"metrics": {m: v for m, v in results[k].items() if m != "palette"},
                                         "baseline": base_cases.get(k), "failures": verdicts[k]}
                                     for k in results}}, f, indent=2, sort_keys=True)
        if update and not all_failures:
            os.makedirs(os.path.dirname(BASELINE), exist_ok=True)
            auto_keys = {key(AUTO_REGIME, name) for name in inputs}
            with open(BASELINE, "w") as f:
                json.dump({"about": "Quality baseline for tools/regression.py; regenerate with --update.",
                           "regimes": {regime_name(r): r for r in REGIMES + [BOOK_REGIME]},
                           "cases": {k: baseline_entry(results[k]) for k in sorted(results) if k not in auto_keys}},
                          f, indent=2, sort_keys=True)
                f.write("\n")
            with open(AUTO_BASELINE, "w") as f:
                json.dump({"about": "Settings Auto suggests per sample, for tools/regression.py's auto regime "
                                    "(informational); regenerate with --update.",
                           "regime": {regime_name(AUTO_REGIME): AUTO_REGIME},
                           "cases": {k: auto_baseline_entry(results[k]) for k in sorted(auto_keys)}},
                          f, indent=2, sort_keys=True)
                f.write("\n")
            print(f"baselines written to {os.path.relpath(BASELINE, ROOT)} and {os.path.relpath(AUTO_BASELINE, ROOT)}")
        elif update:
            print("baseline not written: the hard invariants must hold first")
        return 1 if all_failures else 0
    finally:
        if not options.get("--out"):
            shutil.rmtree(work, ignore_errors=True)


# ---------------------------------------------------------------------------- self-test

def self_test():
    """Exercises the comparison rules on synthetic metrics."""
    regime = {"colors": 150, "detail": 1.0}
    floor = palette_floor(regime, {})
    base = {"regions": 1000, "meanDeltaE": 0.02, "p95DeltaE": 0.05, "encodedBytes": 2_000_000, "colors": 140,
            "regionsUnderRadius3": 50, "minInscribedRadius": 2.2, "minPaletteDistance": 0.0162, "totalMs": 400.0,
            "bandRings": 100, "templateSHA1": "a" * 40}
    good = dict(base, regionsUnderRadius2=0, validation="valid edges 0", deterministic=True,
                templateSHA1="a" * 40, width=1152, height=768, someFutureMetric=[1, 2])
    checks = 0

    def expect(changes, failing, base_entry=base, regime=regime):
        nonlocal checks
        result = dict(good, **changes)
        failures = check_case(regime, result, base_entry)
        assert bool(failures) == failing, f"{changes}: expected {'failure' if failing else 'pass'}, got {failures}"
        # The table and the baseline entry must cope with whatever the result holds.
        row("x", regime, result, base_entry, failures)
        if not result.get("error"):
            baseline_entry(result)
        checks += 1
        return failures

    expect({}, False)
    # Bands: mean ΔE may only rise 5 %, regions move 15 %, bytes 20 %.
    expect({"meanDeltaE": 0.02 * 1.04}, False)
    expect({"meanDeltaE": 0.02 * 1.06}, True)
    expect({"meanDeltaE": 0.01}, False)
    expect({"regions": 1140}, False)
    expect({"regions": 1160}, True)
    expect({"regions": 860}, False)
    expect({"regions": 840}, True)
    expect({"encodedBytes": 2_380_000}, False)
    expect({"encodedBytes": 2_420_000}, True)
    expect({"encodedBytes": 1_580_000}, True)
    # Informational metrics never fail.
    expect({"totalMs": 4000.0, "p95DeltaE": 0.5, "colors": 20, "regionsUnderRadius3": 900, "bandRings": 400,
            "templateSHA1": "b" * 40}, False)
    expect({"bandRings": None}, False)
    # Hard invariants.
    expect({"regionsUnderRadius2": 1}, True)
    expect({"minPaletteDistance": floor}, False)
    expect({"minPaletteDistance": floor - 1e-4}, True)
    assert expect({"minPaletteDistance": 0.03}, True, regime={"colors": 24, "detail": 0.5})
    expect({"minPaletteDistance": 0.04}, False, regime={"colors": 12, "detail": 0.0})
    # The floor pbn reports wins over the formula.
    expect({"minPaletteDistanceFloor": 0.02}, True)
    expect({"minPaletteDistanceFloor": 0.01, "minPaletteDistance": 0.012}, False)
    expect({"minPaletteDistanceFloor": None, "minPaletteDistance": 0.012}, True)
    expect({"labelsBelowLegibleSize": 0}, False)
    expect({"labelsBelowLegibleSize": 3}, True)
    expect({"labelsBelowLegibleSize": "n/a"}, False)
    expect({"deterministic": False}, True)
    expect({"validation": "INVALID edges 2"}, True)
    expect({"validation": None}, True)
    assert expect({"error": "generation failed: boom"}, True) == ["pbn: generation failed: boom"]
    # Missing or malformed fields are failures with a message, never crashes.
    del good["regionsUnderRadius2"]
    assert "regionsUnderRadius2" in expect({}, True)[0]
    good["regionsUnderRadius2"] = 0
    expect({"meanDeltaE": None}, True)
    expect({"regions": "many"}, True)
    expect({"regions": float("nan")}, True)
    expect({"regionsUnderRadius2": True}, True)
    expect({}, True, base_entry=None)
    expect({}, True, base_entry={k: v for k, v in base.items() if k != "encodedBytes"})
    expect({}, False, base_entry=dict(base, meanDeltaE=0.0205, unknown="x"))
    # Invariants alone (--update) ignore the bands; baselines not produced by a run are stale.
    assert invariant_failures(regime, dict(good, regions=5000)) == []
    assert invariant_failures(regime, dict(good, regionsUnderRadius2=2))
    assert stale_entries({"c24-d0.5/a": {}, "c24-d0.5/b": {}}, {"c24-d0.5/a": {}}) == ["c24-d0.5/b"]
    checks += 3
    # Reporting helpers.
    assert pct(105, 100) == "+5.0%" and pct(99.9, 100) == "-0.1%" and pct(0, 0) == "=" and pct(1, 0) == "new"
    assert cell(None) == "-" and cell(3, 2, "{:.0f}") == "3 +50.0%"
    assert regime_name({"colors": 24, "detail": 0.5}) == "c24-d0.5"
    assert regime_name({"colors": 12, "detail": 0.0}) == "c12-d0"
    assert abs(palette_floor({"colors": 24}, {}) - 0.04) < 1e-12
    assert abs(palette_floor({"colors": 150}, {}) - 0.016) < 1e-12
    assert palette_floor({"colors": 150}, {"minPaletteDistanceFloor": 0.02}) == 0.02
    assert abs(palette_floor({"colors": 150}, {"minPaletteDistanceFloor": "x"}) - 0.016) < 1e-12
    checks += 7
    # Baseline-held metrics show their delta.
    cells = dict(zip(COLUMNS, row("x", regime, dict(good, minInscribedRadius=2.09, colors=147, bandRings=105,
                                                     minPaletteDistanceFloor=0.016), base, [])))
    assert cells["min r"] == "2.090 -5.0%" and cells["colors"] == "147 +5.0%", cells
    assert cells["rings"] == "105 +5.0%", cells
    assert cells["paint gap"] == "0.0162 = >= 0.0160", cells
    checks += 1
    table([row("x", regime, good, base, [])])
    totals({"k": good}, {"k": base}, ["k"])
    totals({"k": good}, {}, ["k"])
    checks += 3
    # The book regime: the same rules on the book's cells, its drawing metrics informational.
    book_regime = {"book": "coloringBook", "colors": 24, "detail": 0.5}
    assert regime_name(book_regime) == "book-c24-d0.5" and columns(book_regime) == BOOK_COLUMNS
    book_base = dict(base, minPaletteDistance=0.045, enclosedAreas=40, largestAreaFraction=0.6, inkDensity=8.0,
                     openEndsPer1000=5.0, interiorStrokes=120)
    book_good = dict(good, minPaletteDistance=0.045, minPaletteDistanceFloor=0.04, enclosedAreas=44,
                     largestAreaFraction=0.62, inkDensity=8.4, openEndsPer1000=4.0, interiorStrokes=100)
    assert check_case(book_regime, book_good, book_base) == []
    assert check_case(book_regime, dict(book_good, enclosedAreas=4000, largestAreaFraction=1.0, inkDensity=None), book_base) == []
    assert check_case(book_regime, dict(book_good, regions=1200), book_base)
    assert check_case(book_regime, dict(book_good, regionsUnderRadius2=1), book_base)
    cells = dict(zip(BOOK_COLUMNS, make_row("x", book_regime, book_good, book_base, [])))
    assert cells["cells"] == "1000 =" and cells["areas"] == "44 +10.0%" and cells["largest"] == "0.620 +3.3%", cells
    assert cells["strokes"] == "100 -16.7%" and cells["verdict"] == "ok", cells
    assert make_row("x", book_regime, {"error": "pbn: boom"}, None, ["x"])[-1] == "FAIL"
    assert set(BOOK_METRICS) <= set(baseline_entry(book_good)), baseline_entry(book_good)
    assert make_row("x", regime, good, base, []) == row("x", regime, good, base, [])
    table([make_row("x", book_regime, book_good, book_base, [])], BOOK_COLUMNS)
    checks += 10
    # The auto regime: the choice must lie inside the bands pbn reports; the rest is
    # informational, but the baseline entry must exist.
    auto_regime = {"auto": "relaxed"}
    settings = {"colorCount": 24, "detail": 0.45, "smoothness": 0.5, "seed": 24301}
    decision = {"preference": "relaxed", "settings": settings, "winner": 1,
                "candidates": [{"settings": dict(settings, colorCount=18)}, {"settings": settings}],
                "bands": {"colors": [8, 40], "detail": [0.15, 0.85], "smoothness": [0.25, 0.8], "minutes": [40, 120]}}
    auto_good = dict(good, auto=decision, minPaletteDistance=0.045, minPaletteDistanceFloor=0.04)
    auto_base = dict(base, settings={"colorCount": 24, "detail": 0.45, "smoothness": 0.5}, winner=1)

    def expect_auto(changes, failing, base_entry=auto_base, auto_changes=None):
        nonlocal checks
        result = dict(auto_good, **changes)
        if auto_changes is not None:
            result["auto"] = dict(decision, **auto_changes)
        failures = check_case(auto_regime, result, base_entry)
        assert bool(failures) == failing, f"{changes} {auto_changes}: expected {'failure' if failing else 'pass'}, got {failures}"
        auto_row("x", auto_regime, result, base_entry, failures)
        if not result.get("error") and isinstance(result.get("auto"), dict):
            auto_baseline_entry(result)
        checks += 1
        return failures

    expect_auto({}, False)
    # Informational: metrics and choices may move freely.
    expect_auto({"regions": 5000, "meanDeltaE": 0.5, "encodedBytes": 1}, False)
    expect_auto({}, False, base_entry=dict(auto_base, settings={"colorCount": 30, "detail": 0.6, "smoothness": 0.4}))
    expect_auto({}, True, base_entry=None)
    # Hard: the choice inside the bands, the winner's settings, the preference asked for.
    expect_auto({}, True, auto_changes={"settings": dict(settings, colorCount=42),
                                        "candidates": [{"settings": dict(settings, colorCount=42)}] * 2})
    expect_auto({}, True, auto_changes={"settings": dict(settings, detail=0.9),
                                        "candidates": [{"settings": dict(settings, detail=0.9)}] * 2})
    expect_auto({}, True, auto_changes={"settings": dict(settings, smoothness=0.2),
                                        "candidates": [{"settings": dict(settings, smoothness=0.2)}] * 2})
    expect_auto({}, False, auto_changes={"settings": dict(settings, colorCount=40),
                                         "candidates": [{"settings": dict(settings, colorCount=40)}] * 2})
    expect_auto({}, True, auto_changes={"winner": 0})
    expect_auto({}, True, auto_changes={"winner": 2})
    expect_auto({}, True, auto_changes={"winner": True})
    expect_auto({}, True, auto_changes={"preference": "quick"})
    expect_auto({}, True, auto_changes={"bands": {"colors": [8], "detail": [0.15, 0.85], "smoothness": [0.25, 0.8]}})
    expect_auto({}, True, auto_changes={"bands": "wide"})
    expect_auto({}, True, auto_changes={"settings": {"colorCount": "many"}})
    assert "auto decision" in expect_auto({"auto": None}, True)[0]
    # The usual invariants hold in the auto regime too.
    expect_auto({"regionsUnderRadius2": 1}, True)
    expect_auto({"deterministic": False}, True)
    assert expect_auto({"error": "suggestion failed: boom"}, True) == ["pbn: suggestion failed: boom"]
    cells = dict(zip(AUTO_COLUMNS, auto_row("x", auto_regime, dict(auto_good, regions=1000), auto_base, [])))
    assert cells["choice"] == "24c d0.45 s0.5" and cells["baseline"] == "same" and cells["est min"] == "50", cells
    cells = dict(zip(AUTO_COLUMNS, auto_row("x", auto_regime, dict(auto_good, regions=100), dict(auto_base, settings={
        "colorCount": 30, "detail": 0.6, "smoothness": 0.4}), [])))
    assert cells["baseline"] == "was 30c d0.6 s0.4" and cells["est min"] == "5 <", cells
    assert dict(zip(AUTO_COLUMNS, auto_row("x", auto_regime, auto_good, None, [])))["baseline"] == "new"
    assert regime_name(auto_regime) == "auto-relaxed"
    assert abs(palette_floor(auto_regime, {"auto": decision}) - 0.04) < 1e-12
    assert abs(palette_floor(auto_regime, {}) - 0.04) < 1e-12
    table([auto_row("x", auto_regime, auto_good, auto_base, [])], AUTO_COLUMNS)
    checks += 5
    print(f"self-test passed ({checks} checks)")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        sys.exit(main(sys.argv[1:]))
