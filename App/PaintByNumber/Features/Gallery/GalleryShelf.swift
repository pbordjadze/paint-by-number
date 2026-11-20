import SwiftUI

/// Something new to paint on the gallery itself (painting-company row 317: every critic round of
/// row 237 found the newcomer's gallery two cards in an empty room, and the Paint page its most
/// beautiful screen). Under the painter's own paintings, every day, Tonight's Picture, the Paint
/// page's, one the gallery doesn't hold yet; while the gallery holds only a few paintings,
/// the nights after it fill out its row, and More to Paint opens the whole Paint page. The tiles lie on
/// the cards' own columns, a card's width each, so the page reads as one grid and no library
/// picture outshines the painter's own (the critic's round 1). A tap paints a picture as the
/// Paint page's does (`AppShellView.paint(_:)`). In the release from 1.2.
///
/// In SideStore and Debug builds, once the museums' schedule is on the device (`Nights`), the
/// shelf keeps to one night: tonight's picture while the gallery doesn't hold it, and, once its
/// painting is finished, the vote for a coming night's (`NightsBallotTile`, the mock's round 2:
/// one time frame on the shelf), until the painter has chosen.
struct GalleryShelf: View {
    /// The library pictures the gallery holds (`Artwork.sampleName`), offered no more.
    let held: Set<String>
    /// The pictures of the gallery's finished paintings: tonight's among them opens the vote.
    var finished: Set<String> = []
    /// The gallery holds only a few paintings: room for the nights after tonight.
    let hasRoom: Bool
    /// The gallery's card columns and the space between their rows.
    let columns: [GridItem]
    let rowSpacing: CGFloat
    var onPaint: (Sample) -> Void
    var onMore: () -> Void

    #if UNRELEASED
    @State private var voting: Nights.Ballot?
    #endif

    var body: some View {
        #if UNRELEASED
        // Drawn again when a refresh lands.
        let _ = Nights.revision.value
        if let tonight = Nights.shared.night(on: .now) {
            nightsShelf(tonight)
        } else {
            libraryShelf
        }
        #else
        libraryShelf
        #endif
    }

    #if UNRELEASED
    /// Tonight's picture, or once it is painted, the vote it opens (`Nights.shared`'s schedule).
    @ViewBuilder
    private func nightsShelf(_ tonight: Sample) -> some View {
        let ballot = finished.contains(tonight.id) ? Nights.shared.openBallot() : nil
        let votable = ballot.flatMap { Nights.shared.choice(for: $0.night) == nil ? $0 : nil }
        if !held.contains(tonight.id) || votable != nil {
            VStack(alignment: .leading, spacing: 16) {
                if let votable {
                    Text(NightsBallotSheet.heading(for: votable))
                        .font(.display(.title2))
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: rowSpacing) {
                        Button { voting = votable } label: { NightsBallotTile(ballot: votable) }
                            .buttonStyle(PressableCardStyle())
                            .accessibilityIdentifier("gallery-vote")
                    }
                } else {
                    Text("Tonight’s Picture")
                        .font(.display(.title2))
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: rowSpacing) {
                        Button { onPaint(tonight) } label: { SampleTile(sample: tonight).overlay(alignment: .topTrailing) { moon } }
                            .buttonStyle(PressableCardStyle())
                            .accessibilityValue(String(localized: "Tonight’s Picture"))
                            .accessibilityIdentifier("gallery-tonight")
                    }
                }
                if hasRoom {
                    Button("More to Paint", systemImage: "plus", action: onMore)
                        .buttonStyle(.glass)
                        .accessibilityHint(Text("Opens the Paint page: your own photos, a blank page and the earlier nights"))
                        .accessibilityIdentifier("gallery-more-to-paint")
                }
            }
            .sheet(item: $voting) { ballot in
                NightsBallotSheet(ballot: ballot)
            }
        }
    }
    #endif

    /// Tonight's, told from the nights after it by the design's crescent alone (the critic's
    /// round 2: which tile is tonight's?).
    private var moon: some View {
        Image(systemName: "moon.fill")
            .font(.title3)
            .foregroundStyle(Theme.gold)
            // On a dark disc: alone, it was lost on a warm picture (Oriental Poppies, CI's first look).
            .padding(8)
            .background(.black.opacity(0.45), in: .circle)
            .padding(10)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var libraryShelf: some View {
        // Tonight and, while there is room, the nights after it to the end of its row.
        let nights = Sample.nights(count: hasRoom ? max(1, columns.count) : 1, excluding: held)
        if !nights.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tonight’s Picture")
                    .font(.display(.title2))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns, alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(nights.enumerated()), id: \.element.id) { index, sample in
                        Button { onPaint(sample) } label: {
                            SampleTile(sample: sample)
                                .overlay(alignment: .topTrailing) {
                                    if index == 0 { moon }
                                }
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityValue(index == 0 ? String(localized: "Tonight’s Picture") : "")
                        .accessibilityIdentifier(index == 0 ? "gallery-tonight" : "gallery-night")
                    }
                }
                if hasRoom {
                    Button("More to Paint", systemImage: "plus", action: onMore)
                        .buttonStyle(.glass)
                        .accessibilityHint(Text("Opens the Paint page: your own photos, a blank page and the whole library"))
                        .accessibilityIdentifier("gallery-more-to-paint")
                }
            }
        }
    }
}
