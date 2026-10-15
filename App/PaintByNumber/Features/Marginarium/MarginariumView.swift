import Foundation
import SwiftUI

/// The Marginarium: how Paint by Moonlight is made, told in chapters, with Pip, Codex's teapot,
/// and Colophon, Claude's moth, near the top, a "New here?" box pointing to Chapter 1 and Who's
/// Who (`MarginariumWhosWhoView`), and one passage from each chapter and appendix
/// (`MarginariumEntry`). A sheet from the gallery's toolbar; each entry opens its native
/// `MarginariumReaderView`, whose blocks come from the bundled MarginariumDocument manifest.
///
/// Chief Architect Paul's rule for the whole book: anyone who opens it should have a nice time
/// and roughly follow what's going on. Pages say who people are and what the Lamp's words mean,
/// or point to Who's Who; the box says so in his words.
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
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "marginarium.subtitle", defaultValue: "How Paint by Moonlight is made, told in chapters.",
                                    comment: "The Marginarium: the line under the page's title"))
                            .font(.display(.title3, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "marginarium.intro",
                                    defaultValue: "This is the story of how the app gets made, written down as it happens. Paul and Caroline make it together, with help from Codex and Claude, two AI helpers, and from the Lamp: a panel of imaginary guardians who each care about one thing. The big choices stay with people, and a person's choice always wins.",
                                    comment: "The Marginarium: the introduction under the subtitle; Paul and Caroline are people, Codex and Claude AI helpers, the Lamp a panel of imaginary guardians"))
                    }

                    MarginariumGreeting()

                    MarginariumWelcome()

                    VStack(alignment: .leading, spacing: 28) {
                        Text(String(localized: "marginarium.passages", defaultValue: "One passage from each chapter, quoted as written.",
                                    comment: "The Marginarium: the line above the list of chapters"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(MarginariumEntry.chapters) { entryLink($0) }
                    }

                    VStack(alignment: .leading, spacing: 28) {
                        Text("Appendices")
                            .font(.display(.title2))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(MarginariumEntry.appendices) { entryLink($0) }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How the Lamp works")
                            .font(.display(.title2))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(MarginariumLamp.lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .accessibilityHidden(true)
                                Text(line)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Text(String(localized: "marginarium.footer", defaultValue: "The \"I\" in these passages is Claude, the narrator. Pip, Colophon and the guardians are drawn by Codex with an OpenAI image model.",
                                comment: "The Marginarium: the note at the end of the page identifying the narrator and crediting the AI-generated art of Pip, Colophon and the guardians"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
}

/// A chapter or an appendix: its number (or letter) beside its title and the line under it,
/// then its passage set as a quotation, behind a leading rule.
private struct MarginariumEntryView: View {
    let entry: MarginariumEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(entry.passage)
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint.opacity(0.45))
                        .frame(width: 3)
                }
        }
    }
}

/// Where a newcomer starts: Chapter 1, Who's Who, how a page reads, and Paul's rule for the book.
private struct MarginariumWelcome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New here?")
                .font(.display(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            NavigationLink(value: "marginarium") {
                line("book", Text(String(localized: "marginarium.welcome.start", defaultValue: "Start with Chapter 1, the night it all began.",
                                         comment: "The Marginarium: a link in the New here? box that opens Chapter 1")), link: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("marginarium-start-chapter1")
            NavigationLink(value: MarginariumCast.whosWho) {
                line("person.3", Text(String(localized: "marginarium.welcome.whosWho", defaultValue: "Meet everyone in Who's Who, guardians and all.",
                                             comment: "The Marginarium: a link in the New here? box that opens Who's Who, the page of people, helpers and guardians")), link: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("marginarium-whos-who-link")
            line("highlighter", Text(String(localized: "marginarium.welcome.reading",
                                               defaultValue: "The story runs down the middle of each page. Highlighted words have notes from the guardians: tap one to read them. Tap a guardian or a pet to say hello.",
                                               comment: "The Marginarium: a line in the New here? box on how a chapter page reads")), link: false)
            Text(String(localized: "marginarium.welcome.rule",
                        defaultValue: "A rule from Paul, our Chief Architect: anyone should be able to open this book, have a nice time and roughly follow what's going on. If something here loses you, that's our mistake, not yours.",
                        comment: "The Marginarium: the last line of the New here? box, Paul's rule for the book"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func line(_ symbol: String, _ text: Text, link: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            text
                .fixedSize(horizontal: false, vertical: true)
            if link {
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The pets sit together, with Pip's speech bubble below so captions and speech have room
/// to wrap on narrow windows and at accessibility text sizes.
private struct MarginariumGreeting: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                MarginariumSpritePlayer(pet: .pip, caption: String(localized: "Pip, Codex's teapot"))
                MarginariumSpritePlayer(pet: .colophon, caption: String(localized: "Colophon, Claude's moth"))
            }

            Text(String(localized: "marginarium.pip.bubble", defaultValue: "Still being written! Codex says more chapters are on the way.",
                        comment: "The Marginarium: what Pip, Codex's teapot, says in its speech bubble"))
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.top, SpeechBubble.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SpeechBubble().fill(Theme.surface))
        }
    }
}

/// A rounded speech bubble whose top tail points to Pip in the leading half of the pair.
/// Its content leaves `tail` of room above it.
nonisolated private struct SpeechBubble: Shape {
    static let tail: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let tail = Self.tail
        let body = CGRect(x: rect.minX, y: rect.minY + tail,
                          width: rect.width, height: max(0, rect.height - tail))
        var path = Path(roundedRect: body, cornerRadius: 18, style: .continuous)
        let x = body.minX + body.width / 4
        path.move(to: CGPoint(x: x - tail, y: body.minY))
        path.addLine(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x + tail, y: body.minY))
        path.closeSubpath()
        return path
    }
}
