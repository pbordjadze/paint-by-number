#!/usr/bin/env python3
"""Render figure clips, clips, review sheets, and pixel checks.

    tools/factory/render.py factory/specs/baseline.json factory/scenes/hero.json ~/factory-out/hero

Prerequisites: Pillow, DejaVu Sans (DejaVuSans.ttf), node (npm ci --prefix tools), ffmpeg with libx264/libwebp_anim.
Build the host executable first: swift build -c release --product figures
--static-swift-stdlib. FIGURES_BIN or --figures selects another executable. All rasterization
runs in one node process on at most four threads; PNG composition uses at most four workers.
Encoders use at most four threads; the WebP preview uses display-point resolution. Runtime excludes building.
"""
import argparse
import copy
from concurrent.futures import ProcessPoolExecutor
import json
import math
import os
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def run(command):
    subprocess.run([str(part) for part in command], check=True)


def key_frames(manifest, spec):
    actions, fps, last = manifest["actions"], manifest["fps"], manifest["frameCount"] - 1
    walk = next((a for a in actions if a["kind"] in {"walk", "ink", "sweep"}), None)
    cast = next((a for a in actions if a["kind"] == "cast"), None)
    moments = [("mid-walk", (walk["start"] + walk["end"]) / 2 if walk else 0),
               ("wind-up", cast["windUp"] if cast else 0),
               ("release", cast["release"] if cast else 0),
               ("settled", cast["end"] if cast else manifest["duration"])]
    if walk and not cast:
        moments = [("start-" + walk["kind"], walk["start"]),
                   ("mid-" + walk["kind"], (walk["start"] + walk["end"]) / 2),
                   ("end-" + walk["kind"], walk["end"]), ("settled", manifest["duration"])]
    # The first held pose at or after each key time, including animation on twos.
    quantum = 2 if spec.get("motion", {}).get("onTwos", True) else 1
    return [(name, min(last, int(math.ceil(t * fps / quantum)) * quantum)) for name, t in moments]


def isolated(tree, layer):
    tree = copy.deepcopy(tree)
    layers = {layer} if isinstance(layer, str) else set(layer)
    for element in list(tree):
        if element.tag != f"{{{SVG}}}defs" and element.get("data-layer") not in layers:
            tree.remove(element)
    return tree


def write_svg(tree, path):
    path.write_bytes(ET.tostring(tree, encoding="utf-8", xml_declaration=True))


def color(value):
    digits = value[1:]
    if len(digits) in [3, 4]:
        digits = "".join(c * 2 for c in digits)
    return tuple(int(digits[i:i + 2], 16) for i in [0, 2, 4])


def luminance(rgb):
    channels = [v / 255 for v in rgb]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, [0.2126, 0.7152, 0.0722]))


def ink_contrast(background, masks, ink):
    ink_luma, worst = luminance(color(ink)), math.inf
    pixels = background.convert("RGB")
    for mask in masks:
        alpha = mask.getchannel("A")
        bounds = alpha.getbbox()
        if bounds is None:
            continue
        for rgb, coverage in zip(pixels.crop(bounds).getdata(), alpha.crop(bounds).getdata()):
            if coverage >= 128:
                light = luminance(rgb)
                worst = min(worst, (max(light, ink_luma) + 0.05) / (min(light, ink_luma) + 0.05))
    return round(worst if math.isfinite(worst) else 1, 6)


def labelled_grid(images, labels, columns, path, thumb=None):
    font = ImageFont.truetype("DejaVuSans.ttf", 18)
    if thumb:
        images = [image.resize(thumb, Image.Resampling.LANCZOS) for image in images]
    width, height = images[0].size
    footer = 32
    sheet = Image.new("RGB", (width * columns, (height + footer) * math.ceil(len(images) / columns)), "#F6F1E7")
    draw = ImageDraw.Draw(sheet)
    for i, (image, label) in enumerate(zip(images, labels)):
        x, y = (i % columns) * width, (i // columns) * (height + footer)
        sheet.paste(image, (x, y))
        draw.text((x + 12, y + height + 5), label, font=font, fill="#2B2622")
    sheet.save(path)


def background_image(scene, scene_file, size):
    paper = Image.new("RGB", size, color(scene["canvas"].get("paper", "#F6F1E7")))
    if scene.get("background"):
        with Image.open(scene_file.parent / scene["background"]) as original:
            resized = original.convert("RGBA").resize(size, Image.Resampling.LANCZOS)
            paper.paste(resized, (0, 0), resized)
    return paper


_frame_background = None


def init_compositor(path):
    global _frame_background
    with Image.open(path) as image:
        _frame_background = image.convert("RGB")


def composite_frame(path):
    with Image.open(path) as overlay:
        panel = _frame_background.copy()
        panel.paste(overlay, (0, 0), overlay)
        panel.save(path, compress_level=1)


def composite_frames(paths, background, scratch):
    path = scratch / "background.png"
    background.save(path, compress_level=1)
    # Independent processes keep PNG filtering and encoding on four cores.
    with ProcessPoolExecutor(max_workers=4, initializer=init_compositor, initargs=(path,)) as workers:
        list(workers.map(composite_frame, paths, chunksize=8))


def compose(spec, scene, scene_file, out, manifest, motion, scratch, overlay_dir=None, no_card=False):
    width, height, fps = manifest["pixelWidth"], manifest["pixelHeight"], manifest["fps"]
    count = manifest["frameCount"]
    trees = [ET.parse(out / f"frames/{i:04d}.svg").getroot() for i in range(count)]
    if no_card:
        for i, tree in enumerate(trees):
            for element in list(tree):
                if element.get("data-layer") == "card":
                    tree.remove(element)
            write_svg(tree, out / f"frames/{i:04d}.svg")
    # Rasterize moving layers alone; the static painting is decoded/resized once.
    jobs = []
    for i, tree in enumerate(trees):
        path = scratch / f"frame-{i}.svg"
        write_svg(isolated(tree, ["figure", "particles", "card"]), path)
        jobs.append({"input": str(path), "output": str(out / f"frames/{i:04d}.png"), "width": width})
    if scene.get("background", "").lower().endswith(".svg"):
        background_path = (scene_file.parent / scene["background"]).resolve()
        scene = {**scene, "background": str(scratch / "scene-background.png")}
        jobs.append({"input": str(background_path), "output": scene["background"], "width": width})
    moments = key_frames(manifest, spec)
    for j, (_, frame) in enumerate(moments):
        path = scratch / f"figure-{j}.svg"
        write_svg(isolated(trees[frame], "figure"), path)
        jobs.append({"input": str(path), "output": str(path.with_suffix(".png")), "width": width})
        path = scratch / f"moment-{j}.svg"
        write_svg(isolated(trees[frame], ["figure", "particles", "card"]), path)
        jobs.append({"input": str(path), "output": str(path.with_suffix(".png")), "width": width})
    card_frame = min(count - 1, int((manifest["cardHoldStart"] + manifest["cardHoldEnd"]) / 2 * fps))
    card_svg = scratch / "card.svg"
    write_svg(isolated(trees[card_frame], "card"), card_svg)
    jobs.append({"input": str(card_svg), "output": str(card_svg.with_suffix(".png")), "width": width})
    trail_pngs, trail_labels = [], []
    for index, action in enumerate(manifest["actions"]):
        selection = [i for i in range(0, count, 2) if action["start"] <= i / fps < action["end"]]
        root = ET.Element(f"{{{SVG}}}svg", {k: trees[0].attrib[k] for k in ["width", "height", "viewBox"]})
        ET.SubElement(root, f"{{{SVG}}}rect", {"width": root.get("width"), "height": root.get("height"),
                                               "fill": scene["canvas"].get("paper", "#F6F1E7")})
        for order, frame in enumerate(selection):
            group = ET.SubElement(root, f"{{{SVG}}}g", {"opacity": f"{0.05 + 0.45 * (order + 1) / max(1, len(selection)):.4f}"})
            for element in isolated(trees[frame], "figure"):
                if element.tag == f"{{{SVG}}}defs":
                    continue
                shape = copy.deepcopy(element)
                shape.attrib.pop("filter", None)
                group.append(shape)
        for name, stroke in [("head", "#7B628D"), ("leftHand", "#B57644"), ("rightHand", "#A79444"),
                             ("leftAnkle", "#477B85"), ("rightAnkle", "#67834F")]:
            coords = [next(actor for actor in motion[i]["actors"] if actor["id"] == action["actor"])["joints"][name] for i in selection]
            if coords:
                d = "M" + " L".join(f"{p['x']:.4f},{p['y']:.4f}" for p in coords)
                ET.SubElement(root, f"{{{SVG}}}path", {"d": d, "stroke": stroke, "stroke-width": "0.8", "fill": "none"})
        path = scratch / f"trail-{index}.svg"
        write_svg(root, path)
        jobs.append({"input": str(path), "output": str(path.with_suffix(".png")), "width": 800})
        trail_pngs.append(path.with_suffix(".png"))
        prefix = action['actor'] + "  " if len(scene["actors"]) > 1 else ""
        trail_labels.append(f"{prefix}{action['kind']}  {action['start']:.2f}–{action['end']:.2f} s")
    (scratch / "jobs.json").write_text(json.dumps(jobs))
    run(["node", ROOT / "tools/factory/rasterize.mjs", scratch / "jobs.json"])

    if overlay_dir is not None:
        overlay_dir.mkdir(parents=True, exist_ok=True)
        for path in overlay_dir.glob("*.png"):
            path.unlink()
        for i in range(count):
            shutil.copyfile(out / f"frames/{i:04d}.png", overlay_dir / f"{i:04d}.png")

    background = background_image(scene, scene_file, (width, height))
    composite_frames([out / f"frames/{i:04d}.png" for i in range(count)], background, scratch)

    sheets = out / "sheets"
    sheets.mkdir(exist_ok=True)
    contact_indices = [round((count - 1) * i / 11) for i in range(12)]
    contact = [Image.open(out / f"frames/{i:04d}.png").convert("RGB") for i in contact_indices]
    labelled_grid(contact, [f"{i / fps:.2f} s" for i in contact_indices], 4, sheets / "contact.png",
                  thumb=(440, round(440 * height / width)))
    if trail_pngs:
        labelled_grid([Image.open(path).convert("RGB") for path in trail_pngs], trail_labels, 2, sheets / "trail.png")
    else:
        Image.new("RGB", (800, 600), color(scene["canvas"].get("paper", "#F6F1E7"))).save(sheets / "trail.png")
    masks = [Image.open(scratch / f"figure-{j}.png").convert("RGBA") for j in range(4)]
    light = background_image(scene, scene_file, (width, height))
    dark = Image.new("RGB", (width, height), color(scene["canvas"].get("paperDark", "#1E1B24")))
    light_panels, dark_panels, silhouettes = [], [], []
    for index, mask in enumerate(masks):
        overlay = Image.open(scratch / f"moment-{index}.png").convert("RGBA")
        panel = light.copy(); panel.paste(overlay, (0, 0), overlay); light_panels.append(panel)
        panel = dark.copy(); panel.paste(overlay, (0, 0), overlay); dark_panels.append(panel)
        panel = Image.new("RGB", (width, height), "white"); panel.paste("black", (0, 0), mask.getchannel("A")); silhouettes.append(panel)
    labels = [f"{label}  {frame / fps:.2f} s" for label, frame in moments]
    labelled_grid(light_panels, labels, 2, sheets / "atsize-light.png")
    labelled_grid(dark_panels, labels, 2, sheets / "atsize-dark.png")
    labelled_grid(silhouettes, labels, 2, sheets / "silhouette.png")
    card = Image.open(scratch / "card.png").convert("RGBA")
    card_panel = light.copy(); card_panel.paste(card, (0, 0), card); card_panel.save(sheets / "card.png")
    contrast = ink_contrast(light, masks, spec.get("ink", {}).get("color", "#2B2622"))
    checks_file = out / "checks.json"
    checks = [c for c in json.loads(checks_file.read_text()) if c["name"] != "inkContrast"]
    if no_card:
        checks = [c for c in checks if c["name"] not in {"cardHold", "cardSize", "cardOnScreen"}]
    checks.append({"name": "inkContrast", "value": contrast, "limit": 3, "pass": contrast >= 3})
    checks_file.write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path); parser.add_argument("scene", type=Path); parser.add_argument("out", type=Path)
    parser.add_argument("--figures", type=Path, default=Path(os.environ.get("FIGURES_BIN", ROOT / ".build/release/figures")))
    parser.add_argument("--overlay-dir", type=Path, help="also save transparent moving layers here, outside the repo")
    parser.add_argument("--no-card", action="store_true", help="omit the card and its checks for an uncited stage")
    parser.add_argument("--frames-only", action="store_true", help="write frames, sheets and checks; skip individual clip encoders")
    args = parser.parse_args()
    try:
        ImageFont.truetype("DejaVuSans.ttf", 18)
    except OSError:
        parser.error("missing DejaVu Sans (DejaVuSans.ttf); install fonts-dejavu-core")
    for dependency in ["node", "ffmpeg"]:
        if not shutil.which(dependency):
            parser.error(f"missing {dependency}; see this script's prerequisites")
    if not args.figures.is_file():
        parser.error("build figures first: swift build -c release --product figures --static-swift-stdlib")
    start = time.monotonic()
    out, spec_file, scene_file = args.out.resolve(), args.spec.resolve(), args.scene.resolve()
    if out == ROOT or ROOT in out.parents:
        parser.error("render output must be outside the repository (CLAUDE.md)")
    overlay_dir = args.overlay_dir.resolve() if args.overlay_dir else None
    if overlay_dir is not None and (overlay_dir == ROOT or ROOT in overlay_dir.parents or
                                    overlay_dir == out or out in overlay_dir.parents or overlay_dir in out.parents):
        parser.error("overlay output must be outside the repository and the render output")
    out.mkdir(parents=True, exist_ok=True)
    run([args.figures.resolve(), "render", "--spec", spec_file, "--scene", scene_file, "--out", out])
    spec, scene = json.loads(spec_file.read_text()), json.loads(scene_file.read_text())
    manifest, motion = json.loads((out / "manifest.json").read_text()), json.loads((out / "motion.json").read_text())
    with tempfile.TemporaryDirectory(prefix="figure-review-", dir=out) as temporary:
        compose(spec, scene, scene_file, out, manifest, motion, Path(temporary), overlay_dir, args.no_card)
    if not args.frames_only:
        input_flags = ["ffmpeg", "-v", "error", "-y", "-threads", "4", "-framerate", manifest["fps"], "-i", out / "frames/%04d.png"]
        run(input_flags + ["-an", "-c:v", "libx264", "-threads", "4", "-preset", "ultrafast", "-crf", "20", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out / "clip.mp4"])
        preview_width = manifest["pixelWidth"] // (2 if scene.get("display", "ipad13") == "ipad13" else 3)
        run(input_flags + ["-an", "-vf", f"scale={preview_width}:-2", "-c:v", "libwebp_anim", "-threads", "4", "-quality", "75", "-compression_level", "0", "-loop", "0", out / "clip.webp"])
    checks = json.loads((out / "checks.json").read_text())
    failed = [c["name"] for c in checks if not c["pass"]]
    print(f"Rendered {manifest['frameCount']} frames and all review artifacts in {time.monotonic() - start:.2f} s; "
          + ("checks pass" if not failed else f"failed checks: {', '.join(failed)}"))

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
