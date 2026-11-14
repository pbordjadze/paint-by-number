import Accessibility
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// Where the template starts from, asked until the first edit: what the generator made (the
/// default), or the photo as one area (Blank), which the painter's lines and paint then make
/// into the picture. Out of the way while a note shows at the top.
struct RefineStartChooser: View {
    let refine: RefineModel

    private var model: CreateModel { refine.model }

    var body: some View {
        // A page from scratch has nothing to generate: Blank is all it is.
        if refine.showsStartFrom {
            Picker("Start From", selection: Binding(get: { model.refinements.start }, set: { model.start(from: $0) })) {
                Text("Generated").tag(TemplateRefinements.Start.generated)
                Text("Blank").tag(TemplateRefinements.Start.blank)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(6)
            .glassEffect(.regular, in: .capsule)
            .background(Theme.surface, in: .capsule)
            .disabled(model.phase == .generating)
            .accessibilityIdentifier("refine-start")
            .transition(.opacity)
        }
    }
}

/// How many numbers are near the smallest: a tap brings the next of them up close. Out of the
/// way while a note or the draft's save toast holds the top, which it covered.
struct RefineTinyBadge: View {
    let refine: RefineModel
    /// For the draft's save toast, which the badge makes way for.
    @Environment(Library.self) private var library: Library?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: CreateModel { refine.model }

    var body: some View {
        // The template is read at the tap, not here (there is one whenever there are tiny
        // numbers): the badge comes and goes at once with the count, not in a landing's fade.
        if !refine.tiny.isEmpty, model.note == nil, library?.drafts.saveFailed != model.photoID {
            Button {
                guard let template = refine.base?.template else { return }
                refine.tinyShown = (refine.tinyShown + 1) % refine.tiny.count
                let label = refine.tiny[refine.tinyShown].label
                refine.tinyMarked = refine.tiny[refine.tinyShown].region
                refine.focus = RefineFocus(
                    id: (refine.focus?.id ?? 0) + 1, rect: RefineTinyAreas.focus(on: label, in: template), animated: !reduceMotion)
                FeedbackEngine.shared.selectionChanged()
            } label: {
                Label { Text(RefineView.tinyText(refine.tiny.count)) } icon: { Image(systemName: "magnifyingglass") }
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
            // The glass alone took the paint's light behind it, which washed out the gold label
            // at night (QA, November 7): on the card's surface it reads over any paint.
            .background(Theme.surface, in: .capsule)
            .accessibilityShowsLargeContentViewer()
            .accessibilityHint(Text(String(
                localized: "refine.tiny.hint", defaultValue: "Shows the next one up close.",
                comment: "Refine screen: VoiceOver hint of the badge that counts the areas whose numbers are near the smallest size; a tap zooms in on the next one")))
            .accessibilityIdentifier("refine-tiny")
            .transition(.opacity)
        }
    }
}
