import Foundation
import QuartzCore
import PaintCore
import simd
import Testing
import UIKit
@testable import PaintByNumber

@MainActor
struct PaintingSessionTests {
    let template = Fixtures.mosaic

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

    /// Brute-force reference for drag painting: for every region of `color` not yet painted,
    /// the stroke parameter at which a brush of radius `r` moving from `a` to `b` first covers
    /// one of its pixel centres (checked pixel by pixel over the stroke's bounding box).
    private func capsuleReference(
        _ session: PaintingSession, from a: SIMD2<Float>, to b: SIMD2<Float>, radius r: Float, color: Int
    ) -> [Int: Float] {
        let d = b - a, len2 = simd_length_squared(d), len = len2.squareRoot()
        let xs = max(0, Int(min(a.x, b.x) - r) - 2)...min(template.width - 1, Int(max(a.x, b.x) + r) + 2)
        let ys = max(0, Int(min(a.y, b.y) - r) - 2)...min(template.height - 1, Int(max(a.y, b.y) + r) + 2)
        var enter: [Int: Float] = [:]
        for y in ys {
            for x in xs {
                let centre = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                guard let region = template.region(at: centre), !session.isPainted(region), session.colorOf(region) == color
                else { continue }
                let p = centre - a
                let along = len2 > 0 ? simd_dot(p, d) / len2 : 0
                guard simd_length_squared(p - d * min(max(along, 0), 1)) <= r * r else { continue }
                var t: Float = 0
                if len > 0 {
                    let perp2 = max(0, simd_length_squared(p) - along * along * len2)
                    t = min(max(along - max(0, r * r - perp2).squareRoot() / len, 0), 1)
                }
                enter[region] = min(enter[region] ?? .infinity, t)
            }
        }
        return enter
    }

    /// A drag paints exactly the regions (of the selected color, not yet painted) that the
    /// brush sweeps over, in the order it reaches them.
    @Test func dragPaintsExactlyTheCapsule() throws {
        var rng = SplitMix64(seed: 42)
        let radii: [Float] = [0.5, 2, 4, 7.5, 11, 18, 30]
        for trial in 0..<20 {
            let session = PaintingSession(template: template)
            // Some regions are painted already and must be left alone.
            session.paint(template.regions.indices.filter { $0 % 4 == 0 }, from: .zero, animated: false)
            let a = SIMD2(rng.nextFloat() * Float(template.width), rng.nextFloat() * Float(template.height))
            let offset = SIMD2(rng.nextFloat() - 0.5, rng.nextFloat() - 0.5) * 240
            // Every fifth stroke is a single touch (a stroke's first point).
            let b = trial % 5 == 0 ? a : a + offset
            let radius = radii[trial % radii.count]
            let color = session.colorOf(try #require(template.region(at: a)))
            session.select(color: color)

            let reference = capsuleReference(session, from: a, to: b, radius: radius, color: color)
            let event = session.drag(from: a, to: b, radius: radius)
            guard case let .painted(regions, _)? = event else {
                #expect(reference.isEmpty, "trial \(trial): nothing painted, expected \(reference.keys.sorted())")
                continue
            }
            #expect(Set(regions) == Set(reference.keys), "trial \(trial)")
            for (first, second) in zip(regions, regions.dropFirst()) {
                let e1 = reference[first] ?? .infinity, e2 = reference[second] ?? .infinity
                #expect(e1 <= e2 + 1e-4, "trial \(trial): \(first) (\(e1)) before \(second) (\(e2))")
                if e1 == e2 { #expect(first < second, "trial \(trial): ties go by region") }
            }
        }
    }

    /// However large the requested brush, a drag reaches at most `maxBrushRadius` units.
    @Test func dragRadiusIsCapped() throws {
        let centre = SIMD2(Float(template.width) / 2, Float(template.height) / 2)
        // Each region's nearest pixel centre to the brush.
        var nearest = [Float](repeating: .infinity, count: template.regions.count)
        for y in 0..<template.height {
            for x in 0..<template.width {
                let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                let region = try #require(template.region(at: p))
                nearest[region] = min(nearest[region], simd_distance(p, centre))
            }
        }
        let cap = PaintingSession.maxBrushRadius
        // A color with regions both inside and (well) outside the cap.
        let color = try #require((0..<template.palette.count).first { candidate in
            let distances = regions(ofColor: candidate).map { nearest[$0] }
            return distances.contains { $0 <= cap - 1 } && distances.contains { $0 > cap + 1 }
        })
        let session = PaintingSession(template: template)
        session.select(color: color)
        session.drag(from: centre, to: centre, radius: 500)
        for region in regions(ofColor: color) where abs(nearest[region] - cap) > 0.01 {
            #expect(session.isPainted(region) == (nearest[region] <= cap), "region \(region) at \(nearest[region])")
        }
    }

    /// Zoomed far out, the finger covers a large part of the canvas; a drag across it must
    /// still keep up, since a stroke costs what its brush sweeps: each of these 300-unit
    /// strokes scans 2.8 times the pixels of one stamp of the (capped) brush, where stamping
    /// the disc every canvas unit would scan about 300 stamps' worth. This Debug-build test
    /// shares the CPU with the parallel run, so each stroke is timed against a stamp of the
    /// same brush taken just before it on a second session, which load slows alike: the median
    /// of the 40 ratios (measured 2.4 to 3.0, single pairs up to 6.7) must stay under 10.
    @Test func zoomedOutDragIsFast() throws {
        let big = SyntheticTemplate.make(.init(width: 2048, height: 1536, columns: 24, rows: 18, seed: 11))
        let session = PaintingSession(template: big)
        let stamps = PaintingSession(template: big)
        let start = SIMD2<Float>(100, 400)
        let color = session.colorOf(try #require(big.region(at: start)))
        for painting in [session, stamps] {
            painting.select(color: color)
            painting.autoAdvance = false
        }
        // A zigzag of 40 strokes of about 300 units across the canvas.
        let points = (0...40).map { i -> SIMD2<Float> in
            SIMD2(100 + Float(i) * 46, i % 2 == 0 ? 400 : 700)
        }
        let clock = ContinuousClock()
        var ratios: [Double] = []
        var strokeTime = Duration.zero, stampTime = Duration.zero
        session.beginStroke()
        for (a, b) in zip(points, points.dropFirst()) {
            let t0 = clock.now
            stamps.drag(from: a, to: a, radius: 200)
            let t1 = clock.now
            session.drag(from: a, to: b, radius: 200)
            let t2 = clock.now
            ratios.append((t2 - t1) / (t1 - t0))
            stampTime += t1 - t0
            strokeTime += t2 - t1
        }
        session.endStroke()
        ratios.sort()
        let median = ratios[ratios.count / 2]
        func rounded(_ ratio: Double) -> String { String(format: "%.2f", ratio) }
        let report = """
            stroke ÷ stamp: median \(rounded(median)) (\(rounded(ratios[0])) to \(rounded(ratios[ratios.count - 1]))); \
            40 strokes \(strokeTime), 40 stamps \(stampTime)
            """
        Attachment.record(Data(report.utf8), named: "zoomed-out-drag-timings.txt")
        #expect(median < 10, "\(report)")

        for (a, b) in zip(points, points.dropFirst()) {
            for step in 0...40 {
                let p = a + (b - a) * (Float(step) / 40)
                let region = try #require(big.region(at: p))
                if session.colorOf(region) == color { #expect(session.isPainted(region)) }
            }
        }
        for region in big.regions.indices where session.isPainted(region) {
            #expect(session.colorOf(region) == color)
        }
    }

    /// Fills registered with an undo manager: a tap undoes alone, a stroke as a whole, and
    /// redo paints them again.
    @Test func undoManagerUndoesTapsAndWholeStrokes() throws {
        let session = PaintingSession(template: template)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let chrome = PaintChromeState()
        chrome.undoManager = undo
        chrome.observe(session, controller: CanvasController())
        let color = try #require(template.palette.indices.first { regions(ofColor: $0).count >= 4 })
        let reds = regions(ofColor: color)
        session.select(color: color)

        undo.beginUndoGrouping()
        session.paint([reds[0]], from: label(reds[0]), animated: false)
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        session.beginStroke()
        session.paint([reds[1]], from: label(reds[1]), animated: false)
        session.paint([reds[2], reds[3]], from: label(reds[2]), animated: false)
        session.endStroke()
        undo.endUndoGrouping()
        #expect(!session.isStroking)

        undo.undo()
        #expect(session.isPainted(reds[0]))
        #expect(!session.isPainted(reds[1]) && !session.isPainted(reds[2]) && !session.isPainted(reds[3]))
        undo.undo()
        #expect(!session.isPainted(reds[0]))
        #expect(!undo.canUndo)
        undo.redo()
        #expect(session.isPainted(reds[0]))
        undo.redo()
        #expect(session.isPainted(reds[1]) && session.isPainted(reds[2]) && session.isPainted(reds[3]))
        #expect(session.progress.paintedCount == 4)
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

    @Test func hintReportsTheRegionItShows() throws {
        let session = PaintingSession(template: template)
        let canvas = RecordingCanvas()
        session.canvas = canvas
        session.select(color: 4)
        let events = recordEvents(session)
        session.showHint(near: SIMD2(240, 320))
        let shown = try #require(canvas.focused.first)
        #expect(events() == [.hintShown(region: shown)])
    }

    @Test func hintWithNothingLeftStaysQuiet() {
        let session = PaintingSession(template: template)
        session.autoAdvance = false
        let canvas = RecordingCanvas()
        session.canvas = canvas
        session.select(color: 4)
        session.paint(regions(ofColor: 4), from: .zero, animated: false)
        let events = recordEvents(session)
        session.showHint(near: SIMD2(240, 320))
        #expect(events().isEmpty)
        #expect(canvas.focused.isEmpty)
    }

    /// Stripe 0 is 20 wide (inscribed radius 10): a tap 15.5 units from its nearest pixel
    /// misses the 10-unit tolerance but lands within 3× of it.
    @Test func tapBesideASmallAreaReportsAMiss() {
        let stripes = Fixtures.stripes(count: 3, stripeWidth: 20, height: 40)
        let session = PaintingSession(template: stripes)
        session.select(color: 0)
        let events = recordEvents(session)
        let event = session.tap(at: SIMD2(35, 20), tolerance: 10)
        #expect(event == .rejected(region: 1, expectedColor: 1))
        #expect(events() == [.rejected(region: 1, expectedColor: 1), .missedSmallArea(region: 0)])
        #expect(!session.isPainted(0))
    }

    /// A wide stripe nearby is easy to hit at this zoom: no zoom suggestion.
    @Test func tapBesideALargeAreaIsNoMiss() {
        let stripes = Fixtures.stripes(count: 3, stripeWidth: 60, height: 100)
        let session = PaintingSession(template: stripes)
        session.select(color: 0)
        let events = recordEvents(session)
        session.tap(at: SIMD2(70, 50), tolerance: 4)
        #expect(events() == [.rejected(region: 1, expectedColor: 1)])
    }

    /// Progress of another template is an error to handle, not a trap.
    @Test func mismatchedProgressThrows() {
        let progress = PaintProgress(regionCount: template.regions.count + 1)
        let error = #expect(throws: PaintingSession.ProgressMismatch.self) {
            try PaintingSession(template: template, progress: progress)
        }
        #expect(error?.templateRegions == template.regions.count)
        #expect(error?.progressRegions == template.regions.count + 1)
    }

    /// Frames must keep flowing: a lost completion handler would exhaust the frames-in-flight
    /// semaphore after three frames and freeze the canvas.
    @Test func rendererKeepsProducingFrames() async throws {
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: template, context: context))
        let states = template.regions.indices.map { _ in RegionState.settled(painted: false) }
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
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
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

    /// The completion bar's share picture renders once per completion, however often the bar
    /// is rebuilt, and again for a new completion.
    @Test func completionShareRendersOncePerCompletion() async throws {
        let session = PaintingSession(template: template)
        let share = CompletionShare()
        await share.prepare(for: session)
        #expect(share.picture == nil)

        for color in 0..<session.paletteCount {
            session.paint(regions(ofColor: color), from: .zero, animated: false)
        }
        #expect(session.isComplete)
        await share.prepare(for: session)
        let first = try #require(share.picture)
        await share.prepare(for: session)
        #expect(share.picture === first)

        let region = try #require(session.undo())
        session.paint([region], from: .zero, animated: false)
        #expect(session.isComplete)
        await share.prepare(for: session)
        let second = try #require(share.picture)
        #expect(second !== first)
    }

    /// With Metal (the simulator has it) the canvas draws, so the painting screen never shows
    /// its "Can't Show the Canvas" stand-in.
    @Test func canvasIsRenderableWithMetal() {
        #expect(CanvasView(session: PaintingSession(template: template)).isRenderable)
    }

    @Test func colorNamesMatchPalette() {
        let session = PaintingSession(template: template)
        #expect(session.colorNames.count == session.paletteCount)
        for (i, color) in template.palette.enumerated() {
            #expect(session.colorNames[i] == color.colorName)
        }
    }

    /// A painting's nicknames come from its seed alone: reopening it (a new session, any progress)
    /// names the colors the same, and another painting of the same photo differs.
    @Test func nicknamesFollowThePaintingsSeed() throws {
        let id = try #require(UUID(uuidString: "5F3B7A1E-0C2D-4E8F-9A6B-1D4C7E2F8A30"))
        let seed = ColorNickname.seed(for: id)
        let session = PaintingSession(template: template, nicknameSeed: seed)
        #expect(session.colorNicknames.count == session.paletteCount)
        #expect(session.colorNicknames.allSatisfy { $0 != nil })
        let reopened = try PaintingSession(
            template: template, progress: PaintProgress(regionCount: template.regions.count), nicknameSeed: seed)
        #expect(reopened.colorNicknames == session.colorNicknames)
        #expect(Set(session.colorNicknames.compactMap { $0 }).count == session.paletteCount)
        let other = PaintingSession(template: template, nicknameSeed: seed ^ 0xFFFF)
        #expect(other.colorNicknames != session.colorNicknames)
    }

    @Test func plainStyleHidesTheNicknames() {
        let session = PaintingSession(template: template, nicknameSeed: 7)
        #expect(session.colorNameStyle == .playful)
        #expect(session.nickname(of: 0) == session.colorNicknames[0])
        #expect(session.nickname(of: 0) != nil)
        session.colorNameStyle = .plain
        #expect((0..<session.paletteCount).allSatisfy { session.nickname(of: $0) == nil })
    }
}

@MainActor
final class RecordingCanvas: PaintingCanvas {
    var painted: [(regions: [Int], animated: Bool)] = []
    var unpainted: [[Int]] = []
    var focused: [Int] = []

    func session(_ session: PaintingSession, didPaint regions: [Int], from origin: SIMD2<Float>, animated: Bool) {
        painted.append((regions, animated))
    }

    func session(_ session: PaintingSession, didUnpaint regions: [Int]) { unpainted.append(regions) }

    func sessionDidChangeSelection(_ session: PaintingSession) {}

    func session(_ session: PaintingSession, focusOn region: Int) { focused.append(region) }
}
