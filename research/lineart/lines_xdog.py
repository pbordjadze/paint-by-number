"""Family B: XDoG (Winnemoeller, Kyprianidis, Olsen 2012), thresholded for ink.

Written from the paper ("XDoG: An eXtended difference-of-Gaussians compendium including
advanced image stylization", Computers & Graphics 36(6), 2012). On the lightness L in [0, 1]:

    S = (1 + p) G_sigma * L  -  p G_{k sigma} * L          (the sharpened DoG, eq. 5)
    T(u) = 1                         if u >= eps
           1 + tanh(phi (u - eps))   otherwise              (soft threshold, eq. 6)

ink = 1 - T(S): 1 where the image is drawn black. A large phi makes the threshold nearly
hard, the "ink" look. L is OKLab lightness (perceptually even, so eps means the same on
dark and light pictures); the picture is first normalized so its 2nd..98th lightness
percentiles span [0.05, 0.95], which keeps one eps working across exposures, then
bilateral-filtered twice (range 0.06, space 3 px; as in Winnemoeller's 2006 abstraction
pipeline that XDoG grew out of) so film grain and JPEG noise don't ink as speckle.
sigma 1.6 (not the paper's ~1) because the working images are 1152 px: at sigma 1 every
feather and brick inks.

Usage: python lines_xdog.py <pic-dir> <out.png>
"""

import sys

import cv2
import numpy as np
from scipy import ndimage

import lines_common as lc

PARAMS = dict(sigma=1.6, k=1.6, p=24.0, eps=0.30, phi=6.0, bilateral=(0.06, 3.0), bilateral_iters=2)


def lightness(rgb):
    L = lc.rgb8_to_oklab(rgb)[..., 0].astype(np.float64)
    lo, hi = np.percentile(L, [2, 98])
    return np.clip(0.05 + 0.9 * (L - lo) / max(hi - lo, 1e-6), 0, 1)


def response(pic, **kw):
    prm = dict(PARAMS, **kw)
    sigma, k, p, eps, phi = prm["sigma"], prm["k"], prm["p"], prm["eps"], prm["phi"]
    L = lightness(pic["working"]).astype(np.float32)
    if prm["bilateral"]:
        sc, ss = prm["bilateral"]
        for _ in range(prm["bilateral_iters"]):
            L = cv2.bilateralFilter(L, -1, sc, ss)
    L = L.astype(np.float64)
    g1 = ndimage.gaussian_filter(L, sigma, mode="nearest")
    g2 = ndimage.gaussian_filter(L, k * sigma, mode="nearest")
    s = (1 + p) * g1 - p * g2
    t = np.where(s >= eps, 1.0, 1.0 + np.tanh(phi * (s - eps)))
    return np.clip(1.0 - t, 0, 1).astype(np.float32)


if __name__ == "__main__":
    pic = lc.load_picture(sys.argv[1])
    lc.save_raw_png(sys.argv[2], response(pic))
