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
        self.feed(page)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "article":
            self.guardian = attrs["id"]
        if tag == "div" and "pet" in attrs.get("class", "").split():
            self.cards[self.guardian] = attrs


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

    def build(self):
        # The output is separate from the input repo, including when paths contain spaces.
        output = self.folder / "review page.html"
        subprocess.run([sys.executable, str(ROOT / "tools/factory/collection.py"),
                        str(self.repo), str(output),
                        str(ROOT / "tools/factory/collection_template.html")],
                       check=True, capture_output=True, text=True, cwd=self.folder)
        return output.read_text()

    def atlas(self, guardian):
        image = Image.new("RGBA", (192 * 8, 208 * 9))
        draw = ImageDraw.Draw(image)
        for row in range(9):
            for column in range(8):
                draw.rectangle((column * 192, row * 208,
                                (column + 1) * 192 - 1, (row + 1) * 208 - 1),
                               fill=(20 + column * 30, 20 + row * 25, 100, 255))
        path = self.repo / "factory" / "pets" / guardian / "spritesheet.webp"
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
        atlases = {guardian: self.atlas(guardian) for guardian in ("medea", "robber-girl")}
        page = self.build()
        self.assertEqual(page, self.build())
        pets = Pets(page).cards
        for guardian, path in atlases.items():
            pet = pets[guardian]
            self.assertEqual(pet["class"], "pet pet-sprite")
            self.assertEqual(pet["aria-hidden"], "true")
            encoded = re.fullmatch(r"background-image: url\(data:image/webp;base64,(.+)\)",
                                   pet["style"]).group(1)
            data = base64.b64decode(encoded, validate=True)
            self.assertEqual(data, path.read_bytes())
            with Image.open(io.BytesIO(data)) as image:
                self.assertEqual(image.size, (1536, 1872))
                self.assertNotEqual(image.getpixel((0, 0)), image.getpixel((192, 0)))
        self.assertEqual(pets["moon"]["class"], "pet")

    def test_idle_uses_six_first_row_cells_with_the_specified_holds(self):
        page = self.build()
        sprite = re.search(r"\.pet-sprite\s*\{([^}]+)\}", page).group(1)
        width = float(re.search(r"width: ([\d.]+)px", sprite).group(1))
        height = float(re.search(r"height: ([\d.]+)px", sprite).group(1))
        sheet_width, sheet_height = map(float, re.search(
            r"background-size: ([\d.]+)px ([\d.]+)px", sprite).groups())
        self.assertEqual(width / height, 192 / 208)
        self.assertEqual((sheet_width / width, sheet_height / height), (8, 9))
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


if __name__ == "__main__":
    unittest.main()
