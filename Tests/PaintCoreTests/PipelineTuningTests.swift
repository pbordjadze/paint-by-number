import Foundation
import Testing
@testable import PaintCore

@Suite("Pipeline tuning and line art settings")
struct PipelineTuningTests {

    /// Every stored knob of the parameters by name (Float and Int knobs, as Doubles).
    static func knobs(_ p: SegmentationParameters) -> [String: Double] {
        var out: [String: Double] = [:]
        for child in Mirror(reflecting: p).children {
            guard let name = child.label else { continue }
            if let v = child.value as? Float { out[name] = Double(v) }
            if let v = child.value as? Int { out[name] = Double(v) }
            if let v = child.value as? UInt64 { out[name] = Double(v) }
        }
        return out
    }

    @Test func eachFactorScalesExactlyItsKnobs() {
        let base = GenerationSettings(colorCount: 30, detail: 0.6, smoothness: 0.4)
        let plain = Self.knobs(SegmentationParameters(settings: base, width: 1200, height: 800))
        let cases: [(WritableKeyPath<PipelineTuning, Float>, [String])] = [
            (\.smoothing, ["smoothSpatial"]),
            (\.textureFlattening, ["textureFlattening"]),
            (\.minimumCellSize, ["minArea"]),
            (\.subjectEmphasis, ["importanceStrength", "importanceSharpening"]),
            (\.accentColors, ["paletteSaliency"]),
            (\.colorfulness, ["chromaScale"]),
        ]
        for (path, names) in cases {
            var settings = base
            settings.tuning[keyPath: path] = 2
            let tuned = Self.knobs(SegmentationParameters(settings: settings, width: 1200, height: 800))
            for (name, value) in plain {
                if names.contains(name) {
                    #expect(tuned[name] == value * 2, "\(names) → \(name)")
                } else {
                    #expect(tuned[name] == value, "\(names) moved \(name)")
                }
            }
        }
        // The default tuning, and the default spelled out, derive the very same knobs.
        var spelled = base
        spelled.tuning = PipelineTuning(
            smoothing: 1, textureFlattening: 1, minimumCellSize: 1, subjectEmphasis: 1, accentColors: 1, colorfulness: 1)
        #expect(Self.knobs(SegmentationParameters(settings: spelled, width: 1200, height: 800)) == plain)
        #expect(PipelineTuning().isDefault)
    }

    @Test func coloringBookFlatteningScalesOnlyThePaintKnobs() {
        let settings = GenerationSettings(colorCount: 30, detail: 0.6, smoothness: 0.4)
        let plain = SegmentationParameters(settings: settings, width: 1200, height: 800)
        var flat = plain
        flat.flattenForColoringBook()
        let before = Self.knobs(plain), after = Self.knobs(flat)
        let flattened: Set<String> = ["smoothSpatial", "textureFlattening", "minArea"]
        #expect(after.count == before.count)
        // The radius knobs must stay: the vectorizer rebuilds its parameters without the
        // flattening and reads them for label room.
        #expect(flattened.union(["minRadius"]).isSubset(of: before.keys))
        for (name, value) in before {
            let expected = flattened.contains(name) ? Double(Float(value) * SegmentationParameters.coloringBookFlattening) : value
            #expect(after[name] == expected, "\(name)")
        }
    }

    @Test func tuningIsClamped() {
        let wild = PipelineTuning(smoothing: 100, textureFlattening: 0, minimumCellSize: .nan, subjectEmphasis: -3,
                                  accentColors: .infinity, colorfulness: 0.3).normalized
        #expect(wild == PipelineTuning(smoothing: 4, textureFlattening: 0.25, minimumCellSize: 1, subjectEmphasis: 0.25,
                                       accentColors: 1, colorfulness: 0.3))
        var settings = GenerationSettings()
        settings.tuning.smoothing = 9
        #expect(TemplateGenerator(settings: settings).settings.tuning.smoothing == 4)
    }

    @Test func minimumCellSizeChangesTheTemplate() throws {
        // The Parrots draft (Auto's fixture): enough texture for small regions.
        let image = try Netpbm.read(LineArtTests.fixture("auto-parrots-draft.ppm"))
        func regions(_ factor: Float) throws -> Int {
            var settings = GenerationSettings(colorCount: 24, detail: 0.5)
            settings.tuning.minimumCellSize = factor
            return try TemplateGenerator(settings: settings).generate(from: image, cancel: .none).template.regions.count
        }
        let small = try regions(0.25), plain = try regions(1), large = try regions(4)
        #expect(small >= plain && plain >= large && small > large, "\(small) \(plain) \(large)")
    }

    @Test func settingsDecodeTolerantly() throws {
        // meta.json of artworks saved before line art existed: they were made with classic
        // lines, so they regenerate with them whatever the default style is now.
        let old = #"{"colorCount": 20, "detail": 0.4, "smoothness": 0.6, "seed": 7}"#
        let settings = try JSONDecoder().decode(GenerationSettings.self, from: Data(old.utf8))
        #expect(settings == GenerationSettings(
            colorCount: 20, detail: 0.4, smoothness: 0.6, seed: 7, lineArt: LineArtSettings(style: .classic)))
        #expect(GenerationSettings().lineArt.style == .coloringBook)
        // Unknown and malformed values fall back field by field.
        let odd = #"{"colorCount": 20, "detail": 0.4, "smoothness": 0.6, "seed": 7,"#
            + #" "lineArt": {"style": "watercolor", "outlineThreshold": "high", "gapBridging": 12, "samePaint": "split"},"#
            + #" "tuning": {"smoothing": 2, "colorfulness": null, "future": 3}}"#
        let decoded = try JSONDecoder().decode(GenerationSettings.self, from: Data(odd.utf8))
        var expected = LineArtSettings()
        expected.gapBridging = 12
        expected.samePaint = .split
        #expect(decoded.lineArt == expected)
        // A missing number takes its style's default.
        let layered = try JSONDecoder().decode(LineArtSettings.self, from: Data(#"{"style": "layered"}"#.utf8))
        #expect(layered == LineArtSettings(style: .layered) && layered.outlineThreshold == 0.85)
        #expect(decoded.tuning == PipelineTuning(smoothing: 2))
        // Round trip.
        var full = GenerationSettings()
        full.lineArt = LineArtSettings(style: .layered, outlineThreshold: 0.9, samePaint: .joinAllButOutlines, keepColorEdges: false)
        full.tuning = PipelineTuning(minimumCellSize: 0.5, colorfulness: 3)
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: JSONEncoder().encode(full)) == full)
    }

    @Test func lineArtSettingsAreClampedAndOrdered() {
        let s = LineArtSettings(
            outlineThreshold: 0.2, detailThreshold: 0.5, textureThreshold: 1.4, minimumStrokeLength: -4, gapBridging: 400,
            lineSmoothing: 2).normalized
        #expect(s.textureThreshold == 1 && s.detailThreshold == 1 && s.outlineThreshold == 1)
        #expect(s.minimumStrokeLength == 0 && s.gapBridging == 40 && s.lineSmoothing == 1)
    }

    @Test func autoCandidatesCarryLineArtAndTuning() throws {
        let image = TestScenes.scene(width: 300, height: 200)
        let classic = LineArtSettings(style: .classic)
        let plain = try AutoSettings.choose(
            image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 3, lineArt: classic,
            cancel: .none, firstDraft: nil)
        var lineArt = LineArtSettings(style: .layered)
        lineArt.keepColorEdges = false
        // Neutral tuning and layered lines change nothing but what the settings carry.
        let carried = try AutoSettings.choose(
            image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 3, lineArt: lineArt,
            tuning: PipelineTuning(), cancel: .none, firstDraft: nil)
        #expect(carried.candidates.allSatisfy { $0.settings.lineArt == lineArt && $0.settings.tuning.isDefault })
        #expect(carried.candidates.map(\.score) == plain.candidates.map(\.score))
        #expect(carried.winner == plain.winner)
        #expect(plain.candidates.allSatisfy { $0.settings.lineArt == classic })
        // Without line art given, candidates carry the default style: a coloring book, whose
        // flatter paint reaches the drafts.
        let book = try AutoSettings.choose(
            image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 3, cancel: .none, firstDraft: nil)
        #expect(book.candidates.allSatisfy { $0.settings.lineArt == LineArtSettings() })
        #expect(book.candidates[0].score!.regions <= plain.candidates[0].score!.regions)
        // A tuning reaches the drafts Auto scores.
        let tuned = try AutoSettings.choose(
            image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 3,
            tuning: PipelineTuning(minimumCellSize: 4), cancel: .none, firstDraft: nil)
        #expect(tuned.settings.tuning.minimumCellSize == 4)
        #expect(tuned.candidates[0].score!.regions <= plain.candidates[0].score!.regions)
    }
}
