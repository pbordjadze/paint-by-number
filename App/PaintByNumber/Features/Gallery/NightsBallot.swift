#if UNRELEASED
import Accessibility
import CoreGraphics
import SwiftUI

/// The vote for a coming night's picture (painting-company row 368; the mock's round 3 in
/// painting-company's `factory/pieces/daily-pick`): on the gallery's shelf once tonight's
/// painting is finished, an invitation with three small pictures fanned, and a sheet that asks which of them
/// everyone paints that night. One tap is the vote (`Nights.vote(_:on:)`); no counts are shown.
struct NightsBallotTile: View {
    let ballot: Nights.Ballot
    @State private var images: [String: CGImage] = [:]
    @ScaledMetric(relativeTo: .headline) private var fanHeight: CGFloat = 64

    var body: some View {
        // An invitation, not a painting (the critic's round 1 on CI's screens): a row lighter and
        // smaller than a card, its three pictures small and fanned beside the question.
        HStack(spacing: 16) {
            ZStack {
                fanned(1, angle: -10, x: -fanHeight * 0.36)
                fanned(2, angle: 9, x: fanHeight * 0.36)
                fanned(0, angle: 0, x: 0)
            }
            .frame(width: fanHeight * 1.5, height: fanHeight * 1.1)
            VStack(alignment: .leading, spacing: 2) {
                Text(NightsBallotSheet.heading(for: ballot))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Choose one of three")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Theme.surface.opacity(0.7), in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect(cornerRadius: 18, style: .continuous))
        .hoverEffect(.highlight)
        .task(id: ballot.night) {
            for id in ballot.choices {
                guard let sample = Nights.shared.sample(id) else { continue }
                if let image = await SampleImages.shared.load(sample, maxPixelSize: 240) { images[id] = image }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NightsBallotSheet.heading(for: ballot)))
        .accessibilityHint(Text("Choose one of three pictures for everyone to paint that night"))
        .accessibilityAddTraits(.isButton)
    }

    private func fanned(_ index: Int, angle: Double, x: CGFloat) -> some View {
        let id = ballot.choices.indices.contains(index) ? ballot.choices[index] : ""
        return Color.clear
            .frame(width: fanHeight * 0.72, height: fanHeight * 0.92)
            .overlay {
                if let image = images[id] {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .background(Theme.paper)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white, lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .rotationEffect(.degrees(angle))
            .offset(x: x)
    }
}

/// What should everyone paint on <night>? Three pictures, one tap.
struct NightsBallotSheet: View {
    let ballot: Nights.Ballot
    @State private var chosen: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The night's weekday, "Sunday": a ballot closes before its night begins anywhere, so its
    /// weekday is the same for every painter.
    static func weekday(of ballot: Nights.Ballot) -> String {
        Nights.date(of: ballot.night, in: .current)?.formatted(.dateTime.weekday(.wide)) ?? ballot.night
    }

    /// The shelf's heading over the vote: "Sunday’s Picture".
    static func heading(for ballot: Nights.Ballot) -> String {
        String(
            localized: "nights.ballot.heading", defaultValue: "\(weekday(of: ballot))’s Picture",
            comment: "The gallery's heading over the vote for a coming night's picture. The argument is the night's weekday, \"Sunday\".")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text(String(
                            localized: "nights.ballot.question", defaultValue: "What should everyone paint on \(Self.weekday(of: ballot))?",
                            comment: "The vote's question. The argument is the night's weekday, \"Sunday\"."))
                            .font(.display(.title2))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(String(
                            localized: "nights.ballot.explanation", defaultValue: "Tap one. The winner opens on \(Self.weekday(of: ballot)) night.",
                            comment: "Under the vote's question. The argument is the night's weekday, \"Sunday\"."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(ballot.choices, id: \.self) { id in
                        if let sample = Nights.shared.sample(id) {
                            Button { choose(id) } label: { SampleTile(sample: sample) }
                                .buttonStyle(PressableCardStyle())
                                .overlay {
                                    if chosen == id {
                                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                                            .stroke(Theme.signature, lineWidth: 3)
                                            .padding(-3)
                                    }
                                }
                                .opacity(chosen == nil || chosen == id ? 1 : 0.35)
                                .disabled(chosen != nil)
                                .accessibilityValue(chosen == id ? Text("Chosen") : Text(verbatim: ""))
                                .accessibilityIdentifier("ballot-choice")
                        }
                    }
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.paper)
    }

    private func choose(_ id: String) {
        guard chosen == nil, Date.now < ballot.closes else { return dismiss() }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { chosen = id }
        AccessibilityNotification.Announcement(String(localized: "Chosen")).post()
        let ballot = ballot
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 0.9))
            // Cast as the sheet goes: the shelf it came from leaves with the vote cast.
            Nights.shared.vote(id, on: ballot)
            dismiss()
        }
    }
}
#endif
