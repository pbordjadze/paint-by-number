#if UNRELEASED
import Observation
import os
import PaintCore
import SwiftUI
import UIKit

/// Makes the Live Photo with visible progress and saves it to Photos (`LivePhoto`).
@Observable
final class LivePhotoSaveModel {
    enum Phase: Equatable {
        /// Fraction of the movie's frames made.
        case making(Double)
        case saved
        case notAllowed
        case failed
    }

    let request: TimelapseRequest
    private(set) var phase: Phase = .making(0)

    init(request: TimelapseRequest) {
        self.request = request
    }

    /// Makes and saves it; cancelling the calling task stops it between frames and leaves
    /// nothing behind.
    func run() async {
        phase = .making(0)
        let (updates, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        async let saved: Void = Self.save(request, updates: continuation)
        for await fraction in updates { phase = .making(fraction) }
        do {
            try await saved
            phase = .saved
        } catch is CancellationError {
        } catch LivePhoto.SaveError.notAllowed {
            phase = .notAllowed
        } catch {
            Log.library.error("Live Photo failed: \(String(describing: error), privacy: .public)")
            phase = .failed
        }
    }

    /// The progress closure is formed here, off the main actor: the exporter calls it from its
    /// own thread.
    @concurrent
    private static func save(_ request: TimelapseRequest, updates: AsyncStream<Double>.Continuation) async throws {
        defer { updates.finish() }
        try await LivePhoto.save(request) { updates.yield($0) }
    }
}

/// "Save as Live Photo", from a time-lapse's share sheet (`LivePhotoActivity`): the movie's
/// progress with Cancel, then Saved to Photos. Closing it cancels.
struct LivePhotoSaveSheet: View {
    @State private var model: LivePhotoSaveModel
    @State private var attempt = 0
    @Environment(\.openURL) private var openURL
    /// Hands the sheet back to the share sheet that presented it; true once it is saved.
    let onClose: (_ saved: Bool) -> Void

    init(request: TimelapseRequest, onClose: @escaping (_ saved: Bool) -> Void) {
        _model = State(initialValue: LivePhotoSaveModel(request: request))
        self.onClose = onClose
    }

    private func dismiss() { onClose(model.phase == .saved) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: model.phase == .saved ? "livephoto" : "livephoto.play")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: isMaking)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("Making Your Live Photo")
                        .font(.display(.title3))
                    Text(model.request.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                status
            }
            .padding(28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .background(Theme.paper)
        .task(id: attempt) { await model.run() }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .making(let fraction):
            ProgressView(value: fraction) {
                EmptyView()
            } currentValueLabel: {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .accessibilityLabel(Text("Making Your Live Photo"))
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            Text("Press and hold it in Photos to watch it paint itself.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .keyboardShortcut(.defaultAction)
        case .notAllowed:
            Text("Paint by Moonlight can’t add to your photos. You can allow it in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Close") { dismiss() }
                    .buttonStyle(.glass)
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
            }
        case .failed:
            Text("The Live Photo couldn’t be saved.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Close") { dismiss() }
                    .buttonStyle(.glass)
                Button("Try Again") { attempt += 1 }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
            }
        }
    }

    private var isMaking: Bool {
        if case .making = model.phase { true } else { false }
    }
}
/// Save as Live Photo in a time-lapse's share sheet (`TimelapseRequest.shareActivities`): it
/// makes its own few seconds of replay, so the time-lapse being shared is only what led here.
/// UIKit's `UIActivity` is not main-actor isolated, so neither is this; UIKit asks it everything
/// on the main thread, where its few mutable properties are used.
nonisolated final class LivePhotoActivity: UIActivity, @unchecked Sendable {
    private let request: TimelapseRequest
    private var host: UIViewController?
    private var watcher: LivePhotoSheetWatcher?
    private var finished = false

    init(request: TimelapseRequest) {
        self.request = request
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("com.pbordjadze.paintbynumber.livePhoto") }
    override var activityTitle: String? {
        String(localized: "share.livePhoto", defaultValue: "Save as Live Photo",
               comment: "Action in a time-lapse's share sheet: saves the painting to Photos as a Live Photo that plays its painting")
    }
    override var activityImage: UIImage? { UIImage(systemName: "livephoto") }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    /// Made once: UIKit may ask for the controller more than once.
    override var activityViewController: UIViewController? {
        MainActor.assumeIsolated { () -> UIViewController in
            if let host { return host }
            let made = UIHostingController(rootView: LivePhotoSaveSheet(request: request) { [weak self] saved in
                self?.finish(saved)
            })
            if let sheet = made.sheetPresentationController {
                sheet.detents = [.medium()]
            }
            // Swiped away, it is finished too, or the time-lapse's sheet waits for a share sheet
            // that never closes.
            let watcher = LivePhotoSheetWatcher { [weak self] in self?.finish(false) }
            made.presentationController?.delegate = watcher
            self.watcher = watcher
            host = made
            return made
        }
    }

    private func finish(_ completed: Bool) {
        guard !finished else { return }
        finished = true
        activityDidFinish(completed)
    }
}

/// Tells `LivePhotoActivity` its sheet was swiped away.
final class LivePhotoSheetWatcher: NSObject, UIAdaptivePresentationControllerDelegate {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss()
    }
}
#endif
