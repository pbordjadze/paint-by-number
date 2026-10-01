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
    /// The license ported code is distributed under; nil for published methods.
    var license: License?

    var id: String { name }
}

/// Credits shown in Settings › Acknowledgements and repeated in `ACKNOWLEDGEMENTS.md`
/// (`AboutTests` keeps the two in step).
nonisolated enum Acknowledgements {
    /// Where the source of the app, and with it the ported code below, is published.
    static let sourceRepository = "https://github.com/pbordjadze/paint-by-number"

    /// Swift ports of open-source libraries (`Sources/PaintCore/Vector`).
    static let code: [Acknowledgement] = [
        Acknowledgement(
            name: "Earcut",
            credit: "mapbox/earcut 3.0 by Mapbox",
            usage: String(
                localized: "acknowledgements.earcut.usage", defaultValue: "Triangulates each region's outline into the mesh the canvas paints.",
                comment: "What a credited third-party method or library is used for in the template engine (Earcut); shown in Settings under Acknowledgements"),
            copyright: "Copyright (c) 2016, Mapbox",
            license: .isc),
        Acknowledgement(
            name: "Polylabel",
            credit: "mapbox/polylabel by Mapbox",
            usage: String(
                localized: "acknowledgements.polylabel.usage", defaultValue: "Finds the point of a region farthest from its edges, where its number is placed.",
                comment: "What a credited third-party method or library is used for in the template engine (Polylabel); shown in Settings under Acknowledgements"),
            copyright: "Copyright (c) 2016 Mapbox",
            license: .isc),
        Acknowledgement(
            name: "Potrace",
            credit: "potrace 1.16 by Peter Selinger",
            usage: String(
                localized: "acknowledgements.potrace.usage", defaultValue: "Turns stair-stepped region outlines into smooth curves.",
                comment: "What a credited third-party method or library is used for in the template engine (Potrace); shown in Settings under Acknowledgements"),
            copyright: "Copyright (C) 2001-2019 Peter Selinger",
            license: .gpl2OrLater),
    ]

    /// What the GPL asks of anyone who receives the app: where the source of the potrace
    /// translation, and of the app it is part of, can be had.
    static var sourceNotice: String {
        String(localized: "acknowledgements.sourceNotice",
               defaultValue: "The curve fitting is a Swift translation of potrace and is used under the GNU General Public License. Its source, and that of the rest of the app, is published at \(sourceRepository).",
               comment: "GPL source notice shown in Settings under Acknowledgements; the argument is the repository URL, which must stay in the text")
    }

    /// The footer under the open-source code credits: what the ports are, then the GPL notice.
    static var codeFooter: String {
        let notice = sourceNotice
        return String(localized: "acknowledgements.codeFooter",
                      defaultValue: "Swift ports of these libraries are part of the template engine. \(notice)",
                      comment: "Footer under the Open-Source Code list in Acknowledgements; the argument is the GPL source notice")
    }

    /// Published methods the template engine implements.
    static let methods: [Acknowledgement] = [
        Acknowledgement(
            name: "Domain transform",
            credit: "Eduardo Gastal and Manuel Oliveira, \"Domain Transform for Edge-Aware Image and Video Processing\", 2011",
            usage: String(
                localized: "acknowledgements.domainTransform.usage", defaultValue: "Smooths texture into painterly patches while keeping contours sharp.",
                comment: "What a credited third-party method or library is used for in the template engine (Domain transform); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Relative total variation",
            credit: "Li Xu, Qiong Yan, Yang Xia and Jiaya Jia, \"Structure Extraction from Texture via Relative Total Variation\", 2012",
            usage: String(
                localized: "acknowledgements.rtv.usage", defaultValue: "Tells texture from structure, so faces and edges keep their detail.",
                comment: "What a credited third-party method or library is used for in the template engine (Relative total variation); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Distance transforms",
            credit: "Pedro Felzenszwalb and Daniel Huttenlocher, \"Distance Transforms of Sampled Functions\", 2012",
            usage: String(
                localized: "acknowledgements.distanceTransforms.usage", defaultValue: "Measures how thick each region is, so every area is big enough to paint.",
                comment: "What a credited third-party method or library is used for in the template engine (Distance transforms); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "OKLab",
            credit: "Björn Ottosson, \"A perceptual color space for image processing\", 2020",
            usage: String(
                localized: "acknowledgements.oklab.usage", defaultValue: "Compares colors the way the eye does when choosing the palette.",
                comment: "What a credited third-party method or library is used for in the template engine (OKLab); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "k-means++",
            credit: "David Arthur and Sergei Vassilvitskii, \"k-means++: The Advantages of Careful Seeding\", 2007",
            usage: String(
                localized: "acknowledgements.kmeans.usage", defaultValue: "Picks well-spread starting colors for the palette.",
                comment: "What a credited third-party method or library is used for in the template engine (k-means++); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Douglas-Peucker",
            credit: "David Douglas and Thomas Peucker, \"Algorithms for the reduction of the number of points required to represent a digitized line or its caricature\", 1973",
            usage: String(
                localized: "acknowledgements.douglasPeucker.usage", defaultValue: "Thins out curve points that do not change the shape.",
                comment: "What a credited third-party method or library is used for in the template engine (Douglas-Peucker); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "SplitMix64",
            credit: "Guy Steele, Doug Lea and Christine Flood, \"Fast Splittable Pseudorandom Number Generators\", 2014",
            usage: String(
                localized: "acknowledgements.splitmix.usage", defaultValue: "Makes the same photo and settings always give the same template.",
                comment: "What a credited third-party method or library is used for in the template engine (SplitMix64); shown in Settings under Acknowledgements")),
    ]
}
