import Foundation

/// Settings › About's two ways out (painting-company row 310): the privacy policy, the page the
/// App Store listing links to (`ci/store-listing.json`), and the address `PRIVACY.md` gives for
/// questions and for deleting a report.
nonisolated enum AboutLinks {
    static let privacyPolicy = URL(string: "https://github.com/pbordjadze/paint-by-number/blob/main/PRIVACY.md")!
    static let supportAddress = "support@paulbordjadze.com"
    static let contact = URL(string: "mailto:support@paulbordjadze.com")!
}
