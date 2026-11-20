#if UNRELEASED
import Accessibility
import CoreGraphics
import SwiftUI

/// The vote for a coming night's picture (painting-company row 368; the mock's round 3 in
/// painting-company's `factory/pieces/daily-pick`): on the gallery's shelf once tonight's
/// painting is finished, three pictures fanned on one card, and a sheet that asks which of them
/// everyone paints that night. One tap is the vote (`Nights.vote(_:on:)`); no counts are shown.
struct NightsBallotTile: View {
    let ballot: Nights.Ballot
    @State private var images: [String: CGImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        let card = CGSize(width: proxy.size.width * 0.36, height: proxy.size.width * 0.47)
                        ZStack {
                            fanned(1, card: card, angle: -9, x: -0.22 * proxy.size.width)
                            fanned(2, card: card, angle: 8, x: 0.22 * proxy.size.width)
                            fanned(0, card: card, angle: 0, x: 0, y: -6)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .contentShape(.rect(cornerRadius: 18, style: .continuous))
                .hoverEffect(.lift)
            Text("Choose one of three")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
        }
        .task(id: ballot.night) {
            for id in ballot.choices {
                guard let sample = Nights.shared.sample(id) else { continue }
                if let image = await SampleImages.shared.load(sample, maxPixelSize: 320) { images[id] = image }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NightsBallotSheet.heading(for: ballot)))
        .accessibilityHint(Text("Choose one of three pictures for everyone to paint that night"))
        .accessibilityAddTraits(.isButton)
    }

    private func fanned(_ index: Int, card: CGSize, angle: Double, x: CGFloat, y: CGFloat = 0) -> some View {
        let id = ballot.choices.indices.contains(index) ? ballot.choices[index] : ""
        return Color.clear
            .frame(width: card.width, height: card.height)
            .overlay {
                if let image = images[id] {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .background(Theme.paper)
            .clipShape(.rect(cornerRadius: 9, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white, lineWidth: 2) }
            .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
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
                    ForEach(ballot.choices, id: \.self) { id in
                        if let sample = Nights.shared.sample(id) {
                            Button { choose(id) } label: { SampleTile(sample: sample) }
                                .buttonStyle(PressableCardStyle())
                                .overlay {
                                    if chosen == id {
                                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                                            .stroke(Theme.gold, lineWidth: 3)
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
                .frame(maxWidth: 520)
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
        guard chosen == nil else { return }
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
