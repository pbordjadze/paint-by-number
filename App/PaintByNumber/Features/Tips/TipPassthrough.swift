import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Lets a tap outside a tip's popover reach what it was aimed at, and closes the tip as that tap
/// ends. A popover's dimming view takes the first tap outside it to close it: Tap to Paint asked
/// for a tap on an area and that tap only closed it, so a newcomer's first tap seemed to do
/// nothing (QA, November 6: 2 of 2 on iPad; Zen Mode's took a canvas tap and an Undo).
///
/// Once the popover is up, its presentation lets every touch through to the screen that presented
/// it (`passthroughViews`), and a watcher on the window, which never takes a touch from anyone,
/// calls `close` when a touch outside the popover ends. A touch inside it (its ×, its words) is
/// the popover's own. A tip over a sheet lets touches through to that sheet alone: outside it,
/// the sheet's own dimming takes them, and the tip still closes.
///
/// Ravenna keeps its own copy of the tips (App/CLAUDE.md › Ravenna: it follows none of this app's
/// later changes), so its tips are as they were.
struct TipPassthrough: UIViewRepresentable {
    /// Whether a tip's popover is meant to be up now.
    var isShown: Bool
    var close: () -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.close = close
        view.isShown = isShown
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: ()) {
        view.isShown = false
    }

    final class ProbeView: UIView {
        var close: () -> Void = {}
        var isShown = false {
            didSet { if isShown != oldValue { isShown ? find() : stop() } }
        }
        private var watcher: TouchWatcher?
        private var finding: Task<Void, Never>?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop() } else if isShown, watcher == nil { find() }
        }

        /// The popover comes up a moment after the turn is given: looked for until it is there.
        private func find() {
            finding?.cancel()
            finding = Task { @MainActor [weak self] in
                for _ in 0..<40 {
                    guard let self, self.isShown, !Task.isCancelled else { return }
                    if self.attach() { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        private func attach() -> Bool {
            guard let window, let popover = Self.topPopover(in: window), points(at: popover, in: window),
                  let presented = popover.presentedView, let screen = popover.presentingViewController.view else { return false }
            popover.passthroughViews = [screen]
            let watcher = TouchWatcher(inside: presented) { [weak self] in
                guard let self, self.isShown else { return }
                self.close()
            }
            window.addGestureRecognizer(watcher)
            self.watcher = watcher
            return true
        }

        /// Whether `popover` is this tip's: it hangs from the view this probe lies behind, not from
        /// another popover (a swatch's details) up meanwhile.
        private func points(at popover: UIPopoverPresentationController, in window: UIWindow) -> Bool {
            guard let source = popover.sourceView ?? (popover.sourceItem as? UIView) else { return false }
            let rect = popover.sourceRect.isNull || popover.sourceRect.isEmpty ? source.bounds : popover.sourceRect
            let anchor = source.convert(rect, to: window)
            let mine = convert(bounds, to: window)
            return anchor.insetBy(dx: -8, dy: -8).intersects(mine)
        }

        private func stop() {
            finding?.cancel()
            finding = nil
            if let watcher { watcher.view?.removeGestureRecognizer(watcher) }
            watcher = nil
        }

        /// The popover presented last over `window`, if the last presentation is one.
        private static func topPopover(in window: UIWindow) -> UIPopoverPresentationController? {
            var controller = window.rootViewController
            while let next = controller?.presentedViewController, !next.isBeingDismissed { controller = next }
            guard let controller, controller !== window.rootViewController else { return nil }
            return controller.presentationController as? UIPopoverPresentationController
        }
    }

    /// Sees every touch in the window and recognizes none, so nothing it watches is delayed or
    /// cancelled; reports a touch outside `inside` as it ends.
    final class TouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private weak var inside: UIView?
        private let ended: () -> Void

        init(inside: UIView, ended: @escaping () -> Void) {
            self.inside = inside
            self.ended = ended
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesEnded(touches, with: event)
            let outside = touches.contains { touch in
                guard let inside, let view = touch.view else { return true }
                return !view.isDescendant(of: inside)
            }
            state = .failed
            if outside { ended() }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesCancelled(touches, with: event)
            state = .failed
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
