import SwiftUI

/// Says the draft's last save failed (`Drafts.saveFailed`), with a Retry, at the top of the
/// create flow's preview and of Refine, as the painting screen says so of its progress. The flow
/// tells VoiceOver once when it comes (`CreateFlowView`). Nothing while saves land.
struct DraftSaveToast: View {
    @Environment(Library.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var text: String { String(localized: "Couldn’t save the draft") }

    var body: some View {
        let drafts = library.drafts
        VStack {
            if drafts.saveFailed {
                Toast(text: Self.text, systemImage: "exclamationmark.triangle", edge: .top) {
                    Button("Retry") { drafts.retry() }
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .accessibilityIdentifier("draft-save-failed")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: drafts.saveFailed)
    }
}
