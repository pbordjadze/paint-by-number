import UIKit

extension UIResponder {
    /// The app's first responder now, if any: an action sent to no target reaches it first.
    static var current: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(recordAsCurrent), to: nil, from: nil, for: nil)
        return found
    }

    private static weak var found: UIResponder?

    @objc private func recordAsCurrent() {
        UIResponder.found = self
    }
}
