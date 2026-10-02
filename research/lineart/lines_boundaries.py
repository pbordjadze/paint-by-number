"""Family C: pbn's own region boundaries, kept where the contrast across them is strong.

raster.ppm is pbn's color segmentation (each pixel carries its paint). A pixel is on a
boundary when its right or lower neighbour has another paint (a 1 px line). Its strength is
the geometric mean of
  - the photo's OKLab gradient magnitude there (Gaussian derivatives, sigma 1.2), over
    GRAD_REF: a real edge is steep, a posterized gradient's ring boundary is not, and
  - the paint deltaE across it (largest of the right/lower differences), over PAINT_REF,
each clipped to [0, 1], then averaged along the boundary (normalized convolution over
boundary pixels, sigma 2 px) so a boundary does not flicker on and off. The shared cleanup's
hysteresis then keeps strong boundaries and continues them through weaker stretches, and its
fragment pruning drops short ones.

Usage: python lines_boundaries.py <pic-dir> <out.png>
"""

import sys

import numpy as np
from scipy import ndimage

import lines_common as lc

GRAD_REF = 0.045
PAINT_REF = 0.16
ALONG_SIGMA = 2.0


def response(pic):
    raster = pic["raster"]
    key = (raster[..., 0].astype(np.int64) << 16) | (raster[..., 1].astype(np.int64) << 8) | raster[..., 2]
    rlab = lc.rgb8_to_oklab(raster)
    h, w = key.shape
    bnd = np.zeros((h, w), bool)
    paint = np.zeros((h, w), np.float32)
    right = key[:, :-1] != key[:, 1:]
    down = key[:-1, :] != key[1:, :]
    bnd[:, :-1] |= right
    bnd[:-1, :] |= down
    de_r = np.linalg.norm(rlab[:, :-1] - rlab[:, 1:], axis=2)
    de_d = np.linalg.norm(rlab[:-1, :] - rlab[1:, :], axis=2)
    paint[:, :-1] = np.maximum(paint[:, :-1], np.where(right, de_r, 0))
    paint[:-1, :] = np.maximum(paint[:-1, :], np.where(down, de_d, 0))
    grad = lc.oklab_gradient(lc.rgb8_to_oklab(pic["working"]), 1.2)
    s = np.sqrt(np.clip(grad / GRAD_REF, 0, 1) * np.clip(paint / PAINT_REF, 0, 1))
    s = np.where(bnd, s, 0).astype(np.float64)
    num = ndimage.gaussian_filter(s, ALONG_SIGMA, mode="nearest")
    den = ndimage.gaussian_filter(bnd.astype(np.float64), ALONG_SIGMA, mode="nearest")
    sm = np.where(bnd, num / np.maximum(den, 1e-9), 0)
    return np.clip(sm, 0, 1).astype(np.float32)


if __name__ == "__main__":
    pic = lc.load_picture(sys.argv[1])
    lc.save_raw_png(sys.argv[2], response(pic))
