import Foundation
import PaintCore
import SwiftUI

/// Second step of the create flow: the generated template, compared with the photo,
/// tuned live with a few simple controls, and the painting's name.
struct TemplatePreviewView: View {
    @Bindable var model: CreateModel
    var onStart: () async throws -> Void

    @State private var size: CGSize = .zero
    /// `size` with the keyboard's room given back: what the layout is chosen for.
    @State private var roomSize: CGSize = .zero
    /// The layout chosen when title editing began, for that window width: kept until it ends.
    @State private var editingLayout: (width: CGFloat, sideBySide: Bool)?
    @State private var isStarting = false
    @State private var startError: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if isSideBySide {
                HStack(spacing: 24) {
                    canvas
                    // The card keeps its natural height, centred, and scrolls only when the
                    // window is too short for it (iPhone in landscape).
                    ScrollView {
                        controls
                            .background(Theme.surface, in: .rect(cornerRadius: 30, style: .continuous))
                            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
                            .padding(.vertical, 12)
                            .frame(minHeight: max(0, size.height - 2 * sidePadding), alignment: .center)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .frame(width: panelWidth)
                }
                .padding(.horizontal, sidePadding)
                .padding(.vertical, sidePadding - 12)
            } else {
                VStack(spacing: 16) {
                    canvas
                        .padding(.horizontal, sidePadding)
                        .padding(.top, 4)
                    controls
                        // Not scrollable here, unlike the side panel: past this size the
                        // controls would squeeze the preview away on a phone.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .background {
                            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                                .fill(Theme.surface)
                                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: -4)
                                .ignoresSafeArea(edges: .bottom)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .background {
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { roomSize = $0 }
        }
        .onChange(of: titleFocused) { _, focused in
            editingLayout = focused ? (size.width, chosenLayout) : nil
        }
        // The title field names the painting; the bar says which step this is.
        .navigationTitle("New Painting")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t Create Painting", isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startError ?? "")
        }
    }

    /// Canvas beside the controls when that shows the photo larger than stacking them: landscape
    /// windows, and portrait photos on iPad. The controls' size is estimated rather than measured
    /// because measuring it would feed back into the choice of layout. The choice ignores the
    /// keyboard (`roomSize`) and holds while the title is edited: switching layouts then would
    /// rebuild the title field and drop its focus, and the keyboard with it.
    private var isSideBySide: Bool {
        if let editingLayout, editingLayout.width == size.width { return editingLayout.sideBySide }
        return chosenLayout
    }

    private var chosenLayout: Bool {
        let room = roomSize.width > 0 && roomSize.height > 0 ? roomSize : size
        guard room.width.isFinite, room.height.isFinite, room.width > 0, room.height > 0 else { return false }
        // The stacked controls card: title row, settings chip, three or four sliders, summary, Start.
        let stacked = Self.fittedArea(
            width: room.width - 2 * sidePadding, height: room.height - (hasLines ? 512 : 460), aspect: photoAspect)
        let beside = Self.fittedArea(
            width: room.width - 2 * sidePadding - panelWidth - 24, height: room.height - 2 * sidePadding, aspect: photoAspect)
        return beside > stacked
    }

    private var sidePadding: CGFloat { size.width > 900 ? 32 : 16 }
    private var panelWidth: CGFloat { size.width > 900 ? 360 : 320 }
    /// The card's rows sit closer stacked on a phone, where the card and the comparison share
    /// the screen's height: with four sliders, 18 pt between rows left the comparison 125 pt tall
    /// on an iPhone 17 Pro.
    private var rowSpacing: CGFloat { !isSideBySide && size.width < 600 ? 12 : 18 }

    private var photoAspect: CGFloat {
        guard let image = model.source?.image, image.width > 0, image.height > 0 else { return 4 / 3 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    private static func fittedArea(width: CGFloat, height: CGFloat, aspect: CGFloat) -> CGFloat {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        let fittedWidth = min(width, height * aspect)
        return fittedWidth * fittedWidth / aspect
    }

    /// The colors slider runs on a squared scale: the first half of the track covers 6–42,
    /// where each color matters, the rest reaches up to 150.
    private static let colorBounds = (
        Double(GenerationSettings.colorCountRange.lowerBound), Double(GenerationSettings.colorCountRange.upperBound))

    private static func colorCount(at position: Double) -> Double {
        (colorBounds.0 + (colorBounds.1 - colorBounds.0) * position * position).rounded()
    }

    private static func colorPosition(_ count: Double) -> Double {
        min(max((count - colorBounds.0) / (colorBounds.1 - colorBounds.0), 0), 1).squareRoot()
    }

    /// Updates a setting the painter moved, ignoring unchanged values: a slider re-asserting
    /// its value would otherwise invalidate the model on every update.
    private func update(_ keyPath: ReferenceWritableKeyPath<CreateModel, Double>, _ value: Double) {
        guard abs(model[keyPath: keyPath] - value) > 1e-9 else { return }
        model[keyPath: keyPath] = value
        model.settingsChanged()
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack {
            if let source = model.source {
                CompareView(
                    photo: source.preview, after: model.preview?.painting, afterID: model.preview?.id.uuidString ?? "none",
                    afterLabel: String(localized: "Painting"), aspectRatio: photoAspect)
                    .overlay(alignment: .bottom) {
                        status.padding(14)
                    }
            } else if case .failed(let message) = model.phase {
                ContentUnavailableView("Couldn’t Open Photo", systemImage: "photo.badge.exclamationmark", description: Text(message))
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        Group {
            switch model.phase {
            case .loading, .analyzing, .suggesting:
                StatusCapsule {
                    ProgressView().controlSize(.small)
                    if model.phase == .loading {
                        Text("Opening photo…")
                    } else if model.phase == .analyzing {
                        Text("Finding the subject…")
                    } else {
                        Text("Choosing settings…")
                    }
                }
            case .generating where !model.isAdjusting || model.refining != nil:
                StatusCapsule {
                    ProgressView(value: model.progress)
                        .frame(width: 64)
                    if model.preview == nil {
                        Text("Creating template…")
                    } else {
                        Text("Refining…")
                    }
                }
            case .failed(let message):
                StatusCapsule {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).lineLimit(2)
                }
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            titleField
            originChip
            SettingSlider(
                title: "Colors", value: Self.colorPosition(model.colorCount),
                onChange: { update(\.colorCount, Self.colorCount(at: $0)) },
                valueText: Int(model.colorCount.rounded()).formatted(), isPending: model.isChoosingSettings,
                detent: suggested.map { Self.colorPosition(Double($0.colorCount)) }, onEditing: model.setAdjusting)
            SettingSlider(
                title: "Detail", value: model.detail, onChange: { update(\.detail, $0) },
                valueText: Self.detailWord(model.detail), isPending: model.isChoosingSettings,
                detent: suggested.map { Double($0.detail) }, onEditing: model.setAdjusting)
            SettingSlider(
                title: "Smoothness", value: model.smoothness, onChange: { update(\.smoothness, $0) },
                valueText: Self.smoothnessWord(model.smoothness), isPending: model.isChoosingSettings,
                detent: suggested.map { Double($0.smoothness) }, onEditing: model.setAdjusting)
            if hasLines {
                SettingSlider(
                    title: "Lines", value: model.lines, onChange: { update(\.lines, $0) },
                    valueText: Self.linesWord(model.lines), isPending: model.isChoosingSettings,
                    detent: 0.5, onEditing: model.setAdjusting)
            }

            Text(model.stats?.summary ?? " ")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary.opacity(0.7))
                .monospacedDigit()
                .contentTransition(.numericText())
                .opacity(model.isFinal ? 1 : 0.7)
                .animation(.easeInOut(duration: 0.25), value: model.stats)
                .frame(maxWidth: .infinity, alignment: .center)

            Button(action: start) {
                HStack(spacing: 10) {
                    if isStarting { ProgressView().tint(.white) }
                    Text("Start Painting")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.signature)
            .controlSize(.large)
            .disabled(model.preview == nil || model.isChoosingSettings || isStarting)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, isSideBySide ? 22 : 8)
    }

    /// The suggestion's settings, where each slider has a detent.
    private var suggested: GenerationSettings? { model.decision?.settings }

    /// Classic line art has no lines to tune.
    private var hasLines: Bool { model.baseLineArt.style != .classic }

    /// Where the settings came from: the suggestion for this photo, or the painter's own with
    /// a way back to it. Its room is kept, empty, until there is a suggestion.
    private var originChip: some View {
        Group {
            if model.settingsOrigin == .custom {
                Button { model.resetToSuggested() } label: {
                    HStack(spacing: 6) {
                        Text("Custom")
                            .foregroundStyle(.secondary)
                        Text(verbatim: "·")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        SwiftUI.Label("Reset to Suggested", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(Theme.accent)
                    }
                    .chipBackground(Theme.paper)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset to Suggested")
                .accessibilityValue("Custom")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accent)
                    Text("Suggested for this photo")
                }
                .chipBackground(Theme.accent.opacity(0.14))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(String(
                    localized: "create.settingsOrigin.label", defaultValue: "Settings",
                    comment: "VoiceOver label of the chip above the create sliders; its value says whether they are suggested for the photo or custom")))
                .accessibilityValue("Suggested for this photo")
            }
        }
        .accessibilityIdentifier("settings-origin")
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(model.settingsOrigin == nil ? 0 : 1)
        .accessibilityHidden(model.settingsOrigin == nil)
        .animation(.snappy, value: model.settingsOrigin)
    }

    /// Empty shows the default (the sample's name or the date) as the prompt, and the
    /// painting takes that name.
    private var titleField: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Title", text: $model.title, prompt: Text(model.defaultTitle))
                .font(.display(.title3, weight: .semibold))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($titleFocused)
                .onSubmit { titleFocused = false }
                .accessibilityIdentifier("painting-title")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.paper, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func start() {
        guard !isStarting else { return }
        titleFocused = false
        isStarting = true
        Task {
            do {
                try await onStart()
            } catch {
                startError = error.localizedDescription
            }
            isStarting = false
        }
    }

    /// Which of `count` equal steps of 0…1 `value` falls in.
    private static func step(_ value: Double, of count: Int) -> Int {
        min(count - 1, max(0, Int(value * Double(count))))
    }

    private static func detailWord(_ value: Double) -> String {
        switch step(value, of: 4) {
        case 0: String(localized: "create.detail.simple", defaultValue: "Simple",
                       comment: "Detail slider value: the fewest, largest areas")
        case 1: String(localized: "create.detail.moderate", defaultValue: "Moderate",
                       comment: "Detail slider value: second step")
        case 2: String(localized: "create.detail.detailed", defaultValue: "Detailed",
                       comment: "Detail slider value: third step")
        default: String(localized: "create.detail.intricate", defaultValue: "Intricate",
                        comment: "Detail slider value: the most, smallest areas")
        }
    }

    private static func linesWord(_ value: Double) -> String {
        switch step(value, of: 5) {
        case 0: String(localized: "create.lines.fewest", defaultValue: "Fewest",
                       comment: "Lines slider value: only the strongest edges are drawn")
        case 1: String(localized: "create.lines.fewer", defaultValue: "Fewer",
                       comment: "Lines slider value: second step")
        case 2: String(localized: "create.lines.balanced", defaultValue: "Balanced",
                       comment: "Lines slider value: the middle, the lines as a painting is drawn by default")
        case 3: String(localized: "create.lines.more", defaultValue: "More",
                       comment: "Lines slider value: fourth step")
        default: String(localized: "create.lines.most", defaultValue: "Most",
                        comment: "Lines slider value: the faintest edges drawn too")
        }
    }

    private static func smoothnessWord(_ value: Double) -> String {
        switch step(value, of: 4) {
        case 0: String(localized: "create.smoothness.crisp", defaultValue: "Crisp",
                       comment: "Smoothness slider value: sharp, angular outlines")
        case 1: String(localized: "create.smoothness.clean", defaultValue: "Clean",
                       comment: "Smoothness slider value: second step")
        case 2: String(localized: "create.smoothness.smooth", defaultValue: "Smooth",
                       comment: "Smoothness slider value: third step")
        default: String(localized: "create.smoothness.flowing", defaultValue: "Flowing",
                        comment: "Smoothness slider value: soft, flowing outlines")
        }
    }
}

private struct StatusCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

private struct SettingSlider: View {
    let title: LocalizedStringKey
    let value: Double
    var onChange: (Double) -> Void
    let valueText: String
    /// The value is not chosen yet (Suggested settings are being chosen): shown as a
    /// placeholder, and the slider waits.
    var isPending = false
    /// The suggested value: the thumb settles on it within `detentReach`, with a tick.
    var detent: Double?
    var onEditing: (Bool) -> Void

    static let detentReach = 0.02

    var body: some View {
        let value = Binding(get: { self.value }, set: { set($0) })
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: valueText)
                    .redacted(reason: isPending ? .placeholder : [])
            }
            Slider(value: value, in: 0...1, onEditingChanged: onEditing)
                .disabled(isPending)
                .accessibilityLabel(title)
                .accessibilityValue(isPending ? Text("Choosing settings…") : Text(valueText))
        }
    }

    private func set(_ newValue: Double) {
        guard let detent, abs(newValue - detent) < Self.detentReach else {
            onChange(newValue)
            return
        }
        if value != detent { FeedbackEngine.shared.selectionChanged() }
        onChange(detent)
    }
}

private extension View {
    /// The origin chip's shape: a capsule on one line, a rounded card when long text wraps.
    func chipBackground(_ style: some ShapeStyle) -> some View {
        font(.footnote.weight(.semibold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(style, in: .rect(cornerRadius: 15, style: .continuous))
            // A comfortable target without making the chip itself taller.
            .frame(minHeight: 44)
            .contentShape(.rect)
    }
}
