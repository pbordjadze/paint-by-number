"""Prototype: mixing recipes for a template's paints from a small set of real tubes.

Pipeline (all from published math, no third-party data):
- CIE 1931 2-degree observer from Wyman, Sloan & Shirley (2013) "Simple Analytic Approximations to
  the CIE XYZ Color Matching Functions" (multi-lobe piecewise Gaussians), equal-energy white
  balanced so a perfect reflector is sRGB (1, 1, 1).
- Reflectance from linear sRGB: Burns' least hyperbolic-tangent slope squared (LHTSS) smoothest
  reflectance, solved by Newton on the Lagrangian (S. A. Burns, "Numerical methods for smoothest
  reflectance reconstruction", Color Res. Appl. 2020).
- Mixing: single-constant Kubelka-Munk, K/S = (1-R)^2 / 2R mixed linearly by concentration times
  a per-tube tinting strength, R = 1 + K/S - sqrt((K/S)^2 + 2 K/S).
"""
import itertools
import numpy as np

WL = np.arange(380.0, 731.0, 10.0)  # 36 bands


def _g(x, mu, s1, s2):
    s = np.where(x < mu, s1, s2)
    return np.exp(-0.5 * ((x - mu) / s) ** 2)


def cmf(wl=WL):
    x = 1.056 * _g(wl, 599.8, 37.9, 31.0) + 0.362 * _g(wl, 442.0, 16.0, 26.7) - 0.065 * _g(wl, 501.1, 20.4, 26.2)
    y = 0.821 * _g(wl, 568.8, 46.9, 40.5) + 0.286 * _g(wl, 530.9, 16.3, 31.1)
    z = 1.217 * _g(wl, 437.0, 11.8, 36.0) + 0.681 * _g(wl, 459.0, 26.0, 13.8)
    return np.stack([x, y, z])


XYZ_TO_LIN = np.array([[3.2404542, -1.5371385, -0.4985314],
                       [-0.9692660, 1.8760108, 0.0415560],
                       [0.0556434, -0.2040259, 1.0572252]])
T = XYZ_TO_LIN @ cmf()
T = T / T.sum(axis=1, keepdims=True)  # equal-energy white -> (1,1,1)
N = len(WL)
D = np.diff(np.eye(N), axis=0)
DTD = D.T @ D


def srgb_to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)


def reflectance(lin_rgb, iters=60):
    """Smoothest reflectance in (0, 1) whose sRGB is lin_rgb (LHTSS)."""
    rgb = np.clip(np.asarray(lin_rgb, float), 1e-4, 1 - 1e-4)
    z = np.zeros(N)
    lam = np.zeros(3)
    for _ in range(iters):
        t = np.tanh(z)
        rho = (t + 1) / 2
        d1 = (1 - t * t) / 2          # d rho / dz
        d2 = -(1 - t * t) * t         # d2 rho / dz2
        F = np.concatenate([DTD @ z + d1 * (T.T @ lam), T @ rho - rgb])
        J = np.zeros((N + 3, N + 3))
        J[:N, :N] = DTD + np.diag(d2 * (T.T @ lam))
        J[:N, N:] = (T * d1).T
        J[N:, :N] = T * d1
        step = np.linalg.solve(J, -F)
        z += step[:N]
        lam += step[N:]
        if np.abs(F).max() < 1e-9:
            break
    return (np.tanh(z) + 1) / 2


def ks(r):
    return (1 - r) ** 2 / (2 * r)


def from_ks(k):
    return 1 + k - np.sqrt(k * k + 2 * k)


def lin_to_oklab(c):
    c = np.asarray(c, float)
    M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    lms = np.cbrt(np.maximum(c @ M1.T, 0))
    return lms @ M2.T


# A basic student acrylic set: name, masstone sRGB hex, scattering relative to white (two-constant
# KM with S constant per pigment and K = S * K/S of the masstone: opaque paints scatter more,
# transparent ones less). Approximations, to calibrate against painted swatches.
TUBES = [
    ("Titanium White", "#F4F3EE", 1.0),
    ("Lemon Yellow", "#F6E33A", 0.35),
    ("Cadmium Yellow", "#F7B415", 0.5),
    ("Cadmium Red", "#D4302B", 0.5),
    ("Quinacridone Magenta", "#A3215A", 0.15),
    ("Ultramarine Blue", "#2D3A9A", 0.2),
    ("Phthalo Blue", "#0B5A8C", 0.25),
    ("Burnt Umber", "#5A3A26", 0.35),
    ("Mars Black", "#26262A", 0.5),
]


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


class Set:
    def __init__(self, tubes=TUBES):
        self.names = [t[0] for t in tubes]
        self.R = np.array([reflectance(srgb_to_lin(hex_rgb(t[1]))) for t in tubes])
        self.KS = ks(self.R)
        self.strength = np.array([t[2] for t in tubes])

    def mix(self, parts):
        """parts: (M, tubes) array of parts; returns linear sRGB (M, 3)."""
        c = parts * self.strength
        k = (c @ self.KS) / c.sum(axis=1, keepdims=True)
        return from_ks(k) @ T.T


def candidate_parts(n_tubes, white=0, colors=(1, 2, 3, 4, 6), whites=(0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32)):
    """Recipes a painter can follow: some white (or none), one or two colored tubes in small whole
    parts, and maybe a touch (a quarter part) of a third."""
    others = [i for i in range(n_tubes) if i != white]
    rows, desc = [], []

    def add(items):
        v = np.zeros(n_tubes)
        for i, p in items:
            v[i] = p
        rows.append(v)
        desc.append(tuple(items))

    for wp in whites:
        base = [(white, wp)] if wp else []
        for k in (1, 2):
            for combo in itertools.combinations(others, k):
                for ps in itertools.product(colors, repeat=k):
                    if np.gcd.reduce(list(ps) + ([wp] if wp else [])) != 1:
                        continue
                    items = base + list(zip(combo, ps))
                    add(items)
                    if k == 2 or wp:
                        for third in others:
                            if third not in combo:
                                add(items + [(third, 0.25)])
    return np.array(rows), desc


def recipe_text(names, d):
    parts = []
    for i, p in sorted(d, key=lambda x: -x[1]):
        if p == 0.25:
            parts.append(f"a touch of {names[i]}")
        else:
            parts.append(f"{int(p)} {names[i]}")
    return " + ".join(parts)


def complexity(d):
    return len(d) + (0.5 if any(p == 0.25 for _, p in d) else 0) + 0.03 * sum(p for _, p in d)


class Recipes:
    def __init__(self, tubes=TUBES):
        self.set = Set(tubes)
        self.parts, self.desc = candidate_parts(len(tubes))
        self.lin = self.set.mix(self.parts)
        self.lab = lin_to_oklab(self.lin)
        self.cx = np.array([complexity(d) for d in self.desc])

    def best(self, srgb, simplicity=0.004):
        target = lin_to_oklab(srgb_to_lin(srgb))
        de = np.linalg.norm(self.lab - target, axis=1)
        score = de + simplicity * self.cx
        i = int(np.argmin(score))
        return dict(recipe=recipe_text(self.set.names, self.desc[i]), de=float(de[i]),
                    mixed=lin_to_srgb(self.lin[i]), desc=self.desc[i])


if __name__ == "__main__":
    s = Set()
    for name, h, _ in TUBES:
        r = reflectance(srgb_to_lin(hex_rgb(h)))
        back = lin_to_srgb(T @ r)
        print(f"{name:22s} {h} -> {'#%02X%02X%02X' % tuple((back * 255).round().astype(int))}  R in [{r.min():.3f},{r.max():.3f}]")
    tests = [("Lemon Yellow", "Ultramarine Blue"), ("Lemon Yellow", "Phthalo Blue"), ("Cadmium Red", "Titanium White"),
             ("Ultramarine Blue", "Burnt Umber"), ("Cadmium Yellow", "Cadmium Red"), ("Quinacridone Magenta", "Phthalo Blue")]
    for a, b in tests:
        ia, ib = s.names.index(a), s.names.index(b)
        p = np.zeros((1, len(TUBES)))
        p[0, ia] = 1
        p[0, ib] = 1
        out = lin_to_srgb(s.mix(p)[0])
        print(f"{a} + {b} = #{''.join('%02X' % v for v in (out * 255).round().astype(int))}")
