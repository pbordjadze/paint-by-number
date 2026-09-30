import Foundation

/// A third-party work the template engine builds on.
nonisolated struct Acknowledgement: Identifiable, Hashable, Sendable {
    let name: String
    /// Who made it (and when, for papers).
    let credit: String
    /// What the app uses it for.
    let usage: String
    /// The copyright line of ported code; nil for published methods.
    var copyright: String?

    var id: String { name }
}

/// Credits shown in Settings › Acknowledgements and repeated in `ACKNOWLEDGEMENTS.md`
/// (`AboutTests` keeps the two in step).
nonisolated enum Acknowledgements {
    /// Swift ports of open-source libraries (`Sources/PaintCore/Vector`), used under the ISC license.
    static let code: [Acknowledgement] = [
        Acknowledgement(
            name: "Earcut",
            credit: "mapbox/earcut 3.0 by Mapbox",
            usage: "Triangulates each region's outline into the mesh the canvas paints.",
            copyright: "Copyright (c) 2016, Mapbox"),
        Acknowledgement(
            name: "Polylabel",
            credit: "mapbox/polylabel by Mapbox",
            usage: "Finds the point of a region farthest from its edges, where its number is placed.",
            copyright: "Copyright (c) 2016 Mapbox"),
    ]

    /// Published methods the template engine implements.
    static let methods: [Acknowledgement] = [
        Acknowledgement(
            name: "Potrace",
            credit: "Peter Selinger, \"Potrace: a polygon-based tracing algorithm\", 2003",
            usage: "Turns stair-stepped region outlines into smooth curves."),
        Acknowledgement(
            name: "Domain transform",
            credit: "Eduardo Gastal and Manuel Oliveira, \"Domain Transform for Edge-Aware Image and Video Processing\", 2011",
            usage: "Smooths texture into painterly patches while keeping contours sharp."),
        Acknowledgement(
            name: "Relative total variation",
            credit: "Li Xu, Qiong Yan, Yang Xia and Jiaya Jia, \"Structure Extraction from Texture via Relative Total Variation\", 2012",
            usage: "Tells texture from structure, so faces and edges keep their detail."),
        Acknowledgement(
            name: "Distance transforms",
            credit: "Pedro Felzenszwalb and Daniel Huttenlocher, \"Distance Transforms of Sampled Functions\", 2012",
            usage: "Measures how thick each region is, so every area is big enough to paint."),
        Acknowledgement(
            name: "OKLab",
            credit: "Björn Ottosson, \"A perceptual color space for image processing\", 2020",
            usage: "Compares colors the way the eye does when choosing the palette."),
        Acknowledgement(
            name: "k-means++",
            credit: "David Arthur and Sergei Vassilvitskii, \"k-means++: The Advantages of Careful Seeding\", 2007",
            usage: "Picks well-spread starting colors for the palette."),
        Acknowledgement(
            name: "Douglas-Peucker",
            credit: "David Douglas and Thomas Peucker, \"Algorithms for the reduction of the number of points required to represent a digitized line or its caricature\", 1973",
            usage: "Thins out curve points that do not change the shape."),
        Acknowledgement(
            name: "SplitMix64",
            credit: "Guy Steele, Doug Lea and Christine Flood, \"Fast Splittable Pseudorandom Number Generators\", 2014",
            usage: "Makes the same photo and settings always give the same template."),
    ]

    /// The license both ported libraries are distributed under (the copyright lines are per work).
    static let iscLicense = """
        Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

        THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
        """
}
