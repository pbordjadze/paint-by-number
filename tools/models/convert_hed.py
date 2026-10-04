#!/usr/bin/env python3
"""Converts ControlNet's HED edge detector to the app's Core ML model, reproducibly.

    python tools/models/convert_hed.py [--weights ControlNetHED.pth] [--out DIR] [--remake-fixture]
    python tools/models/convert_hed.py --map <in.ppm> <out.pgm> [--compare <app.pgm>]

Writes App/PaintByNumber/Resources/Models/HED.mlpackage (what `EdgeDetector` runs) and the
simulator test's reference map App/PaintByNumberTests/HEDFixture.pgm, computed with PyTorch
from the committed input App/PaintByNumberTests/HEDFixture.ppm exactly the way the layered-lines
research computed its maps (`research/lineart/lines_learned.py` in the `archive/lineart-research`
tag, model `hed`).

--map writes the 8-bit edge map of an image already at its map size (≤ 1152 px; `pbn
generate`'s working.ppm, or the model input the app's tests attach) as `pbn generate --edges`
reads it, the same levels the app computes; --compare also reports how far an app-made map is
from it.

Source. `ControlNetHED.pth` from the Hugging Face repository lllyasviel/Annotators, revision
982e7edaec38759d914a963c48c4726685de7d96, 29,444,406 bytes, sha256 SOURCE_SHA256 below (checked
before anything else; a different file stops the script). It is the network controlnet_aux 0.0.10
ships as `ControlNetHED_Apache2` (imported from there, not copied): a VGG-16 trunk with five
side outputs, retrained by Lvmin Zhang (lllyasviel) for ControlNet on RGB input. License:
Apache-2.0. ControlNet's `annotator/hed/__init__.py`, which downloads exactly this file, opens
with "This is an improved version and model of HED edge detection with Apache License, Version
2.0. Please use this implementation in your products", the ControlNet repository's LICENSE is
the Apache License 2.0, and controlnet_aux (Apache-2.0) carries the same header. The Hugging Face
model card itself only says `license: other`. The method is Saining Xie and Zhuowen Tu,
"Holistically-Nested Edge Detection" (ICCV 2015).

What the model computes. Input `image`: float32 [1, 3, H, W], RGB in 0...255 (sRGB bytes as
floats, no normalization: the network subtracts its own mean), H and W multiples of 16 in
16...1152. The caller reflect-pads the photo at the bottom and right to the multiple of 16 and
crops the output back, as the research did. Output `edges`: float32 [1, 1, H, W], the edge
probability: the five side outputs upsampled bilinearly (half-pixel centers, edges clamped, the
same sampling as cv2.INTER_LINEAR), averaged, through a sigmoid. That is controlnet_aux's
`HEDdetector` up to its final 8-bit cast; the app quantizes to round(p × 255) instead of
truncating, so a byte is the nearest level (the reference map here does the same).

Shapes. One flexible shape (`RangeDim` 16...1152 on both spatial axes) rather than enumerated
shapes: every multiple of 16 up to 1152 on two axes would be 5,184 enumerations, and the model
only ever runs on the CPU, which executes flexible shapes natively.

Precision. The source weights are float16 and are stored as float16 (`constexpr_cast` to
float32 when Core ML loads the model), so the stored weights are bit-identical to the source;
the program computes in float32 (`compute_precision=FLOAT32`), like the research's PyTorch run.
The app runs it with `.cpuOnly`. 29.4 MB on disk: 8-bit weights would halve that, but they
change the maps the research tuned on.

Reproducibility. Same weights, torch 2.14.1 (CPU), coremltools 9.0, controlnet_aux 0.0.10,
numpy 2.4.6 and opencv-python-headless give byte-identical files: the package's manifest
identifiers are derived from the item paths instead of random UUIDs.

--remake-fixture re-derives HEDFixture.ppm from the bundled red-fox.jpg (resize to 512 x 341
with Pillow's Lanczos filter, crop (160, 60, 408, 228)); JPEG decoders differ by a level here
and there, so the committed PPM, not the JPEG, is the fixture's source of truth.
"""

import argparse
import hashlib
import json
import os
import sys
import uuid

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REPO_ID = "lllyasviel/Annotators"
REVISION = "982e7edaec38759d914a963c48c4726685de7d96"
FILENAME = "ControlNetHED.pth"
SOURCE_SHA256 = "5ca93762ffd68a29fee1af9d495bf6aab80ae86f08905fb35472a083a4c7a8fa"
MAX_SIDE = 1152
MULTIPLE = 16
DEFAULT_OUT = os.path.join(ROOT, "App/PaintByNumber/Resources/Models/HED.mlpackage")
FIXTURE_INPUT = os.path.join(ROOT, "App/PaintByNumberTests/HEDFixture.ppm")
FIXTURE_REFERENCE = os.path.join(ROOT, "App/PaintByNumberTests/HEDFixture.pgm")
FIXTURE_SOURCE = os.path.join(ROOT, "App/PaintByNumber/Resources/Samples/red-fox.jpg")
THREADS = 4


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_network(weights):
    import torch
    from controlnet_aux.hed import ControlNetHED_Apache2

    torch.manual_seed(0)
    torch.use_deterministic_algorithms(True)
    torch.set_num_threads(THREADS)
    net = ControlNetHED_Apache2()
    net.load_state_dict(torch.load(weights, map_location="cpu"))
    return net.float().eval()


def edge_module(net):
    """The converted graph: the network plus controlnet_aux's post-processing."""
    import torch
    import torch.nn.functional as F

    class HEDEdges(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.net = net

        def forward(self, image):
            sides = self.net(image)
            # Side k (1-based) is at stride 2^(k-1); scale factors keep the graph shape-agnostic.
            up = [sides[0]] + [
                F.interpolate(s, scale_factor=float(2 ** k), mode="bilinear", align_corners=False)
                for k, s in enumerate(sides[1:], 1)
            ]
            return torch.sigmoid(torch.mean(torch.cat(up, 1), 1, keepdim=True))

    return HEDEdges().eval()


def pad(rgb):
    """Reflect-pads at the bottom and right to the multiple of 16, as the research did."""
    h, w = rgb.shape[:2]
    ph, pw = (-h) % MULTIPLE, (-w) % MULTIPLE
    if ph == 0 and pw == 0:
        return rgb
    return np.pad(rgb, ((0, ph), (0, pw), (0, 0)), mode="reflect")


def research_map(net, rgb):
    """`lines_learned.run_model(rgb, "hed")`, verbatim in substance: float32 edge probability."""
    import cv2
    import torch

    x = pad(rgb)
    h, w = rgb.shape[:2]
    H, W = x.shape[:2]
    t = torch.from_numpy(np.ascontiguousarray(x.astype(np.float32).transpose(2, 0, 1)))[None]
    with torch.no_grad():
        sides = [e.numpy().astype(np.float32)[0, 0] for e in net(t)]
    sides = [cv2.resize(e, (W, H), interpolation=cv2.INTER_LINEAR) for e in sides]
    edge = 1.0 / (1.0 + np.exp(-np.mean(np.stack(sides, 2), axis=2).astype(np.float64)))
    return edge[:h, :w].astype(np.float32)


def module_map(module, rgb):
    import torch

    x = pad(rgb)
    h, w = rgb.shape[:2]
    t = torch.from_numpy(np.ascontiguousarray(x.astype(np.float32).transpose(2, 0, 1)))[None]
    with torch.no_grad():
        return module(t)[0, 0].numpy()[:h, :w]


def quantize(p):
    """The app's 8-bit map: the nearest of 256 levels (round half up)."""
    return np.clip(np.floor(p.astype(np.float64) * 255 + 0.5), 0, 255).astype(np.uint8)


def read_pgm(path):
    return read_ppm(path, magic=b"P5")


def read_ppm(path, magic=b"P6"):
    with open(path, "rb") as f:
        data = f.read()
    tokens, i = [], 0
    while len(tokens) < 4:
        while data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while data[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        tokens.append(data[i:j])
        i = j
    assert tokens[0] == magic and tokens[3] == b"255", f"{path}: expected an 8-bit binary {magic.decode()} file"
    w, h = int(tokens[1]), int(tokens[2])
    channels = 3 if magic == b"P6" else 1
    pixels = np.frombuffer(data[i + 1:i + 1 + w * h * channels], np.uint8)
    return pixels.reshape(h, w, 3) if channels == 3 else pixels.reshape(h, w)


def write_netpbm(path, array):
    magic = b"P6" if array.ndim == 3 else b"P5"
    with open(path, "wb") as f:
        f.write(magic + b"\n%d %d\n255\n" % (array.shape[1], array.shape[0]))
        f.write(np.ascontiguousarray(array, np.uint8).tobytes())


def remake_fixture():
    from PIL import Image

    im = Image.open(FIXTURE_SOURCE).convert("RGB").resize((512, 341), Image.LANCZOS)
    write_netpbm(FIXTURE_INPUT, np.asarray(im.crop((160, 60, 408, 228))))


def float16_weights_pass():
    """Stores every float32 constant as float16 with a load-time cast back to float32. Exact
    here: every weight of the source is float16."""
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
                    if not isinstance(value, np.ndarray) or value.size < 2:
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

    module = edge_module(net)
    example = torch.rand(1, 3, 208, 304, generator=torch.Generator().manual_seed(0)) * 255
    with torch.no_grad():
        traced = torch.jit.trace(module, example)
    side = ct.RangeDim(MULTIPLE, MAX_SIDE, default=768)
    shape = ct.Shape(shape=(1, 3, side, ct.RangeDim(MULTIPLE, MAX_SIDE, default=MAX_SIDE)))
    model = ct.convert(
        traced,
        inputs=[ct.TensorType(name="image", shape=shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="edges", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_ONLY,
        skip_model_load=True,
    )
    model = _apply_graph_pass(model, float16_weights_pass(), skip_model_load=True)
    model.author = "Lvmin Zhang (lllyasviel), ControlNet; converted by tools/models/convert_hed.py"
    model.license = "Apache-2.0"
    model.short_description = (
        "HED edge probability (Xie & Tu 2015) with ControlNet's Apache-2.0 weights: "
        "RGB 0-255 in, sigmoid of the mean of five upsampled side outputs out.")
    model.version = "1"
    model.user_defined_metadata["source"] = f"huggingface.co/{REPO_ID}@{REVISION}/{FILENAME}"
    model.user_defined_metadata["source_sha256"] = SOURCE_SHA256
    model.input_description["image"] = (
        "RGB, 0...255 as float, [1, 3, H, W] with H and W multiples of 16 in 16...1152 "
        "(reflect-pad the photo at the bottom and right)")
    model.output_description["edges"] = "Edge probability 0...1, [1, 1, H, W]"
    # The conversion date would make every run's package differ.
    del model.user_defined_metadata["com.github.apple.coremltools.conversion_date"]
    if os.path.exists(out):
        import shutil
        shutil.rmtree(out)
    model.save(out)
    stabilize(out)
    return traced


def stabilize(package):
    """Makes the package's bytes a function of its content: the specification serialized with
    protobuf's deterministic map order, and manifest identifiers derived from the item paths
    instead of random UUIDs."""
    import coremltools as ct

    spec_path = os.path.join(package, "Data/com.apple.CoreML/model.mlmodel")
    spec = ct.utils.load_spec(package)
    with open(spec_path, "wb") as f:
        f.write(spec.SerializeToString(deterministic=True))
    path = os.path.join(package, "Manifest.json")
    with open(path) as f:
        manifest = json.load(f)
    ids = {}
    entries = {}
    for old, item in manifest["itemInfoEntries"].items():
        new = str(uuid.uuid5(uuid.NAMESPACE_URL, "paint-by-moonlight/HED.mlpackage/" + item["path"])).upper()
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
    ap.add_argument("--weights", help=f"{FILENAME} (default: download {REPO_ID}@{REVISION[:12]})")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--remake-fixture", action="store_true")
    ap.add_argument("--map", nargs=2, metavar=("IN_PPM", "OUT_PGM"), help="only write the edge map of IN_PPM")
    ap.add_argument("--compare", metavar="APP_PGM", help="with --map: compare an app-made map with it")
    args = ap.parse_args(argv)

    weights = args.weights
    if weights is None:
        from huggingface_hub import hf_hub_download
        weights = hf_hub_download(REPO_ID, FILENAME, revision=REVISION)
    digest = sha256(weights)
    if digest != SOURCE_SHA256:
        sys.exit(f"{weights}: sha256 {digest}, expected {SOURCE_SHA256}")
    print(f"weights {weights}\n  sha256 {digest} (matches)")

    net = load_network(weights)
    if args.map:
        q = quantize(research_map(net, read_ppm(args.map[0])))
        write_netpbm(args.map[1], q)
        print(f"edge map {args.map[1]}: {q.shape[1]}x{q.shape[0]}")
        if args.compare:
            app = read_pgm(args.compare)
            d = np.abs(app.astype(int) - q.astype(int))
            print(f"app map {args.compare}: largest difference {d.max()} levels, "
                  f"{int((d > 0).sum())} of {d.size} pixels differ, mean {d.mean():.4f}")
        return
    if args.remake_fixture:
        remake_fixture()
    rgb = read_ppm(FIXTURE_INPUT)
    reference = research_map(net, rgb)

    traced = convert(net, args.out)
    print(f"model {os.path.relpath(args.out, ROOT)}: {package_bytes(args.out):,} bytes")

    # The traced graph is what was converted: it must reproduce the research's map at sizes
    # other than the one it was traced at (the fixture pads to 256 x 176).
    rng = np.random.default_rng(0)
    for name, image in (("fixture", rgb), ("noise 150x100", rng.integers(0, 256, (100, 150, 3), dtype=np.uint8))):
        a, b = research_map(net, image), module_map(traced, image)
        diff = np.abs(a - b)
        print(f"traced vs research ({name}, {image.shape[1]}x{image.shape[0]}): "
              f"max |Δp| {diff.max():.2e}, 8-bit levels differing {int((quantize(a) != quantize(b)).sum())}")
        assert diff.max() < 1e-4

    write_netpbm(FIXTURE_REFERENCE, quantize(reference))
    q = quantize(reference)
    print(f"reference {os.path.relpath(FIXTURE_REFERENCE, ROOT)}: {q.shape[1]}x{q.shape[0]}, "
          f"mean {q.mean():.2f}, ≥ 0.18: {(reference >= 0.18).mean():.3f}, ≥ 0.6: {(reference >= 0.6).mean():.3f}")


if __name__ == "__main__":
    main(sys.argv[1:])
