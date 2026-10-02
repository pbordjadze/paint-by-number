# Line-art research (zen mode)

Exploration only (the spec is `docs/overnight/lineart.md`). Python scripts that turn a picture
into line art at `pbn`'s working resolution, four families competing on one shared cleanup.
Nothing here touches `Sources/`, `App/` or the regression baselines. Findings: `results.md`
(the overall verdict and stage 1), `results_color.md` (stage 2, color inside the lines) and
`results_layers.md` (round 3, layered cells: one set of cells, lines that draw by zoom).

| File | What |
| --- | --- |
| `lines_common.py` | picture IO, OKLab, the importance proxy (spectral-residual saliency + center prior) |
| `lines_flowdog.py` | A. coherent line drawing (Kang, Lee, Chui 2007): ETF + flow-guided DoG |
| `lines_xdog.py` | B. XDoG (Winnemoeller et al. 2012), thresholded for ink |
| `lines_boundaries.py` | C. pbn's own region boundaries where the photo's contrast is strong |
| `lines_learned.py` | D. controlnet_aux detectors on CPU at working resolution |
| `strokes.py` | the shared cleanup: ridge thinning + hysteresis, tracing, spurs, gaps, fragments, smoothing, weights, walls, ink rendering |
| `run_lines.py` | the driver: every family x detail level for one picture |
| `lines_sheet.py` | contact sheets of the options, for looking |

| `color_common.py`, `color_split.py`, `color_segment.py` | stage 2: C1 (pbn's regions split by the lines, the method kept) and C2 (segmentation inside each enclosed area) |
| `panels.py`, `run_color.py`, `color_report.py`, `panel_sheet.py` | stage 2: the painting plan and finished panels, the driver, the numbers, sheets |
| `color_test_picks.json` | which options stage 2 ran per test picture |
| `narrowing/` | the blind legibility check (key, answers) and the options shown to the owner |
| `layers.py` | round 3: layered cells (top / mid / inner / color lines, C1 cells, numbers with a legible zoom), SVG, renders, manifest |
| `subject.py`, `eyes.py` | round 3: the subject silhouette (BiRefNet, MIT) and eye boxes (OWLv2, Apache-2.0; YuNet landmarks for faces), stand-ins for Vision |
| `svg_render.mjs`, `svg_check.cjs` | round 3: batch SVG rasterizing with resvg (renders), opening the SVGs in Chromium (check) |
| `layers_notes.json` | round 3: the one-sentence notes per picture and variant that go into the manifest |

Stage 2 reads each option's `walls.png` and `ink.png`; see `results_color.md` § Reproducing.

## Setup from scratch

Python 3.11, CPU only (4 cores, 15 GB were plenty; peak ~1.7 GB per learned model).

```sh
python3.11 -m venv venv
venv/bin/pip install numpy scipy pillow opencv-python-headless scikit-image einops timm \
    huggingface_hub onnxruntime
venv/bin/pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
venv/bin/pip install controlnet_aux==0.0.10
```

Versions used: numpy 2.4.6, scipy 1.17.1, pillow 12.3.0, opencv-python-headless 5.0.0.93,
scikit-image 0.26.0, torch 2.14.1+cpu, torchvision 0.29.1+cpu, controlnet_aux 0.0.10,
timm 1.0.30, einops 0.8.2, huggingface_hub 2.1.1.

Weights (272 MB) download on first use into the Hugging Face cache; to keep them in one
place set `HF_HOME` (the runs here used `HF_HOME=$S/lineart/hf`) or fetch them up front:

```sh
HF_HOME=$S/lineart/hf venv/bin/python -c "
from huggingface_hub import hf_hub_download
for f in ['sk_model.pth', 'sk_model2.pth', 'table5_pidinet.pth', 'ControlNetHED.pth', 'netG.pth']:
    hf_hub_download('lllyasviel/Annotators', f)
hf_hub_download('fal-ai/teed', '5_model.pth')
hf_hub_download('opencv/face_detection_yunet', 'face_detection_yunet_2023mar.onnx')"
```

YuNet (MIT) is the face detector of the importance proxy; without it the proxy falls back
to saliency and the center prior.

## Inputs

A picture directory is what `pbn generate <pic>.ppm <dir> --auto --length relaxed` writes
(the release `pbn`, `tools/swift.sh build -c release --static-swift-stdlib`): the scripts
read `working.ppm` (the photo at working resolution, 1152 px on the long side for most) and
`raster.ppm` (pbn's color segmentation, same size), so every layer lines up pixel for pixel.

## Running

One picture, every family and detail level (27 options):

```sh
cd research/lineart
HF_HOME=$S/lineart/hf $S/venv/bin/python run_lines.py <pic-dir> --out $S/lineart/out/<pic>
```

Options: `--families flowdog,xdog,boundaries,learned_lineart_fine,...` (default all),
`--details sparse,medium,rich`, `--raw-only` (just compute and cache the detectors' maps),
`--force-raw` (recompute cached maps). Raw maps are cached in `<out>/_cache/<family>.npy`
with their runtime and peak memory, so re-tuning the cleanup is fast.

The `<family>` names: `flowdog`, `xdog`, `boundaries`, `learned_lineart_fine`,
`learned_lineart_coarse`, `learned_pidinet`, `learned_hed`, `learned_teed`,
`learned_lineart_anime`; `<detail>`: `sparse`, `medium`, `rich`.

Per option `<out>/<family>-<detail>/`: `raw.png`, `strokes.json`, `walls.png` (the stage-2
contract: 8-connected 1 px centerlines, uint8 0/255, working size), `ink.png`,
`ink_tapered.png`, `ink_colored.png`, `ink_uniform.png` (RGBA, 2x), `lines_alone.png`
(+ `_tapered`, `_colored`: ink on paper `#F4EFE6`, 2x) and `metrics.json`. Per picture:
`importance.png` (+ `importance.json`, the faces found), `strong_edges.png` (the edges
recall is measured against) and `summary.json`.

All ten dev pictures, three at a time (~9 min on 4 shared cores once the raw maps are
cached; computing the nine raw maps adds ~1-2 min per picture the first time):

```sh
printf "%s\n" parrots kodim04 kodim23 great-wave lighthouse barn espresso hibiscus regatta kodim03 |
  xargs -P 3 -I{} sh -c "HF_HOME=$S/lineart/hf $S/venv/bin/python run_lines.py \
      $S/lineart/inputs/{} --out $S/lineart/out/{} > $S/lineart/out/{}.log 2>&1"
```

Looking: `python lines_sheet.py $S/lineart/out/<pic> --detail medium --photo <pic-dir>
--save sheet.png` (or `--options a,b,c`, `--file lines_alone_tapered.png`).

Determinism: `python lines_learned.py <pic-dir> <model> --check-determinism` runs a model
twice and compares; rerunning `run_lines.py` into a second directory gives byte-identical
files (checked, see results.md).

## Runtimes (4 shared cores, 1152 x 768)

Raw maps: flow DoG 6-8 s, XDoG 0.2 s, boundaries 0.3-0.8 s; learned (inference, plus ~3 s to
load each model): TEED 0.5-2 s, HED 2-6 s, lineart anime 1-5 s, lineart coarse/fine 3.4-11 s,
PiDiNet 5-19 s. Cleanup 0.5-2 s and rendering the four ink variants 0.8-3 s per option. The
spread comes from another agent's batch sharing the machine; see results.md.

## The test set (nine pictures of the new library)

The pictures are the shipped library JPEGs on `claude/library-v2`
(`App/PaintByNumber/Resources/Samples/<id>.jpg`): great-wave, milkmaid, wheat-field,
cezanne-apples, delicate-arch, red-fox, lassen-lupine, santa-fe-freight, hawksbill-turtle.
Each becomes a picture directory the same way as the dev set:

```sh
python3 -c "from PIL import Image; Image.open('<id>.jpg').convert('RGB').save('$S/lineart/inputs/<id>.ppm')"
.build/release/pbn generate $S/lineart/inputs/<id>.ppm $S/lineart/inputs/<id> --auto --length relaxed
HF_HOME=$S/lineart/hf $S/venv/bin/python run_lines.py $S/lineart/inputs/<id> --out $S/lineart/out/<id>
python run_color.py --batch $S/lineart/out --picks color_test_picks.json --flat --jobs 2
```

About 5-7 minutes per picture for stage 1 (the nine models) and 1-2 minutes for stage 2 on the
4 shared cores here.

## The blind legibility check

`narrowing/legibility_selection.json` lists the 36 drawings judged (four per test picture),
`legibility_key.json` maps the anonymous file names back to them, `legibility_answers.json` is
what a fresh agent said when shown only the "lines alone" panels (subject, confidence, whether it
reads as a drawing). Rebuild the anonymous set by shuffling the selection with
`random.Random(7)` and saving each option's `lines_alone.png` at 1100 px as `d01.jpg`...

## Layered cells (round 3)

`layers.py` builds, per picture, five variants of one model: cells bounded by lines, every line
on a cell boundary, each line in a layer (`top`, `mid`, `inner`, `color`) that sets how strongly
it draws at a zoom. It reads stage 1's cached raw maps (`$S/lineart/out/<pic>/_cache/learned_hed.npy`,
`learned_teed.npy`) and `importance.png` / `importance.json`, and pbn's picture directory.

Extra setup (the round-1 venv plus):

```sh
venv/bin/pip install "transformers>=4.45"        # 5.18.0 used; it pins huggingface_hub to 1.33
HF_HOME=$S/lineart/hf venv/bin/python -c "
from huggingface_hub import hf_hub_download, snapshot_download
hf_hub_download('onnx-community/BiRefNet-ONNX', 'onnx/model.onnx')     # 973 MB, MIT
snapshot_download('google/owlv2-base-patch16-ensemble')                # Apache-2.0"
```

Run (the subject mask, ~50 s, and the eye search, ~1-3 min, are cached per picture as
`_subject.png` / `_eyes.json`; then ~45 s per variant):

```sh
cd research/lineart
S=$S HF_HOME=$S/lineart/hf $S/venv/bin/python layers.py santa-fe-freight hawksbill-turtle red-fox --jobs 2
S=$S $S/venv/bin/python layers.py --manifest          # writes and validates $S/lineart/layers/manifest.json
NODE_PATH=/opt/node22/lib/node_modules node svg_check.cjs /tmp/shots $S/lineart/layers/*/recommended/lines.svg
```

Options: `--variants recommended,no-closure,hed-layers,merged-color,joined`; `LAYERS_DEBUG=1` also
writes `$S/lineart/layers/_look/<pic>-<variant>-dbg{1,2,4}.png`, every layer in its own colour
(top black, mid blue, inner green, color orange). Renders need node 22 with `@resvg/resvg-js`
in `$S/node` (as stage 2) and Source Serif 4 in `$S/fonts`. Outputs and the manifest format:
`results_layers.md`.
