import Foundation
import PaintCore
import Testing
@testable import MakingOf

/// What `making_of_inputs.py`'s `Template` reads out of the SVG `SVGExport` writes: the path of the
/// drawing's lines (`lines-drawing`, or a classic template's outline) and the numbers, each
/// coordinate as printed, times the picture's width over the canvas's.
struct ParsedSVG {
    var strokes: [[Point]] = []
    var numbers: [ShowTemplate.Number] = []
    var lineWidth = 0.0

    init(_ svg: String, scale: Double) throws {
        func attribute(_ name: String, in text: Substring) -> Substring? {
            guard let open = text.range(of: " \(name)=\"") ?? text.range(of: "<text \(name)=\"") else { return nil }
            let rest = text[open.upperBound...]
            return rest[..<rest.firstIndex(of: "\"")!]
        }
        let book = svg.range(of: "<g id=\"lines-drawing\"")
        let outline = svg.range(of: "stroke=\"#9ea3aa\"")
        let tag: Substring
        if let book {
            tag = svg[svg.range(of: "<path", range: book.upperBound..<svg.endIndex)!.lowerBound...]
        } else if let outline {
            tag = svg[svg[..<outline.lowerBound].range(of: "<path", options: .backwards)!.lowerBound...]
        } else {
            return
        }
        let path = tag[..<tag.range(of: "/>")!.lowerBound]
        let width = try #require(attribute("stroke-width", in: path))
        let d = try #require(attribute("d", in: path))
        lineWidth = try #require(Double(width)) * scale
        for part in d.split(separator: "M") {
            let numbers = part.split { !"-.0123456789".contains($0) }.map { Double($0)! }
            let points = stride(from: 0, to: numbers.count - 1, by: 2).map { Point(numbers[$0] * scale, numbers[$0 + 1] * scale) }
            if points.count >= 2 { strokes.append(points) }
        }
        for line in svg.split(separator: "\n") where line.hasPrefix("<text ") {
            let x = Double(attribute("x", in: line)!)!, y = Double(attribute("y", in: line)!)!, size = Double(attribute("font-size", in: line)!)!
            numbers.append(.init(x: x * scale, y: y * scale, size: size * scale))
        }
    }
}

@Suite struct ShowTemplateTests {
    private func compare(_ t: ShowTemplate, with svg: String, scale: Double) throws {
        let parsed = try ParsedSVG(svg, scale: scale)
        #expect(t.strokes.map(\.points) == parsed.strokes)
        #expect(t.numbers == parsed.numbers)
        #expect(t.lineWidth == parsed.lineWidth)
        #expect(t.scale == scale)
    }

    @Test func theFixturesSVGIsTheTemplatesRendering() throws {
        let small = try SmallShow()
        let file = try String(contentsOf: small.directory.appendingPathComponent("template.svg"), encoding: .utf8)
        #expect(SVGExport.render(small.template) == file)
    }

    @Test func linesAndNumbersAreTheSVGsAtTheSameSize() throws {
        let small = try SmallShow()
        try compare(small.show, with: SVGExport.render(small.template), scale: 1)
        #expect(small.show.strokes.count == 39)
        #expect(small.show.numbers.count == small.template.labels.count)
        #expect(small.show.lineWidth == 1.5)
    }

    @Test func aSmallerPictureScalesThem() throws {
        let small = try SmallShow()
        let shown = ShowTemplate(small.template, width: 100, height: 67)
        try compare(shown, with: SVGExport.render(small.template), scale: 100.0 / 216)
        #expect(shown.width == 100 && shown.height == 67)
    }

    @Test func aFrozenBookReadsTheSame() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: repo.appendingPathComponent("PaintCoreTests/Fixtures/template-v2-book.pbnt"))
        let t = try Template(encoded: bytes)
        #expect(t.lineArt?.style == .coloringBook)
        let width = t.width * 4 / 5, height = t.height * 4 / 5
        let shown = ShowTemplate(t, width: width, height: height)
        try compare(shown, with: SVGExport.render(t), scale: Double(width) / Double(t.width))
        #expect(!shown.strokes.isEmpty && !shown.numbers.isEmpty)
    }

    @Test func edgesComeFirstAndPaintOnlyEdgesAreNotDrawn() throws {
        let small = try SmallShow()
        let lines = try #require(small.template.lineArt)
        let drawnEdges = small.template.edges.indices.filter { lines.edgeLayers[$0] != LineLayer.color.rawValue && small.template.edges[$0].pointCount >= 2 }
        let drawnInside = lines.strokes.filter { $0.layer != LineLayer.color.rawValue && $0.pointCount >= 2 }
        #expect(small.show.strokes.count == drawnEdges.count + drawnInside.count)
        let first = small.template.points(of: small.template.edges[drawnEdges[0]])
        #expect(small.show.strokes[0].points.count == first.count)
        if let inside = drawnInside.first {
            #expect(small.show.strokes[drawnEdges.count].points.count == Int(inside.pointCount))
        }
        #expect(lines.edgeLayers.contains(LineLayer.color.rawValue) == (drawnEdges.count < small.template.edges.count))
    }

    @Test func aClassicTemplateDrawsEveryEdgeThinly() throws {
        let small = try SmallShow()
        var classic = small.template
        classic.lineArt = nil
        let shown = ShowTemplate(classic, width: 216, height: 144)
        try compare(shown, with: SVGExport.render(classic), scale: 1)
        #expect(shown.strokes.count == classic.edges.filter { $0.pointCount >= 2 }.count)
        #expect(shown.lineWidth == 0.5)
    }

    @Test func aTemplateWithoutLinesHasNone() throws {
        let small = try SmallShow()
        var bare = small.template
        bare.lineArt = nil
        bare.edges = []
        bare.ringEdges = []
        let shown = ShowTemplate(bare, width: 216, height: 144)
        #expect(shown.strokes.isEmpty)
        #expect(shown.numbers.count == bare.labels.count)
    }
}
