import Observation
import SwiftUI
import UIKit

/// Where Refine's Layers panel hangs from: the bar's Layers button, as the screen under the bar
/// finds it. The panel can't be the button's own popover: a popover from anything in the bar is
/// the bar button's, and iOS 26 grows it out of the button over the bar, covering Done, Undo, Redo
/// and the button itself, whatever its arrow edge, as did one put on a view under the button (QA,
/// November 7). So the screen presents it, pointing up at the button's place. That place is
/// UIKit's bar button item's (`frame(in:)`): SwiftUI lays a bar item's content out away from
/// the window, so no frame of it, global or UIKit's, is where the button shows. It keeps the
/// button's place itself, observed, and holds nothing of the screen's: a closure of the screen's
/// kept here held Refine's view, and with it the create flow, past every trip into Refine (Mac's
/// measurement, painting-company row 263: 150–200 MB a trip, never freed).
@Observable
final class RefineLayersAnchor {
    @ObservationIgnored fileprivate weak var screen: UIView?
    /// The Layers button in the screen's coordinates, as last measured (`refresh`).
    private(set) var buttonFrame: CGRect?

    /// Measures the button again: when the screen is laid out or moves to a window, and when the
    /// panel is asked for.
    func refresh() {
        let frame = buttonOnScreen
        if let frame, frame != buttonFrame { buttonFrame = frame }
    }

    /// The Layers button in the screen's coordinates; nil until the screen and its bar are in a
    /// window.
    var buttonOnScreen: CGRect? {
        guard let screen, screen.window != nil, let bar = Self.navigationBar(of: screen) else { return nil }
        let title = String(localized: "Layers")
        let items = (bar.topItem?.trailingItemGroups ?? []).flatMap(\.barButtonItems)
        guard let frame = items.first(where: { $0.title == title })?.frame(in: screen), !frame.isEmpty else { return nil }
        return frame
    }

    /// The bar of the navigation controller showing `view`.
    private static func navigationBar(of view: UIView) -> UINavigationBar? {
        var next: UIResponder? = view
        while let responder = next {
            if let controller = responder as? UIViewController, let navigation = controller.navigationController {
                return navigation.navigationBar
            }
            next = responder.next
        }
        return nil
    }
}

extension View {
    /// Makes this view the screen `anchor` measures the Layers button on.
    func refineLayersAnchor(_ anchor: RefineLayersAnchor) -> some View {
        background(RefineLayersProbe(anchor: anchor).accessibilityHidden(true))
    }
}

/// An empty view the size of the one it is behind, telling the anchor when it moves.
private struct RefineLayersProbe: UIViewRepresentable {
    let anchor: RefineLayersAnchor

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.anchor = anchor
        anchor.screen = view
    }

    final class Probe: UIView {
        weak var anchor: RefineLayersAnchor?

        override func layoutSubviews() {
            super.layoutSubviews()
            tell()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            tell()
        }

        /// After the layout pass (the bar's too), which mustn't change SwiftUI's state.
        private func tell() {
            Task { @MainActor [weak anchor] in anchor?.refresh() }
        }
    }
}
