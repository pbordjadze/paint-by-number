import UIKit

/// The app's keys that iPadOS would take for itself: ⌘, opened the iPad's Settings app even with
/// the app menu's Settings… asking for it (Mac check, painting-company row 263). A key command at
/// the end of every responder chain, the app delegate's, that wants priority over the system's.
final class AppKeys: UIResponder, UIApplicationDelegate {
    /// Asked for by ⌘,: the gallery opens the gear's sheet (`AppShellView`).
    static let openSettings = Notification.Name("AppKeys.openSettings")

    override var keyCommands: [UIKeyCommand]? {
        let settings = UIKeyCommand(
            title: String(localized: "Settings…"), action: #selector(openSettings), input: ",", modifierFlags: .command)
        settings.wantsPriorityOverSystemBehavior = true
        return [settings]
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: Self.openSettings, object: nil)
    }
}
