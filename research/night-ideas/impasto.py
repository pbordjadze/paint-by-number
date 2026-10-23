"""Prototype: a finished painting held to the light.

Reads pbn's raster.ppm (each area in its paint) and boundaries.ppm (the lines), makes a height
field of paint (each area domed up from its edges, with brush marks along one direction per area),
and lights it from a direction that follows the device's tilt. Writes frames for a tilt sweep.

    python3 impasto.py <pbn out dir> <frames dir> [--frames 48] [--crop x,y,w,h] [--scale 1]
"""
import argparse
import os

import numpy as np
from PIL import Image
from scipy import ndimage


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)


def orientation(photo, sigma=4.0):
    """Unit vectors along the photo's local structure (the structure tensor's minor eigenvector):
    the way feathers, grass and hair run. Brush marks follow them."""
    g = photo.mean(axis=2)
    gx = ndimage.sobel(g, axis=1)
    gy = ndimage.sobel(g, axis=0)
    jxx = ndimage.gaussian_filter(gx * gx, sigma)
    jxy = ndimage.gaussian_filter(gx * gy, sigma)
    jyy = ndimage.gaussian_filter(gy * gy, sigma)
    theta = 0.5 * np.arctan2(2 * jxy, jxx - jyy)  # gradient direction
    return -np.sin(theta), np.cos(theta)          # along the structure


def lic(noise, vx, vy, length=8, steps=10):
    """Line integral convolution: the noise averaged along the field, both ways."""
    h, w = noise.shape
    acc = noise.copy()
    for sign in (1, -1):
        y, x = np.mgrid[0:h, 0:w].astype(np.float32)
        px, py = vx, vy
        for _ in range(steps):
            # keep following the field the same way it was going (it has no sign)
            fx = ndimage.map_coordinates(vx, [y, x], order=1, mode="nearest")
            fy = ndimage.map_coordinates(vy, [y, x], order=1, mode="nearest")
            flip = np.sign(fx * px + fy * py)
            flip[flip == 0] = 1
            fx, fy = fx * flip, fy * flip
            x = x + sign * fx * length / steps
            y = y + sign * fy * length / steps
            px, py = fx, fy
            acc += ndimage.map_coordinates(noise, [y, x], order=1, mode="reflect")
    return acc / (2 * steps + 1)


def height_field(painted, lines, photo, seed=7, edge=3.5, relief=1.0, brush=0.5, grain=1.0, stroke=18.0):
    """Paint thickness: each area rises from its edge over `edge` px, with brush marks that follow
    the photo's structure."""
    rng = np.random.default_rng(seed)
    inside = ~lines
    d = ndimage.distance_transform_edt(inside)
    dome = relief * (1 - np.exp(-d / edge))
    noise = ndimage.gaussian_filter(rng.standard_normal(lines.shape).astype(np.float32), grain)
    vx, vy = orientation(photo)
    marks = lic(noise, vx, vy, length=stroke, steps=14)
    marks = ndimage.gaussian_filter(marks, 0.6)
    marks /= marks.std() + 1e-6
    fade = np.clip(d / (edge * 1.5), 0, 1)  # marks settle near the edges
    return dome + brush * 0.25 * marks * fade, lines


def light(albedo_lin, hgt, tilt_x, tilt_y, gloss=0.22, shininess=110.0, ambient=0.55, groove=0.6, lines=None):
    gy, gx = np.gradient(hgt)
    n = np.dstack([-gx, -gy, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    L = np.array([np.sin(tilt_x), -np.sin(tilt_y), 1.0])
    L /= np.linalg.norm(L)
    V = np.array([0.0, 0.0, 1.0])
    H = (L + V) / np.linalg.norm(L + V)
    ndl = np.clip(n @ L, 0, 1)
    flat = L[2]
    diffuse = ambient + (1 - ambient) * ndl / flat
    spec = gloss * np.clip(n @ H, 0, 1) ** shininess
    out = albedo_lin * diffuse[..., None] + spec[..., None]
    if lines is not None:
        # The lines are the canvas showing between paint: a little shadow in the groove.
        g = ndimage.gaussian_filter(lines.astype(np.float32), 0.8)
        out *= (1 - groove * 0.35 * g)[..., None]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pbn_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--frames", type=int, default=48)
    ap.add_argument("--crop", default=None)
    ap.add_argument("--tilt", type=float, default=0.45, help="radians of tilt at the sweep's edge")
    ap.add_argument("--relief", type=float, default=1.0)
    ap.add_argument("--brush", type=float, default=0.5)
    ap.add_argument("--still", action="store_true")
    a = ap.parse_args()
    painted = load(os.path.join(a.pbn_dir, "raster.ppm"))
    bnd = load(os.path.join(a.pbn_dir, "boundaries.ppm"))
    if bnd.shape[:2] != painted.shape[:2]:
        # boundaries.ppm is drawn at 2x: render there, the paint scaled up without smoothing.
        painted = np.asarray(Image.fromarray((painted * 255).astype(np.uint8)).resize(bnd.shape[1::-1], Image.NEAREST),
                             np.float32) / 255
    lines = bnd.mean(axis=2) < 0.5
    if a.crop:
        x, y, w, h = map(int, a.crop.split(","))
        painted, lines = painted[y:y + h, x:x + w], lines[y:y + h, x:x + w]
    photo = load(os.path.join(a.pbn_dir, "working.ppm"))
    if photo.shape[:2] != painted.shape[:2]:
        photo = np.asarray(Image.fromarray((photo * 255).astype(np.uint8)).resize(painted.shape[1::-1], Image.LANCZOS),
                           np.float32) / 255
    if a.crop:
        photo = photo[y:y + h, x:x + w]
    hgt, lines = height_field(painted, lines, photo, relief=a.relief, brush=a.brush)
    alb = to_lin(painted)
    os.makedirs(a.out_dir, exist_ok=True)
    Image.fromarray((painted * 255).astype(np.uint8)).save(os.path.join(a.out_dir, "flat.png"))
    if a.still:
        for name, tx, ty in [("left", -a.tilt, 0.15), ("right", a.tilt, 0.15), ("top", 0.0, a.tilt)]:
            img = to_srgb(light(alb, hgt, tx, ty, lines=lines))
            Image.fromarray((img * 255).astype(np.uint8)).save(os.path.join(a.out_dir, f"lit-{name}.png"))
        return
    for i in range(a.frames):
        t = 2 * np.pi * i / a.frames
        img = to_srgb(light(alb, hgt, a.tilt * np.cos(t), a.tilt * 0.6 * np.sin(t), lines=lines))
        Image.fromarray((img * 255).astype(np.uint8)).save(os.path.join(a.out_dir, f"f{i:03d}.png"))


if __name__ == "__main__":
    main()
