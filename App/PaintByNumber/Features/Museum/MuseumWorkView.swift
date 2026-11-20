#if UNRELEASED
import Foundation
import ImageIO
import SwiftUI
import UIKit

/// A work of the Museum, large, with its wall label: title, artist, date, medium, movement and
/// the museum that holds it, a link to its page there, and Paint This. The full image is fetched
/// as the page opens (it replaces the tile's picture once it comes), so Paint This usually has it
/// at once; tapped before, the button waits for it, and a failure says so in an alert.
struct MuseumWorkView: View {
    let work: MuseumCatalog.Work
    let museum: String
    var onPaint: (Data, String) -> Void

    @State private var picture: CGImage?
    @State private var full: Data?
    @State private var fetchFailed = false
    @State private var wantsToPaint = false
    @State private var showsFailure = false
    @State private var size: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                artwork
                label
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, size.width >= 600 ? 32 : 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .navigationTitle(Text(verbatim: work.title))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { paintButton }
        .task(id: work.id) { await fetch() }
        .alert("Couldn’t Get This Picture", isPresented: $showsFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection, then try again.")
        }
    }

    // MARK: The picture

    /// The picture whole, as large as the page allows (never taller than about 60% of it).
    private var artwork: some View {
        let shown = fitted
        return ZStack {
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .transition(.opacity)
            } else {
                Color(museumHex: work.average)
            }
        }
        .frame(width: shown.width, height: shown.height)
        .clipShape(.rect(cornerRadius: 2))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: work.title))
        .accessibilityAddTraits(.isImage)
    }

    private var fitted: CGSize {
        let width = min(max(size.width - (size.width >= 600 ? 64 : 40), 1), 680)
        let height = max(size.height * 0.6, 1)
        let ratio = work.aspectRatio
        if width / height > ratio {
            return CGSize(width: height * ratio, height: height)
        }
        return CGSize(width: width, height: width / ratio)
    }

    // MARK: The wall label

    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: work.title)
                .font(.display(.title2))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: work.artist)
                .font(.headline)
            if !work.year.isEmpty {
                Text(verbatim: work.year)
                    .foregroundStyle(.secondary)
            }
            if !work.medium.isEmpty {
                Text(verbatim: work.medium)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: work.movement)
                .font(.subheadline.italic())
                .foregroundStyle(.secondary)
            Divider()
                .padding(.vertical, 8)
            if !museum.isEmpty {
                Text(verbatim: museum)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let page = work.page {
                Link(destination: page) {
                    Label("On the Museum’s Website", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabel())
                }
                .font(.footnote.weight(.semibold))
                .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Painting it

    private var paintButton: some View {
        Button(action: paint) {
            HStack(spacing: 10) {
                if wantsToPaint {
                    ProgressView()
                        .tint(.white)
                    Text("Getting the Picture…")
                } else {
                    Label("Paint This", systemImage: "paintbrush.pointed")
                }
            }
            .frame(maxWidth: 420)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.signature)
        .controlSize(.large)
        .disabled(wantsToPaint)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("museum-paint")
    }

    private func paint() {
        if let full {
            onPaint(full, work.title)
        } else if fetchFailed {
            fetchFailed = false
            wantsToPaint = true
            Task { await fetch() }
        } else {
            wantsToPaint = true
        }
    }

    /// The tile's picture at once, then the full image, which the page shows and Paint This
    /// paints.
    private func fetch() async {
        if picture == nil, let tile = await MuseumImages.shared.picture(work.thumb, maxPixelSize: 900) {
            picture = tile
        }
        do {
            let data = try await MuseumImages.shared.data(work.image)
            guard !Task.isCancelled else { return }
            full = data
            let pixels = Int(max(fitted.width, fitted.height) * displayScale)
            if let large = await Background.run({ Self.decode(data, maxPixelSize: max(pixels, 900)) }) {
                withAnimation(.easeOut(duration: 0.3)) { picture = large }
            }
            if wantsToPaint {
                wantsToPaint = false
                onPaint(data, work.title)
            }
        } catch {
            guard !Task.isCancelled else { return }
            fetchFailed = true
            if wantsToPaint {
                wantsToPaint = false
                showsFailure = true
            }
        }
    }

    nonisolated private static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A label with its icon after its title, as a link that leaves the app reads.
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
#endif
