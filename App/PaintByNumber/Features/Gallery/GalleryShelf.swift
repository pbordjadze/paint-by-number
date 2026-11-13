#if UNRELEASED
import SwiftUI

/// Something new to paint on the gallery itself (painting-company row 317: every critic round of
/// row 237 found the newcomer's gallery two cards in an empty room, and the Paint page its most
/// beautiful screen). Under the painter's own paintings, every day, Tonight's Picture as the Paint
/// page shows it, one the gallery doesn't hold yet; while the gallery holds only a few paintings,
/// the nights after it too, and More to Paint, the whole Paint page. A tap paints a picture as
/// the Paint page's does (`AppShellView.paint(_:)`). SideStore and Debug builds until Paul has
/// seen it.
struct GalleryShelf: View {
    /// The library pictures the gallery holds (`Artwork.sampleName`), offered no more.
    let held: Set<String>
    /// The gallery holds only a few paintings: room for the nights after tonight.
    let hasRoom: Bool
    /// The pages' column, the press scale's room taken off: a tile scaled up for a large text
    /// size never grows wider (as `PhotoSourceView.tileWidth`).
    let column: CGFloat
    var onPaint: (Sample) -> Void
    var onMore: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var tileMinimumWidth: CGFloat = 150

    /// The other nights shown while there is room: a row on an iPad, two on a phone.
    static let otherNights = 4

    private var tileWidth: CGFloat { column > 0 ? min(tileMinimumWidth, column) : tileMinimumWidth }

    var body: some View {
        let nights = Sample.nights(count: hasRoom ? 1 + Self.otherNights : 1, excluding: held)
        if let tonight = nights.first {
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
                Button { onPaint(tonight) } label: { SampleTile(sample: tonight) }
                    .buttonStyle(PressableCardStyle())
                    // As large as a card can be without outshining the paintings above it.
                    .frame(maxWidth: 560)
                    .accessibilityIdentifier("gallery-tonight")
                if hasRoom, nights.count > 1 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 14)], alignment: .leading, spacing: 14) {
                        ForEach(nights.dropFirst()) { sample in
                            Button { onPaint(sample) } label: { SampleTile(sample: sample) }
                                .buttonStyle(PressableCardStyle())
                                .accessibilityIdentifier("gallery-night")
                        }
                    }
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
