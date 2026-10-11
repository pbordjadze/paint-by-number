import Foundation
import SwiftUI

/// The Marginarium: how Paint by Moonlight is made, told in chapters, with Pip, Codex's teapot,
/// and Colophon, Claude's moth, near the top and one passage from each chapter and appendix
/// (`MarginariumEntry`). A sheet from the gallery's toolbar.
struct MarginariumView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "marginarium.subtitle", defaultValue: "How Paint by Moonlight is made, told in chapters.",
                                    comment: "The Marginarium: the line under the page's title"))
                            .font(.display(.title3, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "marginarium.intro",
                                    defaultValue: "Paul makes this app with a small team of AI helpers: Codex builds the tools, Claude reviews the work and writes these chapters, and nineteen guardians called the Lamp weigh in on smaller design questions. The big creative choices stay with people, and a person's choice always wins.",
                                    comment: "The Marginarium: the introduction under the subtitle; Codex and Claude are AI helpers, the Lamp a panel of nineteen guardians"))
                    }

                    MarginariumGreeting()

                    VStack(alignment: .leading, spacing: 28) {
                        Text(String(localized: "marginarium.passages", defaultValue: "One passage from each chapter, quoted as written.",
                                    comment: "The Marginarium: the line above the list of chapters"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(MarginariumEntry.chapters) { MarginariumEntryView(entry: $0) }
                    }

                    VStack(alignment: .leading, spacing: 28) {
                        Text("Appendices")
                            .font(.display(.title2))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(MarginariumEntry.appendices) { MarginariumEntryView(entry: $0) }
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

                    Text(String(localized: "marginarium.footer", defaultValue: "The \"I\" in these passages is Claude, the narrator.",
                                comment: "The Marginarium: the note at the end of the page"))
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
                    Text(entry.title)
                        .font(.display(.title3, weight: .semibold))
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

/// The pets sit together, with Pip's speech bubble below so captions and speech have room
/// to wrap on narrow windows and at accessibility text sizes.
private struct MarginariumGreeting: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                MarginariumSpritePlayer(animation: PipSprite.animation,
                                        caption: String(localized: "Pip, Codex's teapot"),
                                        hint: String(localized: "Lifts its lid."))
                MarginariumSpritePlayer(animation: ColophonSprite.animation,
                                        caption: String(localized: "Colophon, Claude's moth"),
                                        hint: String(localized: "Folds its wings like a bookmark."))
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

/// One cancellable player for both pets. A new tap restarts the response; Reduce Motion
/// shows one still pose, and closing the sheet cancels the loop.
private struct MarginariumSpritePlayer: View {
    let animation: SpriteAnimation
    let caption: String
    let hint: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose: SpriteFrame
    @State private var taps = 0
    @State private var played = 0

    init(animation: SpriteAnimation, caption: String, hint: String) {
        self.animation = animation
        self.caption = caption
        self.hint = hint
        _pose = State(initialValue: animation.idle[0])
    }

    private struct Trigger: Equatable {
        let taps: Int
        let reduceMotion: Bool
    }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                taps += 1
            } label: {
                Image(pose.name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 104)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(caption))
            .accessibilityHint(Text(hint))
            // The button already says who the pet is.
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .task(id: Trigger(taps: taps, reduceMotion: reduceMotion)) { await animate() }
    }

    private func animate() async {
        let responds = taps > played
        played = taps
        do {
            if responds {
                for step in animation.actionFrames(reduceMotion: reduceMotion) {
                    pose = step
                    try await Task.sleep(for: step.hold)
                }
            }
            if reduceMotion {
                pose = animation.idle[0]
                return
            }
            while true {
                for step in animation.idle {
                    pose = step
                    try await Task.sleep(for: step.hold)
                }
            }
        } catch {
            // Cancelled: the next run (or nothing, once the page has closed) takes over.
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
