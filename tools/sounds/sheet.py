#!/usr/bin/env python3
"""Draws what tools/sounds/render.sh wrote, for a look at the sounds as well as a listen
(painting-company row 381): for each WAV its waveform over a log-frequency spectrogram
(50 Hz to 16 kHz, 80 dB of range), labelled, in one contact sheet, sheet.png, beside them, with
any click found (a step between two samples over 0.25, which no smooth sound makes) listed in
clicks.txt.

    tools/sounds/sheet.py <out-dir>      (numpy, Pillow)
"""
import pathlib
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw

W, H_WAVE, H_SPEC = 900, 70, 170


def read(path):
    with wave.open(str(path)) as f:
        rate = f.getframerate()
        data = np.frombuffer(f.readframes(f.getnframes()), dtype="<i2").astype(np.float64) / 32767
    return rate, data


def spectrogram(data, rate, seconds):
    n_fft, hop = 2048, 256
    pad = np.concatenate([data, np.zeros(n_fft)])
    frames = max(1, (len(data)) // hop)
    window = np.hanning(n_fft)
    spec = np.stack([np.abs(np.fft.rfft(pad[i * hop:i * hop + n_fft] * window)) for i in range(frames)], axis=1)
    db = 20 * np.log10(spec + 1e-9)
    db = np.clip((db - (db.max() - 80)) / 80, 0, 1)
    freqs = np.fft.rfftfreq(n_fft, 1 / rate)
    rows = np.geomspace(50, 16000, H_SPEC)[::-1]
    idx = np.searchsorted(freqs, rows).clip(0, len(freqs) - 1)
    img = db[idx]
    cols = np.linspace(0, frames - 1, int(W * min(1, len(data) / rate / seconds))).astype(int)
    img = img[:, cols]
    rgb = np.stack([img ** 0.7 * 255, img ** 1.4 * 200, (1 - img) * 60 + img * 90], axis=-1)
    return Image.fromarray(rgb.astype(np.uint8))


def main(out):
    out = pathlib.Path(out)
    wavs = sorted(out.glob("*.wav"))
    longest = max(len(read(p)[1]) / read(p)[0] for p in wavs if p.stem != "reel")
    tiles, clicks = [], []
    for path in wavs:
        rate, data = read(path)
        seconds = len(data) / rate if path.stem == "reel" else longest
        tile = Image.new("RGB", (W, H_WAVE + H_SPEC + 18), (18, 18, 24))
        draw = ImageDraw.Draw(tile)
        draw.text((6, 2), f"{path.stem}  ({len(data) / rate:.2f} s, peak {20 * np.log10(np.abs(data).max() + 1e-9):.1f} dBFS)", fill=(230, 220, 190))
        span = int(W * min(1, len(data) / rate / seconds))
        chunks = np.array_split(data, max(1, span))
        mid = 18 + H_WAVE // 2
        for x, c in enumerate(chunks):
            if len(c):
                draw.line([(x, mid - c.max() * H_WAVE / 2), (x, mid - c.min() * H_WAVE / 2)], fill=(150, 190, 240))
        tile.paste(spectrogram(data, rate, seconds), (0, 18 + H_WAVE))
        tiles.append(tile)
        steps = np.flatnonzero(np.abs(np.diff(data)) > 0.25)
        if len(steps):
            clicks.append(f"{path.stem}: {len(steps)} at {', '.join(f'{s / rate:.3f}s' for s in steps[:8])}")
    sheet = Image.new("RGB", (W, sum(t.height + 6 for t in tiles)), (0, 0, 0))
    y = 0
    for t in tiles:
        sheet.paste(t, (0, y))
        y += t.height + 6
    sheet.save(out / "sheet.png")
    (out / "clicks.txt").write_text("\n".join(clicks) + ("\n" if clicks else "none\n"))
    print(f"{out / 'sheet.png'}; clicks: {len(clicks)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "era-sounds")
