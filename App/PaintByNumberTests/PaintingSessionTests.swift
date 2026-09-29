import Foundation
import QuartzCore
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

@MainActor
struct PaintingSessionTests {
    let template = SyntheticTemplate.make(.init(width: 480, height: 640, columns: 6, rows: 8, seed: 3))

    private func label(_ region: Int) -> SIMD2<Float> { template.labels(ofRegion: region).first!.position }

    private func regions(ofColor color: Int) -> [Int] {
        template.regions.indices.filter { Int(template.regions[$0].colorIndex) == color }
    }

    private func recordEvents(_ session: PaintingSession) -> () -> [PaintEvent] {
        final class Log { var events: [PaintEvent] = [] }
        let log = Log()
        session.onEvent { log.events.append($0) }
        return { log.events }
    }

    @Test func tapPaintsRegionOfSelectedColor() {
        let session = PaintingSession(template: template)
        let r = template.regions.indices.max { template.regions[$0].area < template.regions[$1].area }!
        let color = session.colorOf(r)
        session.select(color: color)
        let event = session.tap(at: label(r), tolerance: 0)
        #expect(event == .painted(regions: [r], color: color))
        #expect(session.isPainted(r))
        #expect(session.remainingByColor[color] == session.totalByColor[color] - 1)
        #expect(session.revision == 1)
    }

    @Test func toleranceReachesANearbySmallRegion() throws {
        let session = PaintingSession(template: template)
        // A small region with a differently colored host around it (a disc or blob).
        let candidates = template.regions.indices.filter { r in
            guard let l = template.labels(ofRegion: r).first, template.regions[r].area < 1500 else { return false }
            let outside = l.position + SIMD2(l.radius + 1.5, 0)
            guard let host = template.region(at: outside) else { return false }
            return host != r && session.colorOf(host) != session.colorOf(r)
        }
        let r = try #require(candidates.first)
        let l = template.labels(ofRegion: r).first!
        session.select(color: session.colorOf(r))
        let event = session.tap(at: l.position + SIMD2(l.radius + 1.5, 0), tolerance: 6)
        #expect(event == .painted(regions: [r], color: session.colorOf(r)))
    }

    @Test func wrongColorIsRejected() {
        let session = PaintingSession(template: template)
        let r = 0
        let other = (session.colorOf(r) + 1) % session.paletteCount
        session.select(color: other)
        let events = recordEvents(session)
        let event = session.tap(at: label(r), tolerance: 0)
        #expect(event == .rejected(region: r, expectedColor: session.colorOf(r)))
        #expect(!session.isPainted(r))
        #expect(events() == [.rejected(region: r, expectedColor: session.colorOf(r))])
    }

    @Test func tapOnPaintedRegionDoesNothing() {
        let session = PaintingSession(template: template)
        let r = 0
        session.select(color: session.colorOf(r))
        session.tap(at: label(r), tolerance: 0)
        #expect(session.tap(at: label(r), tolerance: 0) == nil)
    }

    @Test func dragPaintsOnlyMatchingRegions() {
        let session = PaintingSession(template: template)
        let color = session.colorOf(0)
        session.select(color: color)
        let from = SIMD2<Float>(2, 2), to = SIMD2(Float(template.width) - 2, Float(template.height) - 2)
        let event = session.drag(from: from, to: to, radius: 4)
        guard case let .painted(regions, paintedColor)? = event else {
            Issue.record("diagonal drag should paint something of color \(color)")
            return
        }
        #expect(paintedColor == color)
        #expect(!regions.isEmpty)
        for r in template.regions.indices {
            #expect(session.isPainted(r) == regions.contains(r))
            if session.isPainted(r) { #expect(session.colorOf(r) == color) }
        }
    }

    @Test func undoRevertsTheLastFill() {
        let session = PaintingSession(template: template)
        let canvas = RecordingCanvas()
        session.canvas = canvas
        let a = regions(ofColor: 0)[0], b = regions(ofColor: 1)[0]
        session.select(color: 0)
        session.tap(at: label(a), tolerance: 0)
        session.select(color: 1)
        session.tap(at: label(b), tolerance: 0)
        let events = recordEvents(session)
        session.undo()
        #expect(!session.isPainted(b))
        #expect(session.isPainted(a))
        #expect(session.remainingByColor[1] == session.totalByColor[1])
        #expect(events() == [.undone(region: b)])
        #expect(canvas.unpainted == [[b]])
        #expect(canvas.painted.map(\.regions) == [[a], [b]])
        let allAnimated = canvas.painted.allSatisfy { $0.animated }
        #expect(allAnimated)
    }

    @Test func completingAColorAdvancesToTheNextOne() {
        let session = PaintingSession(template: template)
        session.select(color: 2)
        let events = recordEvents(session)
        let all = regions(ofColor: 2)
        session.paint(all, from: .zero, animated: false)
        #expect(session.isColorComplete(2))
        #expect(events().contains(.colorCompleted(2)))
        #expect(session.selectedColor == session.nextIncompleteColor(after: 2))
        #expect(session.selectedColor != 2)
    }

    @Test func paintingEverythingCompletesTheArtwork() {
        let session = PaintingSession(template: template)
        let events = recordEvents(session)
        for color in 0..<session.paletteCount {
            session.paint(regions(ofColor: color), from: .zero, animated: false)
        }
        #expect(session.isComplete)
        #expect(session.fractionComplete == 1)
        #expect(events().last == .artworkCompleted)
        let completed = events().compactMap { event -> Int? in
            if case let .colorCompleted(c) = event { return c }
            return nil
        }
        #expect(completed == Array(0..<session.paletteCount))
    }

    @Test func resetClearsPaintAndReselects() {
        let session = PaintingSession(template: template)
        let canvas = RecordingCanvas()
        session.canvas = canvas
        session.paint([0, 1, 2], from: .zero, animated: false)
        session.reset()
        #expect(session.progress.paintedCount == 0)
        #expect(session.remainingByColor == session.totalByColor)
        #expect(Set(canvas.unpainted.flatMap { $0 }) == [0, 1, 2])
    }

    @Test func hintFocusesAnUnpaintedRegionOfTheSelectedColor() {
        let session = PaintingSession(template: template)
        let canvas = RecordingCanvas()
        session.canvas = canvas
        session.select(color: 4)
        session.showHint(near: SIMD2(240, 320))
        let focused = canvas.focused
        #expect(focused.count == 1)
        if let r = focused.first {
            #expect(session.colorOf(r) == 4)
            #expect(!session.isPainted(r))
        }
    }

    @Test func progressSurvivesEncoding() throws {
        let session = PaintingSession(template: template)
        session.paint([3, 1, 4, 1, 5, 9, 2, 6], from: .zero, animated: false)
        let data = session.progress.encoded()
        let decoded = try PaintProgress(encoded: data)
        #expect(decoded == session.progress)
        #expect(decoded.log.map(\.region) == [3, 1, 4, 5, 9, 2, 6])
        let restored = PaintingSession(template: template, progress: decoded)
        #expect(restored.remainingByColor == session.remainingByColor)
        #expect(throws: (any Error).self) { try PaintProgress(encoded: data.prefix(10)) }
    }

    /// Frames must keep flowing: a lost completion handler would exhaust the frames-in-flight
    /// semaphore after three frames and freeze the canvas.
    @Test func rendererKeepsProducingFrames() async throws {
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: template, context: context))
        let states = template.regions.indices.map { RegionState.settled(painted: false, origin: .zero, seed: 0) }
        let renderer = try #require(CanvasRenderer(scene: scene, context: context, states: states))
        let layer = CAMetalLayer()
        layer.device = context.device
        layer.pixelFormat = RenderContext.colorFormat
        layer.drawableSize = CGSize(width: 240, height: 320)
        let uniforms = CanvasSnapshot.uniforms(scene: scene, width: 240, height: 320, options: .preview)
        var drawn = 0
        for _ in 0..<12 {
            if renderer.draw(in: layer, uniforms: uniforms, content: RenderContext.Content()) { drawn += 1 }
            try await Task.sleep(for: .milliseconds(40))
        }
        #expect(drawn >= 10)
    }

    /// The on-screen canvas animates a tapped fill: the region's paint state starts now and
    /// the display link keeps presenting frames while it spreads.
    @Test func liveCanvasAnimatesATap() async throws {
        let session = PaintingSession(template: template)
        let view = CanvasView(session: session)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.addSubview(view)
        view.frame = window.bounds
        window.isHidden = false
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let before = view.framesRendered
        let r = template.regions.indices.max { template.regions[$0].area < template.regions[$1].area }!
        session.select(color: session.colorOf(r))
        session.tap(at: label(r), tolerance: 0)
        let state = try #require(view.regionState(r))
        #expect(state.painted == 1)
        #expect(state.duration > 0.2)
        try await Task.sleep(for: .milliseconds(500))
        #expect(view.framesRendered > before + 5, "frames before \(before), after \(view.framesRendered)")
        window.isHidden = true
    }

    @Test func canvasFitsAndCentresTheArtwork() {
        let session = PaintingSession(template: template)
        let view = CanvasView(session: session)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.chromeInsets = UIEdgeInsets(top: 100, left: 0, bottom: 120, right: 0)
        view.layoutIfNeeded()
        let center = view.visibleCenter
        #expect(abs(center.x - Float(template.width) / 2) < 1)
        #expect(abs(center.y - Float(template.height) / 2) < 1)
        #expect(session.canvas === view)
    }
}

@MainActor
final class RecordingCanvas: PaintingCanvas {
    var painted: [(regions: [Int], animated: Bool)] = []
    var unpainted: [[Int]] = []
    var selections = 0
    var focused: [Int] = []

    func session(_ session: PaintingSession, didPaint regions: [Int], from origin: SIMD2<Float>, animated: Bool) {
        painted.append((regions, animated))
    }

    func session(_ session: PaintingSession, didUnpaint regions: [Int]) { unpainted.append(regions) }

    func sessionDidChangeSelection(_ session: PaintingSession) { selections += 1 }

    func session(_ session: PaintingSession, focusOn region: Int) { focused.append(region) }
}
