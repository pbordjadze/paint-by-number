import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The subjects' silhouettes (`ObjectFinder`, Vision's foreground instance mask traced by
/// `MaskContours`), on the red fox: well-formed polygons, the fox among them when Vision finds
/// it, and an overlay attached so the mask's fit can be judged from the CI report.
struct ObjectFinderTests {
    @Test func foxSilhouetteIsWellFormedAndRecorded() throws {
        let url = try #require(Bundle.main.url(forResource: "red-fox", withExtension: "jpg"))
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 1152)
        let image = try #require(PhotoLoader.cgImage(from: photo))
        let objects = ObjectFinder.objects(in: image)
        let again = ObjectFinder.objects(in: image)
        #expect(objects == again, "the subjects differ between two runs")
        var shares: [Double] = []
        for polygon in objects {
            #expect(polygon.count >= 3)
            #expect(polygon.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 })
            var sum = 0.0
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                sum += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
            }
            shares.append(abs(sum) / 2)
        }
        // Largest first, each a subject: at least the mask's minimum share of the frame.
        #expect(shares == shares.sorted(by: >))
        #expect(shares.allSatisfy { $0 >= Double(MaskContours.minimumArea) * 0.5 })
        Attachment.record(Data("""
            subjects: \(objects.count), shares of the frame: \(shares.map { String(format: "%.3f", $0) }.joined(separator: " ")), \
            points: \(objects.map(\.count))
            """.utf8), named: "fox-subjects.txt")
        if let overlay = Self.overlay(objects, on: image), let png = ImageCodec.pngData(overlay) {
            Attachment.record(png, named: "fox-subjects.png")
        }
        // The simulator's Vision may find nothing; on a device the fox is the subject.
        if let largest = shares.first {
            #expect(largest > 0.08 && largest < 0.6, "the largest subject covers \(largest) of the frame")
        }
    }

    /// The photo with each polygon drawn over it in red.
    static func overlay(_ polygons: [[SIMD2<Float>]], on image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Polygons are y-down; the context is y-up.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.setLineWidth(3)
        for polygon in polygons where polygon.count >= 2 {
            ctx.move(to: CGPoint(x: CGFloat(polygon[0].x) * CGFloat(w), y: CGFloat(polygon[0].y) * CGFloat(h)))
            for p in polygon.dropFirst() { ctx.addLine(to: CGPoint(x: CGFloat(p.x) * CGFloat(w), y: CGFloat(p.y) * CGFloat(h))) }
            ctx.closePath()
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}
