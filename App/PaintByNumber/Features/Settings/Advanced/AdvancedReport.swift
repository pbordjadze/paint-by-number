import Foundation
import PaintCore

/// The text Copy Settings and Share with a Note hand over: what the painter saw (picture,
/// numbers, every setting that differs from its default, their note) and the settings as JSON,
/// which reproduce the preview exactly for a library picture (generation is deterministic).
/// Paste Settings reads the same text back (`settings(in:)`), so settings travel between
/// devices, and a preset is any text written like it (`docs/presets/`).
nonisolated enum AdvancedReport {
    /// The settings a pasted text holds: each group the text has, clamped to its range.
    struct Imported: Equatable, Sendable {
        var lineArt: LineArtSettings?
        var tuning: PipelineTuning?
        var lineAppearance: LineAppearance?

        var isEmpty: Bool { lineArt == nil && tuning == nil && lineAppearance == nil }
    }

    /// The settings in `text`: the JSON object in it that holds any of the three groups, read
    /// the way stored settings are (fields a build doesn't know fall back to their defaults),
    /// clamped. Nil when there is none. Objects are tried from each `{` to the last `}`, so a
    /// note before the JSON may hold braces.
    static func settings(in text: String) -> Imported? {
        guard let close = text.lastIndex(of: "}") else { return nil }
        var start = text.startIndex
        while let open = text[start..<close].firstIndex(of: "{") {
            if let groups = try? JSONDecoder().decode(Groups.self, from: Data(text[open...close].utf8)) {
                let imported = Imported(
                    lineArt: groups.lineArt?.normalized, tuning: groups.tuning?.normalized,
                    lineAppearance: groups.lineAppearance?.normalized)
                return imported.isEmpty ? nil : imported
            }
            start = text.index(after: open)
        }
        return nil
    }

    /// The three groups of the snapshot, each optional and read leniently: a group that is not
    /// an object counts as absent.
    private struct Groups: Decodable {
        var lineArt: LineArtSettings?
        var tuning: PipelineTuning?
        var lineAppearance: LineAppearance?

        private enum CodingKeys: String, CodingKey { case lineArt, tuning, lineAppearance }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lineArt = try? c.decodeIfPresent(LineArtSettings.self, forKey: .lineArt)
            tuning = try? c.decodeIfPresent(PipelineTuning.self, forKey: .tuning)
            lineAppearance = try? c.decodeIfPresent(LineAppearance.self, forKey: .lineAppearance)
        }
    }

    struct Snapshot: Codable, Equatable, Sendable {
        struct Numbers: Codable, Equatable, Sendable {
            var areas: Int
            var colors: Int
            var minutes: Int

            init(_ stats: AdvancedStats) {
                areas = stats.areas
                colors = stats.colors
                minutes = Int((stats.seconds / 60).rounded())
            }
        }

        var app: String
        /// The library picture's id, or "photo" for the painter's own.
        var picture: String
        var paintingLength: String
        var lineArt: LineArtSettings
        var tuning: PipelineTuning
        var lineAppearance: LineAppearance
        var preview: Numbers?
        var defaults: Numbers?
    }

    static func json(_ snapshot: Snapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// - Parameters:
    ///   - changes: The settings that differ from their defaults, already worded.
    ///   - summary: The preview's numbers, already worded; nil before there is a preview.
    static func text(snapshot: Snapshot, pictureTitle: String, summary: String?, changes: [String], note: String) -> String {
        let app = snapshot.app
        var lines = [
            String(localized: "advanced.report.title", defaultValue: "Paint by Moonlight \(app): Advanced settings",
                   comment: "First line of the settings text Settings › Advanced copies or shares for feedback; the argument is the app version, e.g. 1.0.42 (42)"),
            String(localized: "advanced.report.picture", defaultValue: "Picture: \(pictureTitle)",
                   comment: "Line of the shared Advanced settings text: the picture the preview showed; the argument is its title"),
        ]
        if let summary {
            lines.append(String(localized: "advanced.report.preview", defaultValue: "Preview: \(summary)",
                                comment: "Line of the shared Advanced settings text: the preview's numbers; the argument is e.g. 24 colors · 1,284 areas · ~1 h, +212 areas from the defaults"))
        }
        if changes.isEmpty {
            lines.append(String(localized: "advanced.report.allDefault", defaultValue: "Every setting is at its default.",
                                comment: "Line of the shared Advanced settings text when nothing was changed"))
        } else {
            let list = changes.formatted(.list(type: .and))
            lines.append(String(localized: "advanced.report.changes", defaultValue: "Changed: \(list)",
                                comment: "Line of the shared Advanced settings text listing the changed settings; the argument is a list such as Line Style Layered and Smallest Area 2×"))
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append("")
            lines.append(trimmed)
        }
        lines.append("")
        lines.append(json(snapshot))
        return lines.joined(separator: "\n")
    }
}

extension AdvancedSettingsModel {
    /// Every setting that differs from its default, worded ("Smallest Area 2×"), after the
    /// preset they add up to, if any.
    var changes: [String] {
        var list: [String] = []
        // A preset other than the defaults names the style, so the style line is left out.
        let preset = currentPreset
        if let preset, preset != .defaults {
            list.append(Self.change(AdvancedText.presetTitle, preset.name))
        }
        for control in AdvancedControl.allCases
        where isChanged(control) && control.applies(to: lineArt.style) && (control != .style || preset == nil) {
            list.append(Self.change(control.title(for: lineArt.style), valueText(of: control)))
        }
        var layers = appearance
        layers.coloringBookWeight = LineAppearance.default.coloringBookWeight
        if layers != .default {
            let value = LineAppearancePreset.matching(appearance)?.name
                ?? String(localized: "advanced.preset.custom", defaultValue: "Custom",
                          comment: "Settings › Advanced › Line Appearance: the layers' values match no preset; in shared settings text")
            list.append(Self.change(AdvancedText.lineAppearanceTitle, value))
            if appearance.weighted != LineAppearance.default.weighted {
                list.append(Self.change(AdvancedText.weightTitle, AdvancedText.onOff(appearance.weighted)))
            }
            for layer in LineLayer.allCases where appearance[layer].painted != LineAppearance.default[layer].painted {
                list.append(Self.change(AdvancedText.paintedTitle(of: layer), AdvancedText.percent(appearance[layer].painted)))
            }
        }
        if appearance.coloringBookWeight != LineAppearance.default.coloringBookWeight {
            list.append(Self.change(AdvancedText.coloringBookWeightTitle, AdvancedText.multiplier(Double(appearance.coloringBookWeight))))
        }
        return list
    }

    private static func change(_ title: String, _ value: String) -> String {
        String(localized: "advanced.report.change", defaultValue: "\(title) \(value)",
               comment: "Settings › Advanced: one changed setting in shared settings text, e.g. Smallest Area 2×; the arguments are the setting's name and its value")
    }

    /// The preview's numbers worded for the shared text, with their change from the defaults.
    var summary: String? {
        guard let stats = preview?.stats else { return nil }
        let numbers = TemplateCounts.summary(colors: stats.colors, areas: stats.areas, seconds: stats.seconds)
        guard let delta = statsDelta, !delta.isZero else { return numbers }
        let effect = AdvancedText.effect(delta)
        return String(localized: "advanced.report.numbersWithChange", defaultValue: "\(numbers) (\(effect) from the defaults)",
                      comment: "Settings › Advanced: the preview's numbers and their change from the default settings in shared settings text; the arguments are the numbers and the change, e.g. +212 areas")
    }

    /// The text Copy Settings and Share with a Note hand over.
    func report(note: String = "") -> String {
        let snapshot = AdvancedReport.Snapshot(
            app: AppInfo().summary, picture: pictureID, paintingLength: paintingLength.rawValue, lineArt: lineArt,
            tuning: tuning, lineAppearance: appearance, preview: preview.map { .init($0.stats) },
            defaults: baseline.map { .init($0) })
        return AdvancedReport.text(snapshot: snapshot, pictureTitle: pictureTitle, summary: summary, changes: changes, note: note)
    }

    private var pictureID: String {
        switch picture {
        case .sample(let id): id
        case .photo: "photo"
        }
    }
}
