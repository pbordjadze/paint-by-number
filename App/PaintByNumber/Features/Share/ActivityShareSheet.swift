import SwiftUI
import UIKit

/// Presents the system share sheet for a file as soon as there is one, and reports when it
/// closes, whether the file was shared or not. SwiftUI's `ShareLink` can neither present from
/// code nor tell when sharing ends, and exported movies are deleted once it does.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let item: URL?
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.item = item
        controller.onFinish = onFinish
        // Never inside SwiftUI's update pass: it can race the sheet's own presentation.
        Task { @MainActor [weak controller] in controller?.presentIfNeeded() }
    }

    final class Controller: UIViewController {
        var item: URL?
        var onFinish: (() -> Void)?
        private var presentedItem: URL?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            Task { @MainActor [weak self] in self?.presentIfNeeded() }
        }

        func presentIfNeeded() {
            guard let item, item != presentedItem, viewIfLoaded?.window != nil, presentedViewController == nil else { return }
            presentedItem = item
            let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                // iPad: centred over the sheet, without an arrow.
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            activity.completionWithItemsHandler = Self.completion { [weak self] in self?.onFinish?() }
            present(activity, animated: true)
        }

        /// Built outside the main actor: UIKit may call it on any thread.
        nonisolated private static func completion(
            _ finish: @escaping @MainActor @Sendable () -> Void
        ) -> UIActivityViewController.CompletionWithItemsHandler {
            { _, _, _, _ in Task { @MainActor in finish() } }
        }
    }
}
