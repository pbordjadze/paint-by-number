import SwiftUI

/// Shown when the gallery is empty: an invitation to make the first painting.
struct EmptyGalleryView: View {
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 34) {
            SnapshotFan()
                .frame(height: 220)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Paint something beautiful")
                    .font(.rounded(.title, weight: .bold))
                Text("Turn any photo into a numbered canvas, then bring it to life one color at a time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .containerRelativeFrame(.horizontal) { length, _ in max(0, min(length - 64, 400)) }

            Button(action: onCreate) {
                Label("New Painting", systemImage: "plus")
                    .font(.rounded(.headline, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Three sample snapshots fanned out, the middle one with its numbered palette.
private struct SnapshotFan: View {
    private let cards: [(sample: Sample, palette: [Color])] = [
        (Sample.all[2], []),
        (Sample.all[0], [
            Color(red: 0.84, green: 0.18, blue: 0.16), Color(red: 0.98, green: 0.78, blue: 0.1),
            Color(red: 0.2, green: 0.55, blue: 0.3), Color(red: 0.22, green: 0.5, blue: 0.72),
        ]),
        (Sample.all[1], []),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                Snapshot(sample: card.sample, palette: card.palette)
                    .rotationEffect(.degrees(Double(index - 1) * 10))
                    .offset(x: CGFloat(index - 1) * 82, y: index == 1 ? -8 : 12)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
    }
}

private struct Snapshot: View {
    let sample: Sample
    let palette: [Color]
    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: 128, height: 146)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    }
                }
                .background(Theme.paper)
                .clipShape(.rect(cornerRadius: 7, style: .continuous))
            HStack(spacing: 5) {
                ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(color, in: .circle)
                }
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        .task { image = await SampleImages.shared.load(sample, maxPixelSize: 400) }
    }
}
