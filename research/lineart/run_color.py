"""Stage 2 runner: color regions inside a drawing, and their panels.

    run_color.py <pic-dir> <option-dir> [--method c1|c2|both] [--out DIR] [--ink ink.png]

<pic-dir> holds pbn's outputs (working.ppm, raster.ppm, stats.json, template.svg, painted.svg);
<option-dir> holds stage 1's walls.png and ink.png. Writes into --out (default: the option
folder itself, next to stage 1's files): regions_<m>.png (uint16 label map, every pixel
labelled), regions_<m>.json (palette index per region), plan_<m>.png, finished_<m>.png,
metrics_<m>.json (and with --flat flat_<m>.png); and, once per picture (in <out>/..), current_template.png and
current_painted.png.

Batch over every finished stage-1 option (folders with walls.png, ink.png and metrics.json;
options whose outputs are newer than stage 1's metrics.json are skipped), then
summary_color.json / summary_color.tsv under the output root:

    python run_color.py --batch $S/lineart/out [--inputs $S/lineart/inputs] [--picks picks.json] \
        [--pics parrots,kodim04] [--options '*-medium'] [--method c1] [--jobs 2] [--force]
"""

from __future__ import annotations

import argparse
import json
import os
import time

import numpy as np

from color_common import digit_count, enclosed_areas, load_option, load_picture, min_radius, rooms, save_labels
from color_segment import segment
from color_split import split
import panels


def metrics(pic, opt, reg, finished_lab=None) -> dict:
    lab, col = reg.lab, reg.color
    n = len(col)
    room, _, area = rooms(lab, n, opt.ink)
    room_raw, _, _ = rooms(lab, n, None)
    need = np.array([min_radius(digit_count(c + 1)) for c in col])
    # perimeter: cracks to other regions (canvas border not counted)
    per = np.zeros(n, np.int64)
    for a, b in ((lab[:, :-1], lab[:, 1:]), (lab[:-1, :], lab[1:, :])):
        m = a != b
        per += np.bincount(a[m], minlength=n) + np.bincount(b[m], minlength=n)
    thin = (area / np.maximum(per, 1)) < 1.0
    sliver = (room < 2.0) | thin
    areas, n_areas = enclosed_areas(opt.walls | reg.absorbed)
    # regions per enclosed area, from the labels before wall assignment
    ol = reg.open_lab
    m = (ol >= 0) & (areas > 0)
    pair = np.unique(areas[m].astype(np.int64) * (1 << 20) + ol[m])
    per_area = np.bincount((pair >> 20).astype(np.int64), minlength=n_areas + 1)[1:]
    painted_areas = per_area[per_area > 0]
    # unlined vs lined boundary cracks
    unlined = 0
    for a, b in ((ol[:, :-1], ol[:, 1:]), (ol[:-1, :], ol[1:, :])):
        unlined += int(((a >= 0) & (b >= 0) & (a != b)).sum())
    total = sum(int((a != b).sum()) for a, b in ((lab[:, :-1], lab[:, 1:]), (lab[:-1, :], lab[1:, :])))
    photo = pic.photo_lab
    flat = pic.palette_lab[col[lab]]
    raster = pic.palette_lab[pic.raster]
    out = {
        "regions": int(n),
        "pbnRegions": int(pic.stats.get("regions", 0)),
        "enclosedAreas": int(len(painted_areas)),
        "regionsPerArea": {
            "mean": round(float(painted_areas.mean()), 3) if len(painted_areas) else 0,
            "median": float(np.median(painted_areas)) if len(painted_areas) else 0,
            "max": int(painted_areas.max()) if len(painted_areas) else 0,
            "areasWithSeveral": int((painted_areas > 1).sum()),
        },
        "slivers": int(sliver.sum()),
        "sliversRoomUnder2": int((room < 2.0).sum()),
        "sliversThin": int(thin.sum()),
        "minRoom": round(float(room.min()), 3) if n else 0,
        "minRoomIgnoringInk": round(float(room_raw.min()), 3) if n else 0,
        "minimumRadius": 2.12,
        "regionsBelowMinimumRadius": int((room < need).sum()),
        "cellsTooSmall": reg.cells.get("tooSmall", 0),
        "cellsJoinedAcrossLine": reg.cells.get("joinedAcrossLine", 0),
        "cellsAbsorbed": reg.cells.get("absorbed", 0),
        "medianRegionArea": float(np.median(area)) if n else 0,
        "unlinedBoundaryShare": round(unlined / max(total, 1), 3),
        "colorsUsed": int(len(np.unique(col))),
        "meanDeltaE": round(float(np.sqrt(((flat - photo) ** 2).sum(-1)).mean()), 4),
        "pbnMeanDeltaE": round(float(np.sqrt(((raster - photo) ** 2).sum(-1)).mean()), 4),
        # where the paint shows: the photo's own dark lines are ink here, paint in pbn's raster
        "meanDeltaEOutsideInk": round(float(np.sqrt(((flat - photo) ** 2).sum(-1))[~opt.ink].mean()), 4),
        "pbnMeanDeltaEOutsideInk": round(float(np.sqrt(((raster - photo) ** 2).sum(-1))[~opt.ink].mean()), 4),
    }
    if finished_lab is not None:
        out["finishedMeanDeltaE"] = round(float(np.sqrt(((finished_lab - photo) ** 2).sum(-1)).mean()), 4)
    return out


def run(pic_dir: str, opt_dir: str, method: str, out_dir: str, ink: str = "ink.png", current: bool = True,
        panels_too: bool = True, flat: bool = False) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    pic = load_picture(pic_dir)
    opt = load_option(opt_dir, pic.height, pic.width, ink)
    results = {}
    for m in (["c1", "c2"] if method == "both" else [method]):
        t0 = time.time()
        reg = split(pic, opt) if m == "c1" else segment(pic, opt)
        t1 = time.time()
        save_labels(os.path.join(out_dir, f"regions_{m}.png"), reg.lab)
        json.dump({"colors": reg.color.tolist(), "absorbedPixels": int(reg.absorbed.sum())},
                  open(os.path.join(out_dir, f"regions_{m}.json"), "w"))
        fin_lab = None
        if panels_too:
            c2x = panels.smooth_colors_2x(panels.region_colors(reg), opt.walls | reg.absorbed)
            panels.plan(pic, opt, reg, c2x).save(os.path.join(out_dir, f"plan_{m}.png"), compress_level=9)
            img, soft = panels.finished(pic, opt, reg, c2x, return_lab=True)
            img.save(os.path.join(out_dir, f"finished_{m}.png"), compress_level=9)
            if flat:
                panels.flat_paint(pic, opt, reg, c2x).save(os.path.join(out_dir, f"flat_{m}.png"), compress_level=9)
            h, w = pic.height, pic.width
            fin_lab = soft.reshape(h, 2, w, 2, 3).mean(axis=(1, 3))
        t2 = time.time()
        met = metrics(pic, opt, reg, fin_lab)
        met.update({"picture": pic.name, "option": os.path.relpath(opt.dir, os.path.dirname(os.path.dirname(opt.dir))),
                    "method": m, "seconds": {"regions": round(t1 - t0, 2), "panels": round(t2 - t1, 2)}})
        json.dump(met, open(os.path.join(out_dir, f"metrics_{m}.json"), "w"), indent=1)
        results[m] = met
    if current:
        pic_out = os.path.dirname(os.path.abspath(out_dir.rstrip("/")))
        if not os.path.exists(os.path.join(pic_out, "current_template.png")):
            panels.current_template(pic, pic_out)
    return results


def default_out(opt_dir: str) -> str:
    """Next to stage 1's files, in the option folder (no file names collide: stage 1 writes
    metrics.json, stage 2 metrics_c1.json / metrics_c2.json)."""
    return os.path.abspath(opt_dir.rstrip("/"))


def report(met: dict) -> str:
    return (f"{met['picture']} {met['option']} {met['method']}: regions {met['regions']} (pbn {met['pbnRegions']}), "
            f"areas {met['enclosedAreas']}, per area {met['regionsPerArea']['mean']}, slivers {met['slivers']}, "
            f"minRoom {met['minRoom']}, below min {met['regionsBelowMinimumRadius']}, ΔE {met['meanDeltaE']} "
            f"(pbn {met['pbnMeanDeltaE']}), {met['seconds']}")


def _batch_job(job):
    pic_dir, opt_dir, out_dir, method, ink, force, flat = job
    stamp = os.path.join(out_dir, f"metrics_{'c1' if method == 'c1' else 'c2'}.json")   # written last
    done = os.path.join(opt_dir, "metrics.json")       # stage 1 writes it last
    if not force and os.path.exists(stamp) and os.path.getmtime(stamp) > os.path.getmtime(done):
        return f"skip {out_dir} (up to date)"
    try:
        res = run(pic_dir, opt_dir, method, out_dir, ink, flat=flat)
        return "\n".join(report(m) for m in res.values())
    except Exception as e:   # keep the batch going; the failure is in the log
        return f"FAILED {opt_dir}: {type(e).__name__}: {e}"


def batch(lines_root: str, inputs_root: str, out_root: str, method: str, ink: str, jobs: int, force: bool,
          pics: list | None, options: str | None, picks: dict | None = None, flat: bool = False) -> None:
    """Every stage-1 option (a folder with walls.png) under <lines_root>/<pic>/<option>/;
    with ``picks`` ({pic: [option, ...]}) only those."""
    import fnmatch
    from multiprocessing import Pool
    work = []
    for pic in sorted(os.listdir(lines_root)):
        if pics and pic not in pics:
            continue
        if picks is not None and pic not in picks:
            continue
        if not os.path.isdir(os.path.join(lines_root, pic)):
            continue
        pic_dir = os.path.join(inputs_root, pic)
        if not os.path.exists(os.path.join(pic_dir, "stats.json")):
            continue
        for opt in sorted(os.listdir(os.path.join(lines_root, pic))):
            opt_dir = os.path.join(lines_root, pic, opt)
            if not all(os.path.exists(os.path.join(opt_dir, f)) for f in ("walls.png", "ink.png", "metrics.json")):
                continue        # not an option, or stage 1 is still writing it
            if options and not any(fnmatch.fnmatch(opt, pat) for pat in options.split(",")):
                continue
            if picks is not None and opt not in picks[pic]:
                continue
            work.append((pic_dir, opt_dir, os.path.join(out_root, pic, opt), method, ink, force, flat))
    print(f"{len(work)} options", flush=True)
    with Pool(jobs) as pool:
        for line in pool.imap(_batch_job, work):
            print(line, flush=True)
    summarize(out_root)


def summarize(out_root: str) -> None:
    """Collects every metrics_c*.json under <out_root>/<pic>/<option>/ into summary_color.json
    and summary_color.tsv."""
    rows = []
    for pic in sorted(os.listdir(out_root)):
        pdir = os.path.join(out_root, pic)
        if not os.path.isdir(pdir):
            continue
        for opt in sorted(os.listdir(pdir)):
            for m in ("c1", "c2"):
                f = os.path.join(pdir, opt, f"metrics_{m}.json")
                if os.path.exists(f):
                    rows.append(json.load(open(f)))
    json.dump(rows, open(os.path.join(out_root, "summary_color.json"), "w"), indent=1)
    cols = ["picture", "option", "method", "regions", "pbnRegions", "enclosedAreas", "regionsPerArea.mean",
            "slivers", "cellsTooSmall", "cellsJoinedAcrossLine", "cellsAbsorbed", "minRoom", "regionsBelowMinimumRadius", "unlinedBoundaryShare",
            "colorsUsed", "meanDeltaE", "pbnMeanDeltaE", "finishedMeanDeltaE"]
    with open(os.path.join(out_root, "summary_color.tsv"), "w") as fh:
        fh.write("\t".join(cols) + "\n")
        for r in rows:
            vals = []
            for c in cols:
                v = r
                for part in c.split("."):
                    v = v.get(part, "") if isinstance(v, dict) else ""
                vals.append(str(v))
            fh.write("\t".join(vals) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pic_dir", nargs="?")
    ap.add_argument("option_dir", nargs="?")
    ap.add_argument("--method", default="both", choices=["c1", "c2", "both"])
    ap.add_argument("--out", default=None, help="output folder (default: the option folder; batch: output root, "
                    "default LINES_ROOT itself)")
    ap.add_argument("--ink", default="ink.png", help="ink layer in the option dir (ink_tapered.png, ink_colored.png)")
    ap.add_argument("--no-current", action="store_true", help="skip rendering pbn's template for comparison")
    ap.add_argument("--flat", action="store_true", help="also write flat_<m>.png (the paint unblurred)")
    ap.add_argument("--batch", metavar="LINES_ROOT", help="run every <LINES_ROOT>/<pic>/<option>/ holding walls.png")
    ap.add_argument("--inputs", default=None, help="batch: pbn outputs root (default <LINES_ROOT>/../inputs)")
    ap.add_argument("--pics", default=None, help="batch: comma-separated picture names")
    ap.add_argument("--options", default=None, help="batch: comma-separated option globs, e.g. '*-medium'")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--force", action="store_true", help="batch: redo options whose outputs are newer than walls.png")
    ap.add_argument("--picks", default=None, help="batch: JSON file {pic: [option, ...]} (e.g. stage1_picks.json)")
    ap.add_argument("--summarize", metavar="OUT_ROOT", help="only rebuild summary_color.json/tsv under OUT_ROOT")
    a = ap.parse_args()
    if a.summarize:
        summarize(a.summarize)
        return
    if a.batch:
        root = os.path.abspath(a.batch.rstrip("/"))
        batch(root, a.inputs or os.path.join(os.path.dirname(root), "inputs"), a.out or root, a.method, a.ink,
              a.jobs, a.force, a.pics.split(",") if a.pics else None, a.options,
              json.load(open(a.picks)) if a.picks else None, a.flat)
        return
    if not (a.pic_dir and a.option_dir):
        ap.error("pic_dir and option_dir are required (or --batch)")
    res = run(a.pic_dir, a.option_dir, a.method, a.out or default_out(a.option_dir), a.ink, not a.no_current,
              flat=a.flat)
    for met in res.values():
        print(report(met))


if __name__ == "__main__":
    main()
