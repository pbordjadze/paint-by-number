"""Collection page checks using only generated atlases, never real pet fixtures.

python3 -m unittest discover -s tools/factory -p 'test_collection.py'
"""
import base64
from html.parser import HTMLParser
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]


class Pets(HTMLParser):
    def __init__(self, page):
        super().__init__()
        self.cards = {}
        self.buttons = {}
        self.articles = []
        self.feed(page)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "article":
            self.guardian = attrs["id"]
            self.articles.append(self.guardian)
        if tag in ("div", "span") and "pet" in attrs.get("class", "").split():
            self.cards[self.guardian] = attrs
        if tag == "button" and "maker" in attrs.get("class", "").split():
            self.buttons[self.guardian] = attrs


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="collection-test-")
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.repo = self.folder / "repo"
        factory = self.repo / "factory"
        factory.mkdir(parents=True)
        for filename in ("GUARDIANS.md", "panel.json"):
            shutil.copyfile(ROOT / "factory" / filename, factory / filename)

    def build(self, pets=None):
        # The output is separate from the input repo, including when paths contain spaces.
        output = self.folder / "review page.html"
        command = [sys.executable, str(ROOT / "tools/factory/collection.py"),
                   str(self.repo), str(output),
                   str(ROOT / "tools/factory/collection_template.html")]
        if pets is not None:
            command.extend(["--pets", str(pets)])
        subprocess.run(command,
                       check=True, capture_output=True, text=True, cwd=self.folder)
        return output.read_text()

    def atlas(self, guardian, rows=9, pets=None):
        image = Image.new("RGBA", (192 * 8, 208 * rows))
        draw = ImageDraw.Draw(image)
        for row in range(rows):
            for column in range(8):
                draw.rectangle((column * 192, row * 208,
                                (column + 1) * 192 - 1, (row + 1) * 208 - 1),
                               fill=(20 + column * 30, 20 + row * 20, 100, 255))
        root = pets if pets is not None else self.repo / "factory" / "pets"
        path = root / guardian / "spritesheet.webp"
        path.parent.mkdir(parents=True)
        image.save(path, lossless=True)
        return path

    def test_missing_atlases_keep_every_letter_circle(self):
        page = self.build()
        pets = Pets(page).cards
        panel = json.loads((self.repo / "factory/panel.json").read_text())
        self.assertEqual(set(pets), {g["id"] for g in panel["guardians"]})
        self.assertTrue(all(pet["class"] == "pet" for pet in pets.values()))
        self.assertIn('<div class="pet" aria-hidden="true">M</div>', page)
        self.assertIn('id="pet-robber-girl"', page)

    def test_available_atlases_replace_only_their_guardians_and_are_portable(self):
        atlases = {guardian: self.atlas(guardian, rows)
                   for guardian, rows in (("medea", 9), ("robber-girl", 11))}
        page = self.build()
        self.assertEqual(page, self.build())
        pets = Pets(page).cards
        for guardian, path in atlases.items():
            pet = pets[guardian]
            self.assertEqual(pet["class"], "pet pet-sprite")
            self.assertEqual(pet["aria-hidden"], "true")
            encoded, sheet_width, sheet_height = re.fullmatch(
                r"background-image: url\(data:image/webp;base64,(.+)\); "
                r"background-size: (\d+)px (\d+)px", pet["style"]).groups()
            sheet_size = (int(sheet_width), int(sheet_height))
            expected_size = (1536, 1872 if guardian == "medea" else 2288)
            self.assertEqual(sheet_size, tuple(side // 4 for side in expected_size))
            data = base64.b64decode(encoded, validate=True)
            self.assertEqual(data, path.read_bytes())
            with Image.open(io.BytesIO(data)) as image:
                self.assertEqual(image.size, expected_size)
                self.assertNotEqual(image.getpixel((0, 0)), image.getpixel((192, 0)))
        self.assertEqual(pets["moon"]["class"], "pet")

    def test_unsupported_atlas_sizes_fail_and_name_the_file(self):
        path = self.repo / "factory/pets/medea/spritesheet.webp"
        path.parent.mkdir(parents=True)
        for size in ((1536, 2080), (768, 936), (1535, 2288)):
            with self.subTest(size=size):
                Image.new("RGBA", size).save(path, lossless=True)
                with self.assertRaises(subprocess.CalledProcessError) as caught:
                    self.build()
                self.assertIn(str(path), caught.exception.stderr)
                self.assertIn(f"unsupported atlas size {size[0]} × {size[1]}",
                              caught.exception.stderr)

    def test_idle_uses_six_first_row_cells_with_the_specified_holds(self):
        page = self.build()
        sprite = re.search(r"\.pet-sprite\s*\{([^}]+)\}", page).group(1)
        width = float(re.search(r"width: ([\d.]+)px", sprite).group(1))
        height = float(re.search(r"height: ([\d.]+)px", sprite).group(1))
        self.assertEqual(width / height, 192 / 208)
        duration = float(re.search(r"animation: pet-idle ([\d.]+)ms steps\(1, end\) infinite",
                                   sprite).group(1))
        keyframes = re.search(r"@keyframes pet-idle\s*\{(.*?)\n\}", page, re.S).group(1)
        frames = [(float(percent), float(x)) for percent, x in re.findall(
            r"([\d.]+)%\s*\{ background-position: (-?[\d.]+)(?:px)? 0; \}", keyframes)]
        self.assertEqual([x for _, x in frames], [-width * i for i in range(6)] + [0])
        self.assertEqual((frames[0][0], frames[-1][0]), (0, 100))
        for (start, _), (end, _), hold in zip(frames, frames[1:], (280, 110, 110, 140, 140, 320)):
            self.assertAlmostEqual((end - start) * duration / 100, hold, places=4)

    def test_reduced_motion_shows_the_first_frame_without_animation(self):
        page = self.build()
        reduced = re.search(r"@media \(prefers-reduced-motion: reduce\)\s*\{\s*"
                            r"\.pet-sprite\s*\{([^}]+)\}", page).group(1)
        self.assertIn("animation: none;", reduced)
        self.assertIn("background-position: 0 0;", reduced)

    def test_makers_close_the_collection_with_the_exact_words_and_no_circles(self):
        page = self.build()
        parsed = Pets(page)
        panel = json.loads((self.repo / "factory/panel.json").read_text())
        self.assertEqual(parsed.articles, [g["id"] for g in panel["guardians"]]
                         + ["pip", "colophon"])
        self.assertLess(page.index('aria-label="The guardians"'),
                        page.index('<h2 id="makers-title">The makers</h2>'))
        self.assertLess(page.index('id="colophon"'), page.index("<footer>"))
        self.assertIn("Pip</span>", page)
        self.assertIn("Codex's teapot. A plain white teapot, a little lopsided, with no face. "
                      "Lift the lid and there is a blue dot underneath.", page)
        self.assertIn("Colophon</span>", page)
        self.assertIn("Claude's moth. A small round moth with pale page wings. "
                      "It circles the lamp once, at a safe distance, and lands beside "
                      "the words like a bookmark.", page)
        self.assertNotIn("pip", parsed.cards)
        self.assertNotIn("colophon", parsed.cards)
        self.assertEqual(parsed.buttons, {})

    def test_pets_flag_selects_external_sheets_for_guardians_and_makers(self):
        external = self.folder / "external pets"
        self.atlas("moon")  # --pets replaces the default directory, with no fallback.
        sheets = {pet_id: self.atlas(pet_id, rows=11, pets=external)
                  for pet_id in ("medea", "pip", "colophon")}
        page = self.build(pets=external)
        self.assertEqual(page, self.build(pets=external))
        parsed = Pets(page)
        self.assertEqual(parsed.cards["moon"]["class"], "pet")
        for pet_id, path in sheets.items():
            attrs = parsed.cards[pet_id]
            self.assertIn("background-size: 384px 572px", attrs["style"])
            encoded = re.search(r"base64,([^)]*)", attrs["style"]).group(1)
            self.assertEqual(base64.b64decode(encoded, validate=True), path.read_bytes())
        self.assertEqual(set(parsed.buttons), {"pip", "colophon"})
        self.assertNotIn(str(external), page)

    def test_maker_rows_have_reference_frame_counts_holds_and_accessible_labels(self):
        for pet_id in ("pip", "colophon"):
            self.atlas(pet_id, rows=11)
        parsed = Pets(self.build())
        expected = {
            "pip": (3, [140, 140, 140, 280], "Pip, Codex's teapot. Tap to lift the lid."),
            "colophon": (8, [150, 150, 150, 150, 150, 280],
                         "Colophon, Claude's moth. Tap to fold the wings flat."),
        }
        for pet_id, (row, holds, label) in expected.items():
            with self.subTest(pet_id=pet_id):
                button = parsed.buttons[pet_id]
                self.assertEqual(button["type"], "button")
                self.assertEqual(int(button["data-row"]), row)
                self.assertEqual(json.loads(button["data-holds"]), holds)
                self.assertEqual(button["aria-label"], label)
                self.assertEqual(parsed.cards[pet_id]["aria-hidden"], "true")

    def test_one_missing_maker_is_text_only_while_the_other_is_a_button(self):
        self.atlas("pip", rows=11)
        page = self.build()
        parsed = Pets(page)
        self.assertEqual(set(parsed.buttons), {"pip"})
        colophon = re.search(r'<article[^>]*id="colophon">(.*?)</article>',
                             page, re.S).group(1)
        self.assertIn("Claude's moth.", colophon)
        self.assertNotIn("button", colophon)
        self.assertNotIn('class="pet', colophon)


if __name__ == "__main__":
    unittest.main()
