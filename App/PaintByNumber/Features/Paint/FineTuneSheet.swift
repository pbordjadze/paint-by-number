#if UNRELEASED
import PaintCore
import SwiftUI

/// Fine-Tune (painting-company row 352): the length chip's way to a painting's Colors, Detail and
/// Lines, which went with the create flow's preview when a picked picture began opening straight
/// as a painting (row 239). Its sliders are the preview's (`SettingSlider`), opening on what the
/// painting was cut with, each with a detent there, Colors on the paints its palette has (rich
/// paint gives a face paints of its own and drops any unused, so the count asked for is not the
/// count the painter sees); Cut Again makes the painting again with them (`Library.retune`). A
/// compact sheet, as tall as its sliders, so the painting stays in view above it. SideStore and
/// Debug builds, until Paul chooses it for a release.
struct FineTuneSheet: View {
    /// What the painting was cut with.
    let settings: GenerationSettings
    /// The paints the painting has.
    let paints: Int
    var onCut: (GenerationSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var colorCount: Double
    @State private var detail: Double
    @State private var lines: Double
    private let openingLines: Double
    /// The sliders' height, which the sheet's is fitted to.
    @State private var contentHeight: CGFloat = 300

    init(settings: GenerationSettings, paints: Int, onCut: @escaping (GenerationSettings) -> Void) {
        self.settings = settings
        self.paints = min(max(paints, GenerationSettings.colorCountRange.lowerBound), GenerationSettings.colorCountRange.upperBound)
        self.onCut = onCut
        _colorCount = State(initialValue: Double(self.paints))
        _detail = State(initialValue: Double(settings.detail))
        let position = Self.linesPosition(of: settings.lineArt)
        _lines = State(initialValue: position)
        openingLines = position
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingSlider(
                        title: "Colors", value: TemplatePreviewView.colorPosition(colorCount),
                        onChange: { colorCount = TemplatePreviewView.colorCount(at: $0) },
                        valueText: Int(colorCount.rounded()).formatted(),
                        detent: TemplatePreviewView.colorPosition(Double(paints)), onEditing: { _ in })
                        .accessibilityIdentifier("fine-tune-colors")
                    SettingSlider(
                        title: "Detail", value: detail, onChange: { detail = $0 },
                        valueText: TemplatePreviewView.detailWord(detail),
                        detent: Double(settings.detail), onEditing: { _ in })
                        .accessibilityIdentifier("fine-tune-detail")
                    if hasLines {
                        SettingSlider(
                            title: "Lines", value: lines, onChange: { lines = $0 },
                            valueText: TemplatePreviewView.linesWord(lines),
                            detent: openingLines, onEditing: { _ in })
                            .accessibilityIdentifier("fine-tune-lines")
                    }
                }
                .padding(20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .navigationTitle("Fine-Tune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cut Again") {
                        onCut(made)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(made == settings.normalized)
                    .accessibilityIdentifier("fine-tune-cut")
                }
            }
        }
        // The navigation bar's height above the sliders.
        .presentationDetents([.height(contentHeight + 64), .large])
    }

    /// Classic line art has no lines to tune.
    private var hasLines: Bool { settings.lineArt.style != .classic }

    /// The painting's settings with the sliders' values; its line art untouched while Lines is
    /// where it opened, so a painting not tuned there keeps its own exactly.
    private var made: GenerationSettings {
        var made = settings
        // Colors where it opened asks for what the painting was cut with.
        if Int(colorCount.rounded()) != paints { made.colorCount = Int(colorCount.rounded()) }
        made.detail = Float(detail)
        if hasLines && lines != openingLines {
            made.lineArt = Self.lineArt(settings.lineArt, lines: lines)
        }
        return made.normalized
    }

    /// Where the Lines slider stands for `art`: the create flow's slider moves the style's
    /// defaults (`CreateModel.lineArt(_:lines:)`), the shortest line halving toward More and
    /// growing half again toward Fewer, so that length says where it was left. The middle for
    /// line art the slider can't have made.
    static func linesPosition(of art: LineArtSettings) -> Double {
        let base = LineArtSettings(style: art.style).normalized
        guard art.style != .classic, base.minimumStrokeLength > 0 else { return 0.5 }
        let more = Double(1 - art.minimumStrokeLength / base.minimumStrokeLength) / 0.5
        return min(max(0.5 + more / 2, 0), 1)
    }

    /// `art` with the Lines slider at `lines`: the thresholds and shortest line it moves, from
    /// the style's defaults as the create flow's slider moves them; the rest of `art` kept.
    static func lineArt(_ art: LineArtSettings, lines: Double) -> LineArtSettings {
        let tuned = CreateModel.lineArt(LineArtSettings(style: art.style).normalized, lines: lines)
        var made = art
        made.outlineThreshold = tuned.outlineThreshold
        made.detailThreshold = tuned.detailThreshold
        made.minimumStrokeLength = tuned.minimumStrokeLength
        return made.normalized
    }
}
#endif
