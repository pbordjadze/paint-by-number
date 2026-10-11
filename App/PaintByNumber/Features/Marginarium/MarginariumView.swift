import Foundation
import SwiftUI

/// The Marginarium: how Paint by Moonlight is made, told in chapters, with Pip, Codex's teapot,
/// near the top and one passage from each chapter and appendix (`MarginariumEntry`). A sheet
/// from the gallery's toolbar.
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
                                    defaultValue: "Paul makes this app with a small team of AI helpers: Codex builds the tools, Claude reviews the work and writes these chapters, and nineteen guardians called the Lamp vote on matters of taste. Paul has the last word.",
                                    comment: "The Marginarium: the introduction under the subtitle; Codex and Claude are AI helpers, the Lamp a panel of nineteen guardians"))
                    }

                    PipGreeting()

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

/// Pip, Codex's teapot, with what it has to say. It idles on a loop of its sprite's frames
/// (`PipSprite`); a tap plays its waving row once and goes back to idling. Under Reduce Motion
/// it stands still on its first idle frame, and a tap shows the lid lifted for a moment.
private struct PipGreeting: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The frame on screen.
    @State private var pose = PipSprite.idle[0]
    /// Taps so far, and how many of them have had their wave: a new tap restarts the animation.
    @State private var taps = 0
    @State private var waved = 0

    private struct Trigger: Equatable {
        let taps: Int
        let reduceMotion: Bool
    }

    var body: some View {
        // Pip above its bubble at accessibility text sizes, beside it otherwise.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
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
                .accessibilityLabel(Text("Pip, Codex's teapot"))
                .accessibilityHint(Text("Lifts its lid."))
                // The button already says who Pip is.
                Text("Pip, Codex's teapot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
            .layoutPriority(1)

            Text(String(localized: "marginarium.pip.bubble", defaultValue: "Still being written! Codex says more chapters are on the way.",
                        comment: "The Marginarium: what Pip, Codex's teapot, says in its speech bubble"))
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(stacked ? Edge.Set.top : Edge.Set.leading, SpeechBubble.tail)
                .background(SpeechBubble(tailOnTop: stacked).fill(Theme.surface))
        }
        .task(id: Trigger(taps: taps, reduceMotion: reduceMotion)) { await animate() }
    }

    /// Idles until cancelled (by the next tap, a Reduce Motion change or the page closing),
    /// after playing the waving row once if a tap hasn't had its wave yet.
    private func animate() async {
        let waves = taps > waved
        waved = taps
        do {
            if reduceMotion {
                if waves {
                    pose = PipSprite.lidLifted
                    try await Task.sleep(for: PipSprite.lidLifted.hold)
                }
                pose = PipSprite.idle[0]
                return
            }
            if waves {
                for step in PipSprite.waving {
                    pose = step
                    try await Task.sleep(for: step.hold)
                }
            }
            while true {
                for step in PipSprite.idle {
                    pose = step
                    try await Task.sleep(for: step.hold)
                }
            }
        } catch {
            // Cancelled: the next run (or nothing, once the page has closed) takes over.
        }
    }
}

/// A rounded speech bubble whose tail points to its leading side (Pip beside it) or its top
/// (Pip above it). Its content leaves `tail` of room on that side.
nonisolated private struct SpeechBubble: Shape {
    static let tail: CGFloat = 10
    var tailOnTop: Bool

    func path(in rect: CGRect) -> Path {
        let tail = Self.tail
        let body = tailOnTop
            ? CGRect(x: rect.minX, y: rect.minY + tail, width: rect.width, height: max(0, rect.height - tail))
            : CGRect(x: rect.minX + tail, y: rect.minY, width: max(0, rect.width - tail), height: rect.height)
        var path = Path(roundedRect: body, cornerRadius: 18, style: .continuous)
        if tailOnTop {
            let x = body.minX + 48
            path.move(to: CGPoint(x: x - tail, y: body.minY))
            path.addLine(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + tail, y: body.minY))
        } else {
            let y = body.midY
            path.move(to: CGPoint(x: body.minX, y: y - tail))
            path.addLine(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: body.minX, y: y + tail))
        }
        path.closeSubpath()
        return path
    }
}
