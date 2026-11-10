#if DEBUG
import Foundation
import os
import UIKit

/// Demo and UI-test launches: whenever the software keyboard is about to show, logs which
/// responder has it and every window's first responder (`Log.demo`, CI's `test-app.log`). A
/// keyboard rose under the painting screen's menus with no text field on screen (the Mac
/// critic's sweep and QA, November 9), and the responder chain from the key window named none.
nonisolated enum KeyboardWatch {
    /// Call on the main thread, once.
    static func start() {
        // The center keeps the observer for the launch.
        _ = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { KeyboardWatch.report() }
        }
    }

    @MainActor
    private static func report() {
        let current = UIResponder.current.map { String(describing: type(of: $0)) } ?? "none"
        var lines = ["The keyboard is about to show; the first responder is \(current)"]
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                let responder = firstResponder(in: window)
                let name = responder.map { describe($0) } ?? "none"
                let presented = window.rootViewController?.presentedViewController.map { String(describing: type(of: $0)) } ?? "none"
                lines.append(
                    "  window \(type(of: window)) key \(window.isKeyWindow) level \(window.windowLevel.rawValue) "
                        + "hidden \(window.isHidden) presented \(presented) first responder \(name)")
            }
        }
        Log.demo.notice("\(lines.joined(separator: "\n"), privacy: .public)")
    }

    @MainActor
    private static func firstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        if let controller = view.next as? UIViewController, controller.isFirstResponder { return controller }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }

    @MainActor
    private static func describe(_ responder: UIResponder) -> String {
        var chain: [String] = []
        var next: UIResponder? = responder
        while let item = next, chain.count < 6 {
            chain.append(String(describing: type(of: item)))
            next = item.next
        }
        let keyInput = responder is UIKeyInput ? " (UIKeyInput)" : ""
        return chain.joined(separator: " → ") + keyInput
    }
}
#endif
