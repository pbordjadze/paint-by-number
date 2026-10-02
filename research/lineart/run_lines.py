"""Stage 1 driver: every line family x detail level on one picture directory.

    python run_lines.py <pic-dir> [--families all|f1,f2] [--details sparse,medium,rich]
                        --out <out-dir> [--force-raw]

<pic-dir> is a `pbn generate <pic> <dir> --auto --length relaxed` output (working.ppm,
raster.ppm). Per option `<family>-<detail>` it writes into <out-dir>/<option>/:
  raw.png           the family's raw response (dark = line), working size
  strokes.json      {"width", "height", "strokes": [{"points", "closed", "width",
                    "width_tapered", "contrast", "importance", "free_ends", "color"}]}
  walls.png         uint8 0/255, the centerlines as 8-connected 1 px lines (stage 2 contract)
  ink.png           RGBA 2x: weighted ink; ink_tapered.png, ink_colored.png, ink_uniform.png
  lines_alone.png   ink.png on paper #F4EFE6 (panel 1); lines_alone_tapered.png and
                    lines_alone_colored.png for the variants
  metrics.json      ink coverage, strokes, mean length, fragments, strong-edge recall,
                    edge precision, runtimes, peak memory
Raw maps are cached in <out-dir>/_cache/<family>.npy (+ .json with runtime and memory), so
re-tuning the cleanup does not rerun the detectors (--force-raw recomputes them).
Also written: importance.png (+ importance.json: the faces found), strong_edges.png and
summary.json (all options' metrics).
"""

import argparse
import json
import os
import resource
import subprocess
import sys
import time

import numpy as np
from PIL import Image
from scipy import ndimage

import lines_common as lc
import strokes as st

HERE = os.path.dirname(os.path.abspath(__file__))

# Hysteresis (high, low) per family and detail level, on each family's raw scale (1 = line).
# Tuned by eye per family (see results.md); the rest of the cleanup is shared (strokes.DETAIL).
FAMILIES = {
    "flowdog": dict(kind="py", module="lines_flowdog",
                    th={"sparse": (0.50, 0.15), "medium": (0.30, 0.08), "rich": (0.18, 0.05)}),
    "xdog": dict(kind="py", module="lines_xdog", fill=0.7,
                 th={"sparse": (0.90, 0.55), "medium": (0.85, 0.48), "rich": (0.72, 0.38)}),
    "boundaries": dict(kind="py", module="lines_boundaries",
                       th={"sparse": (0.45, 0.25), "medium": (0.33, 0.18), "rich": (0.22, 0.12)}),
    "learned_lineart_fine": dict(kind="learned", model="lineart_fine",
                                 th={"sparse": (0.42, 0.22), "medium": (0.32, 0.15), "rich": (0.22, 0.10)}),
    "learned_lineart_coarse": dict(kind="learned", model="lineart_coarse",
                                   th={"sparse": (0.65, 0.35), "medium": (0.50, 0.25), "rich": (0.38, 0.18)}),
    "learned_pidinet": dict(kind="learned", model="pidinet",
                            th={"sparse": (0.85, 0.45), "medium": (0.65, 0.30), "rich": (0.45, 0.20)}),
    "learned_hed": dict(kind="learned", model="hed",
                        th={"sparse": (0.85, 0.50), "medium": (0.70, 0.35), "rich": (0.50, 0.25)}),
    "learned_teed": dict(kind="learned", model="teed",
                         th={"sparse": (0.80, 0.50), "medium": (0.60, 0.35), "rich": (0.45, 0.28)}),
    "learned_lineart_anime": dict(kind="learned", model="lineart_anime",
                                  th={"sparse": (0.32, 0.14), "medium": (0.22, 0.09), "rich": (0.15, 0.06)}),
}
DETAILS = ["sparse", "medium", "rich"]

STRONG_EDGE = 0.030   # OKLab gradient (sigma 1.5, deltaE / px) x importance above this is "strong"
MODERATE_EDGE = 0.012  # gradient above this counts as an edge for precision
RECALL_RADIUS = 2.0


def raw_map(fam, pic, cache_dir, force=False):
    spec = FAMILIES[fam]
    npy = os.path.join(cache_dir, fam + ".npy")
    meta_path = os.path.join(cache_dir, fam + ".json")
    if not force and os.path.exists(npy) and os.path.exists(meta_path):
        with open(meta_path) as f:
            return np.load(npy), json.load(f)
    if spec["kind"] == "py":
        mod = __import__(spec["module"])
        t0 = time.time()
        raw = mod.response(pic).astype(np.float32)
        meta = {"seconds": round(time.time() - t0, 2)}
    else:
        cmd = [sys.executable, os.path.join(HERE, "lines_learned.py"), pic["dir"], spec["model"],
               npy, "--meta", meta_path]
        subprocess.run(cmd, check=True, stderr=subprocess.DEVNULL)
        raw = np.load(npy)
        with open(meta_path) as f:
            meta = json.load(f)
    np.save(npy, raw)
    with open(meta_path, "w") as f:
        json.dump(meta, f)
    return raw, meta


def strong_edges(lab, importance):
    """Di Zenzo color gradient (sigma 1.5) of OKLab, non-maximum suppressed to 1 px."""
    jxx = np.zeros(lab.shape[:2])
    jyy = np.zeros(lab.shape[:2])
    jxy = np.zeros(lab.shape[:2])
    for c in range(3):
        ch = lab[..., c].astype(np.float64)
        gx = ndimage.gaussian_filter(ch, 1.5, order=(0, 1), mode="nearest")
        gy = ndimage.gaussian_filter(ch, 1.5, order=(1, 0), mode="nearest")
        jxx += gx * gx
        jyy += gy * gy
        jxy += gx * gy
    tr = jxx + jyy
    lam = 0.5 * (tr + np.sqrt((jxx - jyy) ** 2 + 4 * jxy * jxy))
    mag = np.sqrt(lam)
    theta = 0.5 * np.arctan2(2 * jxy, jxx - jyy)
    dx, dy = np.cos(theta), np.sin(theta)
    h, w = mag.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)

    def at(ox, oy):
        return ndimage.map_coordinates(mag, [yy + oy, xx + ox], order=1, mode="nearest")

    nms = (mag >= at(dx, dy)) & (mag >= at(-dx, -dy))
    nms[:st.FRAME + 1, :] = False
    nms[-st.FRAME - 1:, :] = False
    nms[:, :st.FRAME + 1] = False
    nms[:, -st.FRAME - 1:] = False
    strong = nms & (mag * importance > STRONG_EDGE)
    lab_, n = ndimage.label(strong, structure=np.ones((3, 3), bool))
    if n:
        sizes = ndimage.sum(strong, lab_, np.arange(1, n + 1))
        strong = np.isin(lab_, np.flatnonzero(sizes >= 10) + 1)
    moderate = nms & (mag > MODERATE_EDGE)
    return strong, moderate


def metrics(strokes, wall, ink_rgba, strong, moderate):
    lengths = [s["length"] for s in strokes]
    m = {
        "strokes": len(strokes),
        "mean_stroke_length": round(float(np.mean(lengths)), 1) if lengths else 0.0,
        "total_stroke_length": round(float(np.sum(lengths)), 1),
        "fragments": int(sum(1 for L in lengths if L < st.FRAGMENT_METRIC)),
        "closed_strokes": int(sum(1 for s in strokes if s["closed"])),
        "ink_coverage": round(float(ink_rgba[..., 3].mean() / 255.0), 4),
        "wall_pixels": int((wall > 0).sum()),
    }
    if (wall > 0).any():
        d_wall = ndimage.distance_transform_edt(wall == 0)
        m["strong_edge_recall"] = round(float((d_wall[strong] <= RECALL_RADIUS).mean()), 4) if strong.any() else None
        # DoG-type lines sit on the dark side of an edge, 2-3 px off its maximum
        m["strong_edge_recall_4px"] = round(float((d_wall[strong] <= 4.0).mean()), 4) if strong.any() else None
        d_edge = ndimage.distance_transform_edt(~moderate)
        m["edge_precision"] = round(float((d_edge[wall > 0] <= RECALL_RADIUS).mean()), 4)
    else:
        m["strong_edge_recall"] = 0.0
        m["edge_precision"] = None
    m["strong_edge_pixels"] = int(strong.sum())
    return m


def save_png(path, arr):
    Image.fromarray(arr).save(path, optimize=False, compress_level=6)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pic_dir")
    ap.add_argument("--families", default="all")
    ap.add_argument("--details", default=",".join(DETAILS))
    ap.add_argument("--out", required=True)
    ap.add_argument("--force-raw", action="store_true")
    ap.add_argument("--raw-only", action="store_true", help="only compute and cache raw maps")
    args = ap.parse_args()

    fams = list(FAMILIES) if args.families == "all" else args.families.split(",")
    details = args.details.split(",")
    os.makedirs(args.out, exist_ok=True)
    cache = os.path.join(args.out, "_cache")
    os.makedirs(cache, exist_ok=True)

    pic = lc.load_picture(args.pic_dir)
    if args.raw_only:
        for fam in fams:
            raw_map(fam, pic, cache, args.force_raw)
            print(pic["name"], fam, "raw cached", flush=True)
        return
    h, w = pic["working"].shape[:2]
    faces = lc.detect_faces(pic["working"])
    importance = lc.importance_map(pic["working"], faces)
    with open(os.path.join(args.out, "importance.json"), "w") as f:
        json.dump({"faces": [[round(v, 1) for v in box] for box in faces]}, f)
    lab = lc.rgb8_to_oklab(pic["working"])
    lab_smooth = np.stack([ndimage.gaussian_filter(lab[..., c], 1.0, mode="nearest")
                           for c in range(3)], 2)
    raster_lab = lc.rgb8_to_oklab(pic["raster"]) if "raster" in pic else None
    strong, moderate = strong_edges(lab, importance)
    grad = lc.oklab_gradient(lab, 1.0)
    lc.save_gray(os.path.join(args.out, "importance.png"), importance)
    save_png(os.path.join(args.out, "strong_edges.png"), np.where(strong, 0, 255).astype(np.uint8))

    summary_path = os.path.join(args.out, "summary.json")
    summary = {}
    if os.path.exists(summary_path):
        with open(summary_path) as f:
            summary = json.load(f)
    for fam in fams:
        raw, raw_meta = raw_map(fam, pic, cache, args.force_raw)
        for detail in details:
            t0 = time.time()
            high, low = FAMILIES[fam]["th"][detail]
            fill_level = FAMILIES[fam].get("fill", FAMILIES[fam]["th"]["sparse"][0])
            g, strokes = st.extract(raw, importance, high, low, detail, fill_level, grad)
            st.weigh(strokes, lab_smooth, importance, raster_lab)
            wall = st.walls(strokes, w, h)
            t_clean = time.time() - t0
            ink = st.render(strokes, w, h, "width")
            ink_t = st.render(strokes, w, h, "width_tapered")
            ink_c = st.render(strokes, w, h, "width", "color" if raster_lab is not None else None)
            ink_u = st.render(strokes, w, h, "width_uniform")
            t_render = time.time() - t0 - t_clean
            opt = f"{fam}-{detail}"
            od = os.path.join(args.out, opt)
            os.makedirs(od, exist_ok=True)
            lc.save_raw_png(os.path.join(od, "raw.png"), raw)
            with open(os.path.join(od, "strokes.json"), "w") as f:
                json.dump(st.to_json(strokes, w, h), f, separators=(",", ":"))
            save_png(os.path.join(od, "walls.png"), wall)
            save_png(os.path.join(od, "ink.png"), ink)
            save_png(os.path.join(od, "ink_tapered.png"), ink_t)
            save_png(os.path.join(od, "ink_colored.png"), ink_c)
            save_png(os.path.join(od, "ink_uniform.png"), ink_u)
            save_png(os.path.join(od, "lines_alone.png"), st.on_paper(ink))
            save_png(os.path.join(od, "lines_alone_tapered.png"), st.on_paper(ink_t))
            save_png(os.path.join(od, "lines_alone_colored.png"), st.on_paper(ink_c))
            m = metrics(strokes, wall, ink, strong, moderate)
            m.update({
                "family": fam, "detail": detail, "thresholds": [high, low],
                "cleanup": st.DETAIL[detail],
                "raw_seconds": raw_meta.get("seconds"),
                "raw_model_load_seconds": raw_meta.get("load_seconds"),
                "raw_peak_rss_mb": raw_meta.get("peak_rss_mb"),
                "cleanup_seconds": round(t_clean, 2),
                "render_seconds": round(t_render, 2),
                "driver_peak_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024, 1),
            })
            with open(os.path.join(od, "metrics.json"), "w") as f:
                json.dump(m, f, indent=1)
            summary[opt] = m
            print(f"{pic['name']:12s} {opt:32s} strokes {m['strokes']:5d} mean {m['mean_stroke_length']:6.1f} "
                  f"ink {m['ink_coverage']:.3f} recall {m['strong_edge_recall']} prec {m['edge_precision']} "
                  f"t {t_clean:.1f}+{t_render:.1f}s", flush=True)
    with open(summary_path, "w") as f:
        json.dump(dict(sorted(summary.items())), f, indent=1)


if __name__ == "__main__":
    main()
