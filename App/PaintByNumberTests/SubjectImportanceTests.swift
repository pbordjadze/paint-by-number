import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

struct SubjectImportanceTests {
    /// Vision's rects (bottom-left origin) become top-left rects inside the image, quantized to
    /// hundredths and sorted; labels keep only the allowlist at a confidence of at least 0.3.
    @Test func hintsAreQuantizedClippedAndFiltered() throws {
        let hints = SubjectImportance.hints(
            faces: [
                CGRect(x: 0.5, y: 0.1, width: 0.1, height: 0.2),
                CGRect(x: 0.123, y: 0.456, width: 0.2049, height: 0.3),
                // Reaches past the top-left corner: clipped.
                CGRect(x: -0.1, y: 0.9, width: 0.3, height: 0.3),
                // Outside the image: dropped.
                CGRect(x: 1.2, y: 0.2, width: 0.1, height: 0.1),
            ],
            animals: [CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.5)],
            labels: [
                (identifier: "cat", confidence: 0.8123),
                (identifier: "flower", confidence: 0.304),
                (identifier: "sky", confidence: 0.29),
                (identifier: "kitchen_utensil", confidence: 0.95),
            ])

        func expect(_ rect: NormalizedRect, _ x: Float, _ y: Float, _ width: Float, _ height: Float,
                    sourceLocation: SourceLocation = #_sourceLocation) {
            for (value, expected) in [(rect.x, x), (rect.y, y), (rect.width, width), (rect.height, height)] {
                #expect(abs(value - expected) < 1e-5, "\(rect)", sourceLocation: sourceLocation)
                #expect(abs(value * 100 - (value * 100).rounded()) < 1e-3, "\(rect) isn't in hundredths",
                        sourceLocation: sourceLocation)
            }
        }
        #expect(hints.faces.count == 3)
        // Sorted from the top: the clipped corner face, the quantized one, then the low one.
        expect(hints.faces[0], 0, 0, 0.2, 0.1)
        expect(hints.faces[1], 0.12, 0.24, 0.2, 0.3)
        expect(hints.faces[2], 0.5, 0.7, 0.1, 0.2)
        #expect(hints.animals.count == 1)
        expect(hints.animals[0], 0.2, 0.3, 0.6, 0.5)

        #expect(Set(hints.labels.keys) == ["cat", "flower"])
        #expect(abs((hints.labels["cat"] ?? 0) - 0.81) < 1e-5)
        #expect(abs((hints.labels["flower"] ?? 0) - 0.3) < 1e-5)
    }

    @Test func noObservationsMeanEmptyHints() {
        #expect(SubjectImportance.hints(faces: [], animals: [], labels: []) == SubjectHints())
    }

    /// A plain synthetic image: Vision finds no faces or animals (and may find nothing at all
    /// on a simulator). The analysis still returns well-formed hints, never a crash.
    @Test func analysisOfAnImageWithoutSubjectsGivesWellFormedHints() throws {
        let width = 320, height = 240
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.55, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.3, green: 0.55, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 3))
        let image = try #require(context.makeImage())

        let analysis = SubjectImportance.analyze(image)
        #expect(analysis.hints.faces.isEmpty)
        #expect(analysis.hints.animals.isEmpty)
        for (identifier, confidence) in analysis.hints.labels {
            #expect(SubjectImportance.labelAllowlist.contains(identifier))
            #expect(confidence >= SubjectImportance.minimumLabelConfidence && confidence <= 1)
            #expect(abs(confidence * 100 - (confidence * 100).rounded()) < 1e-3)
        }
        if let map = analysis.map {
            #expect(max(map.width, map.height) == SubjectImportance.resolution)
            #expect(map.storage.allSatisfy { (0...1).contains($0) })
        }
    }
}
