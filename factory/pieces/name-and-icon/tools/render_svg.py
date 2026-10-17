"""Render an icon SVG to an opaque 1024 PNG with headless Chromium (Source Serif 4 available to <text>)."""
import subprocess, sys, pathlib
from PIL import Image
CHROME = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
FONTS = pathlib.Path("scratchpad/store/fonts/local.css")

def render(svg, png, size=1024):
    svg, png = pathlib.Path(svg).resolve(), pathlib.Path(png).resolve()
    markup = svg.read_text()
    if markup.lstrip().startswith("<?xml"):
        markup = markup.split("?>", 1)[1]
    html = png.with_suffix(".html")
    html.write_text(f"""<!doctype html><html><head><meta charset=utf-8><link rel=stylesheet href='{FONTS.as_uri()}'>
<style>*{{margin:0}}html,body{{width:{size}px;height:{size}px;overflow:hidden;background:#fff}}svg{{display:block;width:{size}px;height:{size}px}}</style>
</head><body>{markup}</body></html>""")
    subprocess.run([CHROME, "--headless", "--no-sandbox", "--hide-scrollbars", "--allow-file-access-from-files",
                    "--force-device-scale-factor=1", f"--window-size={size},{size + 400}", "--virtual-time-budget=3000",
                    f"--screenshot={png}", html.as_uri()], check=True, capture_output=True)
    Image.open(png).crop((0, 0, size, size)).convert("RGB").save(png)
    html.unlink()

if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2])
