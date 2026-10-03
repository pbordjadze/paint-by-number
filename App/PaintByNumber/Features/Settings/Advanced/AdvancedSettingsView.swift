import PaintCore
import SwiftUI
import UIKit

/// Settings › Advanced (Experimental): line art, line appearance and pipeline tuning for new
/// paintings, with a live preview pinned on top (beside the controls in wide windows). Every
/// control shows its value, a line on what it does and what it does to the preview right now.
struct AdvancedSettingsView: View {
    @State private var model: AdvancedSettingsModel
    private let onClose: (() -> Void)?
    @State private var controller = PreviewCanvasController()
    @State private var zoom: CGFloat = 1
    @State private var showsPainted = false
    @State private var size: CGSize = .zero
    @State private var isSharing = false
    @State private var isConfirmingReset = false
    @State private var copied = false
    @State private var pasted = false
    @State private var pasteFailed = false
    #if DEBUG
    @State private var didPrepareDemo = false
    #endif

    /// - Parameters:
    ///   - picture: The picture to preview (demo scenarios); nil picks it as the model does.
    ///   - onClose: Shows a Done button (the screen was presented over the whole window).
    init(library: Library?, picture: AdvancedSettingsModel.Picture? = nil, onClose: (() -> Void)? = nil) {
        _model = State(initialValue: AdvancedSettingsModel(library: library, picture: picture))
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if isSideBySide {
                HStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)
                        FittedCard(model: model, height: { sideCardHeight(aspect: $0) }) { card }
                        stats
                        Text(Self.estimateNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    controls
                        .frame(width: controlsWidth)
                }
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        FittedCard(model: model, height: { compactCardHeight(aspect: $0) }) { card }
                        stats
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    Divider()
                    controls
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .navigationTitle("Advanced")
        .navigationSubtitle("Experimental")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if let onClose {
                    Button("Done", systemImage: "checkmark", action: onClose)
                }
            }
        }
        .task { model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: $isSharing) {
            AdvancedShareSheet(model: model)
        }
    }

    // MARK: Layout

    /// The preview beside the controls in wide windows (iPad, iPhone in landscape).
    private var isSideBySide: Bool { size.width >= 900 || (size.width >= 640 && size.width > size.height) }
    private var controlsWidth: CGFloat { min(440, max(360, size.width * 0.4)) }
    /// Pinned on top, the preview takes about a third of the height, so the controls keep room;
    /// less when the picture is wide enough not to need it.
    private func compactCardHeight(aspect: CGFloat) -> CGFloat {
        min(max(size.height * 0.36, 210), 360, fittedCardHeight(width: size.width - 32, aspect: aspect))
    }

    /// Beside the controls, the card is as tall as the picture needs, within the column.
    private func sideCardHeight(aspect: CGFloat) -> CGFloat {
        let room = size.height - 220
        return max(240, min(room, fittedCardHeight(width: size.width - controlsWidth - 40, aspect: aspect)))
    }

    /// A card `width` wide that shows the whole picture (`aspect` = width / height) with the
    /// canvas's margins and the overlays above and below it.
    private func fittedCardHeight(width: CGFloat, aspect: CGFloat) -> CGFloat {
        max(0, width - 32) / aspect + 2 * (AdvancedPreviewCard.overlayInset + 16) + 8
    }

    private static var estimateNote: String {
        String(localized: "advanced.estimateNote",
               defaultValue: "The preview is a quick, smaller version of the picture; its numbers are estimated for the full painting.",
               comment: "Settings › Advanced: note on the preview's numbers (areas, colors, painting time)")
    }

    private var card: some View {
        AdvancedPreviewCard(
            model: model, showsPainted: $showsPainted, zoom: zoom, controller: controller,
            onZoomChange: { value in
                // Reported from UIKit's layout and scrolling: applied after the current update.
                Task { @MainActor in if abs(zoom - value) > 0.005 { zoom = value } }
            })
    }

    private var stats: some View { AdvancedStatsBar(model: model) }

    // MARK: Controls

    private var controls: some View {
        ScrollViewReader { proxy in
            Form {
                introSection
                lineArtSection
                LineAppearanceSection(model: model, zoom: zoom) { level in controller.zoom(to: CGFloat(level)) }
                pipelineSection
                PaintingEffectsSections()
                feedbackSection
            }
            .accessibilityIdentifier("advanced-controls")
            #if DEBUG
            .onChange(of: isDemoSettled) { _, settled in
                guard settled, !didPrepareDemo, let demo = ShellDemo.current, demo.opensAdvanced else { return }
                didPrepareDemo = true
                if let anchor = demo.advancedScrollAnchor { proxy.scrollTo(anchor, anchor: .top) }
                if let level = demo.advancedZoom { controller.zoom(to: level) }
                Task {
                    // The scroll and the zoom settle first.
                    try? await Task.sleep(for: .seconds(1))
                    DemoMode.markReady()
                }
            }
            #endif
        }
    }

    #if DEBUG
    /// The preview shows the current settings and every effect is measured.
    private var isDemoSettled: Bool { model.isIdle && model.preview?.key == model.currentKey }
    #endif

    private var introSection: some View {
        Section {
            SwiftUI.Label {
                Text("Line Art and Pipeline settings apply to new paintings. Line Appearance changes how every layered painting is drawn.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "flask")
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityIdentifier("advanced-intro")
        } footer: {
            if !isSideBySide {
                Text(Self.estimateNote)
            }
        }
    }

    private var lineArtSection: some View {
        Section {
            LineStyleRow(model: model)
                .id("advanced-lineArt")
            if model.lineArt.style == .layered {
                SensitivityBand(lineArt: model.lineArt, lines: model.preview?.stats.lines)
                ForEach(AdvancedControl.thresholds, id: \.self) { control in
                    AdvancedSliderRow(control: control, model: model)
                }
                AdvancedSliderRow(control: .minimumStrokeLength, model: model)
                AdvancedSliderRow(control: .gapBridging, model: model)
                AdvancedSliderRow(control: .lineSmoothing, model: model)
                SamePaintRow(model: model)
                AdvancedToggleRow(
                    title: AdvancedControl.keepColorEdges.title, summary: AdvancedControl.keepColorEdges.summary,
                    isOn: $model.lineArt.keepColorEdges, effect: model.effects[.keepColorEdges] ?? .atDefault,
                    identifier: "advanced-control-keepColorEdges")
                AdvancedToggleRow(
                    title: AdvancedControl.outlineEyes.title, summary: AdvancedControl.outlineEyes.summary,
                    isOn: $model.lineArt.outlineEyes, effect: model.effects[.outlineEyes] ?? .atDefault,
                    identifier: "advanced-control-outlineEyes")
            }
        } header: {
            AdvancedSectionHeader(
                title: String(localized: "advanced.section.lineArt", defaultValue: "Line Art",
                              comment: "Settings › Advanced: header of the section on how a template's lines are made"),
                canReset: !model.isLineArtDefault, identifier: "advanced-reset-lineArt") { model.resetLineArt() }
        }
    }

    private var pipelineSection: some View {
        Section {
            ForEach(AdvancedControl.pipeline, id: \.self) { control in
                AdvancedSliderRow(control: control, model: model)
                    .id(control == AdvancedControl.pipeline.first ? "advanced-pipeline" : control.rawValue)
            }
        } header: {
            AdvancedSectionHeader(
                title: String(localized: "advanced.section.pipeline", defaultValue: "Pipeline",
                              comment: "Settings › Advanced: header of the section of multipliers on the template generator's own settings"),
                canReset: !model.isTuningDefault, identifier: "advanced-reset-pipeline") { model.resetTuning() }
        } footer: {
            Text("Each multiplies what the generator works out for the picture; 1× leaves it as it is.")
        }
    }

    private var feedbackSection: some View {
        Section {
            Button(action: copy) {
                if copied {
                    SwiftUI.Label("Copied", systemImage: "checkmark")
                } else {
                    SwiftUI.Label("Copy Settings", systemImage: "doc.on.doc")
                }
            }
            .accessibilityIdentifier("advanced-copy")
            .id("advanced-feedback")
            Button {
                isSharing = true
            } label: {
                SwiftUI.Label("Share with a Note…", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("advanced-share")
            pasteRow
            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                SwiftUI.Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .disabled(model.isLineArtDefault && model.isAppearanceDefault && model.isTuningDefault)
            .accessibilityIdentifier("advanced-reset-all")
            .confirmationDialog("Reset All Advanced Settings?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset All", role: .destructive) {
                    FeedbackEngine.shared.selectionChanged()
                    withAnimation(.snappy) { model.resetAll() }
                }
            } message: {
                Text("Line art, line appearance and the pipeline go back to their defaults.")
            }
        } header: {
            Text(String(localized: "advanced.section.feedback", defaultValue: "Feedback",
                        comment: "Settings › Advanced: header of the section for sending the settings to the developer and resetting them"))
        } footer: {
            Text("Copies include the picture, the preview’s numbers and every setting, so what you saw can be made again. Paste takes the settings in copied text, from another device or a preset.")
        }
    }

    /// Paste Settings: the system paste button (no permission prompt) beside what it does. The
    /// button is enabled while the clipboard holds text.
    private var pasteRow: some View {
        HStack(spacing: 12) {
            if pasted {
                SwiftUI.Label("Pasted", systemImage: "checkmark")
            } else {
                SwiftUI.Label("Paste Settings", systemImage: "doc.on.clipboard")
            }
            Spacer(minLength: 8)
            PasteButton(payloadType: String.self) { texts in paste(texts) }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Theme.signature)
                .accessibilityIdentifier("advanced-paste")
        }
        .alert("Couldn’t Read Settings", isPresented: $pasteFailed) {} message: {
            Text("The pasted text holds no Paint by Moonlight settings.")
        }
    }

    private func paste(_ texts: [String]) {
        guard let imported = texts.lazy.compactMap(AdvancedReport.settings(in:)).first else {
            pasteFailed = true
            return
        }
        FeedbackEngine.shared.selectionChanged()
        withAnimation(.snappy) {
            model.apply(imported)
            pasted = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { pasted = false }
        }
    }

    private func copy() {
        UIPasteboard.general.string = model.report()
        FeedbackEngine.shared.selectionChanged()
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { copied = false }
        }
    }
}

/// Sizes the preview card for the picture it shows, reading the model in a body of its own: on
/// iPhone the screen's body missed the preview's arrival, while views that read the model
/// themselves, like the card and the controls, followed it.
private struct FittedCard<Content: View>: View {
    let model: AdvancedSettingsModel
    /// The card's height for a picture of this aspect (width / height).
    let height: (CGFloat) -> CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content.frame(height: height(aspect))
    }

    private var aspect: CGFloat {
        guard let template = model.preview?.template, template.width > 0, template.height > 0 else { return 4 / 3 }
        return CGFloat(template.width) / CGFloat(template.height)
    }
}

/// The preview's numbers. Neither the screen's body nor a view observing the model kept them
/// current on every route: they stayed "–" under a finished preview pushed from Settings on
/// iPhone (drawn by the screen) and over Settings on iPad (drawn here), until a touch. So the
/// bar looks at the model four times a second while it is on screen and redraws when they
/// change.
private struct AdvancedStatsBar: View {
    let model: AdvancedSettingsModel
    @State private var seen: Numbers?

    nonisolated private struct Numbers: Equatable {
        var stats: AdvancedStats?
        var delta: AdvancedStats.Delta?
        var isAtDefaults: Bool
        var isStale: Bool
    }

    private var numbers: Numbers {
        Numbers(
            stats: model.preview?.stats, delta: model.statsDelta,
            isAtDefaults: model.currentKey == .defaults, isStale: model.isUpdating || model.phase == .loading)
    }

    var body: some View {
        let shown = seen ?? numbers
        AdvancedStatsRow(stats: shown.stats, delta: shown.delta, isAtDefaults: shown.isAtDefaults, isStale: shown.isStale)
            .task {
                while !Task.isCancelled {
                    let current = numbers
                    if current != seen { seen = current }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
    }
}

/// Share with a Note: the painter's words on top of the settings text, shared through the
/// system share sheet.
private struct AdvancedShareSheet: View {
    let model: AdvancedSettingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you notice?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("advanced-share-note")
                } header: {
                    Text("Note")
                } footer: {
                    Text("What looked right or wrong, and where in the picture.")
                }
                Section {
                    Text(report)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("Included")
                }
            }
            .navigationTitle("Share Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: report, subject: Text("Paint by Moonlight Feedback")) {
                        SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("advanced-share-send")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.accent)
    }

    private var report: String { model.report(note: note) }
}
