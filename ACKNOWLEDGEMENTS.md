# Acknowledgements

Paint by Numbers builds on the work below. It is also shown in the app under
Settings › About › Acknowledgements. Everything runs on the device; none of it sends your
photos anywhere.

## Open-source code

Swift ports of these libraries (`Sources/PaintCore/Vector`) are part of the template engine.
Both are distributed under the ISC License, given in full below.

### Earcut

Triangulates each region's outline into the mesh the canvas paints.

mapbox/earcut 3.0 by Mapbox

Copyright (c) 2016, Mapbox

### Polylabel

Finds the point of a region farthest from its edges, where its number is placed.

mapbox/polylabel by Mapbox

Copyright (c) 2016 Mapbox

### ISC License

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

## Methods

Published techniques the template engine builds on.

### Potrace

Turns stair-stepped region outlines into smooth curves.

Peter Selinger, "Potrace: a polygon-based tracing algorithm", 2003

### Domain transform

Smooths texture into painterly patches while keeping contours sharp.

Eduardo Gastal and Manuel Oliveira, "Domain Transform for Edge-Aware Image and Video Processing", 2011

### Relative total variation

Tells texture from structure, so faces and edges keep their detail.

Li Xu, Qiong Yan, Yang Xia and Jiaya Jia, "Structure Extraction from Texture via Relative Total Variation", 2012

### Distance transforms

Measures how thick each region is, so every area is big enough to paint.

Pedro Felzenszwalb and Daniel Huttenlocher, "Distance Transforms of Sampled Functions", 2012

### OKLab

Compares colors the way the eye does when choosing the palette.

Björn Ottosson, "A perceptual color space for image processing", 2020

### k-means++

Picks well-spread starting colors for the palette.

David Arthur and Sergei Vassilvitskii, "k-means++: The Advantages of Careful Seeding", 2007

### Douglas-Peucker

Thins out curve points that do not change the shape.

David Douglas and Thomas Peucker, "Algorithms for the reduction of the number of points required to represent a digitized line or its caricature", 1973

### SplitMix64

Makes the same photo and settings always give the same template.

Guy Steele, Doug Lea and Christine Flood, "Fast Splittable Pseudorandom Number Generators", 2014
