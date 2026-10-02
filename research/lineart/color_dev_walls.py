"""Stand-in wall maps for developing stage 2 before stage 1's drawings exist.

    color_dev_walls.py <pic-dir> <out-dir>

Writes ``walls.png`` (thinned Canny edges of working.ppm, 8-connected, short bits dropped) and a
plain ``ink.png`` at 2x. Not a drawing: just walls with open ends, closed loops and junctions to
exercise C1/C2.
"""

import os
import sys

import cv2
import numpy as np
from PIL import Image
from skimage.morphology import skeletonize, remove_small_objects

from color_common import ink_from_walls


def dev_walls(photo: np.ndarray, low: int = 15, high: int = 45, min_len: int = 40) -> np.ndarray:
    gray = cv2.cvtColor(photo, cv2.COLOR_RGB2GRAY)
    gray = cv2.bilateralFilter(gray, 9, 40, 7)
    gray = cv2.GaussianBlur(gray, (0, 0), 1.6)
    edges = cv2.Canny(gray, low, high, L2gradient=True) > 0
    sk = skeletonize(edges)
    sk = remove_small_objects(sk, max_size=min_len - 1, connectivity=2)
    return sk


def main():
    pic, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    photo = np.asarray(Image.open(os.path.join(pic, "working.ppm")).convert("RGB"))
    walls = dev_walls(photo)
    Image.fromarray((walls * 255).astype(np.uint8)).save(os.path.join(out, "walls.png"))
    Image.fromarray(ink_from_walls(walls)).save(os.path.join(out, "ink.png"))


if __name__ == "__main__":
    main()
