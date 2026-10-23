"""How much of the canvas paint 1 covers, and its rank by area, for pbn generate output dirs.

    python3 first-paint.py <pbn out dir>...
"""
import json
import sys

import numpy as np
from PIL import Image

for d in sys.argv[1:]:
    s = json.load(open(f"{d}/stats.json"))
    a = np.asarray(Image.open(f"{d}/raster.ppm").convert("RGB")).reshape(-1, 3).astype(int)
    keys = a[:, 0] * 65536 + a[:, 1] * 256 + a[:, 2]
    count = {i + 1: int((keys == int(h, 16)).sum()) for i, h in enumerate(s["palette"])}
    total = sum(count.values())
    order = sorted(count, key=lambda k: -count[k])
    print(f"{d}: paint 1 covers {100 * count[1] / total:.1f}% (rank {order.index(1) + 1}/{len(count)}); "
          f"the largest, {order[0]}, {100 * count[order[0]] / total:.0f}%")
