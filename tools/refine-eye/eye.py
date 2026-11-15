#!/usr/bin/env python3
"""What run_eye.sh recorded, measured: Refine's fades and stills compared between two builds
(painting-company row 338's review). Needs ffmpeg; no Python packages.

  eye.py marks <eye dir> <crop w:h:x:y> [name=crop ...]
      For each `eye: <step> <epoch>` line of <eye dir>/test.log, the screen's change in the 3.5 s
      after it, inside each crop (pixels of the recording; the first is called canvas), as runs
      of changing frames at 60 fps: `start..end ms (frames, peak)`. A fade is a run of many
      frames with a low peak, a pop one or two frames with a high one. An XCUITest action lands
      0.5 to 1.6 s after its marker, so look for the run, not for 0 ms. Also writes
      <eye dir>/sheets/<step>.png, 16 frames 50 ms apart of the first crop from the marker
      (SHEET_AT=<seconds> starts them later), to look at with an image viewer.
  eye.py stills <shots dir> <tag A> <tag B>
      Each scenario's still of build A against build B: the mean and largest difference of
      their pixels (0 0 is identical), and diff-<scenario>.png, white where they differ.

On an iPad Pro 13-inch (2064 × 2752 pixels, upright) with `create-refine`, the canvas is
1672:2414:392:172 and the tiny badge 266:60:1772:196; `eye-frame` lines in test.log give other
elements' frames in points (double them).

Limits: `stills` compares whole screens, status bar included, so two runs either side of midnight
differ there; a tag that is another's prefix ("main", "main-s") pairs the other's files too; on a
loaded Mac the simulator loses taps, so compare only stills whose `eye-state` lines in test.log match.
"""
import os, re, subprocess, sys

BEFORE, AFTER = 0.2, 3.5
FLOOR = 0.15  # a frame's mean difference below this is the codec's noise


def ffmpeg_lines(*args):
    return subprocess.run(["ffmpeg", "-v", "error", *args], capture_output=True, text=True).stdout


def diffs(video, at, crop):
    vf = f"fps=60,crop={crop},tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-"
    out = ffmpeg_lines("-ss", f"{max(0, at - BEFORE):.3f}", "-t", f"{BEFORE + AFTER:.3f}", "-i", video, "-vf", vf, "-f", "null", "-")
    return [float(x) for x in re.findall(r"YAVG=([0-9.]+)", out)]


def runs(d):
    """Runs of changing frames; a gap of up to two still frames joins two."""
    found, cur = [], None
    for i, v in enumerate(d):
        if v <= FLOOR:
            continue
        if cur and i - cur[1] <= 3:
            cur[1], cur[2], cur[3] = i, cur[2] + 1, max(cur[3], v)
        else:
            cur = [i, i, 1, v]
            found.append(cur)
    return found


def marks(eye_dir, crops):
    video = os.path.join(eye_dir, "screen.mp4")
    start = float(open(os.path.join(eye_dir, "start")).read())
    log = open(os.path.join(eye_dir, "test.log"), errors="replace").read()
    sheets = os.path.join(eye_dir, "sheets")
    os.makedirs(sheets, exist_ok=True)
    seen, steps = set(), []
    for m in re.finditer(r"eye: (\S+) ([0-9.]+)", log):
        if m.group(1) not in seen:  # xcodebuild echoes a test's output twice
            seen.add(m.group(1))
            steps.append((m.group(1), float(m.group(2))))
    ms = lambda i: (i / 60 - BEFORE) * 1000
    for step, epoch in steps:
        at = epoch - start
        print(f"{step:18s} t={at:7.2f}s")
        for name, crop in crops.items():
            found = runs(diffs(video, at, crop))
            print(f"    {name}: " + (", ".join(f"{ms(a):.0f}..{ms(b):.0f} ms ({n}f, pk {p:.1f})" for a, b, n, p in found) or "none"))
        first = next(iter(crops.values()))
        ffmpeg_lines("-y", "-ss", f"{max(0, at + float(os.environ.get('SHEET_AT', '0'))):.3f}", "-t", "0.8", "-i", video,
                     "-vf", f"fps=20,crop={first},scale=480:-2,tile=4x4", "-frames:v", "1", os.path.join(sheets, f"{step}.png"))


def stills(shots, a, b):
    names = sorted(f[len(a) + 1:-4] for f in os.listdir(shots) if f.startswith(a + "-") and f.endswith(".png"))
    for scenario in names:
        pa, pb = (os.path.join(shots, f"{t}-{scenario}.png") for t in (a, b))
        if not os.path.exists(pb):
            print(f"{scenario}: no {b} still")
            continue
        out = ffmpeg_lines("-i", pa, "-i", pb, "-filter_complex",
                           "blend=all_mode=difference,format=gray,signalstats,metadata=print:file=-", "-f", "null", "-")
        mean = re.search(r"YAVG=([0-9.]+)", out)
        top = re.search(r"YMAX=([0-9]+)", out)
        print(f"{scenario}: mean {mean.group(1) if mean else '?'}, largest {top.group(1) if top else '?'}")
        ffmpeg_lines("-y", "-i", pa, "-i", pb, "-filter_complex",
                     "blend=all_mode=difference,format=gray,lut=y='if(gt(val,10),255,0)'", "-frames:v", "1",
                     os.path.join(shots, f"diff-{scenario}.png"))


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "marks":
        crops = {"canvas": sys.argv[3]}
        crops.update(arg.split("=", 1) for arg in sys.argv[4:])
        marks(sys.argv[2], crops)
    elif len(sys.argv) == 5 and sys.argv[1] == "stills":
        stills(*sys.argv[2:])
    else:
        sys.exit(__doc__)
