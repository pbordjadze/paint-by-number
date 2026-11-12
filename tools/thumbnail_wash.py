#!/usr/bin/env python3
"""Preview of the gallery thumbnails' wash (TemplateRasterizer.sketchColor) on a screenshot.

  tools/thumbnail_wash.py <painted.png> <out.png> <lift> <base> <chroma>

<painted.png> is a picture with every area in its paint (Refine's Painting layer, cropped from a
screenshot). Each pixel's OKLab lightness becomes base + lift × L and its chroma × chroma, as the
app does per area. The app's values are lift 0.30, base 0.68, chroma 0.5 (painting-company row
237; the old grey sketch is about 0.22, 0.76, 0). The darkest pixels (L < 0.35) are kept as ink,
which also keeps the darkest paints unwashed: a preview, unlike the app, which washes every area.
Needs numpy and Pillow.
"""
import sys

import numpy as np
from PIL import Image

def srgb_to_lin(c): return np.where(c<=0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
def lin_to_srgb(c): c=np.clip(c,0,1); return np.where(c<=0.0031308, c*12.92, 1.055*c**(1/2.4)-0.055)
M1=np.array([[0.4122214708,0.5363325363,0.0514459929],[0.2119034982,0.6806995451,0.1073969566],[0.0883024619,0.2817188376,0.6299787005]])
M2=np.array([[0.2104542553,0.7936177850,-0.0040720468],[1.9779984951,-2.4285922050,0.4505937099],[0.0259040371,0.7827717662,-0.8086757660]])
def to_ok(rgb):
    lms=np.cbrt(srgb_to_lin(rgb)@M1.T); return lms@M2.T
def from_ok(lab):
    lms=(lab@np.linalg.inv(M2).T)**3; return lin_to_srgb(lms@np.linalg.inv(M1).T)
img=np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(float)/255
lab=to_ok(img)
L,a,b=lab[...,0],lab[...,1],lab[...,2]
lift,base,chroma=[float(x) for x in sys.argv[3:6]]
ink = L<0.35  # keep the drawing's dark lines
lab2=np.stack([base+lift*L, a*chroma, b*chroma],-1)
out=from_ok(lab2)
out[ink]=img[ink]*0.6+0.4*np.array([0.45,0.46,0.49])
Image.fromarray((np.clip(out,0,1)*255).astype(np.uint8)).save(sys.argv[2])
