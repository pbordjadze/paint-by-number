import SwiftUI

/// A gallery card: the painting as it stands, its title and progress.
struct ArtworkCard: View {
    let artwork: Artwork
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardFrame {
                ArtworkThumbnail(artwork: artwork)
            }
            .overlay(alignment: .topTrailing) {
                if artwork.needsNewerApp {
                    NeedsUpdateBadge().padding(10)
                } else if artwork.isComplete {
                    FinishedBadge().padding(10)
                }
            }
            // The pointer lifts the picture, not its caption.
            .contentShape(.hoverEffect, .rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .hoverEffect(.lift)
            .matchedTransitionSource(id: artwork.id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(artwork.title)
                    .font(.rounded(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                ProgressCaption(artwork: artwork)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(artwork.title)
        .accessibilityValue(ProgressCaption.spoken(artwork))
        .accessibilityAddTraits(.isButton)
    }
}

/// Square, rounded, softly shadowed frame shared by cards and placeholders.
struct CardFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.09), radius: 16, x: 0, y: 8)
    }
}

/// The artwork's stored thumbnail, reloaded (with a crossfade) when it changes.
struct ArtworkThumbnail: View {
    let artwork: Artwork
    var contentMode: ContentMode = .fill
    @Environment(Library.self) private var library
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: ThumbnailCache.key(artwork)) {
            if image == nil { image = ThumbnailCache.shared.cached(artwork) }
            let loaded = await ThumbnailCache.shared.load(artwork, from: library.store)
            if let loaded, loaded !== image {
                withAnimation(.easeInOut(duration: 0.3)) { image = loaded }
            }
        }
    }
}

private struct FinishedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .glassEffect(.regular.tint(Theme.accent), in: .circle)
            .accessibilityHidden(true)
    }
}

/// Marks an artwork made by a newer version of the app, which this one can't open.
private struct NeedsUpdateBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.orange)
            .frame(width: 30, height: 30)
            .glassEffect(.regular, in: .circle)
            .accessibilityHidden(true)
    }
}

/// "42%", "Ready to paint", "Finished", "Needs app update".
struct ProgressCaption: View {
    let artwork: Artwork

    var body: some View {
        HStack(spacing: 6) {
            if artwork.needsNewerApp {
                Image(systemName: "arrow.up.circle").foregroundStyle(.orange)
                Text("Needs app update")
            } else if artwork.isComplete {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                if artwork.activeSeconds >= 60 {
                    Text("Finished · \(PaintingTime.spent(artwork.activeSeconds))")
                } else {
                    Text("Finished")
                }
            } else if artwork.isStarted {
                ProgressRing(fraction: artwork.fractionComplete, lineWidth: 2.4)
                    .frame(width: 14, height: 14)
                Text(verbatim: "\(Self.percent(artwork))% painted").monospacedDigit()
            } else {
                Image(systemName: "paintbrush.pointed").foregroundStyle(.tint)
                Text("Ready to paint")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        // Wraps rather than clips at large text sizes on narrow cards.
        .lineLimit(2)
    }

    static func percent(_ artwork: Artwork) -> Int {
        // Never round up to 100% before the last region is painted.
        min(99, Int((artwork.fractionComplete * 100).rounded(.down)))
    }

    static func spoken(_ artwork: Artwork) -> String {
        if artwork.needsNewerApp { return "Needs a newer version of the app" }
        if artwork.isComplete { return "Finished" }
        if !artwork.isStarted { return "Not started, \(artwork.colorCount) colors" }
        return "\(percent(artwork)) percent painted"
    }
}

/// Stands in for an artwork that is still being prepared.
struct PlaceholderCard: View {
    let placeholder: Library.Placeholder
    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardFrame {
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .saturation(0.15)
                            .opacity(0.4)
                            .blur(radius: 8)
                    }
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, options: .repeating)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(placeholder.sample.title)
                    .font(.rounded(.headline, weight: .semibold))
                    .lineLimit(1)
                Text("Preparing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .task { image = await SampleImages.shared.load(placeholder.sample, maxPixelSize: 400) }
        .accessibilityElement(children: .combine)
    }
}
