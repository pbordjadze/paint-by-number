#!/usr/bin/env python3
"""Make the tiny lossless WebP geometry fixture (colored cells, no pet artwork).

    python3 tools/tests/fixtures/make_sprite_atlas.py /root/factory-out/F37/pet-fixture.webp

Copy the result to App/PaintByNumberTests/pet-fixture.webp only when changing the fixture.
Each required cell has a unique center color and different top/bottom corner markers;
unused cells and an eight-pixel border stay transparent. Requires Pillow.
"""

from pathlib import Path
import sys

from PIL import Image, ImageDraw


def make_atlas(path):
    sheet = Image.new("RGBA", (1536, 2288))
    draw = ImageDraw.Draw(sheet)
    for row, count in enumerate((6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8)):
        for column in range(count):
            x, y = column * 192, row * 208
            draw.rectangle((x + 8, y + 8, x + 183, y + 199), fill=(15 + 20 * row, 11 + 27 * column, 100, 255))
            draw.rectangle((x + 8, y + 8, x + 16, y + 16), fill="white")
            draw.rectangle((x + 175, y + 191, x + 183, y + 199), fill="blue")
    sheet.save(path, format="WEBP", lossless=True, exact=True)


if __name__ == "__main__":
    make_atlas(Path(sys.argv[1]))
