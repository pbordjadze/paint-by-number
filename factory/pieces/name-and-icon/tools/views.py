"""The six seat views of a set of name-and-icon candidates, per reviewer (each with its own shuffled letters).

    views.py candidates.json OUTDIR SEED [KEY,KEY,KEY,KEY]

The optional keys fix the letter order (A first); without them SEED shuffles it. candidates.json: [{"key": ..., "name": ..., "icon": png, "icon_dark": png or null}]. Writes
OUTDIR/<view>.png for astrologer, rikyu, child, hedge, madeleine, originality, and OUTDIR/letters.json
(letter -> candidate key).
"""
import json, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps, ImageEnhance
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ID = os.path.dirname(HERE)
F = "/usr/share/fonts/opentype/inter/"
def font(size, w="Regular"): return ImageFont.truetype(F + f"Inter-{w}.otf", size)

def squircle(im, size):
    im = im.convert("RGBA").resize((size, size), Image.LANCZOS)
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * .2237), fill=255)
    im.putalpha(m.resize((size, size), Image.LANCZOS)); return im

def placeholders(n, seed=3):
    r = random.Random(seed); out = []
    cols = [(88, 120, 160), (190, 120, 90), (110, 150, 120), (150, 110, 160), (200, 170, 90), (90, 150, 170), (170, 90, 110), (120, 120, 130)]
    for i in range(n):
        im = Image.new("RGB", (256, 256), cols[i % len(cols)]); d = ImageDraw.Draw(im)
        k = r.randrange(3); c = (245, 245, 245)
        if k == 0: d.ellipse((76, 76, 180, 180), outline=c, width=18)
        elif k == 1: d.rounded_rectangle((70, 70, 186, 186), radius=22, outline=c, width=18)
        else: d.polygon([(128, 64), (196, 186), (60, 186)], outline=c, width=18)
        out.append(im)
    return out

def fit_label(d, text, fnt):
    """iOS cuts a home-screen label by width, not by count, and ends it with an ellipsis. The limit
    is an estimate: a tenth wider than "Voice Memos", which fits on every iPhone, so "Google Photos"
    fits and "YouTube Music" doesn't."""
    limit = 1.10 * d.textlength("Voice Memos", font=fnt)
    if d.textlength(text, font=fnt) <= limit: return text
    while text and d.textlength(text.rstrip() + "…", font=fnt) > limit: text = text[:-1]
    return text.rstrip() + "…"

def home(cands, letters, dark, W=1179, dim=1.0, tags=True):
    """A home screen at 3x: 60 pt icons, the 12 pt label (the home-screen name, else the name),
    and each candidate's letter in a tag above its icon, off the label."""
    bg = Image.new("RGB", (W, 2556))
    top, bot = ((20, 22, 38), (48, 40, 70)) if dark else ((214, 226, 236), (238, 230, 214))
    arr = np.linspace(0, 1, 2556)[:, None, None]
    bg = Image.fromarray((np.array(top) * (1 - arr) + np.array(bot) * arr).astype("uint8").repeat(W, axis=1))
    d = ImageDraw.Draw(bg); size = 180; gx = (W - 4 * size) // 5
    ph = placeholders(24); slots = list(range(24))
    pos = [1, 6, 9, 14]  # candidate slots in a 4-wide grid
    order = {p: letters[i] for i, p in enumerate(pos[:len(letters)])}
    fnt = font(34, "Medium"); tagf = font(24, "SemiBold"); lab = (245, 245, 245) if dark else (30, 30, 36)
    for s in slots:
        cx, cy = gx + (s % 4) * (size + gx), 260 + (s // 4) * (size + 120)
        if s in order:
            L = order[s]; c = cands[L]
            src = Image.open(c["icon_dark"] if dark and c.get("icon_dark") else c["icon"])
            label = fit_label(d, c.get("home") or c["name"], fnt)
            if tags:
                tx, ty = cx + size / 2, cy - 32
                d.ellipse((tx - 19, ty - 19, tx + 19, ty + 19), fill=(255, 196, 64))
                d.text((tx, ty), L, font=tagf, fill=(20, 20, 20), anchor="mm")
        else:
            src = ph[s]; label = ""
        ic = squircle(src, size); bg.paste(ic, (cx, cy), ic)
        if label:
            d.text((cx + size / 2, cy + size + 14), label, font=fnt, fill=lab, anchor="ma")
    if dim < 1: bg = ImageEnhance.Brightness(bg).enhance(dim)
    return bg

def main():
    cands_list = json.load(open(sys.argv[1])); out = sys.argv[2]; seed = int(sys.argv[3])
    os.makedirs(out, exist_ok=True)
    keys = [c["key"] for c in cands_list]; r = random.Random(seed); r.shuffle(keys)
    if len(sys.argv) > 4: keys = sys.argv[4].split(",")
    byk = {c["key"]: c for c in cands_list}
    letters = "ABCD"[:len(keys)]
    cands = {letters[i]: byk[k] for i, k in enumerate(keys)}
    json.dump({L: cands[L]["key"] for L in letters}, open(f"{out}/letters.json", "w"))
    L = list(letters)
    # Astrologer: two hours, day and night home screens side by side
    day, night = home(cands, L, False), home(cands, L, True)
    two = Image.new("RGB", (day.width * 2 + 40, day.height), (0, 0, 0)); two.paste(day, (0, 0)); two.paste(night, (day.width + 40, 0))
    two.resize((two.width // 2, two.height // 2), Image.LANCZOS).save(f"{out}/astrologer.png")
    # Rikyu: two-tone silhouettes, names in plain type
    cell = 420; sheet = Image.new("RGB", (len(L) * (cell + 40) + 40, cell + 180), (255, 255, 255)); d = ImageDraw.Draw(sheet)
    for i, x in enumerate(L):
        g = ImageOps.grayscale(Image.open(cands[x]["icon"]).resize((cell, cell), Image.LANCZOS))
        a = np.asarray(g); t = np.median(a); sil = Image.fromarray(np.where(a > t, 255, 0).astype("uint8")).convert("RGB")
        sq = squircle(sil, cell); sheet.paste(sq, (40 + i * (cell + 40), 40), sq)
        d.text((40 + i * (cell + 40), cell + 70), f"{x}  {cands[x]['name']}", font=font(30), fill=(20, 20, 20))
    sheet.save(f"{out}/rikyu.png")
    # Child at Bedtime: the dark home screen at phone size, dimmed, one look
    home(cands, L, True, dim=.55).resize((590, 1278), Image.LANCZOS).save(f"{out}/child.png")
    # Hedge Witch: 100% crops of each icon's materials
    crop = 380; sheet = Image.new("RGB", (2 * crop + 60, len(L) * (crop + 70) + 20), (250, 248, 244)); d = ImageDraw.Draw(sheet)
    for i, x in enumerate(L):
        im = Image.open(cands[x]["icon"]).convert("RGB"); a = np.asarray(ImageOps.grayscale(im).filter(ImageFilter.FIND_EDGES)).astype(float)
        best, bxy = -1, (322, 322)
        for yy in range(0, 1024 - crop, 64):
            for xx in range(0, 1024 - crop, 64):
                v = a[yy:yy + crop, xx:xx + crop].mean()
                if v > best: best, bxy = v, (xx, yy)
        y0 = 20 + i * (crop + 70)
        d.text((20, y0), f"{x}  {cands[x]['name']}", font=font(26, "Medium"), fill=(30, 30, 30))
        sheet.paste(im.crop((322, 322, 322 + crop, 322 + crop)), (20, y0 + 40))
        sheet.paste(im.crop((bxy[0], bxy[1], bxy[0] + crop, bxy[1] + crop)), (40 + crop, y0 + 40))
    sheet.save(f"{out}/hedge.png")
    # Madeleine: tinted (monochrome) appearance at three sizes; each name in a plain sentence, large text
    sheet = Image.new("RGB", (1400, len(L) * 300 + 40), (18, 18, 22)); d = ImageDraw.Draw(sheet)
    tint = np.array([255, 196, 120])
    for i, x in enumerate(L):
        g = np.asarray(ImageOps.grayscale(Image.open(cands[x]["icon"]).resize((180, 180), Image.LANCZOS))).astype(float) / 255
        rgb = (g[..., None] * tint + (1 - g[..., None]) * np.array([28, 24, 20])).astype("uint8")
        t = Image.fromarray(rgb); y0 = 30 + i * 300
        for j, s in enumerate((180, 120, 60)):
            ic = squircle(t, s); sheet.paste(ic, (40 + sum((180, 120, 60)[:j]) + j * 30, y0 + (180 - s) // 2), ic)
        d.text((500, y0 + 20), f"{x}", font=font(40, "SemiBold"), fill=(240, 240, 240))
        d.text((500, y0 + 80), f"“I’ve been painting in", font=font(50), fill=(240, 240, 240))
        d.text((500, y0 + 145), f"{cands[x]['name']} every evening.”", font=font(50), fill=(240, 240, 240))
    sheet.save(f"{out}/madeleine.png")
    # Originality: the candidates as a row above real App Store competitors; names beside theirs
    grid = Image.open(f"{ID}/market/market-grid.png").convert("RGB")
    row = Image.new("RGB", (grid.width, 260), (255, 255, 255)); d = ImageDraw.Draw(row)
    d.text((28, 12), "Candidates", font=font(22, "SemiBold"), fill=(30, 26, 34))
    for i, x in enumerate(L):
        x0 = 28 + i * 156
        d.text((x0 + 64, 56), x, font=font(18, "SemiBold"), fill=(30, 26, 34), anchor="mm")
        ic = squircle(Image.open(cands[x]["icon"]), 128); row.paste(ic, (x0, 72), ic)
        lines, cur = [], ""  # the whole name, as search shows it, wrapped under the icon
        for wd in cands[x]["name"].split():
            if cur and d.textlength(f"{cur} {wd}", font=font(15)) > 148: lines.append(cur); cur = wd
            else: cur = f"{cur} {wd}".strip()
        for k, ln in enumerate(lines + [cur]):
            d.text((x0, 208 + k * 19), ln, font=font(15), fill=(60, 56, 66))
    names = json.load(open(f"{ID}/market/market.json"))
    rival = [r["name"] for k in ("photo", "pbn") for r in names.get(k, [])][:24]
    d.text((700, 40), "Rival names:", font=font(18, "SemiBold"), fill=(30, 26, 34))
    for j, n in enumerate(rival[:12]):
        d.text((700 + (j // 6) * 440, 70 + (j % 6) * 30), n[:40], font=font(16), fill=(60, 56, 66))
    full = Image.new("RGB", (grid.width, grid.height + row.height)); full.paste(row, (0, 0)); full.paste(grid, (0, row.height))
    full.save(f"{out}/originality.png")

if __name__ == "__main__":
    main()
