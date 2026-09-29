import PaintCore
import SwiftUI

/// Second step of the create flow: the generated template, compared with the photo,
/// tuned live with a few simple controls.
struct TemplatePreviewView: View {
    @Bindable var model: CreateModel
    var onStart: () async throws -> Void

    enum Layer: String, CaseIterable, Identifiable {
        case painting, numbers
        var id: String { rawValue }
    }

    @State private var size: CGSize = .zero
    @State private var layer: Layer = .painting
    @State private var split: CGFloat = 0.5
    @State private var isStarting = false
    @State private var startError: String?

    var body: some View {
        Group {
            if isSideBySide {
                HStack(spacing: 24) {
                    canvas
                    ViewThatFits(in: .vertical) {
                        controls
                        ScrollView { controls }
                    }
                    .frame(width: size.width > 900 ? 360 : 320)
                    .background(Theme.surface, in: .rect(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
                }
                .padding(size.width > 900 ? 32 : 16)
            } else {
                VStack(spacing: 16) {
                    canvas
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    controls
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
        .navigationTitle(model.source?.title ?? "Preview")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.settings) { model.settingsChanged() }
        .alert("Couldn’t Create Painting", isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startError ?? "")
        }
    }

    /// Canvas beside the controls on wide containers (iPad, iPhone in landscape).
    private var isSideBySide: Bool { size.width >= 700 || size.width > size.height * 1.2 }

    // MARK: Canvas

    private var canvas: some View {
        VStack(spacing: 14) {
            Picker("Show", selection: $layer) {
                Text("Painting").tag(Layer.painting)
                Text("Numbers").tag(Layer.numbers)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .disabled(model.preview == nil)

            ZStack {
                if let source = model.source {
                    CompareView(
                        photo: source.preview, after: afterImage, afterID: afterID,
                        afterLabel: layer == .painting ? "Painting" : "Numbers",
                        aspectRatio: CGFloat(source.image.width) / CGFloat(max(1, source.image.height)),
                        split: $split)
                        .overlay(alignment: .bottom) {
                            status.padding(14)
                        }
                } else if case .failed(let message) = model.phase {
                    ContentUnavailableView("Couldn’t Open Photo", systemImage: "photo.badge.exclamationmark", description: Text(message))
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var afterImage: CGImage? {
        guard let preview = model.preview else { return nil }
        return layer == .painting ? preview.painting : preview.outlines
    }

    private var afterID: String { "\(model.preview?.id.uuidString ?? "none")-\(layer.rawValue)" }

    @ViewBuilder
    private var status: some View {
        Group {
            switch model.phase {
            case .loading, .analyzing:
                StatusCapsule {
                    ProgressView().controlSize(.small)
                    Text(model.phase == .loading ? "Opening photo…" : "Finding the subject…")
                }
            case .generating where !model.isAdjusting:
                StatusCapsule {
                    ProgressView(value: model.progress)
                        .frame(width: 64)
                    Text(model.preview == nil ? "Creating template…" : "Refining…")
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
        VStack(alignment: .leading, spacing: 18) {
            SettingSlider(
                title: "Colors", value: $model.colorCount, range: Double(6)...Double(60), step: 1,
                valueText: "\(Int(model.colorCount.rounded()))", onEditing: model.setAdjusting)
            SettingSlider(
                title: "Detail", value: $model.detail, range: 0...1,
                valueText: Self.word(model.detail, ["Simple", "Moderate", "Detailed", "Intricate"]),
                onEditing: model.setAdjusting)
            SettingSlider(
                title: "Smoothness", value: $model.smoothness, range: 0...1,
                valueText: Self.word(model.smoothness, ["Crisp", "Clean", "Smooth", "Flowing"]),
                onEditing: model.setAdjusting)

            Text(model.stats?.summary ?? " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .opacity(model.isFinal ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.25), value: model.stats)
                .frame(maxWidth: .infinity, alignment: .center)

            Button(action: start) {
                HStack(spacing: 10) {
                    if isStarting { ProgressView().tint(.white) }
                    Text("Start Painting")
                }
                .font(.rounded(.headline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(model.preview == nil || isStarting)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, isSideBySide ? 22 : 8)
    }

    private func start() {
        guard !isStarting else { return }
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

    private static func word(_ value: Double, _ words: [String]) -> String {
        words[min(words.count - 1, max(0, Int(value * Double(words.count))))]
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
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let valueText: String
    var onEditing: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.rounded(.subheadline, weight: .semibold))
                Spacer()
                Text(valueText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: valueText)
            }
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step, onEditingChanged: onEditing)
                } else {
                    Slider(value: $value, in: range, onEditingChanged: onEditing)
                }
            }
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
        }
    }
}
