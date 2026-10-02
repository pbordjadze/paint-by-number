"""Family A: coherent line drawing (Kang, Lee, Chui 2007): edge tangent flow + flow-guided DoG.

Written from the paper ("Coherent Line Drawing", NPAR 2007; details as in the TVCG 2009
follow-up "Flow-Based Image Abstraction"), on OKLab lightness L in [0, 1]:

1. Edge tangent flow (ETF). t0 = the gradient rotated 90 degrees (Sobel on L blurred by
   `pre_sigma`), normalized; g = gradient magnitude normalized to [0, 1]. Each iteration
   replaces t by the normalized sum over a box of radius `mu` of
       phi(x,y) w_d(x,y) w_m(x,y) t(y),  with phi w_d = t(x).t(y) (sign and alignment),
       w_m = (1 + tanh(eta (g(y) - g(x)))) / 2   (neighbours with stronger edges dominate),
   applied separably (a horizontal then a vertical pass), `etf_iters` times, as the paper
   suggests for speed.
2. Flow-guided DoG. F(x) = sum_t L(x + t n(x)) f(t) across the flow (n = t rotated back to
   the gradient direction), f = G_sigma_c - rho G_{1.6 sigma_c}; then
   H(x) = sum_s G_sigma_m(s) F(c_x(s)) along the ETF streamline c_x through x, traced both
   ways in unit steps (nearest tangent, flipped to keep the direction: the field is
   sign-free), F sampled bilinearly.
3. The paper binarizes: black where H < 0 and 1 + tanh(H) < tau. We return the continuous
   ink = max(0, -tanh(gain H)) so the shared hysteresis does the thresholding; `gain`
   maps L in [0, 1] to the paper's 0..255-like scale.
4. `fdog_iters` > 1 repeats step 2 on L darkened by the previous lines (the paper's
   iterated FDoG, which closes gaps along coherent contours).

Usage: python lines_flowdog.py <pic-dir> <out.png>
"""

import sys

import cv2
import numpy as np
from scipy import ndimage

import lines_common as lc

PARAMS = dict(pre_sigma=1.0, mu=5, eta=1.0, etf_iters=3, sigma_c=1.0, rho=0.99,
              sigma_m=3.0, gain=40.0, fdog_iters=2, tau=0.5)


def _shift(a, dy, dx):
    """a shifted so out[y, x] = a[y + dy, x + dx], edges clamped."""
    h, w = a.shape
    ys = np.clip(np.arange(h) + dy, 0, h - 1)
    xs = np.clip(np.arange(w) + dx, 0, w - 1)
    return a[ys][:, xs]


def edge_tangent_flow(L, pre_sigma, mu, eta, iters):
    Ls = ndimage.gaussian_filter(L, pre_sigma, mode="nearest") if pre_sigma > 0 else L
    gx = cv2.Sobel(Ls.astype(np.float32), cv2.CV_32F, 1, 0, ksize=3).astype(np.float64)
    gy = cv2.Sobel(Ls.astype(np.float32), cv2.CV_32F, 0, 1, ksize=3).astype(np.float64)
    mag = np.hypot(gx, gy)
    g = mag / max(mag.max(), 1e-12)
    nz = np.maximum(mag, 1e-12)
    tx, ty = -gy / nz, gx / nz
    flat = mag < 1e-9
    tx[flat], ty[flat] = 1.0, 0.0
    for _ in range(iters):
        for axis in (1, 0):
            ax_acc = np.zeros_like(tx)
            ay_acc = np.zeros_like(ty)
            for d in range(-mu, mu + 1):
                dy, dx = (0, d) if axis == 1 else (d, 0)
                txs, tys, gs = _shift(tx, dy, dx), _shift(ty, dy, dx), _shift(g, dy, dx)
                dot = tx * txs + ty * tys            # phi * w_d
                wm = 0.5 * (1.0 + np.tanh(eta * (gs - g)))
                w = dot * wm
                ax_acc += w * txs
                ay_acc += w * tys
            n = np.hypot(ax_acc, ay_acc)
            keep = n > 1e-12
            tx = np.where(keep, ax_acc / np.where(keep, n, 1), tx)
            ty = np.where(keep, ay_acc / np.where(keep, n, 1), ty)
    return tx.astype(np.float32), ty.astype(np.float32)


def _gauss(x, s):
    return np.exp(-x * x / (2 * s * s)) / (np.sqrt(2 * np.pi) * s)


def fdog(L, tx, ty, sigma_c, rho, sigma_m):
    h, w = L.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = ty, -tx  # gradient direction (t rotated by -90 degrees)
    sigma_s = 1.6 * sigma_c
    T = int(np.ceil(3 * sigma_s))
    Lf = L.astype(np.float32)
    F = np.zeros((h, w), np.float64)
    for t in range(-T, T + 1):
        f = _gauss(t, sigma_c) - rho * _gauss(t, sigma_s)
        sample = cv2.remap(Lf, xx + t * nx, yy + t * ny, cv2.INTER_LINEAR,
                           borderMode=cv2.BORDER_REPLICATE)
        F += f * sample
    F = F.astype(np.float32)
    S = int(np.ceil(3 * sigma_m))
    H = _gauss(0, sigma_m) * F.astype(np.float64)
    norm = _gauss(0, sigma_m)
    for sign in (1.0, -1.0):
        px, py = xx.copy(), yy.copy()
        dx, dy = sign * tx, sign * ty
        for s in range(1, S + 1):
            ix = np.clip(np.rint(px), 0, w - 1).astype(np.int32)
            iy = np.clip(np.rint(py), 0, h - 1).astype(np.int32)
            ntx, nty = tx[iy, ix], ty[iy, ix]
            flip = (ntx * dx + nty * dy) < 0
            ntx = np.where(flip, -ntx, ntx)
            nty = np.where(flip, -nty, nty)
            px, py = px + ntx, py + nty
            dx, dy = ntx, nty
            sample = cv2.remap(F, px, py, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
            gs = _gauss(s, sigma_m)
            H += gs * sample
            norm += gs
    return (H / norm).astype(np.float32)


def response(pic, **kw):
    p = dict(PARAMS, **kw)
    L = lc.rgb8_to_oklab(pic["working"])[..., 0].astype(np.float64)
    tx, ty = edge_tangent_flow(L, p["pre_sigma"], p["mu"], p["eta"], p["etf_iters"])
    cur = L
    for _ in range(p["fdog_iters"]):
        H = fdog(cur, tx, ty, p["sigma_c"], p["rho"], p["sigma_m"])
        ink = np.clip(-np.tanh(p["gain"] * H), 0, 1)
        black = (H < 0) & (1 + np.tanh(p["gain"] * H) < p["tau"])
        cur = np.where(black, np.minimum(L, 0.0), L)
    return ink.astype(np.float32)


if __name__ == "__main__":
    pic = lc.load_picture(sys.argv[1])
    lc.save_raw_png(sys.argv[2], response(pic))
