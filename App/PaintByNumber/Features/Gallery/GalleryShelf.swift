#if UNRELEASED
import SwiftUI

/// Something new to paint on the gallery itself (painting-company row 317: every critic round of
/// row 237 found the newcomer's gallery two cards in an empty room, and the Paint page its most
/// beautiful screen). Under the painter's own paintings, every day, Tonight's Picture as the Paint
/// page shows it, one the gallery doesn't hold yet; while the gallery holds only a few paintings,
/// the nights after it fill out its row, and More to Paint opens the whole Paint page. The tiles lie on
/// the cards' own columns, a card's width each, so the page reads as one grid and no library
/// picture outshines the painter's own (the critic's round 1). A tap paints a picture as the
/// Paint page's does (`AppShellView.paint(_:)`). SideStore and Debug builds until Paul has seen it.
struct GalleryShelf: View {
    /// The library pictures the gallery holds (`Artwork.sampleName`), offered no more.
    let held: Set<String>
    /// The gallery holds only a few paintings: room for the nights after tonight.
    let hasRoom: Bool
    /// The gallery's card columns and the space between their rows.
    let columns: [GridItem]
    let rowSpacing: CGFloat
    var onPaint: (Sample) -> Void
    var onMore: () -> Void

    var body: some View {
        // Tonight and, while there is room, the nights after it to the end of its row.
        let nights = Sample.nights(count: hasRoom ? max(1, columns.count) : 1, excluding: held)
        if !nights.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tonight’s Picture")
                        .font(.display(.title2))
                        .accessibilityAddTraits(.isHeader)
                    Text("A different picture every day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                LazyVGrid(columns: columns, alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(nights.enumerated()), id: \.element.id) { index, sample in
                        Button { onPaint(sample) } label: { SampleTile(sample: sample) }
                            .buttonStyle(PressableCardStyle())
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
#endif
