import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// A painter's edits survive every base made again (painting-company row 278, the audit's Part 3):
/// a repaint, a merge, a rub of the Eraser and an Only This Area made in Refine, then the base made
/// again by a Writing mark, Detail, Colors, Smoothness, Continue Refining without the draft's kept
/// trail, and a damaged painting's recovery. The base keeps its paints (`TemplateRefinements.pin`)
/// unless the painter changed how many there are, the edits land where they were made, on a
/// canvas of another size too, and none is left out unseen.
extension CreateModelTests {
    /// A refined flow: the four edits laid on `base`, and what each should still do.
    struct Refined {
        let model: CreateModel
        let base: Template
        /// The repaint, and the paint it made.
        let repaint: TemplateEditor.Edit
        let repainted: SIMD3<Float>
        /// Only This Area's point (canvas units of `base`) and color.
        let area: SIMD2<Float>
        let areaColor: SIMD3<Float>
        /// The merge's first and last points: one area now.
        let merged: (SIMD2<Float>, SIMD2<Float>)
    }

    /// The paint of the area under `point` (canvas units).
    static func paint(_ t: Template, at point: SIMD2<Float>) -> SIMD3<Float> {
        t.palette[Int(t.regions[region(t, at: point)].colorIndex)].oklab
    }

    static func region(_ t: Template, at point: SIMD2<Float>) -> Int {
        let x = min(max(Int(point.x), 0), t.width - 1), y = min(max(Int(point.y), 0), t.height - 1)
        return Int(t.regionMap[x, y])
    }

    /// The share of the picture (sampled on a grid laid over both, whatever their canvases) whose
    /// paint is the same in `a` and `b`, away from `exclude` (a box normalized to the picture).
    static func samePaint(_ a: Template, _ b: Template, excluding exclude: (SIMD2<Float>, SIMD2<Float>)? = nil) -> Double {
        var same = 0, total = 0
        for j in 0..<80 {
            for i in 0..<80 {
                let u = SIMD2((Float(i) + 0.5) / 80, (Float(j) + 0.5) / 80)
                if let (low, high) = exclude, u.x >= low.x, u.y >= low.y, u.x <= high.x, u.y <= high.y { continue }
                total += 1
                let pa = paint(a, at: u * SIMD2(Float(a.width), Float(a.height)))
                let pb = paint(b, at: u * SIMD2(Float(b.width), Float(b.height)))
                if pa == pb { same += 1 }
            }
        }
        return Double(same) / Double(max(total, 1))
    }

    /// Lays a repaint (Similar Colors as `family`), a merge, a rub and an Only This Area on the red
    /// fox's template, each checked to be made.
    func refined(family: Bool = false) async throws -> Refined {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let base = try #require(model.preview?.template)
        let bySize = base.regions.indices.sorted { base.regions[$0].area > base.regions[$1].area }
        func settledCount(_ count: Int) async throws {
            await model.settled()
            try await waitUntil { model.isFinal && model.historySteps == 0 }
            #expect(model.refinements.edits.count == count, "edit \(count) wasn't made")
        }

        // A repaint of the paint of the second largest area.
        let from = base.palette[Int(base.regions[bySize[1]].colorIndex)].oklab
        let to = SIMD3<Float>(0.55, 0.16, 0.06)
        model.recolor(.repaint(from: from, to: to, family: family))
        try await settledCount(1)
        let repaint = try #require(model.refinements.edits.first)

        // A merge of two areas side by side with numbers of their own, of paints the repaint left.
        let shown = try #require(model.preview?.template)
        var merged: (SIMD2<Float>, SIMD2<Float>)?
        for edge in shown.edges {
            let a = Int(edge.left), b = Int(edge.right)
            guard a < shown.regions.count, b < shown.regions.count, a != b,
                  shown.regions[a].area > 4000, shown.regions[b].area > 4000,
                  let pa = shown.labels(ofRegion: a).first?.position, let pb = shown.labels(ofRegion: b).first?.position,
                  Self.region(shown, at: pa) == a, Self.region(shown, at: pb) == b
            else { continue }
            merged = (pa, pb)
            break
        }
        let (start, end) = try #require(merged)
        model.edit(.merge(points: [start, end]))
        try await settledCount(2)
        let joined = try #require(model.preview?.template)
        #expect(Self.region(joined, at: start) == Self.region(joined, at: end))

        // A rub of the Eraser across ink, somewhere it takes ink out.
        let edges = joined.edges.filter { $0.pointCount > 6 }
        for edge in edges.prefix(40) {
            let middle = joined.points[Int(edge.pointStart + edge.pointCount / 2)]
            model.edit(.erase(path: [middle - SIMD2(3, 0), middle + SIMD2(3, 0)], radius: 4))
            await model.settled()
            try await waitUntil { model.isFinal }
            if model.refinements.edits.count == 3 { break }
        }
        #expect(model.refinements.edits.count == 3, "no rub took ink out")

        // Only This Area, on the third largest area.
        let rubbed = try #require(model.preview?.template)
        let area = try #require(rubbed.labels(ofRegion: Self.region(rubbed, at: base.labels(ofRegion: bySize[2]).first?.position ?? .zero)).first?.position)
        let areaColor = SIMD3<Float>(0.42, -0.12, 0.13)
        model.paintArea(at: area, color: areaColor)
        try await settledCount(4)
        let painted = try #require(model.preview?.template)
        #expect(ColorScience.distance(Self.paint(painted, at: area), areaColor) < 0.03)
        #expect(model.refinements.pin?.palette == base.palette, "the pin is the base's paints")
        #expect(model.leftOut == 0 && model.shownChangeCount == 4)
        return Refined(
            model: model, base: base, repaint: repaint, repainted: TemplateEditor.recolor(from, by: repaint),
            area: area, areaColor: areaColor, merged: (start, end))
    }

    /// What the edits still do on the template on screen, their points scaled to its canvas.
    func expectEditsHold(_ r: Refined, on template: Template, repainted: SIMD3<Float>? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        let scale = SIMD2(Float(template.width) / Float(r.base.width), Float(template.height) / Float(r.base.height))
        #expect(template.palette.contains { $0.oklab == (repainted ?? r.repainted) }, "the repaint was lost", sourceLocation: sourceLocation)
        #expect(ColorScience.distance(Self.paint(template, at: r.area * scale), r.areaColor) < 0.03,
                "Only This Area isn't where it was made", sourceLocation: sourceLocation)
        #expect(Self.region(template, at: r.merged.0 * scale) == Self.region(template, at: r.merged.1 * scale),
                "the merge isn't where it was made", sourceLocation: sourceLocation)
    }

    /// Item 3: a Writing mark makes the base again; it keeps its paints, every edit lands, and the
    /// picture away from the mark keeps its paints. Undo gives the template back as it was.
    @Test func aWritingMarkKeepsEveryEdit() async throws {
        let r = try await refined()
        let model = r.model
        let before = try #require(model.preview?.template)
        let box = (SIMD2<Float>(0.05, 0.05), SIMD2<Float>(0.35, 0.14))
        model.change(.markText(TemplateRefinements.textLine(from: box.0, to: box.1)))
        try await waitUntil { model.refinements.addedText.count == 1 && model.isFinal }
        let after = try #require(model.preview?.template)
        #expect(Set(model.paintsBeforeEdits).isSubset(of: Set(r.base.palette)), "the base chose its paints again")
        #expect(model.leftOut == 0 && model.shownChangeCount == 5 && model.refinements.edits.count == 4)
        expectEditsHold(r, on: after)
        let margin: Float = 0.1
        #expect(Self.samePaint(before, after, excluding: (box.0 - margin, box.1 + margin)) > 0.85)

        model.undo()
        try await waitUntil { model.refinements.addedText.isEmpty && model.isFinal }
        #expect(model.preview?.template == before)
        model.cancelAll()
    }

    /// Item 2: Detail makes the canvas another size: the edits are scaled onto it and land where
    /// they were made, the paints kept; back at the first Detail the template is the one it was.
    @Test func detailScalesTheEditsOntoTheNewCanvas() async throws {
        let r = try await refined()
        let model = r.model
        let before = try #require(model.preview?.template)
        let detail = model.detail
        model.detail = detail < 0.7 ? detail + 0.3 : detail - 0.3
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        let after = try #require(model.preview?.template)
        #expect(after.width != before.width, "Detail left the canvas as it was")
        #expect(Set(model.paintsBeforeEdits).isSubset(of: Set(r.base.palette)))
        #expect(model.refinements.pin?.width == after.width)
        // The rub was made across a line this Detail may draw elsewhere, and is then honestly
        // left out: the count says so. The other edits land.
        #expect(model.leftOut <= 1 && model.shownChangeCount == 4 - model.leftOut)
        Log.create.notice("Row 278: at another Detail \(model.leftOut, privacy: .public) edit was left out")
        expectEditsHold(r, on: after)

        model.detail = detail
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        #expect(model.preview?.template.width == before.width)
        expectEditsHold(r, on: try #require(model.preview?.template))
        model.cancelAll()
    }

    /// Item 4: more Colors choose the paints anew; the repaint goes to the nearest new paint and the
    /// painter is told, nothing is left out. Smoothness keeps the paints.
    @Test func colorsSendARepaintToTheNearestNewPaintAndSmoothnessKeepsThePaints() async throws {
        let r = try await refined()
        let model = r.model
        model.smoothness = model.smoothness < 0.8 ? model.smoothness + 0.1 : model.smoothness - 0.1
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        #expect(Set(model.paintsBeforeEdits).isSubset(of: Set(r.base.palette)))
        #expect(model.leftOut == 0)
        expectEditsHold(r, on: try #require(model.preview?.template))

        let smoothed = try #require(model.preview?.template)
        let count = model.colorCount
        model.colorCount += 4
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        #expect(model.note?.kind == .repainted(1))
        let paints = model.paintsBeforeEdits
        guard case .repaint(let from, _, _) = model.refinements.edits.first else {
            Issue.record("the repaint is gone")
            return
        }
        #expect(paints.contains { $0.oklab == from }, "the repaint isn't of a paint the new base has")
        // The pin stays the first base's, with the move remembered.
        #expect(model.refinements.pin?.palette == r.base.palette && model.refinements.pin?.moved.count == 1)
        #expect(model.leftOut == 0)
        let repainted = TemplateEditor.recolor(from, by: try #require(model.refinements.edits.first))
        expectEditsHold(r, on: try #require(model.preview?.template), repainted: repainted)

        // The number put back: the repaint is of its own paint again, the template as it was.
        model.colorCount = count
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        #expect(model.refinements.edits.first == r.repaint && model.refinements.pin?.moved.isEmpty == true)
        #expect(model.preview?.template == smoothed)
        model.cancelAll()
    }

    /// Item 5: a repaint with Similar Colors keeps to the same paints on a base made again, whose
    /// paints are the first base's; after a Colors change it moves to the nearest paints, said so,
    /// and the number put back gives the template as it was.
    @Test func aRepaintWithSimilarColorsKeepsItsPaints() async throws {
        let r = try await refined(family: true)
        let model = r.model
        let firstLaid = try #require(model.preview?.template)
        model.change(.markText(TemplateRefinements.textLine(from: SIMD2(0.6, 0.8), to: SIMD2(0.9, 0.9))))
        try await waitUntil { model.refinements.addedText.count == 1 && model.isFinal }
        let paints = model.paintsBeforeEdits
        #expect(Set(paints).isSubset(of: Set(r.base.palette)))
        // Every paint the repaint gave a color in the first template it gives the same one now:
        // the template's paints are the first's, or a pinned paint as the repaint colors it (one
        // that merged with another there, now its neighbour in color has left).
        let laid = try #require(model.preview?.template)
        let recolored = Set(r.base.palette.map { TemplateEditor.recolor($0.oklab, by: r.repaint) })
        #expect(laid.palette.allSatisfy { firstLaid.palette.contains($0) || recolored.contains($0.oklab) })
        #expect(model.leftOut == 0)

        let count = model.colorCount
        model.colorCount += 4
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        #expect(model.note?.kind == .repainted(1) && model.leftOut == 0)
        guard case .repaint(let from, _, true)? = model.refinements.edits.first else {
            Issue.record("the repaint with Similar Colors is gone")
            return
        }
        #expect(model.paintsBeforeEdits.contains { $0.oklab == from })
        model.colorCount = count
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        #expect(model.refinements.edits.first == r.repaint && model.preview?.template == laid)
        model.cancelAll()
    }

    /// Item 1: Continue Refining without the draft's kept trail makes the base again of the
    /// draft's JPEG of the photo, of the paints it pins: every edit lands and the picture keeps
    /// its paints.
    @Test func continuingWithoutAKeptTrailKeepsThePaintsAndEdits() async throws {
        let r = try await refined()
        let saved = try #require(r.model.draft)
        #expect(saved.refinements.pin != nil)
        let source = try #require(r.model.source)
        let jpeg = try #require(ImageCodec.jpegData(source.preview, quality: 0.88))
        let before = try #require(r.model.preview?.template)

        let resumed = CreateModel()
        resumed.load(draft: saved, photo: jpeg)
        try await waitUntil { resumed.isFinal }
        let after = try #require(resumed.preview?.template)
        #expect(Set(resumed.paintsBeforeEdits).isSubset(of: Set(r.base.palette)))
        #expect(resumed.leftOut == 0 && resumed.refinements.edits.count == 4)
        expectEditsHold(r, on: after)
        let same = Self.samePaint(before, after)
        // The audit's replay without a pin: 49 % of the picture changed paint.
        Log.create.notice("Row 278: continuing without a kept trail kept the paint of \(same, privacy: .public) of the picture")
        #expect(same > 0.8)
        r.model.cancelAll()
        resumed.cancelAll()
    }

    /// Item 1: a damaged painting made again keeps its paints and lays its edits where they were
    /// made, from the photo it stored.
    @Test func recoveringARefinedPaintingKeepsThePaintsAndEdits() async throws {
        let r = try await refined()
        let made = try await r.model.makeDraft()
        #expect(made.refinements.pin != nil)
        let root = FileManager.default.temporaryDirectory.appending(path: "remake-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(store: ArtworkStore(root: root))
        let artwork = try await library.create(made)
        let document = try await library.regenerate(artwork: artwork.id, settings: made.settings)
        let template = document.template
        #expect(Set(template.palette).isSubset(of: Set(made.template.palette).union(r.base.palette)))
        expectEditsHold(r, on: template)
        let same = Self.samePaint(made.template, template)
        Log.create.notice("Row 278: recovery kept the paint of \(same, privacy: .public) of the picture")
        #expect(same > 0.8)
        #expect(!(await library.regenerationMayRepaint(artwork.id)), "a pinned painting is said to change")
        r.model.cancelAll()
    }

    /// The critic's case: refined at one Colors count, repainted after moving it, and started there.
    /// The base laid with edits at the new count gives that count's paints to the pin
    /// (`Pin.others`), so the painting made again keeps them and the repaint made on them.
    @Test func aPaintingFinishedAtAnotherColorsCountKeepsThosePaints() async throws {
        let r = try await refined()
        let model = r.model
        model.colorCount += 4
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings == model.settings }
        let paints = model.paintsBeforeEdits
        #expect(model.refinements.pin?.palette(for: model.settings.colorCount) == paints)
        // A paint of the template on screen that the moved repaint doesn't already use.
        let shownPaints = try #require(model.preview?.template.palette)
        guard case .repaint(let movedFrom, _, _)? = model.refinements.edits.first else {
            Issue.record("the repaint is gone")
            return
        }
        // The largest such paint, so the painting made again from the stored photo still has it.
        let shown = try #require(model.preview?.template)
        var area: [SIMD3<Float>: Int] = [:]
        for region in shown.regions { area[shown.palette[Int(region.colorIndex)].oklab, default: 0] += Int(region.area) }
        let from = try #require(
            paints.filter { paint in shownPaints.contains(paint) && paint.oklab != movedFrom }
                .max { area[$0.oklab, default: 0] < area[$1.oklab, default: 0] }?.oklab)
        let repaint = TemplateEditor.Edit.repaint(from: from, to: SIMD3(0.3, -0.05, -0.12), family: false)
        model.recolor(.repaint(from: from, to: SIMD3(0.3, -0.05, -0.12), family: false))
        await model.settled()
        try await waitUntil { model.isFinal && model.refinements.edits.count == 5 }
        let made = try await model.makeDraft()
        let root = FileManager.default.temporaryDirectory.appending(path: "remake-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(store: ArtworkStore(root: root))
        let artwork = try await library.create(made)
        #expect(!(await library.regenerationMayRepaint(artwork.id)))
        let document = try await library.regenerate(artwork: artwork.id, settings: made.settings)
        #expect(Set(document.template.palette).isSubset(of: Set(made.template.palette).union(paints)))
        #expect(document.template.palette.contains { $0.oklab == TemplateEditor.recolor(from, by: repaint) }, "the repaint made at the new count was lost")
        model.cancelAll()
    }

    /// A painting refined before refinements kept their paints has no pin: made again it keeps
    /// today's re-make, and its recovery says the paints may come out different.
    @Test func recoveringAPaintingWithoutAPinSaysItsPaintsMayChange() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "remake-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(store: ArtworkStore(root: root))
        var refinements = TemplateRefinements()
        refinements.edits = [.repaint(from: SIMD3(0.5, 0, 0), to: SIMD3(0.4, 0.1, 0), family: false)]
        var older = ArtworkDraft(
            title: "Older", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12), photo: nil, sampleName: nil)
        older.refinements = refinements
        let artwork = try await library.create(older)
        #expect(await library.regenerationMayRepaint(artwork.id))
        let plain = try await library.create(ArtworkDraft(
            title: "Plain", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12), photo: nil, sampleName: nil))
        #expect(!(await library.regenerationMayRepaint(plain.id)))
    }
}
