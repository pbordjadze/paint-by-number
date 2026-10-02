# Line-art research (zen mode): stage 1, the drawing

Exploration only (the spec is `docs/overnight/lineart.md`). Python scripts that turn a picture
into line art at `pbn`'s working resolution, four families competing on one shared cleanup.
Nothing here touches `Sources/`, `App/` or the regression baselines. Findings: `results.md`.

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

Stage 2 (`color_*.py`, `panels.py`, `run_color.py`) reads each option's `walls.png` and
`ink.png`.

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
hf_hub_download('fal-ai/teed', '5_model.pth')"
```

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

Per option `<out>/<family>-<detail>/`: `raw.png`, `strokes.json`, `walls.png` (the stage-2
contract: 8-connected 1 px centerlines, uint8 0/255, working size), `ink.png`,
`ink_tapered.png`, `ink_colored.png`, `ink_uniform.png` (RGBA, 2x), `lines_alone.png`
(+ `_tapered`, `_colored`: ink on paper `#F4EFE6`, 2x) and `metrics.json`. Per picture:
`importance.png`, `strong_edges.png` (the edges recall is measured against) and
`summary.json`.

All ten dev pictures, three at a time (~4 min after the raw maps are cached; the detectors
add ~1 min per picture the first time):

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

## Runtimes (this machine, 4 cores, 1152 x 768)

Raw maps: flow DoG ~6 s, XDoG ~0.4 s, boundaries ~0.5 s; learned (inference only, plus ~3 s
to load each model): TEED ~0.5 s, HED ~2.3 s, lineart anime ~2.6 s, lineart coarse/fine
~3.7-6.6 s, PiDiNet ~8 s. Cleanup ~0.5-1 s and rendering of the four ink variants ~1-2 s per
option.
