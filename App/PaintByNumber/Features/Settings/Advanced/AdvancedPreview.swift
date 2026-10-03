import CoreGraphics
import PaintCore
import SwiftUI
import UIKit
import simd

/// Lets the Advanced screen drive the preview's canvas (zoom buttons, the zoom strip) and
/// hands the camera from one canvas to the next when a new template replaces the old.
final class PreviewCanvasController {
    fileprivate weak var view: CanvasView?

    func zoom(to level: CGFloat) { view?.zoom(toRelative: level) }

    /// Where a canvas of a `width` × `height` template should open: where the current one
    /// looks, when it shows a template of that size (the same picture), else nil (fitted).
    fileprivate func camera(forWidth width: Int, height: Int) -> CanvasCamera? {
        guard let view, view.bounds.width > 1, view.bounds.height > 1,
              view.session.template.width == width, view.session.template.height == height
        else { return nil }
        return view.camera
    }
}

/// The preview's zoom levels: 1 shows the whole picture.
enum PreviewZoom {
    static let levels = [1, 2, 4]

    /// The level `zoom` is at (within a tenth), if any.
    static func level(near zoom: CGFloat) -> Int? {
        levels.first { abs(log2(max(zoom, 0.01) / CGFloat($0))) < 0.14 }
    }
}

/// The real painting canvas, showing the preview's template the way painting shows it: touches
/// only navigate (no paint is on the brush), and Template / Painted fills or clears every area.
private struct AdvancedPreviewCanvas: UIViewRepresentable {
    let preview: AdvancedSettingsModel.Preview
    let showsPainted: Bool
    let paperAppearance: PaperAppearance
    let lineAppearance: LineAppearance
    let controller: PreviewCanvasController
    var onZoomChange: (CGFloat) -> Void
    var onUnavailable: () -> Void


    final class Coordinator {
        var session: PaintingSession?
        var showsPainted = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CanvasView {
        let template = preview.template
        var progress = PaintProgress(regionCount: template.regions.count)
        if showsPainted {
            for region in template.regions.indices { progress.paint(region) }
        }
        let session = (try? PaintingSession(template: template, progress: progress)) ?? PaintingSession(template: template)
        // No paint on the brush: touches navigate, nothing is highlighted.
        session.select(color: nil)
        let view = CanvasView(session: session)
        view.initialCamera = controller.camera(forWidth: template.width, height: template.height)
        view.chromeInsets = UIEdgeInsets(
            top: AdvancedPreviewCard.overlayInset, left: 0, bottom: AdvancedPreviewCard.overlayInset, right: 0)
        view.paperAppearance = paperAppearance
        view.lineAppearance = lineAppearance
        view.reduceMotion = context.environment.accessibilityReduceMotion
        view.onZoomChange = onZoomChange
        // The card is one VoiceOver element of its own; the canvas's areas and actions are for painting.
        view.accessibilityElementsHidden = true
        context.coordinator.session = session
        context.coordinator.showsPainted = showsPainted
        controller.view = view
        // Deferred: state mustn't change while SwiftUI is making views.
        if !view.isRenderable { Task { onUnavailable() } }
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.paperAppearance = paperAppearance
        // Drawing only: the open canvas redraws at once.
        view.lineAppearance = lineAppearance
        view.reduceMotion = context.environment.accessibilityReduceMotion
        view.onZoomChange = onZoomChange
        let coordinator = context.coordinator
        guard let session = coordinator.session, coordinator.showsPainted != showsPainted else { return }
        coordinator.showsPainted = showsPainted
        let painted = showsPainted
        // After this update: painting notifies the canvas, which must not happen mid-update.
        Task { @MainActor in
            if painted {
                let t = session.template
                session.paint(Array(t.regions.indices), from: SIMD2(Float(t.width), Float(t.height)) / 2, animated: true)
            } else {
                session.reset()
                session.select(color: nil)
            }
        }
    }
}

/// Stands in for the canvas where Metal can't draw: the same template, rendered once.
private struct AdvancedRasterPreview: View {
    let preview: AdvancedSettingsModel.Preview
    let showsPainted: Bool
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.vertical, AdvancedPreviewCard.overlayInset + 16)
                    .padding(.horizontal, 16)
            }
        }
        .task(id: showsPainted) {
            let template = preview.template, painted = showsPainted
            image = await Background.run {
                TemplateRasterizer.image(template, style: painted ? .finished : .template, maxPixelSize: 1600)
            }
        }
    }
}

/// The preview card: the canvas with the picture menu, a quiet progress cue, Template /
/// Painted and the zoom levels floating over it.
struct AdvancedPreviewCard: View {
    /// Room for the overlays above and below the painting, in points.
    static let overlayInset: CGFloat = 30

    @Bindable var model: AdvancedSettingsModel
    @Binding var showsPainted: Bool
    let zoom: CGFloat
    let controller: PreviewCanvasController
    var onZoomChange: (CGFloat) -> Void

    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var canvasUnavailable = false
    @State private var showsCue = false
    @State private var width: CGFloat = 0
    @State private var seen: Shown?

    /// What the card shows of the model. Like the numbers (`AdvancedStatsBar`), the card once
    /// stayed on its spinner under a finished preview, so it checks the model itself too.
    private struct Shown: Equatable {
        var preview: UUID?
        var phase: AdvancedSettingsModel.Phase
        var isUpdating: Bool
        var appearance: LineAppearance
        var title: String
    }

    private var shown: Shown {
        Shown(preview: model.preview?.id, phase: model.phase, isUpdating: model.isUpdating,
              appearance: model.appearance, title: model.pictureTitle)
    }

    var body: some View {
        // Read so that the checks below redraw the card when what it shows has changed.
        let _ = seen
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if let preview = model.preview {
                Group {
                    if canvasUnavailable {
                        AdvancedRasterPreview(preview: preview, showsPainted: showsPainted)
                    } else {
                        AdvancedPreviewCanvas(
                            preview: preview, showsPainted: showsPainted, paperAppearance: paperAppearance,
                            lineAppearance: model.appearance, controller: controller, onZoomChange: onZoomChange,
                            onUnavailable: { canvasUnavailable = true })
                    }
                }
                .id(preview.id)
                .transition(.opacity)
                .accessibilityHidden(true)
                // An earlier picture's preview stays up, dimmed, until the new one is ready.
                .opacity(model.phase == .loading ? 0.4 : 1)
            } else if case .failed(let message) = model.phase {
                ContentUnavailableView("Couldn’t Open Picture", systemImage: "photo.badge.exclamationmark", description: Text(message))
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay { accessibilityElement }
        .overlay(alignment: .topLeading) { picturePicker.padding(8) }
        .overlay(alignment: .topTrailing) { cue.padding(8) }
        .overlay(alignment: .bottom) { bottomBar.padding(8) }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .task(id: isBusy) {
            // Only work that takes a moment shows the cue, so quick updates don't flicker it.
            if isBusy {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsCue = isBusy }
        }
        .task {
            while !Task.isCancelled {
                let current = shown
                if current != seen { seen = current }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private var isBusy: Bool { model.isUpdating || model.phase == .loading }

    // MARK: Overlays

    private var picturePicker: some View {
        Menu {
            if let recent = model.recentPhoto {
                Section("Your Photo") {
                    pictureButton(.photo(recent.id), title: recent.title)
                }
            }
            Section("Paintings") {
                ForEach(Sample.all(of: .painting)) { sample in pictureButton(.sample(sample.id), title: sample.title) }
            }
            Section("Photographs") {
                ForEach(Sample.all(of: .photograph)) { sample in pictureButton(.sample(sample.id), title: sample.title) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .imageScale(.small)
                Text(model.pictureTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        // As wide as the title, leaving room for the progress cue beside it.
        .frame(maxWidth: max(140, min(320, width - 150)), alignment: .leading)
        .accessibilityLabel("Picture")
        .accessibilityValue(Text(model.pictureTitle))
        .accessibilityIdentifier("advanced-picture")
    }

    private func pictureButton(_ picture: AdvancedSettingsModel.Picture, title: String) -> some View {
        Button {
            model.choose(picture)
        } label: {
            if model.picture == picture {
                SwiftUI.Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private var cue: some View {
        if showsCue {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.mini)
                if model.phase == .loading {
                    Text("Opening Picture…")
                } else {
                    Text("Updating…")
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("advanced-progress")
        }
    }

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                layerSegments
                Spacer(minLength: 8)
                zoomSegments
            }
            VStack(spacing: 6) {
                layerSegments
                zoomSegments
            }
        }
    }

    private var layerSegments: some View {
        GlassSegments(
            segments: [
                GlassSegment(value: false, title: String(localized: "advanced.preview.template", defaultValue: "Template",
                                                         comment: "Settings › Advanced: preview choice showing the template's lines and numbers, as a painting starts")),
                GlassSegment(value: true, title: String(localized: "advanced.preview.painted", defaultValue: "Painted",
                                                        comment: "Settings › Advanced: preview choice showing every area painted, as a finished painting")),
            ],
            selection: showsPainted
        ) { painted in
            guard painted != showsPainted else { return }
            FeedbackEngine.shared.selectionChanged()
            showsPainted = painted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
        .accessibilityIdentifier("advanced-painted")
    }

    private var zoomSegments: some View {
        GlassSegments(
            segments: PreviewZoom.levels.map { GlassSegment(value: $0, title: AdvancedText.zoom($0)) },
            selection: PreviewZoom.level(near: zoom),
            leading: PreviewZoom.level(near: zoom) == nil ? AdvancedText.multiplier((Double(zoom) * 10).rounded() / 10) : nil
        ) { level in
            FeedbackEngine.shared.selectionChanged()
            controller.zoom(to: CGFloat(level))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(localized: "advanced.preview.zoom", defaultValue: "Zoom",
                                        comment: "Settings › Advanced: VoiceOver label of the preview's zoom levels (1×, 2×, 4×)")))
        .accessibilityIdentifier("advanced-zoom")
    }

    /// The canvas as one VoiceOver element: what it shows, adjustable through the zoom levels.
    private var accessibilityElement: some View {
        let title = model.pictureTitle
        let shows = showsPainted
            ? String(localized: "advanced.preview.painted", defaultValue: "Painted",
                     comment: "Settings › Advanced: preview choice showing every area painted, as a finished painting")
            : String(localized: "advanced.preview.template", defaultValue: "Template",
                     comment: "Settings › Advanced: preview choice showing the template's lines and numbers, as a painting starts")
        let zoomText = AdvancedText.multiplier((Double(zoom) * 10).rounded() / 10)
        return Rectangle()
            .fill(.clear)
            .contentShape(.rect)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text(String(localized: "advanced.preview.label", defaultValue: "Preview of \(title)",
                                            comment: "Settings › Advanced: VoiceOver label of the preview canvas; the argument is the picture's title")))
            .accessibilityValue(Text(String(localized: "advanced.preview.value", defaultValue: "\(shows), zoom \(zoomText)",
                                            comment: "Settings › Advanced: VoiceOver value of the preview canvas; the arguments are Template or Painted, and the zoom such as 2×")))
            .accessibilityHint(Text(String(localized: "advanced.preview.hint", defaultValue: "Swipe up or down to zoom.",
                                           comment: "Settings › Advanced: VoiceOver hint of the preview canvas")))
            .accessibilityAdjustableAction { direction in
                let levels = PreviewZoom.levels.map { CGFloat($0) }
                var next: CGFloat?
                switch direction {
                case .increment: next = levels.first { $0 > zoom * 1.05 }
                case .decrement: next = levels.last { $0 < zoom / 1.05 }
                @unknown default: break
                }
                if let next { controller.zoom(to: next) }
            }
            .accessibilityIdentifier("advanced-preview")
    }
}

/// One choice of `GlassSegments`.
struct GlassSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

/// A row of choices in a glass capsule, the chosen one on the signature color: the preview's
/// floating controls, which sit over the canvas like the painting screen's.
struct GlassSegments<Value: Hashable>: View {
    let segments: [GlassSegment<Value>]
    /// Nil highlights none (a pinched zoom between levels).
    let selection: Value?
    /// Text before the choices (the zoom between levels).
    var leading: String?
    var onSelect: (Value) -> Void
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            if let leading {
                Text(leading)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.trailing, 2)
                    .accessibilityHidden(true)
            }
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button {
                    onSelect(segment.value)
                } label: {
                    Text(segment.title)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.signature)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

/// The preview's numbers (areas, colors, painting time), estimated for the full painting, each
/// with its change from the default settings.
struct AdvancedStatsRow: View {
    let stats: AdvancedStats?
    let delta: AdvancedStats.Delta?
    /// Every setting is at its default.
    let isAtDefaults: Bool
    /// The numbers are behind the settings (a new preview is on its way).
    let isStale: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Not a ViewThatFits of a row and a column: the numbers inside it stayed "–" under a
        // finished preview when Advanced was opened from Settings.
        let layout = isStacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout { chips }
            .opacity(isStale ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.2), value: isStale)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Side by side, unless text this large would crowd three chips across a narrow screen.
    private var isStacked: Bool { horizontalSizeClass == .compact && dynamicTypeSize >= .xxLarge }

    @ViewBuilder
    private var chips: some View {
        StatChip(
            label: String(localized: "advanced.stat.areas", defaultValue: "Areas",
                          comment: "Settings › Advanced: label of the preview's estimated number of areas to paint"),
            value: stats?.areas.formatted(), change: change(delta?.areas),
            isChanged: (delta?.areas ?? 0) != 0, identifier: "advanced-stat-areas")
        StatChip(
            label: String(localized: "advanced.stat.colors", defaultValue: "Colors",
                          comment: "Settings › Advanced: label of the preview's number of paints"),
            value: stats?.colors.formatted(), change: change(delta?.colors),
            isChanged: (delta?.colors ?? 0) != 0, identifier: "advanced-stat-colors")
        StatChip(
            label: String(localized: "advanced.stat.time", defaultValue: "Painting Time",
                          comment: "Settings › Advanced: label of the preview's estimated painting time"),
            value: stats.map { PaintingTime.approximate($0.seconds) }, change: timeChange,
            isChanged: minutes != 0, identifier: "advanced-stat-time")
    }

    private var minutes: Int { Int(((delta?.seconds ?? 0) / 60).rounded()) }

    private func change(_ value: Int?) -> String? {
        guard let value else { return nil }
        if value != 0 { return AdvancedText.signed(value) }
        return isAtDefaults ? Self.defaultText : Self.sameText
    }

    private var timeChange: String? {
        guard delta != nil else { return nil }
        if minutes != 0 { return AdvancedText.signedDuration(Double(minutes) * 60) }
        return isAtDefaults ? Self.defaultText : Self.sameText
    }

    private static var defaultText: String {
        String(localized: "advanced.stat.default", defaultValue: "Default",
               comment: "Settings › Advanced: under a preview number when every setting is at its default")
    }

    private static var sameText: String {
        String(localized: "advanced.stat.same", defaultValue: "Same as default",
               comment: "Settings › Advanced: under a preview number the changed settings leave as it is at the defaults")
    }
}

private struct StatChip: View {
    let label: String
    let value: String?
    let change: String?
    let isChanged: Bool
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value ?? "–")
                .font(.display(.title3, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(change ?? " ")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isChanged ? Theme.accent : Color.secondary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .animation(.snappy, value: value)
        .animation(.snappy, value: change)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityShowsLargeContentViewer()
        .accessibilityIdentifier(identifier)
    }

    private var accessibilityValue: String {
        guard let value else { return "" }
        guard let change else { return value }
        return String(localized: "advanced.stat.value", defaultValue: "\(value), \(change)",
                      comment: "Settings › Advanced: VoiceOver value of a preview number; the arguments are the number and its change from the defaults, e.g. 1,243, +212")
    }
}
