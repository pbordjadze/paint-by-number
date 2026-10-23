import Foundation
import Observation
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
        chrome.observe(session)
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

    /// Finishing the selected color selects the next color left after it, so the painter carries
    /// on where they were (QA, October 21: finishing 16 of 22 sent them back to 1); finished
    /// colors are passed over.
    @Test func completingAColorSelectsTheNextColorLeft() throws {
        let session = PaintingSession(template: template)
        let last = session.paletteCount - 1
        try #require(last >= 4)
        session.select(color: 2)
        let events = recordEvents(session)
        session.paint(regions(ofColor: 2), from: .zero, animated: false)
        #expect(session.isColorComplete(2))
        #expect(events().contains(.colorCompleted(2)))
        #expect(session.selectedColor == 3)
        // Another color finished meanwhile leaves the selection alone, and is passed over.
        session.paint(regions(ofColor: 4), from: .zero, animated: false)
        #expect(session.selectedColor == 3)
        session.paint(regions(ofColor: 3), from: .zero, animated: false)
        #expect(session.selectedColor == (last >= 5 ? 5 : 0))
    }

    /// An order by areas left (Nearly Done, Most Left) re-sorts as the painting goes: finishing a
    /// color there selects the first swatch left, the order's own next.
    @Test func anOrderByAreasLeftGoesToItsFirstSwatch() {
        #expect(PaletteOrder.allCases.filter(\.followsProgress) == [.nearlyDone, .mostLeft])
        let session = PaintingSession(template: template)
        session.advancesToFirstLeft = true
        session.select(color: 2)
        session.paint(regions(ofColor: 2), from: .zero, animated: false)
        #expect(session.selectedColor == 0)
    }

    /// The next color goes by the palette's order on screen and comes round past its end; a
    /// begun painting opens on its first swatch.
    @Test func theNextColorFollowsThePalettesOrder() throws {
        let last = template.palette.count - 1
        try #require(last >= 3)
        // Begun, so it opens by the palette's order: one area painted of a color that has more.
        let begun = try #require((0...last).first { regions(ofColor: $0).count >= 2 })
        var progress = PaintProgress(regionCount: template.regions.count)
        progress.paint(regions(ofColor: begun)[0])
        let session = try PaintingSession(template: template, progress: progress)
        // In the palette's order on screen: here backwards, so the last number leads.
        session.colorOrder = Array((0...last).reversed())
        #expect(session.selectedColor == last, "The palette's first swatch wasn't selected as it showed")
        session.select(color: 2)
        session.paint(regions(ofColor: 2), from: .zero, animated: false)
        #expect(session.selectedColor == 1)
        session.select(color: 0)
        session.paint(regions(ofColor: 0), from: .zero, animated: false)
        #expect(session.selectedColor == last)
    }

    /// A painting nobody has painted on opens on the color of its largest area, whatever the
    /// palette's order, and so does one started over (`OpeningColor`); by number, 1 was often a
    /// few slivers the opening zoom doesn't show.
    @Test func aFreshPaintingOpensOnItsLargestAreasColor() throws {
        // The largest area, ties going to the lower number.
        let region = try #require(template.regions.indices.max { a, b in
            let ra = template.regions[a], rb = template.regions[b]
            return ra.area != rb.area ? ra.area < rb.area : ra.colorIndex > rb.colorIndex
        })
        let largest = Int(template.regions[region].colorIndex)
        #expect(OpeningColor.largestArea(in: template) == largest)
        let last = template.palette.count - 1
        // Where the opening color is the first by number, the palette's first swatch takes over.
        let opening = OpeningColor.isLargestArea ? largest : 0, shown = OpeningColor.isLargestArea ? largest : last
        let session = PaintingSession(template: template)
        #expect(session.selectedColor == opening)
        session.colorOrder = Array((0...last).reversed())
        #expect(session.selectedColor == shown, "The palette's order moved the largest area's color")
        let other = (largest + 1) % template.palette.count
        session.select(color: other)
        session.paint([regions(ofColor: other)[0]], from: .zero, animated: false)
        session.reset()
        #expect(session.selectedColor == shown, "Started over, the painting didn't open as a fresh one")
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

    /// Zen Mode: a moment after a fill, the canvas is sent to an area of the selected color
    /// still to paint; quick fills in a row send it once, from the last.
    @Test func zenModeMovesOnAfterTheLastFill() async throws {
        let session = PaintingSession(template: template)
        session.autoAdvance = false
        let canvas = RecordingCanvas()
        session.canvas = canvas
        session.flowsToNextArea = true
        session.select(color: 4)
        let areas = regions(ofColor: 4)
        try #require(areas.count >= 3)
        session.paint([areas[0]], from: .zero, animated: false)
        session.paint([areas[1]], from: .zero, animated: false)
        #expect(canvas.focused.isEmpty)
        try await waitUntil(timeout: .seconds(5)) { !canvas.focused.isEmpty }
        try await Task.sleep(for: PaintingSession.zenPause * 2)
        #expect(canvas.focused.count == 1)
        let next = try #require(canvas.focused.first)
        #expect(session.colorOf(next) == 4 && !session.isPainted(next))
    }

    @Test func withoutZenModeAFillStaysPut() async throws {
        let session = PaintingSession(template: template)
        let canvas = RecordingCanvas()
        session.canvas = canvas
        session.select(color: 4)
        session.paint([regions(ofColor: 4)[0]], from: .zero, animated: false)
        try await Task.sleep(for: PaintingSession.zenPause * 2)
        #expect(canvas.focused.isEmpty)
    }

    /// Zen Mode stays on a fill or stroke that finished a color while the color shines, then
    /// flies to the next color's areas; under Reduce Motion nothing shines and the usual pause
    /// holds.
    @Test(arguments: [false, true], [false, true])
    func zenModeWaitsOutAFinishedColorsShine(reduceMotion: Bool, stroke: Bool) async throws {
        let session = PaintingSession(template: template)
        let canvas = RecordingCanvas()
        session.canvas = canvas
        session.flowsToNextArea = true
        session.reduceMotion = reduceMotion
        session.select(color: 4)
        let clock = ContinuousClock()
        let painted = clock.now
        if stroke { session.beginStroke() }
        session.paint(regions(ofColor: 4), from: .zero, animated: false)
        if stroke { session.endStroke() }
        #expect(session.isColorComplete(4))
        let next = try #require(session.selectedColor)
        try await waitUntil(timeout: .seconds(5)) { !canvas.focused.isEmpty }
        let waited = clock.now - painted
        if reduceMotion {
            #expect(waited < PaintingSession.zenShinePause)
        } else {
            #expect(waited >= PaintingSession.zenShinePause)
        }
        let shown = try #require(canvas.focused.first)
        #expect(session.colorOf(shown) == next && !session.isPainted(shown))
    }

    /// A finished painting opens with no color on the brush; undoing a fill picks up the
    /// color of the area it freed, so the painter can paint it again at once.
    @Test func undoOnAFinishedPaintingSelectsTheFreedColor() throws {
        var progress = PaintProgress(regionCount: template.regions.count)
        for r in template.regions.indices { _ = progress.paint(r) }
        let session = try PaintingSession(template: template, progress: progress)
        #expect(session.isComplete && session.selectedColor == nil)
        let region = try #require(session.undo())
        #expect(session.selectedColor == session.colorOf(region))
        session.paint([region], from: .zero, animated: false)
        let picked = (session.colorOf(region) + 1) % session.paletteCount
        session.select(color: picked)
        session.undo()
        #expect(session.selectedColor == picked, "a color on the brush stays")
    }

    /// A stroke paints the color it began with: finishing that color moves the palette's
    /// selection on at once, but the rest of the stroke does not fill the next color's areas.
    @Test func strokeKeepsItsColorAfterAutoAdvance() throws {
        let session = PaintingSession(template: template)
        session.select(color: 4)
        session.beginStroke()
        session.paint(regions(ofColor: 4), from: .zero, animated: false)
        #expect(session.isColorComplete(4))
        let next = try #require(session.selectedColor)
        #expect(next != 4, "the selection moved on")
        let area = try #require(regions(ofColor: next).first)
        #expect(session.drag(from: label(area), to: label(area), radius: 2) == nil)
        #expect(session.tap(at: label(area), tolerance: 0) == .rejected(region: area, expectedColor: next))
        #expect(!session.isPainted(area))
        session.endStroke()

        session.beginStroke()
        #expect(session.drag(from: label(area), to: label(area), radius: 2) != nil)
        session.endStroke()
        #expect(session.isPainted(area))
    }

    /// Replay ends when the session changes under it: the canvas shows what the session holds,
    /// not the log the replay started from.
    @Test func replayEndsWhenTheSessionChangesUnderIt() async throws {
        let session = PaintingSession(template: template)
        let view = CanvasView(session: session)
        view.reduceMotion = true
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.layoutIfNeeded()
        session.paint(Array(template.regions.indices), from: .zero, animated: false)
        view.replay()
        let undone = try #require(session.undo())
        func expectsTheSession(_ note: Comment) throws {
            for r in template.regions.indices {
                let state = try #require(view.regionState(r))
                #expect(state.painted == (r == undone ? 0 : 1), note)
            }
        }
        try expectsTheSession("right after the undo")
        // The replay would have refilled everything once its lift was over.
        try await Task.sleep(for: .milliseconds(700))
        try expectsTheSession("after the replay's schedule began")
    }

    /// The progress badge shows what the replay has on the canvas (`replayed`), while the painting
    /// itself stays whole.
    @Test func aReplayShowsFewerAreasThanThePaintingHolds() {
        let session = PaintingSession(template: template)
        session.paint(Array(template.regions.indices), from: .zero, animated: false)
        let total = template.regions.count
        #expect(session.shownFraction == 1)
        #expect(session.shownPaintedByColor == session.totalByColor)

        let revision = session.revision
        #expect(!session.isReplaying)
        session.showReplayed(0)
        #expect(session.isReplaying, "Undo and Replay wait while a replay plays")
        #expect(session.shownFraction == 0)
        #expect(session.shownPaintedByColor.allSatisfy { $0 == 0 })
        #expect(session.isComplete && session.progress.paintedCount == total && session.revision == revision)

        // The first areas of the stroke log, in the order they were painted.
        let half = total / 2
        session.showReplayed(half)
        #expect(session.shownFraction == Double(half) / Double(total))
        var expected = [Int](repeating: 0, count: session.paletteCount)
        for stroke in session.progress.log.prefix(half) { expected[session.colorOf(Int(stroke.region))] += 1 }
        #expect(session.shownPaintedByColor == expected)
        #expect(session.shownPaintedByColor.reduce(0, +) == half)

        session.showReplayed(total + 100)
        #expect(session.replayed == total, "never more than the painting has")
        session.showReplayed(nil)
        #expect(session.replayed == nil && session.shownFraction == 1 && !session.isReplaying)
    }

    /// A replay tells the session how much is on the canvas, and lets go of it when the session
    /// changes under it (as the replay itself does).
    @Test func aReplayTellsTheSessionWhatIsOnTheCanvas() async throws {
        let session = PaintingSession(template: template)
        let view = CanvasView(session: session)
        view.reduceMotion = true
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.layoutIfNeeded()
        session.paint(Array(template.regions.indices), from: .zero, animated: false)
        #expect(session.replayed == nil)
        view.replay()
        // Under Reduce Motion the paint is gone at once, and then the areas fill one after another.
        try await waitUntil(timeout: .seconds(10)) { session.replayed == 0 }
        #expect(session.isComplete, "the painting is whole while its replay plays")
        try await waitUntil(timeout: .seconds(10)) { (session.replayed ?? 0) >= 3 }
        #expect((session.replayed ?? 0) < template.regions.count, "the whole painting is not back yet")
        #expect(session.shownFraction < 1)

        try #require(session.undo() != nil)
        #expect(session.replayed == nil, "a replay the session changed under tells the screen nothing more")
        #expect(session.shownFraction < 1 && session.shownFraction > 0)
    }

    /// The completion bar's Stop: the replay ends where it is and the painting shows whole, with
    /// nothing taken from it.
    @Test func stoppingAReplayShowsThePaintingWhole() async throws {
        let session = PaintingSession(template: template)
        let view = CanvasView(session: session)
        view.reduceMotion = true
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.layoutIfNeeded()
        session.paint(Array(template.regions.indices), from: .zero, animated: false)
        let revision = session.revision
        view.replay()
        try await waitUntil(timeout: .seconds(10)) { session.isReplaying }
        view.stopReplay()
        #expect(!session.isReplaying && session.shownFraction == 1)
        #expect(session.isComplete && session.revision == revision, "stopping changed the painting")
        view.stopReplay()
        #expect(!session.isReplaying, "a second Stop does nothing")
    }

    /// The painting screen going takes its replay with it: nothing plays on over the next screen,
    /// to finish there and announce the night to VoiceOver.
    @Test func tearingTheCanvasDownEndsItsReplay() async throws {
        let session = PaintingSession(template: template)
        let view = CanvasView(session: session)
        view.reduceMotion = true
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.layoutIfNeeded()
        session.paint(Array(template.regions.indices), from: .zero, animated: false)
        view.replay()
        try await waitUntil(timeout: .seconds(10)) { session.replayed == 0 }
        view.tearDown()
        #expect(session.replayed == nil && !session.isReplaying)
        // Under Reduce Motion a replay still running would show its first areas within this.
        try await Task.sleep(for: .milliseconds(800))
        #expect(session.replayed == nil, "the replay played on after its canvas went")
        #expect(session.isComplete)
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

    /// A canvas 400 × 800 pt under a top bar and a palette with its caption, zoomed 3× into the
    /// middle, with every area but the last painted.
    private func canvasBeforeTheLastArea(_ session: PaintingSession, reduceMotion: Bool = false) throws -> (CanvasView, last: Int) {
        let view = CanvasView(session: session)
        view.reduceMotion = reduceMotion
        view.initialCamera = CanvasCamera(zoom: 3, center: SIMD2(Float(template.width), Float(template.height)) / 2)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.chromeInsets = UIEdgeInsets(top: 100, left: 0, bottom: 176, right: 0)
        view.layoutIfNeeded()
        let last = try #require(template.regions.indices.last)
        session.paint(Array(template.regions.indices.dropLast()), from: .zero, animated: false)
        return (view, last)
    }

    private func expectsTheWholePainting(_ view: CanvasView, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(view.relativeZoom - 1) < 0.001, sourceLocation: sourceLocation)
        let center = view.visibleCenter
        #expect(abs(center.x - Float(template.width) / 2) < 1, sourceLocation: sourceLocation)
        #expect(abs(center.y - Float(template.height) / 2) < 1, sourceLocation: sourceLocation)
    }

    /// Finishing the painting zoomed in ends on the whole painting, though the completion bar
    /// took the palette's place (other chrome insets) as it was finished: the last fill lingers,
    /// the camera eases out once it has landed, and the whole painting shines as it lands.
    @Test func finishFliesOutToTheWholePainting() async throws {
        let session = PaintingSession(template: template)
        let (view, last) = try canvasBeforeTheLastArea(session)
        // The flight runs on the display link.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = view.frame
        window.addSubview(view)
        window.isHidden = false
        defer { window.isHidden = true }
        let painted = view.frameUniforms().time.x
        session.paint([last], from: template.anchor(ofRegion: last), animated: true)
        #expect(session.isComplete)
        view.chromeInsets = UIEdgeInsets(top: 100, left: 0, bottom: 120, right: 0)
        view.layoutIfNeeded()
        #expect(abs(view.relativeZoom - 3) < 0.01 && !view.isCameraFlying, "the last area shows as it is painted")
        try await waitUntil(timeout: .seconds(10)) { !view.isCameraFlying && abs(view.relativeZoom - 1) < 0.001 }
        expectsTheWholePainting(view)
        let shine = view.frameUniforms().shine
        #expect(shine.y == -1, "the whole painting shines")
        // After the lingering fill (0.375 s at least), the rest and the flight.
        #expect(shine.x > painted + 1.2)
    }

    /// Under Reduce Motion the finish cuts to the whole painting a moment after the last fill,
    /// and nothing shines.
    @Test func finishCutsToTheWholePaintingUnderReduceMotion() async throws {
        let session = PaintingSession(template: template)
        let (view, last) = try canvasBeforeTheLastArea(session, reduceMotion: true)
        session.paint([last], from: template.anchor(ofRegion: last), animated: true)
        view.chromeInsets = UIEdgeInsets(top: 100, left: 0, bottom: 120, right: 0)
        view.layoutIfNeeded()
        #expect(abs(view.relativeZoom - 3) < 0.01, "the last area shows as it is painted")
        try await waitUntil(timeout: .seconds(5)) { abs(view.relativeZoom - 1) < 0.001 }
        expectsTheWholePainting(view)
        #expect(view.shineStart == CanvasClock.never)
    }

    /// Finishing with the whole painting in view: no flight to wait for, and the whole painting
    /// shines once the last fill has landed.
    @Test func finishAtFitShinesWithoutAFlight() throws {
        let session = PaintingSession(template: template)
        let view = CanvasView(session: session)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.chromeInsets = UIEdgeInsets(top: 100, left: 0, bottom: 176, right: 0)
        view.layoutIfNeeded()
        let last = try #require(template.regions.indices.last)
        session.paint(Array(template.regions.indices.dropLast()), from: .zero, animated: false)
        let painted = view.frameUniforms().time.x
        session.paint([last], from: template.anchor(ofRegion: last), animated: true)
        let fill = try #require(view.regionState(last))
        let shine = view.frameUniforms().shine
        #expect(shine.y == -1)
        #expect(shine.x >= painted + 0.6 - 0.001 && shine.x >= painted + fill.duration - 0.001)
    }

    /// Zoom to Fit keeps heading for the whole painting through a layout change on the way (a
    /// rotation), rather than stopping where it was.
    @Test func zoomToFitFollowsARotation() {
        let view = CanvasView(session: PaintingSession(template: template))
        view.initialCamera = CanvasCamera(zoom: 3, center: SIMD2(120, 160))
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.chromeInsets = UIEdgeInsets(top: 100, left: 0, bottom: 120, right: 0)
        view.layoutIfNeeded()
        // Without a window no display link steps the flight: it stays under way.
        view.zoomToFit()
        #expect(view.isCameraFlying)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutIfNeeded()
        #expect(view.isCameraFlying, "the flight carries on")
        let target = view.camera
        #expect(abs(target.zoom - 1) < 0.001)
        #expect(abs(target.center.x - Float(template.width) / 2) < 1)
        #expect(abs(target.center.y - Float(template.height) / 2) < 1)
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

    @Test func preparedSessionKeepsProgressAndPaletteText() async throws {
        var progress = PaintProgress(regionCount: template.regions.count)
        for region in regions(ofColor: 0) { progress.paint(region) }
        progress.activeSeconds = 17
        let seed: UInt64 = 42
        let session = try await PaintingSession.make(template: template, progress: progress, nicknameSeed: seed)
        let synchronous = try PaintingSession(template: template, progress: progress, nicknameSeed: seed)
        #expect(session.progress == progress)
        #expect(session.totalByColor == synchronous.totalByColor)
        #expect(session.remainingByColor == synchronous.remainingByColor)
        #expect(session.completedColors == synchronous.completedColors)
        #expect(session.selectedColor == synchronous.selectedColor)
        #expect(session.isComplete == synchronous.isComplete)
        #expect(session.isStarted == synchronous.isStarted)
        #expect(session.colorNames == synchronous.colorNames)
        #expect(session.colorNicknames == synchronous.colorNicknames)
        for color in template.palette.indices {
            let name = template.palette[color].colorName
            let nickname = session.nickname(of: color)
            #expect(session.colorTitles[color] == ColorNameText.title(name))
            #expect(session.numberedColorNames[color] == ColorNameText.numbered(number: color + 1, name: name, nickname: nickname))
            #expect(session.colorLabels[color] == PaintSpeech.colorLabel(number: color + 1, name: name, nickname: nickname))
        }
        let fresh = await PaintingSession.make(template: template, nicknameSeed: seed)
        #expect(fresh.progress == PaintProgress(regionCount: template.regions.count))
        #expect(fresh.colorLabels == session.colorLabels)
    }

    @Test func preparedSessionRejectsMismatchedProgress() async throws {
        let wrong = PaintProgress(regionCount: template.regions.count + 1)
        await #expect(throws: PaintingSession.ProgressMismatch(
            templateRegions: template.regions.count, progressRegions: wrong.regionCount)) {
                try await PaintingSession.make(template: template, progress: wrong)
            }
    }

    @Test func colorsGoByTheirNicknames() {
        let session = PaintingSession(template: template, nicknameSeed: 7)
        #expect((0..<session.paletteCount).allSatisfy { session.nickname(of: $0) == session.colorNicknames[$0] })
        #expect(session.nickname(of: 0) != nil)
    }

    /// Completion, the first fill and each finished color are written only when they flip, so
    /// the painting screen's layout and controls, which read only these, aren't told about
    /// every fill.
    @Test func milestonesChangeOnlyWhenTheyFlip() throws {
        let session = PaintingSession(template: template)
        let color = try #require((0..<session.paletteCount).first { regions(ofColor: $0).count >= 3 })
        let areas = regions(ofColor: color)
        func notifies(_ change: () -> Void) -> Bool {
            let observed = ObservedChange()
            withObservationTracking {
                _ = session.isComplete
                _ = session.isStarted
                _ = session.completedColors
            } onChange: {
                observed.fired = true
            }
            change()
            return observed.fired
        }
        #expect(!session.isStarted && !session.isComplete && session.completedColors.isEmpty)
        let started = notifies { _ = session.paint([areas[0]], from: .zero, animated: false) }
        #expect(started && session.isStarted, "The first fill starts the painting")
        let finishedNothing = notifies { _ = session.paint([areas[1]], from: .zero, animated: false) }
        #expect(!finishedNothing && session.revision == 2 && !session.isColorComplete(color))
        let finishedColor = notifies { _ = session.paint(Array(areas.dropFirst(2)), from: .zero, animated: false) }
        #expect(finishedColor && session.isColorComplete(color) && session.completedColors == [color])
        let undone = notifies { _ = session.undo() }
        #expect(undone && !session.isColorComplete(color) && session.completedColors.isEmpty)
        let finishedAll = notifies { _ = session.paint(Array(template.regions.indices), from: .zero, animated: false) }
        #expect(finishedAll && session.isComplete && session.completedColors == Set(0..<session.paletteCount))
        let restarted = notifies { session.reset() }
        #expect(restarted && !session.isStarted && !session.isComplete && session.completedColors.isEmpty)
        // Saved progress opens with them in step.
        var progress = PaintProgress(regionCount: template.regions.count)
        for r in areas { progress.paint(r) }
        let resumed = try PaintingSession(template: template, progress: progress)
        #expect(resumed.isStarted && !resumed.isComplete && resumed.completedColors == [color])
    }
}

/// What a `withObservationTracking` change handler saw: the handler is `@Sendable`, and here it
/// runs at once, on the main actor, inside the change.
private final class ObservedChange: @unchecked Sendable {
    var fired = false
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
