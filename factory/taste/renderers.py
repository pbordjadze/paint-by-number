"""Portable text, swatch and blind image sheets. All images are render output."""
import math
import textwrap
from pathlib import Path


def font(size):
    from PIL import ImageFont
    for path in ('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                 '/usr/share/fonts/dejavu/DejaVuSans.ttf'):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def write(image, path):
    from .kit import outside_repo
    path = outside_repo(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


def text_in_use(lines, path):
    from PIL import Image, ImageDraw
    wrapped = [part for line in lines for part in textwrap.wrap(line, 64)]
    image = Image.new('RGB', (960, max(120, 40 + 36 * len(wrapped))), '#f4f1ea')
    draw = ImageDraw.Draw(image)
    for i, line in enumerate(wrapped):
        draw.text((24, 20 + 36 * i), line, font=font(24), fill='#2a2622')
    return write(image, path)


def swatches(slots, path):
    from PIL import Image, ImageDraw
    if not slots:
        raise ValueError('cannot render an empty swatch sheet')
    cols = min(4, len(slots))
    image = Image.new('RGB', (cols * 260, math.ceil(len(slots) / cols) * 220), '#f4f1ea')
    draw = ImageDraw.Draw(image)
    for i, slot in enumerate(slots):
        x, y = (i % cols) * 260 + 12, (i // cols) * 220 + 12
        draw.rectangle((x, y, x + 236, y + 150), fill='#' + slot['hex'].lstrip('#'))
        draw.text((x, y + 158), f"{slot['slot']} · {slot.get('incumbent', '')}", font=font(18), fill='#2a2622')
    return write(image, path)


def contacts(lettered_images, path):
    """Order and labels come from one juror's private ballot; never show source filenames."""
    from PIL import Image, ImageDraw, ImageOps
    if not lettered_images:
        raise ValueError('cannot render an empty contact sheet')
    cols = min(3, len(lettered_images))
    image = Image.new('RGB', (cols * 320, math.ceil(len(lettered_images) / cols) * 280), '#f4f1ea')
    draw = ImageDraw.Draw(image)
    for i, (letter, source) in enumerate(lettered_images.items()):
        x, y = i % cols * 320, i // cols * 280
        with Image.open(source) as original:
            tile = ImageOps.contain(original.convert('RGB'), (296, 224))
            image.paste(tile, (x + (320 - tile.width) // 2, y + 12))
        draw.text((x + 12, y + 242), letter, font=font(24), fill='#2a2622')
    return write(image, path)
