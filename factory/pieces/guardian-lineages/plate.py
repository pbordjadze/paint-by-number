"""Mounts one generated photograph as a catalogue plate.

usage: python3 plate.py <lineages.json> <guardian-id> <step 0-3 | wild> <photo.png> <out.webp>

Every plate is the same: an off-white mount, the photograph in a fixed window, the plate number
top left, and below it a label (guardian, step, medium, date) and the liner notes (the trail so
far). The label is typeset here, not drawn by the image model, so the words are exact and every
plate reads the same way; the variety is in the photograph.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 1400
WIN = 1040                      # square photograph window
MOUNT = (238, 234, 226)
INK = (38, 34, 30)
GREY = (112, 104, 96)
SERIF = '/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf'
ITALIC = '/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf'
BOLD = '/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf'
ROMAN = ['0', 'I', 'II', 'III']


def font(path, size):
    return ImageFont.truetype(path, size)


def wrap(draw, text, f, width):
    words, lines, line = text.split(), [], ''
    for w in words:
        trial = (line + ' ' + w).strip()
        if draw.textlength(trial, font=f) <= width:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def main(data_path, gid, step, photo, out):
    data = json.load(open(data_path, encoding='utf-8'))
    g = next(x for x in data['guardians'] if x['id'] == gid)
    s = g['wild'] if step == 'wild' else g['steps'][step]
    plate = Image.new('RGB', (W, H + 400), MOUNT)   # cropped to fit below
    img = Image.open(photo).convert('RGB')
    side = min(img.size)
    img = img.crop(((img.width - side) // 2, (img.height - side) // 2,
                    (img.width + side) // 2, (img.height + side) // 2)).resize((WIN, WIN), Image.LANCZOS)
    x0 = (W - WIN) // 2
    y0 = 80
    plate.paste(img, (x0, y0))
    d = ImageDraw.Draw(plate)
    d.rectangle((x0 - 1, y0 - 1, x0 + WIN, y0 + WIN), outline=(200, 194, 184))
    d.text((x0, 32), 'Wildcard' if step == 'wild' else f"Pl. {ROMAN[step]}", font=font(ITALIC, 30), fill=GREY)
    d.text((x0 + WIN, 32), g['name'], font=font(ITALIC, 30), fill=GREY, anchor='ra')

    y = y0 + WIN + 34
    tw = WIN - 240 if step == 0 else WIN   # step 0 keeps room for the approved drawing
    d.text((x0, y), s['title'], font=font(BOLD, 38), fill=INK)
    y += 52
    for line in wrap(d, ', '.join(x for x in (s['medium'], s['date']) if x), font(SERIF, 30), tw):
        d.text((x0, y), line, font=font(SERIF, 30), fill=INK)
        y += 38
    y += 14
    if step == 'wild':
        trail = ' ← '.join(x['short'] for x in g['steps']) + ' · and a wildcard'
    else:
        trail = ' ← '.join(x['short'] for x in g['steps'][:step + 1])
    for line in wrap(d, trail, font(ITALIC, 28), tw):
        d.text((x0, y), line, font=font(ITALIC, 28), fill=GREY)
        y += 36
    if s.get('link'):
        y += 6
        for line in wrap(d, s['link'], font(SERIF, 24), tw):
            d.text((x0, y), line, font=font(SERIF, 24), fill=GREY)
            y += 31
    if step == 0:
        ref = Image.open(g['approved']).convert('RGBA')
        ref.thumbnail((192, 208), Image.LANCZOS)
        box = Image.new('RGBA', (212, 250), MOUNT + (255,))
        box.alpha_composite(ref, (10, 6))
        bd = ImageDraw.Draw(box)
        bd.text((106, 222), 'approved drawing', font=font(ITALIC, 20), fill=GREY, anchor='ma')
        plate.paste(box.convert('RGB'), (x0 + WIN - 212, y0 + WIN + 24))
    plate = plate.crop((0, 0, W, max(H, y + 40)))
    plate.save(out, 'WEBP', quality=88)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3] if sys.argv[3] == 'wild' else int(sys.argv[3]), sys.argv[4], sys.argv[5])
