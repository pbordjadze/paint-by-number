import CoreGraphics
import Foundation
import PaintCore
import PencilKit
import Testing
import UIKit
@testable import PaintByNumber

/// Feedback on a painting: the ink grouped into marks, the regions a mark touches, PencilKit's
/// strokes in canvas units, the report and the bundle.
@MainActor
struct FeedbackTests {
    private func stroke(
        _ points: [SIMD2<Float>], width: Float = 2, zoom: Float = 1, at seconds: Double, ink: String = "pen"
    ) -> FeedbackStroke {
        FeedbackStroke(
            points: points, width: width, ink: ink, color: "#FF3B30", zoom: zoom, date: Date(timeIntervalSinceReferenceDate: seconds))
    }

    @Test func strokesDrawnCloseTogetherMakeOneMark() {
        let strokes = [
            stroke([SIMD2(10, 10), SIMD2(40, 10)], at: 2),
            stroke([SIMD2(10, 20), SIMD2(40, 20)], at: 1),
            stroke([SIMD2(300, 300), SIMD2(330, 300)], at: 3),
        ]
        let marks = FeedbackMarks.group(strokes)
        #expect(marks.count == 2)
        // In drawing order: the mark begun first, its strokes as they were drawn.
        #expect(marks.first?.strokes == [1, 0])
        #expect(marks.first?.id == Date(timeIntervalSinceReferenceDate: 1))
        #expect(marks.last?.strokes == [2])
    }

    /// Strokes 30 units apart are close at the fitted zoom and far apart zoomed in 4×.
    @Test func reachIsOnScreenAtTheZoomStrokesWereDrawnAt() {
        let near = [stroke([SIMD2(0, 0), SIMD2(20, 0)], at: 1), stroke([SIMD2(0, 30), SIMD2(20, 30)], at: 2)]
        #expect(FeedbackMarks.group(near).count == 1)
        let zoomedIn = near.map { stroke -> FeedbackStroke in
            var zoomed = stroke
            zoomed.zoom = 4
            return zoomed
        }
        #expect(FeedbackMarks.group(zoomedIn).count == 2)
    }

    /// On three stripes (one region each): a line across the first two, and a loop drawn inside
    /// the third, whose inside counts as meant.
    @Test func regionsUnderTheInkAndInsideALoop() throws {
        let template = Fixtures.stripes()
        let line = stroke([SIMD2(5, 10), SIMD2(30, 10)], width: 2, at: 1)
        let circle = (0...24).map { i -> SIMD2<Float> in
            let a = Float(i) / 24 * 2 * .pi
            return SIMD2(50 + 7 * cos(a), 28 + 7 * sin(a))
        }
        let loop = stroke(circle, width: 1, at: 2)
        #expect(loop.isLoop)
        #expect(!line.isLoop)
        let strokes = [line, loop]
        let mark = try #require(FeedbackMarks.group(strokes).first)
        #expect(mark.strokes == [0, 1])
        let hits = Dictionary(uniqueKeysWithValues: FeedbackMarks.regions(of: mark, strokes: strokes, in: template).map { ($0.region, $0) })
        #expect(Set(hits.keys) == [0, 1, 2])
        #expect((hits[0]?.inked ?? 0) > 20 && (hits[1]?.inked ?? 0) > 10)
        #expect((hits[2]?.enclosed ?? 0) > 100)
        #expect(hits[0]?.enclosed == 0)
        #expect(hits[2]?.color == 2)
    }

    @Test func inkComesInCanvasUnitsWithItsZoom() throws {
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let controls = (0...8).map { i in
            PKStrokePoint(
                location: CGPoint(x: 10 + 10 * i, y: 10), timeOffset: Double(i) * 0.01, size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let moved = PKStroke(
            ink: PKInk(.marker, color: .systemYellow), path: PKStrokePath(controlPoints: controls, creationDate: date),
            transform: CGAffineTransform(translationX: 100, y: 50), mask: nil)
        let strokes = FeedbackInk.strokes(of: PKDrawing(strokes: [moved]), zooms: [date: 3])
        #expect(strokes.count == 1)
        let only = try #require(strokes.first)
        #expect(only.ink == "marker" && only.isHighlight)
        #expect(only.zoom == 3 && only.date == date)
        #expect(abs(only.width - 4) < 0.5)
        // Moved by its transform: along y = 60, between x = 110 and 190.
        #expect(only.points.allSatisfy { abs($0.y - 60) < 0.5 && $0.x > 105 && $0.x < 195 })
        let xs = only.points.map(\.x)
        #expect((xs.max() ?? 0) - (xs.min() ?? 0) > 50)
    }

    @Test func reportNamesMarksRegionsAndPaints() throws {
        let contents = sampleContents()
        let regions = contents.marks.map { FeedbackMarks.regions(of: $0, strokes: contents.strokes, in: contents.capture.template) }
        let report = FeedbackReport(contents, regions: regions)
        #expect(report.format == FeedbackReport.currentFormat)
        #expect(report.note == "The stripes are too plain.")
        #expect(report.marks.count == 1)
        let mark = try #require(report.marks.first)
        #expect(mark.comment == "These two" && mark.image == "mark-1.png")
        #expect(Set(mark.regions.map(\.region)) == [0, 1])
        #expect(mark.strokes.first?.points.first == [5, 10])
        #expect(report.painting.paintedRegions == [0])
        #expect(report.painting.selectedNumber == 2)
        #expect(report.painting.lineWeight == "regular")
        #expect(report.painting.sample == "great-wave" && report.painting.photo == nil)
        #expect(report.painting.paints.map(\.number) == [1, 2, 3])
        #expect(report.painting.paints.first?.hex == "#FF0000")
        #expect(report.files.contains("template.pbnt") && !report.files.contains("photo.jpg"))
        let decoded = try JSONDecoder().decode(FeedbackReport.self, from: JSONEncoder().encode(report))
        #expect(decoded.marks.first?.regions == mark.regions)
        #expect(report.markdown.contains("These two"))
        #expect(report.markdown.contains("region 0 (paint 1)"))
        #expect(report.markdown.contains("Library picture great-wave"))
    }

    /// The bundle: the painting with its marks beside a zip of everything, the folder they were
    /// written in gone.
    @Test func bundleIsAPictureAndAZip() async throws {
        let contents = sampleContents()
        let files = try await FeedbackPackage.write(contents)
        defer { ArtworkExporter.removeExport(at: files[0]) }
        let name = FeedbackPackage.bundleName(title: "Stripes", date: contents.capture.date)
        #expect(name.hasPrefix("Stripes Feedback "))
        #expect(files.map(\.lastPathComponent) == ["\(name).png", "\(name).zip"])
        let folder = files[0].deletingLastPathComponent()
        let written = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(written == ["\(name).png", "\(name).zip"])
        let zip = try Data(contentsOf: files[1])
        #expect(zip.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        let picture = try #require(ImageCodec.image(at: files[0]))
        #expect(max(picture.width, picture.height) == Int(FeedbackPackage.Layout.overviewLongSide))
        record(picture, "feedback-marked")
    }

    /// Stripes with the first painted and the second selected, a line across the first two, a
    /// note and the mark's comment.
    private func sampleContents() -> FeedbackPackage.Contents {
        let template = Fixtures.stripes()
        let session = PaintingSession(template: template)
        session.paint([0], from: SIMD2(10, 20), animated: false)
        let capture = FeedbackCapture(
            date: Date(timeIntervalSinceReferenceDate: 0), title: "Stripes", template: template, progress: session.progress,
            selectedColor: 1, nicknames: [nil, nil, nil], nicknameSeed: 7, showsNumbers: true, paper: .light,
            darkInterface: false, lineWeight: .default, visibleRect: CGRect(x: 0, y: 0, width: 60, height: 40),
            pointsPerUnit: 8, displayScale: 2, relativeZoom: 1, app: "1.0 (1)", device: "iPad16,6", system: "iPadOS 26.0",
            source: FeedbackSource(sampleName: "great-wave"))
        let strokes = [stroke([SIMD2(5, 10), SIMD2(30, 10)], at: 1)]
        let marks = FeedbackMarks.group(strokes)
        return FeedbackPackage.Contents(
            capture: capture, note: " The stripes are too plain.\n", strokes: strokes, marks: marks,
            comments: [marks[0].id: "These two"], photo: nil,
            layout: FeedbackPackage.Layout(capture: capture, marks: marks, strokes: strokes),
            ink: FeedbackPackage.Ink(overview: nil, view: nil, marks: [nil]))
    }
}
