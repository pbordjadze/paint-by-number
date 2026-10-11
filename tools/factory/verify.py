#!/usr/bin/env python3
"""Exercise SPEC.md's Done when list against the committed baseline and hero.

Build static figures and pbn first (swift build -c release --static-swift-stdlib).
    taskset -c 0-3 tools/factory/verify.py /tmp/figure-v0-verification
Runtime limits measure warm release binaries and the full review, excluding the build/tests.
It also checks provenance hashes, PNG dimensions, animation and the video codec. All logs and
renders stay outside the repo. Requires render.py's dependencies and ffprobe.
"""
import argparse
import hashlib
import json
import os
import subprocess
import time
from pathlib import Path


from output_paths import outside_repo

ROOT = Path(__file__).resolve().parents[2]


def timed(command, log=None):
    start = time.monotonic()
    subprocess.run([str(arg) for arg in command], cwd=ROOT, check=True, stdout=log, stderr=log)
    return time.monotonic() - start


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def protected_source_diff(root=ROOT):
    base = subprocess.check_output(["git", "merge-base", "HEAD", "origin/claude/vibe-factory"], cwd=root, text=True).strip()
    unchanged = subprocess.check_output(["git", "diff", base, "--", "Sources/PaintCore", "Sources/pbn", "Tests/PaintCoreTests"], cwd=root)
    return unchanged


def figures_binary(value=None):
    binary = Path(value or os.environ.get('FIGURES_BIN', ROOT / '.build/release/figures')).resolve()
    require(binary.is_file(), f'missing figures executable: {binary}; build figures first with '
            'swift build -c release --product figures (add --scratch-path for a custom build directory), '
            'then set FIGURES_BIN or --figures')
    return binary


def swift_test_command(scratch=None, *, skip_build=False, filter=None):
    command = ['swift', 'test']
    scratch = scratch or os.environ.get('SWIFT_SCRATCH_PATH')
    if scratch:
        command += ['--scratch-path', str(scratch)]
    if skip_build:
        command += ['--skip-build']
    if filter:
        command += ['--filter', filter]
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=Path)
    parser.add_argument('--figures', type=Path, help='host executable; defaults to FIGURES_BIN or .build/release/figures')
    parser.add_argument('--swift-scratch-path', type=Path, default=os.environ.get('SWIFT_SCRATCH_PATH'),
                        help='Swift build/test directory; defaults to SWIFT_SCRATCH_PATH')
    args = parser.parse_args()
    from PIL import Image
    try:
        binary = figures_binary(args.figures)
        out = outside_repo(args.out)
    except (ValueError, RuntimeError) as error:
        parser.error(str(error))
    os.environ['FIGURES_BIN'] = str(binary)
    if args.swift_scratch_path:
        os.environ['SWIFT_SCRATCH_PATH'] = str(args.swift_scratch_path)
    out.mkdir(parents=True, exist_ok=True)
    spec, scene = ROOT / "factory/specs/baseline.json", ROOT / "factory/scenes/hero.json"
    # Deliberately different path depths: image references must not depend on --out.
    runs = [out / "first", out / "nested/second"]
    times = [timed([binary, "render", "--spec", spec, "--scene", scene, "--out", run]) for run in runs]
    require(all(elapsed < 5 for elapsed in times), f"engine exceeded 5 s: {times}")
    names = ["manifest.json", "motion.json", "checks.json"] + [str(path.relative_to(runs[0])) for path in sorted((runs[0] / "frames").glob("*.svg"))]
    for name in names:
        require((runs[0] / name).read_bytes() == (runs[1] / name).read_bytes(), f"nondeterministic {name}")
    manifest = json.loads((runs[0] / "manifest.json").read_text())
    for field, path in [("specSHA256", spec), ("sceneSHA256", scene)]:
        require(manifest[field] == hashlib.sha256(path.read_bytes()).hexdigest(), f"wrong {field}")
    review = out / "review"
    elapsed = timed([ROOT / "tools/factory/render.py", spec, scene, review, "--figures", binary])
    require(elapsed < 60, f"review exceeded 60 s: {elapsed}")
    for frame in range(manifest["frameCount"]):
        with Image.open(review / f"frames/{frame:04d}.png") as image:
            require(image.size == (manifest["pixelWidth"], manifest["pixelHeight"]), "incorrect display pixel size")
    for name in ["contact", "trail", "atsize-light", "atsize-dark", "silhouette", "card"]:
        with Image.open(review / f"sheets/{name}.png") as image:
            image.verify()
    with Image.open(review / "clip.webp") as image:
        require(image.is_animated and image.n_frames > 1, "WebP must be animated")
    video = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,pix_fmt", "-of", "json", str(review / "clip.mp4")]))
    require(video["streams"][0]["codec_name"] == "h264" and video["streams"][0]["pix_fmt"] == "yuv420p", "wrong MP4 encoding")
    checks = json.loads((review / "checks.json").read_text())
    require(all(check["pass"] for check in checks), f"checks failed: {checks}")
    with (out / "swift-test.log").open("w") as log:
        timed(swift_test_command(args.swift_scratch_path), log)
    with (out / "python-test.log").open("w") as log:
        timed(["python3", "-m", "unittest", "discover", "-s", "tools/factory", "-p", "test_*.py"], log)
    unchanged = protected_source_diff()
    require(not unchanged, "PaintCore/pbn changed")
    print(f"Done when passed: engine {max(times):.2f} s; review {elapsed:.2f} s; {manifest['frameCount']} identical frames; "
          "all checks, Swift/Python tests, and protected-source checks passed")


if __name__ == "__main__":
    main()
