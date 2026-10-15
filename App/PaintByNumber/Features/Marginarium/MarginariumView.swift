import Foundation
import SwiftUI

/// The Marginarium: how Paint by Moonlight is made, told in chapters. It opens on its drawings,
/// idling (`MarginariumCompany`), with nothing above them; then one way into the story, Chapter 1's
/// opening quoted with a link to keep reading; then the contents, for whoever keeps digging: two
/// chapters, Who's Who (`MarginariumWhosWhoView`) and the appendices (`MarginariumEntry`). A sheet
/// from the gallery's toolbar; each entry opens its native `MarginariumReaderView`, whose blocks
/// come from the bundled MarginariumDocument manifest.
///
/// Chief Architect Paul's rule for the whole book: anyone who opens it should have a nice time
/// and roughly follow what's going on. So it starts small and cute, and the rest waits for
/// whoever wants it.
struct MarginariumView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    init() {
        #if DEBUG
        if let demoPath = ShellDemo.current?.marginariumPath { _path = State(initialValue: demoPath) }
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    MarginariumCompany()

                    if let story = MarginariumEntry.chapters.first {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(String(localized: "marginarium.subtitle", defaultValue: "How Paint by Moonlight is made, told in chapters.",
                                        comment: "The Marginarium: the line under the drawings on the contents page, above the quoted opening of Chapter 1"))
                                .font(.display(.title3, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(story.passage)
                                .padding(.leading, 16)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(.tint.opacity(0.45))
                                        .frame(width: 3)
                                }
                            NavigationLink(value: story.id) {
                                linkLine("book", Text(String(localized: "marginarium.welcome.start", defaultValue: "Start with Chapter 1, the night it all began.",
                                                             comment: "The Marginarium: the link under the quoted opening of Chapter 1 on the contents page, which opens Chapter 1")))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("marginarium-start-chapter1")
                        }
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(MarginariumEntry.chapters) { entryLink($0) }
                        NavigationLink(value: MarginariumCast.whosWho) {
                            linkLine("person.3", Text(String(localized: "marginarium.welcome.whosWho", defaultValue: "Meet the people, the helpers and the guardians in Who's Who.",
                                                             comment: "The Marginarium: a link after the chapters on the contents page that opens Who's Who, the page of people, helpers and guardians")))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("marginarium-whos-who-link")
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        Text("Appendices")
                            .font(.display(.title2))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(MarginariumEntry.appendices) { entryLink($0) }
                    }
                }
                // A comfortable reading measure on wide windows, centered.
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.paper)
            .accessibilityIdentifier("marginarium-contents")
            .navigationDestination(for: String.self) { id in
                if id == MarginariumCast.whosWho {
                    MarginariumWhosWhoView()
                } else if let guardian = MarginariumCast.guardian(destination: id) {
                    MarginariumGuardianView(guardian: guardian)
                } else if let entry = (MarginariumEntry.chapters + MarginariumEntry.appendices).first(where: { $0.id == id }) {
                    MarginariumReaderView(entry: entry)
                }
            }
            .navigationTitle("The Marginarium")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            #if DEBUG
            .task {
                // `marginarium`: a moment for the drawings' sheets to load and start idling.
                guard ShellDemo.current == .marginarium else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                DemoMode.markReady()
            }
            #endif
        }
        .presentationDetents([.large])
        .tint(Theme.accent)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func entryLink(_ entry: MarginariumEntry) -> some View {
        NavigationLink(value: entry.id) {
            MarginariumEntryView(entry: entry)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("marginarium-entry-\(entry.id)")
    }

    /// A link that reads as a line of the page: its symbol, its words, a chevron.
    private func linkLine(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            text
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A line of the contents: a chapter's number (or an appendix's letter) beside its title and the
/// line under it.
private struct MarginariumEntryView: View {
    let entry: MarginariumEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.mark)
                .font(.display(.title2))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(.display(.title3, weight: .semibold))
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(entry.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The book's company, idling at the top of the page: Pip and Colophon, then every guardian in
/// Who's Who's order, each a small copy of its drawing (`MarginariumSpritePlayer(pet:marginWidth:)`),
/// so the page never holds their full sheets. A tap makes one wave (an egg rocks on) and shows its
/// name under it, a link to its brief in Who's Who (Pip's and Colophon's: Who's Who itself). Every
/// name keeps its room while hidden, so a name appearing moves nothing.
private struct MarginariumCompany: View {
    private static let drawingWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .caption) private var cellMinimum: CGFloat = 88
    /// The drawing whose name shows.
    @State private var named: String?
    /// Each drawing's taps: every new one makes it wave.
    @State private var greetings: [String: Int] = [:]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellMinimum), spacing: 8, alignment: .top)],
                  alignment: .center, spacing: 16) {
            member(id: MarginariumPet.pip.id, name: String(localized: "Pip, Codex's teapot"), label: nil,
                   hint: MarginariumPet.pip.hint, destination: MarginariumCast.whosWho) { greeting in
                MarginariumSpritePlayer(pet: .pip, marginWidth: Self.drawingWidth, greeting: greeting)
            }
            member(id: MarginariumPet.colophon.id, name: String(localized: "Colophon, Claude's moth"), label: nil,
                   hint: MarginariumPet.colophon.hint, destination: MarginariumCast.whosWho) { greeting in
                MarginariumSpritePlayer(pet: .colophon, marginWidth: Self.drawingWidth, greeting: greeting)
            }
            ForEach(MarginariumCast.guardians) { guardian in
                member(id: guardian.id, name: guardian.name, label: guardian.petCaption,
                       hint: guardian.hatched ? MarginariumPet.named(guardian.id)?.hint : nil,
                       destination: MarginariumCast.destination(of: guardian)) { greeting in
                    MarginariumGuardianPet(guardian: guardian, width: Self.drawingWidth, greeting: greeting)
                }
            }
        }
    }

    /// One drawing and, once it has been tapped, its name. `label` is what VoiceOver reads for the
    /// drawing when it says more than the name (an egg's).
    private func member<Drawing: View>(id: String, name: String, label: String?, hint: String?, destination: String,
                                       @ViewBuilder drawing: (Int) -> Drawing) -> some View {
        let shown = named == id
        return VStack(spacing: 4) {
            Button {
                greetings[id, default: 0] += 1
                named = id
            } label: {
                ZStack {
                    // The cell is the button; the drawing's own tap stays off.
                    drawing(greetings[id] ?? 0)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label ?? name))
            .accessibilityHint(Text(hint ?? ""))
            .accessibilityIdentifier("marginarium-drawing-\(id)")
            NavigationLink(value: destination) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .opacity(shown ? 1 : 0)
            .disabled(!shown)
            .accessibilityHidden(!shown)
            .accessibilityHint(Text(String(localized: "marginarium.drawing.page", defaultValue: "Opens its page in Who's Who",
                                           comment: "The Marginarium: VoiceOver hint of a guardian's or a pet's name, shown under its drawing on the contents page once tapped")))
            .accessibilityIdentifier("marginarium-name-\(id)")
        }
        .frame(maxWidth: .infinity)
    }
}
