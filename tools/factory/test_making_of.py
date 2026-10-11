"""Making-of unit checks, plus two real corpus renders when MAKING_OF_INTEGRATION=1.

PYTHONDONTWRITEBYTECODE=1 FACTORY_TEST_OUT=/root/factory-out/F16 \
PBN_BIN=<build>/release/pbn FIGURES_BIN=<build>/release/figures \
MAKING_OF_INTEGRATION=1 python3 -m unittest discover -s tools/factory -p test_making_of.py
"""
import hashlib
from concurrent.futures import ProcessPoolExecutor
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from PIL import Image

import making_of
import render
from reveal_sheet import path_points

TEST_OUT = os.environ.get("FACTORY_TEST_OUT", tempfile.gettempdir())


class MakingOfTests(unittest.TestCase):
    def test_citations_are_exact_and_source_drift_is_rejected(self):
        citations = making_of.load_citations()
        # Supplied edges run neither credited neural model; the line-art cell map
        # does use the credited distance transform to enforce cell thickness.
        self.assertEqual({stage for stage, citation in citations.items() if citation is None},
                         {"working-image"})
        with tempfile.TemporaryDirectory(dir=TEST_OUT) as temporary:
            path = Path(temporary) / "citations.json"
            citations["smoothed"]["authors"] = "Gastal & Oliveira"
            making_of.write_json(path, citations)
            with self.assertRaisesRegex(ValueError, "exactly match ACKNOWLEDGEMENTS.md:488"):
                making_of.load_citations(path)
            citations["smoothed"]["line"] = 0
            making_of.write_json(path, citations)
            with self.assertRaises(ValueError):
                making_of.load_citations(path)

    def test_actions_and_cards_follow_the_destination_stage(self):
        metadata = {"width": 100, "height": 60, "path": "M 1 2 L 40 20 L 99 58"}
        citations = making_of.load_citations()
        for stage in ("smoothed", "line-art", "vectorized"):
            scene = making_of.make_scene(metadata, stage, citations[stage])
            actor = scene["actors"][0]
            self.assertEqual(actor["timeline"][0]["do"], "ink" if stage == "line-art" else "sweep")
            self.assertEqual(actor["holds"], "brush" if stage == "line-art" else "broom")
            if citations[stage]:
                self.assertEqual(scene["card"], {**{k: citations[stage][k] for k in ("authors", "year", "title")}, "at": 0})
            self.assertEqual(path_points(scene["paths"]["reveal"]), [(501, 102), (540, 120), (599, 158)])
        idle = making_of.make_scene({**metadata, "path": ""}, "palette", citations["palette"])
        self.assertEqual([a["do"] for a in idle["actors"][0]["timeline"]], ["idle"])
        self.assertGreater(making_of.path_length(idle["paths"]["reveal"]), 0)

    def test_portraits_and_small_images_keep_paths_on_paper(self):
        for width, height in ((10, 10), (512, 768), (1024, 700)):
            box = making_of.layout(width, height)
            self.assertGreaterEqual(box["x"], 50)
            self.assertLessEqual(box["x"] + box["width"], 1050)
            self.assertLessEqual(box["y"] + box["height"] + 200, box["canvasHeight"])

    def test_composition_keeps_the_wipe_under_alpha_and_joins_exact_snapshots(self):
        before = Image.new("RGB", (4, 1), (10, 20, 30))
        after = Image.new("RGB", (4, 1), (11, 21, 31))
        after.putpixel((1, 0), (230, 240, 250))
        field = Image.new("L", (4, 1)); field.putdata([0, 1, 128, 255])
        box = {"x": 1, "y": 1, "width": 4, "height": 1, "canvasWidth": 6, "canvasHeight": 3}
        panel = making_of.compose_picture(before, after, field, 0, box, (6, 3))
        self.assertEqual(panel.getpixel((1, 1)), (10, 20, 30))
        self.assertEqual(panel.getpixel((2, 1)), (230, 240, 250))
        overlay = Image.new("RGBA", panel.size, (0, 0, 0, 0))
        overlay.putpixel((2, 1), (0, 0, 0, 255))
        panel.paste(overlay, (0, 0), overlay)
        self.assertEqual(panel.getpixel((2, 1)), (0, 0, 0))
        complete = making_of.compose_picture(before, after, field, 1, box, (6, 3))
        self.assertEqual(complete.crop((1, 1, 5, 2)).tobytes(), after.tobytes())
        self.assertEqual(complete.getpixel((0, 0)), (246, 241, 231))

    def test_output_guards_apply_before_running_pipeline(self):
        with self.assertRaisesRegex(ValueError, "outside the repository"):
            making_of.making_of(Path("photo.ppm"), render.ROOT / "output", Path("pbn"), Path("figures"))
        with tempfile.TemporaryDirectory(dir=TEST_OUT) as temporary:
            root = Path(temporary)
            (root / "old.png").write_text("keep me")
            with self.assertRaisesRegex(ValueError, "must be empty"):
                making_of.making_of(Path("photo.ppm"), root, Path("pbn"), Path("figures"))
            self.assertEqual((root / "old.png").read_text(), "keep me")

    def test_lines_flag_reaches_the_book_pipeline_and_requires_edges(self):
        with tempfile.TemporaryDirectory(dir=TEST_OUT) as temporary:
            root = Path(temporary)
            executable = root / "executable"
            executable.touch()
            photo, edges, lines = root / "photo.ppm", root / "contours.pgm", root / "drawing.pgm"
            Image.new("RGB", (12, 8), "white").save(photo)
            Image.new("L", (12, 8), 0).save(edges)
            Image.new("L", (12, 8), 255).save(lines)
            with patch("sys.argv", ["making_of.py", str(photo), str(root / "cli"),
                                   "--edges", str(edges), "--lines", str(lines),
                                   "--pbn", str(executable), "--figures", str(executable)]), \
                    patch.object(making_of, "making_of") as invoke:
                making_of.main()
            self.assertEqual(invoke.call_args.args[-2:], (edges, lines))
            with patch.object(render, "run", side_effect=RuntimeError("stop before pipeline")) as run:
                with self.assertRaisesRegex(RuntimeError, "stop before pipeline"):
                    making_of.making_of(photo, root / "book", executable, executable, edges, lines)
            self.assertEqual(run.call_args.args[0][-6:],
                             ["--line-style", "coloringBook", "--edges", edges, "--lines", lines])
            with self.assertRaisesRegex(ValueError, "--lines requires --edges"):
                making_of.making_of(photo, root / "invalid", executable, executable, lines=lines)
            self.assertFalse((root / "invalid").exists())

    def test_contact_crops_photo_and_worker_and_exports_whole_midpoint(self):
        with tempfile.TemporaryDirectory(dir=TEST_OUT) as temporary:
            root = Path(temporary)
            box = making_of.layout(144, 96)
            size = (1100, 825)
            # Frame time is deliberately different from wipe progress: reviews must
            # follow the eased wipe, including the held pose, rather than elapsed time.
            progress = [0, 0.05, 0.25, 0.5, 0.75, 1, 1]
            for i in range(len(progress)):
                panel = Image.new("RGB", size, "#F6F1E7")
                panel.paste(Image.new("RGB", (144, 96), (20 + i, 90, 120)), (478, 100))
                panel.paste("black", (480, 65, 490, 110))  # worker above photo
                panel.save(root / f"{i:06d}.png")
            midpoint = root / "midpoint.png"
            images, labels, selected, crop = making_of.stage_review(
                root, 0, progress, 24, "smoothed", box, size, midpoint)
            self.assertEqual(selected, [0, 2, 3, 4, 5])
            self.assertEqual(len(images), 5)
            self.assertEqual([label.split("wipe ")[1] for label in labels], ["0%", "25%", "50%", "75%", "100%"])
            self.assertEqual(crop, (428, 50, 672, 246))
            self.assertGreater(144 / (crop[2] - crop[0]), 0.5)
            self.assertEqual(midpoint.read_bytes(), (root / "000003.png").read_bytes())
            with Image.open(midpoint) as image:
                self.assertEqual(image.size, size)
            # The contact contains the worker as well as the photo.
            self.assertLess(min(sum(images[0].getextrema(), ())), 10)
            render.labelled_grid(images, labels, 5, root / "contact.png")
            with Image.open(root / "contact.png") as image:
                self.assertEqual(image.size, (5 * images[0].width, images[0].height + 32))

    def test_parallel_composites_match_serial_bytes_with_shared_wipes(self):
        with tempfile.TemporaryDirectory(dir=TEST_OUT) as temporary:
            root = Path(temporary)
            before = Image.new("RGB", (12, 8), (20, 90, 120))
            after = Image.new("L", (12, 8), 220)
            field = Image.new("L", (12, 8))
            field.putdata([1 + (i % 12) * 23 for i in range(96)])
            first, second, field_file = root / "first.ppm", root / "second.pgm", root / "field.pgm"
            before.save(first); after.save(second); field.save(field_file)
            box = {"x": 10, "y": 10, "width": 12, "height": 8, "canvasWidth": 40, "canvasHeight": 30}
            size, jobs, expected = (80, 60), [], []
            for index in range(12):
                fraction = (index // 2) / 5
                overlay_path, frame_path = root / f"overlay-{index}.png", root / f"frame-{index}.png"
                overlay = Image.new("RGBA", size, (index * 20, 0, 0, 128))
                overlay.save(overlay_path)
                panel = making_of.compose_picture(before, after, field, fraction, box, size)
                panel.paste(overlay, (0, 0), overlay)
                serial = root / f"serial-{index}.png"
                panel.save(serial, compress_level=6)
                expected.append(serial.read_bytes())
                jobs.append((index, fraction, overlay_path, frame_path))
            with ProcessPoolExecutor(max_workers=4, initializer=making_of.init_compositor,
                                     initargs=(first, second, field_file, box, size)) as workers:
                results = list(workers.map(making_of.composite_frame, jobs, chunksize=2))
            for index, digest in results:
                actual = (root / f"frame-{index}.png").read_bytes()
                self.assertEqual(actual, expected[index])
                self.assertEqual(digest, hashlib.sha256(actual).hexdigest())

    def test_completed_frame_measurements_survive_encoder_failure(self):
        with tempfile.TemporaryDirectory(dir=TEST_OUT) as temporary:
            root = Path(temporary)
            executable = root / "executable"; executable.touch()
            out = root / "render"
            metadata = {"width": 12, "height": 8, "path": "M 1 4 L 11 4"}
            def command(parts):
                if parts[0] == "ffmpeg":
                    raise subprocess.CalledProcessError(1, parts)
                if parts[1] == "generate":
                    snapshots = out / "snapshots"; snapshots.mkdir()
                    Image.new("RGB", (12, 8), "white").save(snapshots / "working-image.ppm")
                    Image.new("L", (12, 8), 0).save(snapshots / "structure.pgm")
                else:
                    fields = out / "reveal"; fields.mkdir()
                    making_of.write_json(fields / "working-image-structure.json", metadata)
            def pair(*args):
                frames = args[7]
                hashes = []
                for index in range(2):
                    path = frames / f"{index:06d}.png"
                    Image.new("RGB", (110, 83), "white").save(path)
                    hashes.append(hashlib.sha256(path.read_bytes()).hexdigest())
                return {"frameCount": 2, "fps": 24, "pixelWidth": 110, "pixelHeight": 83}, hashes, [0, 1]
            with patch.object(render, "run", side_effect=command), \
                    patch.object(making_of, "render_pair", side_effect=pair):
                with self.assertRaises(subprocess.CalledProcessError):
                    making_of.making_of(root / "photo.ppm", out, executable, executable)
            manifest = json.loads((out / "manifest.json").read_text())
            report = json.loads((out / "report.json").read_text())
            self.assertEqual(manifest["frameCount"], 2)
            self.assertEqual(len(manifest["stages"][0]["frameSHA256"]), 2)
            self.assertFalse(report["movieEncoded"])
            self.assertEqual(report["frameRenderWallSeconds"], report["wallSeconds"])
            self.assertTrue((out / "contact.png").is_file())
            self.assertTrue((out / "midpoints/structure.png").is_file())


def sample(path, fraction):
    points = path_points(path)
    spans = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:])]
    target = sum(spans) * fraction
    for a, b, span in zip(points, points[1:], spans):
        if span and target <= span:
            return tuple(x + (y - x) * target / span for x, y in zip(a, b))
        target -= span
    return points[-1]


@unittest.skipUnless(os.environ.get("MAKING_OF_INTEGRATION") == "1", "set MAKING_OF_INTEGRATION=1 for real corpus renders")
class CorpusRenderTests(unittest.TestCase):
    def test_uncited_unchanged_pair_has_an_idle_worker_and_no_card(self):
        with tempfile.TemporaryDirectory(prefix="making-of-uncited-", dir=TEST_OUT) as temporary:
            root = Path(temporary)
            (root / "stages").mkdir(); (root / "frames").mkdir()
            making_of.write_json(root / "spec.json", {"version": 2})
            image = Image.new("RGB", (8, 8), (200, 201, 202))
            image.save(root / "first.ppm"); image.save(root / "second.ppm")
            Image.new("L", image.size, 0).save(root / "field.pgm")
            metadata = {"width": 8, "height": 8, "path": ""}
            scene = making_of.make_scene(metadata, "line-art", None)
            making_of.write_json(root / "scene.json", scene)
            stage = root / "stages" / "uncited"
            manifest, hashes, progress = making_of.render_pair(root / "first.ppm", root / "second.ppm",
                root / "field.pgm", metadata, root / "scene.json", None, stage, root / "frames",
                Path(os.environ["FIGURES_BIN"]), 0)
            self.assertEqual([action["kind"] for action in manifest["actions"]], ["idle"])
            self.assertTrue(hashes)
            self.assertEqual(progress, [1] * manifest["frameCount"])
            self.assertFalse(list((stage / "frames").glob("*.png")))
            self.assertTrue((stage / "sheets/contact.png").is_file())
            for svg in (stage / "frames").glob("*.svg"):
                self.assertFalse(any(element.get("data-layer") == "card" for element in ET.parse(svg).getroot()))
            checks = json.loads((stage / "checks.json").read_text())
            self.assertFalse(any(c["name"].startswith("card") for c in checks))
            self.assertTrue(all(c["pass"] for c in checks), checks)

    def test_two_corpus_runs_have_identical_frames_and_the_ink_tip_tracks_the_wipe(self):
        # Retain the review artifacts; never put corpus derivatives inside the repo.
        root = Path(tempfile.mkdtemp(prefix="making-of-corpus-", dir=TEST_OUT))
        photo, edges = root / "parrots.ppm", root / "parrots.pgm"
        with Image.open(render.ROOT / "Tests/Corpus/parrots.jpg") as image:
            image.convert("RGB").resize((96, 64), Image.Resampling.LANCZOS).save(photo)
        with Image.open(render.ROOT / "tools/baseline/lines/parrots-contours.png") as image:
            image.convert("L").resize((96, 64), Image.Resampling.LANCZOS).save(edges)
        pbn, figures = Path(os.environ["PBN_BIN"]), Path(os.environ["FIGURES_BIN"])
        runs = [root / "first", root / "second"]
        records = [making_of.making_of(photo, out, pbn, figures, edges) for out in runs]
        self.assertEqual([r["stage"] for r in records[0]],
                         ["structure", "smoothed", "palette", "simplified", "line-art", "vectorized"])
        self.assertEqual((runs[0] / "manifest.json").read_bytes(), (runs[1] / "manifest.json").read_bytes())
        first_files = sorted((runs[0] / "frames").glob("*.png"))
        self.assertEqual(len(first_files), sum(r["frameCount"] for r in records[0]))
        for a in first_files:
            b = runs[1] / "frames" / a.name
            self.assertEqual(a.read_bytes(), b.read_bytes(), a.name)
        for record in records[0]:
            stage = runs[0] / "stages" / record["pair"]
            checks = json.loads((stage / "checks.json").read_text())
            self.assertTrue(all(c["pass"] for c in checks), checks)
            progress = record["wipeProgress"]
            self.assertEqual(progress[-1], 1)
            self.assertEqual(progress, sorted(progress))
            for i, digest in enumerate(record["frameSHA256"]):
                self.assertEqual(hashlib.sha256(first_files[record["startFrame"] + i].read_bytes()).hexdigest(), digest)
            if record["stage"] == "line-art":
                scene = json.loads((runs[0] / "scenes" / (record["pair"] + ".json")).read_text())
                motion = json.loads((stage / "motion.json").read_text())
                for index, frame in enumerate(motion):
                    actor = frame["actors"][0]
                    if actor["action"] == "ink":
                        expected = sample(scene["paths"]["reveal"], progress[index])
                        tip = actor["inkPathPoint"]
                        self.assertLess(math.hypot(expected[0] - tip["x"], expected[1] - tip["y"]), 0.01)
                self.assertEqual(record["citation"]["line"], 500)
                self.assertTrue(any(c["name"] == "cardHold" for c in checks))
        info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-count_frames",
            "-show_entries", "stream=width,height,nb_read_frames,r_frame_rate", "-of", "json",
            str(runs[0] / "making-of.mp4")]))["streams"][0]
        self.assertEqual(int(info["nb_read_frames"]), len(first_files))
        self.assertEqual(info["r_frame_rate"], "24/1")
        self.assertEqual((info["width"], info["height"]), (2064, 1548))
        self.assertTrue((runs[0] / "contact.png").is_file())
        print(f"Two-run corpus review: {root}")


if __name__ == "__main__":
    unittest.main()
