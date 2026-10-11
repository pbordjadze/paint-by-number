#!/usr/bin/env python3
"""Render one photo's pipeline, with walking workers, arrival-time wipes and citations.

    tools/factory/making_of.py <photo.ppm> /root/factory-out/making-of
    tools/factory/making_of.py <photo.ppm> /root/factory-out/book --edges contours.pgm

Build first with Swift 6.2: swift build -c release (no Docker needed).
Requires render.py's dependencies: Pillow, DejaVu Sans, node with tools/node_modules,
and ffmpeg. PBN_BIN/FIGURES_BIN or --pbn/--figures select host executables.
--edges optionally supplies a real edge map; without one pbn skips the line-art stage.
No models or synthetic edges are substituted. The spec is decoded from its defaults.

Output: snapshots/, reveal/, scenes/, stages/<pair>/ (render.py's original paper
reviews and checks), frames/ (the final composite), contact.png, manifest.json and
making-of.mp4. Checks describe the paper reviews; photo/ink contrast is left for the
Lamp's visual review. Render output stays outside the repository. Existing output
must be empty, so stale stages/frames cannot enter a second run.

The photo keeps snapshot pixel coordinates, translated onto the default 1100-wide
paper, downscaled only if needed to leave a figure-height margin. Portrait paper
grows to fit. A blank required FigureScene card is suppressed with --no-card for
uncited stages; it never becomes a citation in the show. Empty fields get an idle
worker. Card fades/holds, walking pace, pose sampling and tail use spec defaults.
The wipe follows the same eased arc-length travel (including the partial final
stride) as Rig.swift, sampled at the worker's recorded poseTime. At completion we
show the exact next snapshot, including subthreshold differences, so cuts join.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

import render
from reveal_sheet import STAGES, path_points, wipe

ROOT = render.ROOT
CITATIONS = ROOT / "factory/scenes/making-of/citations.json"


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def outside_repo(path):
    path = path.resolve()
    if path == ROOT or ROOT in path.parents:
        raise ValueError("render output must be outside the repository (CLAUDE.md)")
    return path


def load_citations(path=CITATIONS, source=ROOT / "ACKNOWLEDGEMENTS.md"):
    citations = json.loads(path.read_text())
    if set(citations) != {Path(name).stem for name in STAGES}:
        raise ValueError("citation map must cover exactly the snapshot stages (null means no card)")
    lines = source.read_text().splitlines()
    for stage, citation in citations.items():
        if citation is None:
            continue
        if set(citation) != {"authors", "year", "title", "line"}:
            raise ValueError(f"{stage}: expected authors, year, title and line")
        number = citation["line"]
        exact = f'{citation["authors"]}, "{citation["title"]}", {citation["year"]}'
        if not isinstance(number, int) or not 1 <= number <= len(lines) or lines[number - 1] != exact:
            raise ValueError(f"{stage}: citation does not exactly match ACKNOWLEDGEMENTS.md:{number}")
    return citations


def layout(width, height):
    scale = min(1, 1000 / width)
    return {"scale": scale, "x": (1100 - width * scale) / 2, "y": 100,
            "width": width * scale, "height": height * scale,
            "canvasWidth": 1100, "canvasHeight": max(825, height * scale + 300)}


def make_scene(metadata, stage, citation):
    box = layout(metadata["width"], metadata["height"])
    points = path_points(metadata["path"])
    if points:
        points = [(box["x"] + x * box["scale"], box["y"] + y * box["scale"]) for x, y in points]
    else:
        # The engine requires a nonzero location path even for idle-only actors.
        points = [(550, 100 + box["height"] / 2), (551, 100 + box["height"] / 2)]
    path = " ".join(f"{'M' if i == 0 else 'L'} {x:.2f} {y:.2f}" for i, (x, y) in enumerate(points))
    kind = "ink" if stage == "line-art" else "sweep"
    action = {"do": kind, "path": "reveal", "to": 1}
    if kind == "ink":
        action["from"] = 0
    # This adapter is never shown for a null citation (--no-card strips its shapes).
    card = {key: citation[key] for key in ("authors", "year", "title")} if citation else {
        "authors": "", "year": 0, "title": ""}
    card["at"] = 0
    words = len((card["authors"] + " " + str(card["year"]) + " " + card["title"]).split())
    hold = max(2, 0.5 + 0.2 * words) + 2 * 0.3 if citation else 0.3
    timeline = ([action] if metadata["path"] else []) + [{"do": "idle", "duration": hold}]
    return {"version": 2, "seed": 1,
            "canvas": {"width": box["canvasWidth"], "height": box["canvasHeight"]},
            "paths": {"reveal": path}, "actors": [{"id": "worker", "holds": "brush" if kind == "ink" else "broom",
                "at": {"path": "reveal", "t": 0}, "timeline": timeline}], "card": card}


def path_length(path):
    points = path_points(path)
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:]))


def progress_at(pose_time, manifest, scene):
    action = next((a for a in manifest["actions"] if a["kind"] in {"ink", "sweep"}), None)
    if action is None:
        return 1
    elapsed, duration = pose_time - action["start"], action["end"] - action["start"]
    if elapsed <= 0:
        return 0
    if elapsed >= duration:
        return 1
    distance = path_length(scene["paths"]["reveal"])
    step = 0.26 * manifest["normalizationScale"] * scene.get("figureHeight", 50)
    gait_distance = math.ceil(distance / step) * step
    ramp = min(0.5, gait_distance / (step * 2))
    speed = gait_distance / max(duration - ramp, 1e-12)
    def integral(u):
        return u ** 3 - 0.5 * u ** 4
    if ramp == 0:
        travelled = min(gait_distance, elapsed * speed)
    elif elapsed < ramp:
        travelled = speed * ramp * integral(elapsed / ramp)
    elif elapsed > duration - ramp:
        travelled = gait_distance - speed * ramp * integral((duration - elapsed) / ramp)
    else:
        travelled = speed * (elapsed - ramp * 0.5)
    last = max(0, gait_distance - step)
    if travelled > last:
        travelled = last + (distance - last) * min(1, max(0, (travelled - last) / step))
    return min(1, max(0, travelled / distance))


def compose_picture(before, after, field, progress, box, size):
    # Match the engine's default paper, without changing the spec's ink or card style.
    panel = Image.new("RGB", size, "#F6F1E7")
    picture = after.convert("RGB") if progress >= 1 else wipe(before, after, field, progress)
    sx, sy = size[0] / box["canvasWidth"], size[1] / box["canvasHeight"]
    origin = (round(box["x"] * sx), round(box["y"] * sy))
    target = (max(1, round(box["width"] * sx)), max(1, round(box["height"] * sy)))
    panel.paste(picture.resize(target, Image.Resampling.LANCZOS), origin)
    return panel


def render_pair(first, second, field_file, metadata, scene_file, citation, out, frames, figures, offset):
    scene = json.loads(scene_file.read_text())
    # Export alpha before render.py composites its ordinary paper review artifacts.
    with tempfile.TemporaryDirectory(prefix="overlays-", dir=out.parent) as temporary:
        overlays = Path(temporary)
        command = [sys.executable, ROOT / "tools/factory/render.py", out.parent.parent / "spec.json",
                   scene_file, out, "--figures", figures, "--overlay-dir", overlays, "--frames-only"]
        if citation is None:
            command.append("--no-card")
        render.run(command)
        manifest = json.loads((out / "manifest.json").read_text())
        motion = json.loads((out / "motion.json").read_text())
        box = layout(metadata["width"], metadata["height"])
        size = (manifest["pixelWidth"], manifest["pixelHeight"])
        hashes, progress = [], []
        with Image.open(first) as before, Image.open(second) as after, Image.open(field_file) as field:
            if before.size != (metadata["width"], metadata["height"]) or after.size != before.size or field.size != before.size:
                raise ValueError("snapshot/reveal dimensions disagree")
            for index, pose in enumerate(motion):
                time = progress_at(pose["actors"][0]["poseTime"], manifest, scene)
                panel = compose_picture(before, after, field, time, box, size)
                with Image.open(overlays / f"{index:04d}.png") as overlay:
                    panel.paste(overlay, (0, 0), overlay)
                path = frames / f"{offset + index:06d}.png"
                panel.save(path, compress_level=1)
                hashes.append(hashlib.sha256(path.read_bytes()).hexdigest())
                progress.append(time)
    return manifest, hashes, progress


def making_of(photo, out, pbn, figures, edges=None):
    out = outside_repo(out)
    if out.exists() and any(out.iterdir()):
        raise ValueError(f"output directory must be empty: {out}")
    # Fail before running the expensive pipeline if the reviewable citation map drifts.
    citations = load_citations()
    for executable in (pbn, figures):
        if not executable.is_file():
            raise ValueError(f"missing executable {executable}; build first with swift build -c release")
    out.mkdir(parents=True, exist_ok=True)
    snapshots, fields = out / "snapshots", out / "reveal"
    generate = [pbn, "generate", photo, out / "painting", "--snapshots", snapshots]
    if edges:
        generate += ["--line-style", "coloringBook", "--edges", edges]
    render.run(generate)
    render.run([figures, "reveal", snapshots, fields])
    write_json(out / "spec.json", {"version": 2})  # All omitted fields are the engine's defaults.
    scenes, stages, frames = out / "scenes", out / "stages", out / "frames"
    for directory in (scenes, stages, frames):
        directory.mkdir()
    present = [snapshots / name for name in STAGES if (snapshots / name).is_file()]
    records, review_images, review_labels = [], [], []
    count = 0
    for first, second in zip(present, present[1:]):
        name = first.stem + "-" + second.stem
        metadata = json.loads((fields / (name + ".json")).read_text())
        citation = citations[second.stem]
        scene_file = scenes / (name + ".json")
        write_json(scene_file, make_scene(metadata, second.stem, citation))
        print(f"Making {name}", flush=True)
        manifest, hashes, progress = render_pair(first, second, fields / (name + ".pgm"), metadata,
                                                scene_file, citation, stages / name, frames, figures, count)
        if records and (manifest["fps"], manifest["pixelWidth"], manifest["pixelHeight"]) != (
                records[0]["fps"], records[0]["pixelWidth"], records[0]["pixelHeight"]):
            raise ValueError("stage video dimensions or frame rates differ")
        # Include the default card's held pose and the exact completed snapshot.
        walk = next((a for a in manifest["actions"] if a["kind"] in {"ink", "sweep"}), None)
        end = min(manifest["frameCount"] - 1, math.ceil(walk["end"] * manifest["fps"])) if walk else 0
        card_frame = min(manifest["frameCount"] - 1,
                         round((manifest["cardHoldStart"] + manifest["cardHoldEnd"]) / 2 * manifest["fps"]))
        selected = [0, card_frame if citation else end // 3, end // 2, manifest["frameCount"] - 1]
        for index in selected:
            with Image.open(frames / f"{count + index:06d}.png") as image:
                review_images.append(image.copy())
            review_labels.append(f"{second.stem}  {index / manifest['fps']:.2f} s  wipe {progress[index]:.0%}")
        records.append({"pair": name, "stage": second.stem, "citation": citation,
                        "startFrame": count, "frameCount": manifest["frameCount"], "fps": manifest["fps"],
                        "pixelWidth": manifest["pixelWidth"], "pixelHeight": manifest["pixelHeight"],
                        "action": "ink" if second.stem == "line-art" else "sweep",
                        "frameSHA256": hashes, "wipeProgress": progress,
                        "checks": str(Path("stages") / name / "checks.json")})
        count += manifest["frameCount"]
    render.labelled_grid(review_images, review_labels, 4, out / "contact.png",
                         thumb=(440, round(440 * manifest["pixelHeight"] / manifest["pixelWidth"])))
    render.run(["ffmpeg", "-v", "error", "-y", "-threads", "4", "-framerate", manifest["fps"],
                "-i", frames / "%06d.png", "-frames:v", count, "-an", "-c:v", "libx264", "-threads", "4",
                "-preset", "ultrafast", "-crf", "20", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart", out / "making-of.mp4"])
    write_json(out / "manifest.json", {"version": 1, "frameCount": count, "fps": manifest["fps"],
               "pixelWidth": manifest["pixelWidth"], "pixelHeight": manifest["pixelHeight"],
               "checkBackground": "default paper (stages/*/sheets); composite photo contrast is visual review",
               "stages": records})
    print(f"{len(records)} stages, {count} frames; {out / 'making-of.mp4'}", flush=True)
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photo", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--pbn", type=Path, default=Path(os.environ.get("PBN_BIN", ROOT / ".build/release/pbn")))
    parser.add_argument("--figures", type=Path, default=Path(os.environ.get("FIGURES_BIN", ROOT / ".build/release/figures")))
    parser.add_argument("--edges", type=Path, help="optional supplied PGM edge map, enabling the line-art snapshot")
    args = parser.parse_args()
    try:
        for dependency in ("node", "ffmpeg"):
            if not shutil.which(dependency):
                raise ValueError(f"missing {dependency}; see --help")
        making_of(args.photo.resolve(), args.out, args.pbn.resolve(), args.figures.resolve(),
                  args.edges.resolve() if args.edges else None)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
