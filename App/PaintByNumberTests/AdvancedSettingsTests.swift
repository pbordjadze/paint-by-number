import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Settings › Advanced: generation keys, setting resets, sliders, effects, presets, the shared
/// text, persistence, and the preview's queue end to end.
@MainActor
struct AdvancedSettingsTests {
    /// Layered line art with every field off its default, and every multiplier at 2.
    private static let changedArt = LineArtSettings(
        style: .layered, outlineThreshold: 0.95, detailThreshold: 0.65, textureThreshold: 0.45, minimumStrokeLength: 30,
        gapBridging: 14, lineSmoothing: 0.9, samePaint: .split, keepColorEdges: false, outlineEyes: false)
    private static let changedTuning = PipelineTuning(
        smoothing: 2, textureFlattening: 2, minimumCellSize: 2, subjectEmphasis: 2, accentColors: 2, colorfulness: 2)

    @Test func classicKeysIgnoreTheLayeredSettings() {
        // The defaults' key is the coloring book, canonical (joining across its absent texture lines is splitting).
        #expect(GenerationKey.defaults == GenerationKey(lineArt: LineArtSettings(), tuning: PipelineTuning()))
        #expect(GenerationKey.defaults.lineArt.style == .coloringBook && GenerationKey.defaults.lineArt.samePaint == .split)
        var classic = Self.changedArt
        classic.style = .classic
        let classicKey = GenerationKey(lineArt: classic, tuning: PipelineTuning())
        #expect(classicKey == GenerationKey(lineArt: LineArtSettings(style: .classic), tuning: PipelineTuning()))
        #expect(classicKey != .defaults)
        let layered = GenerationKey(lineArt: LineArtSettings(style: .layered), tuning: PipelineTuning())
        #expect(layered != .defaults)
        #expect(GenerationKey(lineArt: Self.changedArt, tuning: PipelineTuning()) != layered)
        #expect(GenerationKey(lineArt: LineArtSettings(), tuning: Self.changedTuning) != .defaults)
        let base = GenerationSettings(colorCount: 30, detail: 0.7, smoothness: 0.3)
        let settings = layered.settings(on: base)
        #expect(settings.colorCount == 30 && settings.detail == 0.7 && settings.smoothness == 0.3)
        #expect(settings.lineArt.style == .layered)
    }

    @Test func everySettingResetsToItsDefault() {
        let key = GenerationKey(lineArt: Self.changedArt, tuning: Self.changedTuning)
        for control in AdvancedControl.allCases {
            #expect(control.isChanged(in: key), "\(control) isn't changed in the changed key")
            let reset = control.reset(key)
            #expect(!control.isChanged(in: reset), "\(control) is still changed after its reset")
            #expect(control.value(lineArt: reset.lineArt, tuning: reset.tuning) == control.defaultValue(for: reset.lineArt.style))
            // The style's reset carries the layered defaults into the book; thresholds push each other.
            guard control != .style else { continue }
            for other in AdvancedControl.allCases where other != control && !AdvancedControl.thresholds.contains(other) {
                #expect(other.isChanged(in: reset), "Resetting \(control) reset \(other) too")
            }
        }
        // Under classic lines the drawn-line settings change nothing; the style itself does.
        var classic = Self.changedArt
        classic.style = .classic
        let classicKey = GenerationKey(lineArt: classic, tuning: PipelineTuning())
        for control in AdvancedControl.lineArt where control != .style {
            #expect(!control.isChanged(in: classicKey), "\(control) counts under classic lines")
        }
        #expect(AdvancedControl.style.isChanged(in: classicKey))
        #expect(AdvancedControl.lineArt.filter { !$0.needsEdgeMap } == [.style])
        // A coloring book, the default style, reads everything but the texture threshold, and
        // joining across its (absent) texture lines is splitting.
        var book = Self.changedArt
        book.style = .coloringBook
        let bookKey = GenerationKey(lineArt: book, tuning: PipelineTuning())
        #expect(AdvancedControl.lineArt.filter { !$0.applies(to: .coloringBook) } == [.textureThreshold])
        #expect(!AdvancedControl.textureThreshold.isChanged(in: bookKey))
        #expect(!AdvancedControl.style.isChanged(in: bookKey))
        for control in AdvancedControl.lineArt where ![.textureThreshold, .samePaint, .style].contains(control) {
            #expect(control.isChanged(in: bookKey), "\(control) under a coloring book")
        }
        // Each style has defaults of its own, carried along when the style changes.
        let layeredDefaults = LineArtSettings(style: .layered)
        #expect(layeredDefaults.outlineThreshold == 0.85 && LineArtSettings().outlineThreshold == 0.6)
        #expect(layeredDefaults.changing(to: .coloringBook) == LineArtSettings())
        var custom = layeredDefaults
        custom.gapBridging = 3
        let carried = custom.changing(to: .coloringBook)
        #expect(carried.gapBridging == 3 && carried.outlineThreshold == 0.6 && carried.style == .coloringBook)
        #expect(AdvancedControl.outlineThreshold.defaultValue(for: .layered) == Double(Float(0.85)))
        #expect(AdvancedControl.style.defaultValue(for: .layered) == AdvancedControl.style.defaultValue(for: .classic))
        var joined = LineArtSettings(style: .coloringBook, samePaint: .joinTexture)
        let split = GenerationKey(lineArt: LineArtSettings(style: .coloringBook, samePaint: .split), tuning: PipelineTuning())
        #expect(GenerationKey(lineArt: joined, tuning: PipelineTuning()) == split)
        joined.samePaint = .joinAllButOutlines
        #expect(GenerationKey(lineArt: joined, tuning: PipelineTuning()) != split)
        #expect(AdvancedControl.style.value(lineArt: book, tuning: PipelineTuning()) == 2)
    }

    @Test func slidersMapValuesAndCatchTheDefault() throws {
        let multiplier = try #require(AdvancedControl.minimumCellSize.slider(for: .coloringBook))
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        #expect(close(multiplier.position(of: 1), 0.5))
        #expect(close(multiplier.value(at: 0), 0.25))
        #expect(close(multiplier.value(at: 1), 4))
        #expect(close(multiplier.value(at: 0.75), 2))
        #expect(multiplier.value(at: 0.5 + SliderSpec.detent / 2) == 1, "The default doesn't catch the thumb")
        #expect(close(multiplier.value(at: 0.6), 1.32), "Values aren't rounded to hundredths")
        // VoiceOver moves a multiplier by a quarter of a doubling.
        #expect(close(multiplier.value(1, adjustedBy: 4), 2))
        #expect(close(multiplier.value(4, adjustedBy: 1), 4))
        #expect(multiplier.text(1.5) == "1.5×")

        let threshold = try #require(AdvancedControl.outlineThreshold.slider(for: .layered))
        // Defaults are Floats shown as Doubles.
        #expect(abs(threshold.defaultValue - 0.85) < 1e-6)
        #expect(abs(try #require(AdvancedControl.outlineThreshold.slider(for: .coloringBook)).defaultValue - 0.6) < 1e-6)
        #expect(close(threshold.value(at: threshold.position(of: 0.42)), 0.42))
        // VoiceOver steps land on the step grid, so they never drift.
        #expect(close(threshold.value(0.42, adjustedBy: 1), 0.45))
        var stepped = 1.0
        for _ in 0..<4 { stepped = multiplier.value(stepped, adjustedBy: 1) }
        #expect(stepped == 2, "Four quarter doublings from 1× aren't 2×: \(stepped)")
        #expect(threshold.text(0.6) == 0.6.formatted(.percent.precision(.fractionLength(0))))

        let length = try #require(AdvancedControl.minimumStrokeLength.slider(for: .coloringBook))
        #expect(close(length.value(at: 0.25), 15))
        #expect(length.text(8) == "8 px")
        #expect(AdvancedControl.style.slider(for: .classic) == nil && AdvancedControl.samePaint.slider(for: .layered) == nil)
    }

    @Test func effectsReadAsChanges() {
        #expect(AdvancedText.effect(.init(areas: 212, colors: 0)) == "+212 areas · about 11 min longer")
        #expect(AdvancedText.effect(.init(areas: -1, colors: -2)) == "−1 area · −2 colors")
        #expect(AdvancedText.effect(.init(areas: 0, colors: 0, lines: 40)) == "+40 lines")
        #expect(AdvancedText.effect(.init(areas: 0, colors: 0)) == "No change to areas or colors")
        #expect(AdvancedText.signed(1243) == "+1,243")
        #expect(AdvancedText.signed(-85) == "−85")
        #expect(AdvancedText.signedDuration(-600) == "−10 min")
    }

    @Test func statsGrowTheDraftToTheFullPainting() {
        let template = Fixtures.stripes(count: 3)
        let stats = AdvancedStats(template, areaScale: 2.5)
        #expect(stats.areas == 8)
        #expect(stats.colors == 3)
        #expect(stats.lines == nil, "A classic template has no layers")
        #expect(stats.seconds == 8 * PaintCore.PaintingTime.secondsPerRegion)
        let layered = AdvancedStats(areas: 100, colors: 20, lines: [10, 20, 30, 40])
        let other = AdvancedStats(areas: 90, colors: 21, lines: [10, 20, 20, 0])
        #expect(layered.drawnLines == 60)
        #expect(layered.delta(from: other) == .init(areas: 10, colors: -1, lines: 10))
        #expect(layered.delta(from: stats).lines == nil, "Lines only compare between layered templates")
    }

    @Test func presetsAreRecognizedAndKeepTheWeightAndWhatStaysPainted() {
        #expect(LineAppearancePreset.matching(.default) == .fade)
        var weighted = LineAppearance.default
        weighted.weighted = true
        weighted.outline.painted = 1
        for preset in LineAppearancePreset.allCases {
            let applied = preset.applied(to: weighted)
            #expect(LineAppearancePreset.matching(applied) == preset)
            #expect(applied.weighted, "\(preset) changed the weighting")
            #expect(applied.outline.painted == 1, "\(preset) changed what stays when painted")
        }
        var custom = LineAppearance.default
        custom.texture.opacity[1] = 0.33
        #expect(LineAppearancePreset.matching(custom) == nil)
    }

    /// Paste Settings reads the copied text back, a preset that names only some fields, and
    /// nothing from text without settings; values beyond a setting's range are clamped.
    @Test func pastedTextYieldsItsSettings() throws {
        var kept = LineAppearancePreset.grow.applied(to: .default)
        kept.outline.painted = 1
        let snapshot = AdvancedReport.Snapshot(
            app: "1.0 (1)", picture: "parrots", paintingLength: "relaxed", lineArt: Self.changedArt,
            tuning: Self.changedTuning, lineAppearance: kept, preview: nil, defaults: nil)
        // The note comes before the JSON and may hold braces of its own.
        let text = AdvancedReport.text(snapshot: snapshot, pictureTitle: "Parrots", summary: nil, changes: [], note: "a {note}")
        let imported = try #require(AdvancedReport.settings(in: text))
        #expect(imported == .init(lineArt: Self.changedArt, tuning: Self.changedTuning, lineAppearance: kept))

        let preset = """
            {"lineArt": {"style": "layered", "samePaint": "split"},
             "lineAppearance": {"outline": {"opacity": [1, 1, 1], "width": [1.3, 1.3, 1.35], "painted": 1}}}
            """
        let partial = try #require(AdvancedReport.settings(in: preset))
        #expect(partial.tuning == nil)
        #expect(partial.lineArt == LineArtSettings(style: .layered, samePaint: .split))
        #expect(partial.lineAppearance?.outline.painted == 1 && partial.lineAppearance?.detail == LineAppearance.default.detail)

        let wild = try #require(AdvancedReport.settings(
            in: #"{"tuning": {"smoothing": 99}, "lineAppearance": {"color": {"opacity": [2, 2, 2], "width": [0, 0, 0], "painted": -1}}}"#))
        #expect(wild.tuning?.smoothing == PipelineTuning.range.upperBound)
        #expect(wild.lineAppearance?.color == .init(opacity: [1, 1, 1], width: [0.2, 0.2, 0.2], painted: 0))

        for text in ["Hello", "{}", #"{"picture": "parrots"}"#, #"{"lineArt": 5}"#, "{not json}"] {
            #expect(AdvancedReport.settings(in: text) == nil, "settings found in \(text)")
        }
    }

    /// A preset of the whole screen sets every group, is recognized until a setting moves,
    /// survives its own normalization and the text Copy Settings writes for it; the coloring
    /// book is the defaults.
    @Test func presetsSetEveryGroupAndAreRecognized() throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AdvancedSettingsModel(library: nil, defaults: defaults, picture: .sample("parrots"))
        #expect(AdvancedPreset.defaults == .coloringBook && model.currentPreset == .coloringBook)
        #expect(model.changes.isEmpty)
        model.apply(.layered)
        let layered = AdvancedPreset.layered.settings
        #expect(model.currentPreset == .layered)
        #expect(model.lineArt == layered.lineArt && model.lineArt == LineArtSettings(style: .layered))
        #expect(model.tuning == layered.tuning && model.appearance == layered.lineAppearance)
        let stored = Preferences(defaults: defaults)
        #expect(stored.lineArt == layered.lineArt && stored.tuning == layered.tuning && stored.lineAppearance == layered.lineAppearance)
        #expect(layered.lineArt?.normalized == layered.lineArt && layered.tuning?.normalized == layered.tuning
                    && layered.lineAppearance?.normalized == layered.lineAppearance)
        // The preset names the style, so the style line is left out.
        #expect(model.changes == ["Preset Layered"])
        let snapshot = try AdvancedReport.Snapshot(
            app: "1.0 (1)", picture: "parrots", paintingLength: "relaxed", lineArt: #require(layered.lineArt),
            tuning: #require(layered.tuning), lineAppearance: #require(layered.lineAppearance), preview: nil, defaults: nil)
        let text = AdvancedReport.text(snapshot: snapshot, pictureTitle: "Parrots", summary: nil, changes: model.changes, note: "")
        #expect(AdvancedReport.settings(in: text) == layered)
        model.apply(.classic)
        #expect(model.currentPreset == .classic && model.changes == ["Preset Classic"])

        // Back to the defaults: a setting the book ignores (its texture threshold) doesn't
        // unmatch the preset; a setting it reads does, and so does drawing its lines differently.
        model.apply(.coloringBook)
        #expect(model.currentPreset == .coloringBook && model.currentKey == .defaults && model.isAppearanceDefault)
        #expect(model.changes.isEmpty)
        for key in [SettingsKey.lineArt, SettingsKey.pipelineTuning, SettingsKey.lineAppearance] {
            #expect(defaults.data(forKey: key) == nil, "\(key) is stored at the defaults")
        }
        model.lineArt.textureThreshold = 0.2
        #expect(model.currentPreset == .coloringBook)
        model.coloringBookWeight = 1.5
        #expect(model.currentPreset == nil)
        model.coloringBookWeight = 1
        model.set(.minimumCellSize, to: 2)
        #expect(model.currentPreset == nil)
        #expect(model.changes == ["Smallest Area 2×"])
    }

    @Test func pastedSettingsApplyStoreAndReport() throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AdvancedSettingsModel(library: nil, defaults: defaults, picture: .sample("parrots"))
        var kept = LineAppearance.default
        kept.outline.painted = 1
        model.apply(AdvancedReport.Imported(lineArt: Self.changedArt, lineAppearance: kept))
        #expect(model.lineArt == Self.changedArt && model.tuning.isDefault && model.appearance == kept)
        let stored = Preferences(defaults: defaults)
        #expect(stored.lineArt == Self.changedArt && stored.lineAppearance == kept)
        // Lines kept when painted are reported per layer; the preset is still recognized.
        #expect(model.changes.contains("Line Appearance Fade"))
        #expect(model.changes.contains("Outlines When Painted 100%"))
        // A later paste with one group leaves the others.
        model.apply(AdvancedReport.Imported(tuning: Self.changedTuning))
        #expect(model.lineArt == Self.changedArt && model.tuning == Self.changedTuning && model.appearance == kept)
    }

    @Test func layerClarityNamesTheZoomLinesReadFrom() {
        #expect(AdvancedText.clarity(of: .init(opacity: [0.9, 0.9, 0.9], width: [1, 1, 1])) == "Clear in the full view")
        #expect(AdvancedText.clarity(of: .init(opacity: [0.2, 0.5, 0.8], width: [1, 1, 1])) == "Clear from about 2×")
        #expect(AdvancedText.clarity(of: .init(opacity: [0.1, 0.2, 0.3], width: [1, 1, 1])) == "Faint even at 4×")
        #expect(AdvancedText.clarity(of: .init(opacity: [0, 0, 0], width: [1, 1, 1])) == "Hidden at every zoom")
    }

    @Test func reportCarriesEverySettingAsJSON() throws {
        let snapshot = AdvancedReport.Snapshot(
            app: "1.0 (1)", picture: "parrots", paintingLength: "relaxed", lineArt: Self.changedArt,
            tuning: Self.changedTuning, lineAppearance: LineAppearancePreset.grow.applied(to: .default),
            preview: .init(AdvancedStats(areas: 1200, colors: 24)), defaults: .init(AdvancedStats(areas: 1000, colors: 24)))
        let json = AdvancedReport.json(snapshot)
        let decoded = try JSONDecoder().decode(AdvancedReport.Snapshot.self, from: Data(json.utf8))
        #expect(decoded == snapshot)
        #expect(decoded.preview?.minutes == 60)

        let text = AdvancedReport.text(
            snapshot: snapshot, pictureTitle: "Parrots", summary: nil, changes: ["Smallest Area 2×"], note: "  Too busy  ")
        #expect(text.hasPrefix("Paint by Moonlight 1.0 (1): Advanced settings"))
        #expect(text.contains("Picture: Parrots"))
        #expect(text.contains("Changed: Smallest Area 2×"))
        #expect(text.contains("\nToo busy\n"))
        #expect(text.hasSuffix(json))
    }

    @Test func changesAreStoredAndDefaultsAreNot() throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AdvancedSettingsModel(library: nil, defaults: defaults, picture: .sample("parrots"))
        #expect(model.currentKey == .defaults)
        #expect(model.changes.isEmpty)

        model.set(.minimumCellSize, to: 2)
        model.lineArt = model.lineArt.changing(to: .layered)
        model.apply(.grow)
        let stored = Preferences(defaults: defaults)
        #expect(stored.tuning.minimumCellSize == 2)
        #expect(stored.lineArt == LineArtSettings(style: .layered))
        #expect(stored.lineAppearance == LineAppearancePreset.grow.applied(to: .default))
        #expect(model.changes.contains("Smallest Area 2×"))
        #expect(model.changes.contains("Line Style Layered"))
        #expect(model.changes.contains("Line Appearance Grow"))
        #expect(model.activeControl == .style)

        // A new model (the screen opened again) starts from what was stored.
        let reopened = AdvancedSettingsModel(library: nil, defaults: defaults, picture: .sample("parrots"))
        #expect(reopened.currentKey == model.currentKey)
        #expect(reopened.appearance == model.appearance)

        model.reset(.minimumCellSize)
        #expect(model.tuning.isDefault)
        #expect(defaults.data(forKey: SettingsKey.pipelineTuning) == nil, "A default setting was written down")
        model.resetAll()
        for key in [SettingsKey.lineArt, SettingsKey.pipelineTuning, SettingsKey.lineAppearance] {
            #expect(defaults.data(forKey: key) == nil, "\(key) is still stored after Reset All")
        }
        #expect(model.currentKey == .defaults && model.isAppearanceDefault)
    }

    @Test func thresholdsPushEachOtherAlong() throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AdvancedSettingsModel(library: nil, defaults: defaults, picture: .sample("parrots"))
        model.lineArt.style = .layered
        model.set(.textureThreshold, to: 0.9)
        #expect(model.lineArt.textureThreshold == 0.9)
        #expect(model.lineArt.detailThreshold >= 0.9 && model.lineArt.outlineThreshold >= 0.9)
        #expect(model.activeControl == .textureThreshold)
        model.set(.outlineThreshold, to: 0.1)
        #expect(model.lineArt.detailThreshold <= 0.1 && model.lineArt.textureThreshold <= 0.1)
        #expect(model.lineArt == model.lineArt.normalized, "The stored thresholds aren't what generation uses")
    }

    /// The picture is prepared on its suggestion, the preview follows changed settings, every
    /// changed setting gets its effect measured, and another picture starts over.
    @Test func previewFollowsTheSettingsAndMeasuresEffects() async throws {
        let (defaults, suite) = try Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AdvancedSettingsModel(library: nil, defaults: defaults, picture: .sample("parrots"), paintingLength: .quick)
        model.start()
        defer { model.stop() }
        try await waitUntil { model.isIdle && model.preview != nil }
        #expect(model.phase == .ready)
        let baseline = try #require(model.baseline)
        #expect(model.preview?.key == .defaults)
        #expect(model.preview?.stats == baseline)
        // The defaults are a coloring book, so the preview carries line counts (rendered with the edge map).
        #expect(model.statsDelta == .init(areas: 0, colors: 0, lines: 0))
        #expect(baseline.areas >= model.preview?.template.regions.count ?? .max, "Draft areas weren't grown to the full painting")
        #expect(model.effects.values.allSatisfy { $0 == .atDefault })

        // Twice the smallest area: fewer areas than the defaults', and that is its effect.
        model.set(.minimumCellSize, to: 2)
        try await waitUntil { model.isIdle && model.preview?.key == model.currentKey }
        #expect((model.statsDelta?.areas ?? 0) < 0, "The preview's areas didn't go down from the defaults'")
        if case .measured(let delta) = model.effects[.minimumCellSize] {
            #expect(delta.areas < 0, "Twice the smallest area didn't lower the areas: \(delta)")
        } else {
            Issue.record("Smallest Area's effect wasn't measured: \(String(describing: model.effects[.minimumCellSize]))")
        }

        model.lineArt.style = .layered
        try await waitUntil { model.isIdle && model.preview?.key == model.currentKey }
        #expect(!model.isUpdating)
        for control in [AdvancedControl.style, .minimumCellSize] {
            guard case .measured = model.effects[control] else {
                Issue.record("The effect of \(control) wasn't measured: \(String(describing: model.effects[control]))")
                continue
            }
        }
        #expect(model.effects[.smoothing] == .atDefault)

        // Back to the defaults: their preview was kept, so it shows at once.
        #expect(model.preview?.key != .defaults)
        model.resetAll()
        #expect(model.preview?.key == .defaults)
        #expect(!model.isUpdating)

        model.choose(.sample("hibiscus"))
        #expect(model.phase == .loading)
        #expect(defaults.string(forKey: SettingsKey.advancedPreviewPicture) == "sample:hibiscus")
        try await waitUntil { model.isIdle && model.phase == .ready }
        #expect(model.pictureTitle == Sample.named("hibiscus")?.title)
        #expect(model.baseline != baseline)
        // The choice is remembered for the next time the screen opens.
        #expect(AdvancedSettingsModel(library: nil, defaults: defaults).picture == .sample("hibiscus"))
    }

    @Test func picturesSurviveTheirStorage() {
        let id = UUID()
        for picture in [AdvancedSettingsModel.Picture.sample("great-wave"), .photo(id)] {
            #expect(AdvancedSettingsModel.Picture(storageValue: picture.storageValue) == picture)
        }
        #expect(AdvancedSettingsModel.Picture(storageValue: "photo:not-a-uuid") == nil)
        #expect(AdvancedSettingsModel.Picture(storageValue: "") == nil)
    }

    private static func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "AdvancedSettingsTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func waitUntil(timeout: Duration = .seconds(120), _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for the Advanced settings model")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
