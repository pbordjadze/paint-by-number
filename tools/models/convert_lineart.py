#!/usr/bin/env python3
"""Converts the Informative Drawings line-drawing generator to the app's Core ML model, reproducibly.

    python tools/models/convert_lineart.py [--weights sk_model.pth] [--out DIR]
    python tools/models/convert_lineart.py --map <in.ppm> <out.pgm> [--compare <app.pgm>]

Writes App/PaintByNumber/Resources/Models/LineArt.mlpackage (what `EdgeDetector.lineDrawing`
runs) and the simulator test's reference map App/PaintByNumberTests/LineArtFixture.pgm, computed
with PyTorch from the committed input App/PaintByNumberTests/HEDFixture.ppm (the same photo crop
the HED fixture uses).

--map writes the 8-bit line map of an image already at its map size (≤ 1152 px) as `pbn generate
--lines` reads it, the levels the app computes; --compare also reports how far an app-made map is
from it.

Source. `sk_model.pth` from the Hugging Face repository lllyasviel/Annotators, 17,173,511 bytes,
sha256 SOURCE_SHA256 below (checked before anything else; a different file stops the script). It
is the "contour style" generator of Caroline Chan, Frédo Durand and Phillip Isola, "Learning to
generate line drawings that convey geometry and semantics" (CVPR 2022), the network ControlNet's
lineart annotator runs: ControlNet's `annotator/lineart/__init__.py` opens with "From
https://github.com/carolineec/informative-drawings — MIT License", and that repository's LICENSE
is the MIT License (Copyright (c) 2022 Caroline Chan). The ControlNet repository itself is
Apache-2.0. The Hugging Face model card only says `license: other`.

What the model computes. Input `image`: float32 [1, 3, H, W], RGB in 0...1, H and W multiples of
4 in 4...1152. The caller reflect-pads the photo at the bottom and right to the multiple of 4 and
crops the output back. Output `lines`: float32 [1, 1, H, W], the ink probability: one minus the
generator's sigmoid (which is paper: the generator draws black lines on white), so a line is high
like an edge probability and `EdgeMap.combined` can lay it over the HED map. The app runs it at a
long side of 768 (the generator was trained on smaller crops; at 768 its lines are a touch
heavier and cleaner than at 1152, and it is four times faster) and resamples the drawing up to the
HED map's size.

Precision. The source weights are float32; they are stored as float16 (`constexpr_cast` to float32
when Core ML loads the model), which halves the package to 8.6 MB, and the program computes in
float32 (`compute_precision=FLOAT32`). The reference map is computed with the same float16-rounded
weights in float32, so the app's map differs from it only by compute-order noise, within a level
or two. The app runs the model with `.cpuOnly`, like HED, so every device gets the same map up to
that noise.

Reproducibility. Same weights, torch 2.14.1 (CPU), coremltools 9.0 and numpy 2.4.6 give
byte-identical files: the package's manifest identifiers are derived from the item paths.
"""

import argparse
import json
import os
import sys
import uuid

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_hed import quantize, read_pgm, read_ppm, sha256, write_netpbm  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REPO_ID = "lllyasviel/Annotators"
FILENAME = "sk_model.pth"
SOURCE_SHA256 = "c686ced2a666b4850b4bb6ccf0748031c3eda9f822de73a34b8979970d90f0c6"
MAX_SIDE = 1152
MULTIPLE = 4
DEFAULT_OUT = os.path.join(ROOT, "App/PaintByNumber/Resources/Models/LineArt.mlpackage")
FIXTURE_INPUT = os.path.join(ROOT, "App/PaintByNumberTests/HEDFixture.ppm")
FIXTURE_REFERENCE = os.path.join(ROOT, "App/PaintByNumberTests/LineArtFixture.pgm")
THREADS = 4


def generator():
    """Informative Drawings' `Generator(3, 1, n_residual_blocks=3, sigmoid=True)`, written out."""
    import torch.nn as nn

    class ResidualBlock(nn.Module):
        def __init__(self, features):
            super().__init__()
            self.conv_block = nn.Sequential(
                nn.ReflectionPad2d(1), nn.Conv2d(features, features, 3), nn.InstanceNorm2d(features), nn.ReLU(inplace=True),
                nn.ReflectionPad2d(1), nn.Conv2d(features, features, 3), nn.InstanceNorm2d(features))

        def forward(self, x):
            return x + self.conv_block(x)

    class Generator(nn.Module):
        def __init__(self):
            super().__init__()
            self.model0 = nn.Sequential(nn.ReflectionPad2d(3), nn.Conv2d(3, 64, 7), nn.InstanceNorm2d(64), nn.ReLU(inplace=True))
            self.model1 = nn.Sequential(
                nn.Conv2d(64, 128, 3, stride=2, padding=1), nn.InstanceNorm2d(128), nn.ReLU(inplace=True),
                nn.Conv2d(128, 256, 3, stride=2, padding=1), nn.InstanceNorm2d(256), nn.ReLU(inplace=True))
            self.model2 = nn.Sequential(*[ResidualBlock(256) for _ in range(3)])
            self.model3 = nn.Sequential(
                nn.ConvTranspose2d(256, 128, 3, stride=2, padding=1, output_padding=1), nn.InstanceNorm2d(128), nn.ReLU(inplace=True),
                nn.ConvTranspose2d(128, 64, 3, stride=2, padding=1, output_padding=1), nn.InstanceNorm2d(64), nn.ReLU(inplace=True))
            self.model4 = nn.Sequential(nn.ReflectionPad2d(3), nn.Conv2d(64, 1, 7), nn.Sigmoid())

        def forward(self, x):
            return self.model4(self.model3(self.model2(self.model1(self.model0(x)))))

    return Generator()


def load_network(weights):
    """The generator with its weights rounded to float16 (what the package stores), in float32."""
    import torch

    torch.manual_seed(0)
    torch.use_deterministic_algorithms(True)
    torch.set_num_threads(THREADS)
    net = generator()
    net.load_state_dict(torch.load(weights, map_location="cpu"))
    return net.half().float().eval()


def line_module(net):
    """The converted graph: the generator, its paper turned into ink."""
    import torch

    class Lines(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.net = net

        def forward(self, image):
            return 1.0 - self.net(image)

    return Lines().eval()


def pad(rgb):
    """Reflect-pads at the bottom and right to the multiple of 4."""
    h, w = rgb.shape[:2]
    ph, pw = (-h) % MULTIPLE, (-w) % MULTIPLE
    if ph == 0 and pw == 0:
        return rgb
    return np.pad(rgb, ((0, ph), (0, pw), (0, 0)), mode="reflect")


def module_map(module, rgb):
    """float32 ink probability at `rgb`'s size."""
    import torch

    x = pad(rgb)
    h, w = rgb.shape[:2]
    t = torch.from_numpy(np.ascontiguousarray(x.astype(np.float32).transpose(2, 0, 1)) / 255.0)[None]
    with torch.no_grad():
        return module(t)[0, 0].numpy()[:h, :w]


def float16_weights_pass():
    """Stores every float32 weight tensor as float16 with a load-time cast back to float32 (exact
    here: `load_network` rounded them already); biases, a few kilobytes, stay float32."""
    from coremltools.converters.mil.mil import Builder as mb
    from coremltools.converters.mil.mil import types
    from coremltools.converters.mil.mil.passes.graph_pass import AbstractGraphPass

    class StoreFloat16(AbstractGraphPass):
        def apply(self, prog):
            for f in prog.functions.values():
                for op in list(f.operations):
                    if op.op_type != "const" or op.outputs[0].dtype != types.fp32:
                        continue
                    value = op.outputs[0].val
                    # Biases stay float32 constants: the transposed convolutions' type inference
                    # reads a bias's value, which a compressed constant no longer carries.
                    if not isinstance(value, np.ndarray) or value.ndim < 2:
                        continue
                    half = value.astype(np.float16)
                    assert np.array_equal(half.astype(np.float32), value), f"{op.name} isn't float16-exact"
                    with f:
                        cast = mb.constexpr_cast(source_val=half, output_dtype="fp32", before_op=op,
                                                 name=op.name + "_fp16")
                    op.enclosing_block.replace_uses_of_var_after_op(
                        anchor_op=op, old_var=op.outputs[0], new_var=cast)
                    op.enclosing_block.remove_ops([op])

    return StoreFloat16()


def convert(net, out):
    import torch
    import coremltools as ct
    from coremltools.models.utils import _apply_graph_pass

    module = line_module(net)
    example = torch.rand(1, 3, 168, 248, generator=torch.Generator().manual_seed(0))
    with torch.no_grad():
        traced = torch.jit.trace(module, example)
    shape = ct.Shape(shape=(1, 3, ct.RangeDim(MULTIPLE, MAX_SIDE, default=768), ct.RangeDim(MULTIPLE, MAX_SIDE, default=768)))
    model = ct.convert(
        traced,
        inputs=[ct.TensorType(name="image", shape=shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="lines", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_ONLY,
        skip_model_load=True,
    )
    model = _apply_graph_pass(model, float16_weights_pass(), skip_model_load=True)
    model.author = "Caroline Chan, Frédo Durand, Phillip Isola (Informative Drawings); converted by tools/models/convert_lineart.py"
    model.license = "MIT"
    model.short_description = (
        "Line drawing (Chan, Durand & Isola 2022, contour style; the weights ControlNet's lineart annotator uses): "
        "RGB 0-1 in, ink probability (one minus the generator's paper) out.")
    model.version = "1"
    model.user_defined_metadata["source"] = f"huggingface.co/{REPO_ID}/{FILENAME}"
    model.user_defined_metadata["source_sha256"] = SOURCE_SHA256
    model.input_description["image"] = (
        "RGB, 0...1 as float, [1, 3, H, W] with H and W multiples of 4 in 4...1152 "
        "(reflect-pad the photo at the bottom and right)")
    model.output_description["lines"] = "Ink probability 0...1, [1, 1, H, W]"
    del model.user_defined_metadata["com.github.apple.coremltools.conversion_date"]
    if os.path.exists(out):
        import shutil
        shutil.rmtree(out)
    model.save(out)
    stabilize(out)
    return traced


def stabilize(package):
    """Makes the package's bytes a function of its content (see convert_hed.stabilize)."""
    import coremltools as ct

    spec_path = os.path.join(package, "Data/com.apple.CoreML/model.mlmodel")
    spec = ct.utils.load_spec(package)
    with open(spec_path, "wb") as f:
        f.write(spec.SerializeToString(deterministic=True))
    path = os.path.join(package, "Manifest.json")
    with open(path) as f:
        manifest = json.load(f)
    ids, entries = {}, {}
    for old, item in manifest["itemInfoEntries"].items():
        new = str(uuid.uuid5(uuid.NAMESPACE_URL, "paint-by-moonlight/LineArt.mlpackage/" + item["path"])).upper()
        ids[old] = new
        entries[new] = item
    manifest["itemInfoEntries"] = dict(sorted(entries.items()))
    manifest["rootModelIdentifier"] = ids[manifest["rootModelIdentifier"]]
    with open(path, "w") as f:
        json.dump(manifest, f, indent=4, sort_keys=True)
        f.write("\n")


def package_bytes(package):
    return sum(os.path.getsize(os.path.join(d, n)) for d, _, names in os.walk(package) for n in names)


def main(argv):
    import warnings
    warnings.filterwarnings("ignore")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--weights", help=f"{FILENAME} (default: download from {REPO_ID})")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--map", nargs=2, metavar=("IN_PPM", "OUT_PGM"), help="only write the line map of IN_PPM")
    ap.add_argument("--compare", metavar="APP_PGM", help="with --map: compare an app-made map with it")
    args = ap.parse_args(argv)

    weights = args.weights
    if weights is None:
        from huggingface_hub import hf_hub_download
        weights = hf_hub_download(REPO_ID, FILENAME)
    digest = sha256(weights)
    if digest != SOURCE_SHA256:
        sys.exit(f"{weights}: sha256 {digest}, expected {SOURCE_SHA256}")
    print(f"weights {weights}\n  sha256 {digest} (matches)")

    net = load_network(weights)
    module = line_module(net)
    if args.map:
        q = quantize(module_map(module, read_ppm(args.map[0])))
        write_netpbm(args.map[1], q)
        print(f"line map {args.map[1]}: {q.shape[1]}x{q.shape[0]}")
        if args.compare:
            app = read_pgm(args.compare)
            d = np.abs(app.astype(int) - q.astype(int))
            print(f"app map {args.compare}: max {d.max()} levels off, {(d > 0).mean() * 100:.2f}% of pixels differ")
        return

    rgb = read_ppm(FIXTURE_INPUT)
    reference = quantize(module_map(module, rgb))
    write_netpbm(FIXTURE_REFERENCE, reference)
    print(f"fixture {FIXTURE_REFERENCE}: {reference.shape[1]}x{reference.shape[0]}, "
          f"mean {reference.mean():.1f}, ink >= 0.5: {(reference >= 128).mean() * 100:.1f}%")

    traced = convert(net, args.out)
    print(f"model {args.out}: {package_bytes(args.out) / 1e6:.1f} MB")
    # The traced graph is the converted one: its map must be the reference.
    import torch
    x = pad(rgb)
    t = torch.from_numpy(np.ascontiguousarray(x.astype(np.float32).transpose(2, 0, 1)) / 255.0)[None]
    with torch.no_grad():
        traced_map = quantize(traced(t)[0, 0].numpy()[:rgb.shape[0], :rgb.shape[1]])
    d = np.abs(traced_map.astype(int) - reference.astype(int))
    print(f"traced graph vs reference: max {d.max()} levels, {(d > 0).sum()} pixels differ")


if __name__ == "__main__":
    main(sys.argv[1:])
