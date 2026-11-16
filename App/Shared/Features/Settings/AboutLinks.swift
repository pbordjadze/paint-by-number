import Foundation

/// Settings › About's two ways out (painting-company row 310): the privacy policy, the page the
/// App Store listing links to (`ci/store-listing.json`), and the address `PRIVACY.md` gives for
/// questions and for deleting a report. The page is a copy of `PRIVACY.md` on a site that stays
/// public (painting-company row 346).
nonisolated enum AboutLinks {
    static let privacyPolicy = URL(string: "https://paulbordjadze.com/paint-by-moonlight-privacy/")!
    static let supportAddress = "support@paulbordjadze.com"
    static let contact = URL(string: "mailto:support@paulbordjadze.com")!
}
