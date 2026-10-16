#if DEBUG
import os
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Probe (throwaway): logs where each touch of a window begins, ends or is cancelled, and the
/// views it hit, so a lost tap shows whether the app ever received it.
final class TouchProbe: UIGestureRecognizer, UIGestureRecognizerDelegate {
    static func install() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if (window.gestureRecognizers ?? []).contains(where: { $0 is TouchProbe }) { continue }
                let probe = TouchProbe(target: nil, action: nil)
                probe.cancelsTouchesInView = false
                probe.delaysTouchesBegan = false
                probe.delaysTouchesEnded = false
                probe.delegate = probe
                window.addGestureRecognizer(probe)
                Log.demo.error("probe: touch probe installed on a window")
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        report("began", touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        report("ended", touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        report("cancelled", touches)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    private func report(_ what: String, _ touches: Set<UITouch>) {
        for touch in touches {
            let point = touch.location(in: nil)
            let x = Int(point.x)
            let y = Int(point.y)
            let hit = Self.describe(touch.view)
            Log.demo.error("probe: touch \(what, privacy: .public) at \(x, privacy: .public),\(y, privacy: .public) hit \(hit, privacy: .public)")
        }
    }

    private static func describe(_ start: UIView?) -> String {
        var parts: [String] = []
        var current = start
        while let view = current, parts.count < 6 {
            var part = String(describing: type(of: view))
            if let identifier = view.accessibilityIdentifier, !identifier.isEmpty { part += "#" + identifier }
            parts.append(part)
            current = view.superview
        }
        return parts.joined(separator: " < ")
    }
}
#endif
