import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import PaintByNumber

/// The lines of text Vision finds (`TextFinder`): in reading order and quantized, so Vision's
/// jitter never reaches a template; and on a note written in a handwriting face beside a printed
/// line and a small one, well-formed quadrilaterals, the same on every run, over the words when
/// Vision reads them (the simulator's Vision may read nothing), the small line too, recorded for
/// the CI report.
@MainActor
struct TextFinderTests {
    @Test func linesComeInReadingOrderQuantized() {
        let right: [SIMD2<Double>] = [SIMD2(0.5, 0.400_01), SIMD2(0.9, 0.4), SIMD2(0.9, 0.5), SIMD2(0.5, 0.5)]
        let top: [SIMD2<Double>] = [SIMD2(0.1, 0.2), SIMD2(0.4, 0.2), SIMD2(0.4, 0.3), SIMD2(0.1, 0.3)]
        let left: [SIMD2<Double>] = [SIMD2(0.1, 0.4), SIMD2(0.4, 0.4), SIMD2(0.4, 0.5), SIMD2(0.1, 0.5)]
        let lines = TextFinder.ordered([right, top, left])
        // The top line first; the other two share a top once quantized and go left to right.
        #expect(lines.map { $0[0] } == [SIMD2(0.1, 0.2), SIMD2(0.1, 0.4), SIMD2(0.5, 0.4)].map { quantized($0) })
        #expect(lines.allSatisfy { $0.allSatisfy { p in p == quantized(SIMD2(Double(p.x), Double(p.y))) } })
    }

    @Test func noteLinesAreWellFormedAndRecorded() throws {
        let size = CGSize(width: 1200, height: 900)
        let hello = CGRect(x: 180, y: 260, width: 840, height: 140), printed = CGRect(x: 180, y: 520, width: 840, height: 110)
        // Lower than Vision's default least height (1/32 of the photo), as a note's words often are.
        let small = CGRect(x: 180, y: 640, width: 840, height: 24)
        let picture = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { context in
                UIColor(red: 0.55, green: 0.4, blue: 0.3, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor(white: 0.96, alpha: 1).setFill()
                context.fill(CGRect(x: 120, y: 200, width: 960, height: 480))
                let hand = UIFont(name: "Noteworthy-Bold", size: 96) ?? UIFont.systemFont(ofSize: 96)
                ("Hello there" as NSString).draw(in: hello, withAttributes: [.font: hand, .foregroundColor: UIColor.darkGray])
                ("Printed line" as NSString).draw(
                    in: printed, withAttributes: [.font: UIFont.systemFont(ofSize: 80), .foregroundColor: UIColor.black])
                ("See you all soon" as NSString).draw(
                    in: small, withAttributes: [.font: UIFont(name: "Noteworthy-Bold", size: 18) ?? UIFont.systemFont(ofSize: 18),
                                               .foregroundColor: UIColor.darkGray])
            }
        let image = try #require(picture.cgImage)
        let lines = TextFinder.lines(in: image)
        #expect(TextFinder.lines(in: image) == lines, "the lines differ between two runs")
        for line in lines {
            #expect(line.count == 4)
            #expect(line.allSatisfy { $0.x >= -0.01 && $0.x <= 1.01 && $0.y >= -0.01 && $0.y <= 1.01 })
        }
        #expect(TextFinder.ordered(lines.map { $0.map { SIMD2(Double($0.x), Double($0.y)) } }) == lines)
        Attachment.record(Data("""
            lines: \(lines.count)
            \(lines.map { $0.map { String(format: "(%.3f, %.3f)", $0.x, $0.y) }.joined(separator: " ") }.joined(separator: "\n"))
            """.utf8), named: "text-finder-lines.txt")
        // What Vision reads lies over the words (a phrase may come as one line or a line a word):
        // every line's centre is inside one of the phrases' boxes.
        let boxes = [hello, printed, small].map { $0.insetBy(dx: -40, dy: -30) }
        var centres: [CGPoint] = []
        for line in lines {
            let centre = line.reduce(SIMD2<Float>(0, 0), +) / Float(line.count)
            let point = CGPoint(x: CGFloat(centre.x) * size.width, y: CGFloat(centre.y) * size.height)
            centres.append(point)
            #expect(boxes.contains { $0.contains(point) }, "a line found off the words: \(line)")
        }
        // Where Vision reads the big lines, it reads the small one too.
        if centres.contains(where: { hello.insetBy(dx: -40, dy: -30).contains($0) }) {
            #expect(centres.contains { small.insetBy(dx: 0, dy: -12).contains($0) }, "the small line wasn't found")
        }
    }

    private func quantized(_ p: SIMD2<Double>) -> SIMD2<Float> {
        SIMD2(Float((p.x * TextFinder.quantum).rounded() / TextFinder.quantum), Float((p.y * TextFinder.quantum).rounded() / TextFinder.quantum))
    }
}
