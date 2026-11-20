#!/usr/bin/env python3
"""Judges catalog candidates on their templates (painting-company row 368), as docs/picture-library.md
asks of every library picture, before anyone looks at them.

    tools/nights/judge.py DIR [--max N] [--jobs 4] [--ids id1,id2]
    tools/nights/judge.py DIR --sheets [--top 120] [--per-sheet 24]

Reads DIR/candidates.jsonl (catalog.py), takes those that passed the rules, downloads a ~1024 px
preview of each (the museums' own small renditions; DIR/previews/), measures the picture (too dark,
too grey, too long a shape) and runs `pbn generate --auto --length relaxed` on what survives (pbn
at .build/release/pbn or $PBN; classic lines, since pbn has no line-art models). Writes
DIR/judged.jsonl: the candidate with `measures`, `template` (pbn's stats) and `verdict` ("ok" or
the reason). An already judged id is skipped, so a rerun continues.

--sheets lays the best of the "ok" ones out as contact sheets (DIR/sheets/sheet-NN.jpg: the
picture above its painted template, the id under them), ranked by `score`, for the eye pass.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageStat

ROOT = Path(__file__).resolve().parents[2]
PBN = os.environ.get("PBN", str(ROOT / ".build" / "release" / "pbn"))
UA = "PaintByMoonlight-catalog/1.0 (open-access research)"


def preview_url(c):
    if c["source_name"] == "aic":
        return c["thumb"].replace("/full/400,/", "/full/1024,/")
    return c.get("thumb") or c["image"]


def download(url, path):
    if path.exists() and path.stat().st_size > 0:
        return
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=90) as r:
                if not r.headers.get("Content-Type", "").startswith("image/"):
                    raise ValueError(f"not an image ({r.headers.get('Content-Type')}): a bot wall")
                path.write_bytes(r.read())
            time.sleep(1.0 if "artic.edu" in url else 0.2)
            return
        except ValueError:
            raise
        except Exception:
            time.sleep(3 << attempt)
    raise RuntimeError(f"download failed: {url}")


def measure(img):
    small = img.convert("RGB").resize((160, max(1, round(160 * img.height / img.width))))
    y = small.convert("L")
    hist = y.histogram()
    n = sum(hist)
    dark = sum(hist[:50]) / n
    mean_y = ImageStat.Stat(y).mean[0] / 255
    hsv = small.convert("HSV")
    sat = ImageStat.Stat(hsv.split()[1]).mean[0] / 255
    contrast = ImageStat.Stat(y).stddev[0] / 255
    aspect = max(img.width, img.height) / min(img.width, img.height)
    return {"mean": round(mean_y, 3), "dark": round(dark, 3), "saturation": round(sat, 3),
            "contrast": round(contrast, 3), "aspect": round(aspect, 2), "w": img.width, "h": img.height}


def verdict_of_measures(m):
    if m["mean"] < 0.30 or m["dark"] > 0.40:
        return "too dark"
    if m["saturation"] < 0.12:
        return "too grey"
    if m["contrast"] < 0.10:
        return "too flat"
    if m["aspect"] > 2.2:
        return "too long a shape"
    return None


def judge_one(c, root):
    out = {**c}
    prev = root / "previews" / f"{c['id']}.jpg"
    try:
        download(preview_url(c), prev)
        img = Image.open(prev)
        img.load()
    except Exception as e:
        out["verdict"] = f"no preview: {e}"
        return out
    out["measures"] = m = measure(img)
    bad = verdict_of_measures(m)
    if bad:
        out["verdict"] = bad
        return out
    work = root / "templates" / c["id"]
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        ppm = Path(tmp) / "in.ppm"
        img.convert("RGB").save(ppm)
        r = subprocess.run([PBN, "generate", str(ppm), str(work), "--auto", "--length", "relaxed"],
                           capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        out["verdict"] = "pbn failed"
        return out
    s = json.loads((work / "stats.json").read_text())
    for f in ("template.pbnt", "painted.svg", "painted-outlined.svg", "template.svg", "working.ppm", "boundaries.ppm"):
        (work / f).unlink(missing_ok=True)
    ras = work / "raster.ppm"
    if ras.exists():
        Image.open(ras).convert("RGB").save(work / "painted.jpg", quality=85)
        ras.unlink()
    area = s["width"] * s["height"]
    t = {k: s.get(k) for k in ("regions", "colors", "meanDeltaE", "p95DeltaE", "medianRegionArea",
                                "labelsBelowLegibleSize", "labelRoomUnmet", "valid", "width", "height")}
    t["regionsPerMegapixel"] = round(s["regions"] / area * 1e6)
    out["template"] = t
    if not s.get("valid") or s.get("labelsBelowLegibleSize") or s.get("labelRoomUnmet"):
        out["verdict"] = "template invalid"
    elif t["regionsPerMegapixel"] > 900:
        out["verdict"] = "a crumble of small areas"
    elif s["colors"] < 10:
        out["verdict"] = "too few paints"
    else:
        out["verdict"] = "ok"
    # Higher is better: color and light, a fair number of areas, faithful paint.
    out["score"] = round(m["saturation"] * 2 + m["mean"] + m["contrast"] - s["meanDeltaE"] * 4
                         - abs(t["regionsPerMegapixel"] - 550) / 1000, 4)
    return out


def run(a):
    root = a.dir
    (root / "previews").mkdir(exist_ok=True)
    judged_path = root / "judged.jsonl"
    done = {json.loads(l)["id"] for l in judged_path.open()} if judged_path.exists() else set()
    todo = [c for c in map(json.loads, (root / "candidates.jsonl").open())
            if not c["rejected"] and c["id"] not in done]
    if a.ids:
        wanted = set(a.ids.split(","))
        todo = [c for c in todo if c["id"] in wanted]
    if a.max:
        # Spread a partial run across the sources.
        by = {}
        for c in todo:
            by.setdefault(c["source_name"], []).append(c)
        todo = [c for group in zip(*[iter(v) for v in by.values()]) for c in group][:a.max] or todo[:a.max]
    print(f"judging {len(todo)}", file=sys.stderr)
    with ThreadPoolExecutor(a.jobs) as ex, judged_path.open("a") as f:
        for i, res in enumerate(ex.map(lambda c: judge_one(c, root), todo)):
            f.write(json.dumps(res, ensure_ascii=False) + "\n")
            f.flush()
            if i % 25 == 0:
                print(f"{i}/{len(todo)} {res['id']} {res['verdict']}", file=sys.stderr)


def sheets(a):
    root = a.dir
    rows = [json.loads(l) for l in (root / "judged.jsonl").open()]
    ok = sorted((r for r in rows if r["verdict"] == "ok"), key=lambda r: -r["score"])[:a.top]
    (root / "sheets").mkdir(exist_ok=True)
    cell, cols = 300, 6
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    except OSError:
        font = ImageFont.load_default()
    for s in range(0, len(ok), a.per_sheet):
        chunk = ok[s:s + a.per_sheet]
        nrows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, nrows * (cell * 2 + 40)), (242, 241, 244))
        d = ImageDraw.Draw(sheet)
        for i, r in enumerate(chunk):
            x, y = (i % cols) * cell, (i // cols) * (cell * 2 + 40)
            for j, p in enumerate([root / "previews" / f"{r['id']}.jpg", root / "templates" / r["id"] / "painted.jpg"]):
                if p.exists():
                    im = Image.open(p).convert("RGB")
                    im.thumbnail((cell - 8, cell - 8))
                    sheet.paste(im, (x + (cell - im.width) // 2, y + j * cell + (cell - im.height) // 2))
            d.text((x + 6, y + 2 * cell + 2), f"{s + i + 1}. {r['id']}", fill=(30, 30, 30), font=font)
            d.text((x + 6, y + 2 * cell + 19), f"{r['title'][:34]}", fill=(90, 90, 90), font=font)
        sheet.save(root / "sheets" / f"sheet-{s // a.per_sheet + 1:02d}.jpg", quality=82)
    print(f"{len(ok)} on {(len(ok) + a.per_sheet - 1) // a.per_sheet} sheets", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir", type=Path)
    ap.add_argument("--max", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--ids")
    ap.add_argument("--sheets", action="store_true")
    ap.add_argument("--top", type=int, default=120)
    ap.add_argument("--per-sheet", type=int, default=24)
    a = ap.parse_args()
    sheets(a) if a.sheets else run(a)


if __name__ == "__main__":
    main()
