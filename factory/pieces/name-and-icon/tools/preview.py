"""A designer's own draft as it renders: 1024 master, light and dark home screens, tinted mode, small sizes.

    preview.py DESIGNER_DIR NAME
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageOps
import numpy as np
from render_svg import render
from views import home, squircle, font

def main():
    d, name = sys.argv[1], sys.argv[2]
    render(os.path.join(d, "icon.svg"), os.path.join(d, "icon.png"))
    dark = None
    if os.path.exists(os.path.join(d, "icon-dark.svg")):
        render(os.path.join(d, "icon-dark.svg"), os.path.join(d, "icon-dark.png")); dark = os.path.join(d, "icon-dark.png")
    c = {"A": {"name": name, "icon": os.path.join(d, "icon.png"), "icon_dark": dark}}
    # the home screens show only this designer's icon, in all four candidate slots' first place
    from views import home as _home
    day, night = _home({"A": c["A"], "B": c["A"], "C": c["A"], "D": c["A"]}, ["A", "B", "C", "D"], False, tags=False), None
    night = _home({"A": c["A"], "B": c["A"], "C": c["A"], "D": c["A"]}, ["A", "B", "C", "D"], True, tags=False)
    master = squircle(Image.open(c["A"]["icon"]), 700)
    W = 700 + 40 + 590 * 2 + 40 * 3
    sheet = Image.new("RGB", (W, 1460), (236, 234, 238)); dr = ImageDraw.Draw(sheet)
    sheet.paste(master, (40, 60), master); dr.text((40, 14), "icon.svg at 700 px (iOS's corner mask applied)", font=font(24, "Medium"), fill=(30, 30, 30))
    for k, (im, label) in enumerate(((day, "light home screen"), (night, "dark home screen"))):
        sm = im.resize((590, 1278), Image.LANCZOS); x = 780 + k * 630
        sheet.paste(sm, (x, 60)); dr.text((x, 14), label, font=font(24, "Medium"), fill=(30, 30, 30))
    g = np.asarray(ImageOps.grayscale(Image.open(c["A"]["icon"]).resize((180, 180), Image.LANCZOS))).astype(float) / 255
    tint = Image.fromarray((g[..., None] * np.array([255, 196, 120]) + (1 - g[..., None]) * np.array([28, 24, 20])).astype("uint8"))
    dr.rectangle((40, 800, 740, 1440), fill=(18, 18, 22))
    dr.text((60, 812), "tinted appearance (approximate) and small sizes", font=font(22, "Medium"), fill=(230, 230, 230))
    x = 60
    for s in (180, 120, 60, 40):
        ic = squircle(tint, s); sheet.paste(ic, (x, 860 + (180 - s) // 2), ic)
        ic2 = squircle(Image.open(c["A"]["icon"]), s); sheet.paste(ic2, (x, 1100 + (180 - s) // 2), ic2); x += s + 40
    sheet.save(os.path.join(d, "preview.png")); print(os.path.join(d, "preview.png"))

if __name__ == "__main__":
    main()
