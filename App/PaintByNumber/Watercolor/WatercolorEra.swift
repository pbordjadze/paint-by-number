#if UNRELEASED
import CoreGraphics
import PaintCore
import PhotosUI
import Ravenna
import SwiftUI
import UIKit
import os

/// Watercolor, the era behind 1502 on the year wheel (painting-company row 373; SideStore and
/// Debug builds): paint by number where every tap is real water. A painting is a PaintCore
/// `Template` the app makes as it makes its own, kept by an `ArtworkStore` of its own
/// (`WatercolorShelf`), painted on a sheet where the water and pigment move (`WatercolorSim`,
/// drawn by `WatercolorRenderer`). The era is its gallery, a new painting from a photo or a
/// library picture, and Settings, whose Year wheel leaves it.
struct WatercolorEra: View {
    let leave: (Int) -> Void

    @State private var shelf = WatercolorShelf.shared
    @State private var path: [UUID] = []
    @State private var picking = false
    @State private var choosingPicture = false
    @State private var picked: PhotosPickerItem?
    @State private var showsSettings = false
    @State private var isMaking = false
    /// The Making Of of the painting just made, over its painting screen.
    @State private var makingOf: WatercolorFilm?

    var body: some View {
        NavigationStack(path: $path) {
            WatercolorGalleryView(shelf: shelf, onPhoto: { picking = true }, onPicture: { choosingPicture = true },
                                  onSettings: { showsSettings = true }, onOpen: { path.append($0) })
                .navigationDestination(for: UUID.self) { id in
                    WatercolorPaintScreen(shelf: shelf, id: id)
                }
        }
        .overlay {
            if isMaking {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Making the painting…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(28)
                .background(.regularMaterial, in: .rect(cornerRadius: 22))
            }
        }
        .overlay {
            if let makingOf {
                WatercolorMakingOfView(film: makingOf) { self.makingOf = nil }
            }
        }
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await load(item) }
        }
        .sheet(isPresented: $choosingPicture) {
            WatercolorPicturePicker { sample in
                choosingPicture = false
                Task { await load(sample) }
            }
        }
        .sheet(isPresented: $showsSettings) {
            WatercolorSettingsView(leave: leave)
        }
        .task {
            await shelf.load()
            #if DEBUG
            await WatercolorDemo.run(scenario: DemoMode.scenario, shelf: shelf, path: $path, makingOf: $makingOf)
            #endif
        }
        .tint(WatercolorEra.ink)
    }

    /// The era's accent: an ultramarine wash.
    static let ink = Color(red: 0.22, green: 0.33, blue: 0.62)
    /// The desk the sheet lies on.
    static let desk = Color(red: 0.91, green: 0.89, blue: 0.85)

    /// Whether the launch asked for one of Watercolor's demo scenarios (`-demo watercolor-<name>`),
    /// which open the era whatever the clock says (Debug builds only).
    static var isDemoScenario: Bool {
        #if DEBUG
        return DemoMode.scenario?.hasPrefix("watercolor-") == true
        #else
        return false
        #endif
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let photo = try await Background.run { try PhotoLoader.load(data: data, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            await make(from: photo, title: shelf.title(), sampleName: nil)
        } catch {
            Log.library.error("Couldn't load a photo for a watercolor: \(String(describing: error), privacy: .public)")
        }
    }

    private func load(_ sample: Sample) async {
        guard let url = sample.url else { return }
        do {
            let photo = try await Background.run { try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            await make(from: photo, title: sample.title, sampleName: sample.id)
        } catch {
            Log.library.error("Couldn't load a library picture for a watercolor: \(String(describing: error), privacy: .public)")
        }
    }

    private func make(from photo: RGBAImage, title: String, sampleName: String?) async {
        isMaking = true
        defer { isMaking = false }
        do {
            let (template, settings) = try await WatercolorShelf.template(of: photo, length: Preferences().paintingLength)
            let artwork = try await shelf.create(template: template, settings: settings, photo: photo, title: title, sampleName: sampleName)
            // The Making Of plays over the painting screen as it opens beneath (VoiceOver has
            // nothing to see in it, and goes straight to the painting).
            if !UIAccessibility.isVoiceOverRunning {
                makingOf = await WatercolorFilm.prepare(template: template, seed: WatercolorPainting.seed(of: artwork.id))
            }
            path = [artwork.id]
        } catch {
            Log.library.error("Couldn't make a watercolor: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The paintings: a card each, newest first; none yet, a way to make the first.
struct WatercolorGalleryView: View {
    let shelf: WatercolorShelf
    let onPhoto: () -> Void
    let onPicture: () -> Void
    let onSettings: () -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        Group {
            if shelf.isLoaded && shelf.paintings.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 18)], spacing: 22) {
                        ForEach(shelf.paintings) { artwork in
                            WatercolorCard(shelf: shelf, artwork: artwork, onOpen: { onOpen(artwork.id) })
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(WatercolorEra.desk.ignoresSafeArea())
        .navigationTitle(Text("Watercolor"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape", action: onSettings)
                    .accessibilityIdentifier("watercolor-settings")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("New Painting", systemImage: "plus") {
                    Button("A Photo", systemImage: "photo", action: onPhoto)
                    Button("The Library", systemImage: "books.vertical", action: onPicture)
                }
                .accessibilityIdentifier("watercolor-new")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "drop")
                .font(.system(size: 56))
                .foregroundStyle(WatercolorEra.ink)
                .accessibilityHidden(true)
            Text("No paintings yet")
                .font(.display(.title2))
            Text("Choose a photo or a library picture, and paint it in water.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("A Photo", action: onPhoto)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
                    .accessibilityIdentifier("watercolor-choose-photo")
                Button("The Library", action: onPicture)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("watercolor-choose-picture")
            }
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A painting on the shelf: its picture as it stands, and its name.
struct WatercolorCard: View {
    let shelf: WatercolorShelf
    let artwork: Artwork
    let onOpen: () -> Void
    @State private var picture: CGImage?
    @State private var asksToDelete = false

    private var progress: String {
        String(localized: "watercolor.progress", defaultValue: "Painted: \(artwork.paintedCount) of \(artwork.regionCount)",
               comment: "VoiceOver value and caption of a watercolor painting: areas painted so far; the arguments are the areas painted and all its areas")
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Rectangle().fill(.white.opacity(0.5))
                    if let picture {
                        Image(decorative: picture, scale: 1).resizable().scaledToFit()
                    }
                }
                .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 4))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                Text(artwork.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Group {
                    if artwork.isComplete {
                        Text("Finished").foregroundStyle(WatercolorEra.ink)
                    } else {
                        Text(progress).foregroundStyle(.secondary)
                    }
                }
                .font(.caption.monospacedDigit())
                .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(progress))
        .accessibilityIdentifier("watercolor-card")
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { asksToDelete = true }
        }
        .confirmationDialog(Text("Delete Painting"), isPresented: $asksToDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { shelf.delete(artwork.id) }
        }
        .task(id: artwork.thumbnailVersion) {
            picture = await shelf.thumbnail(of: artwork)
        }
    }
}

/// The library's pictures to paint in water, paintings then photographs.
struct WatercolorPicturePicker: View {
    let onPick: (Sample) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(Text("Paintings"), Sample.all(of: .painting))
                    section(Text("Photographs"), Sample.all(of: .photograph))
                }
                .padding(20)
            }
            .navigationTitle(Text("The Library"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: Text, _ samples: [Sample]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title.font(.display(.title3))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(samples) { sample in
                    Button { onPick(sample) } label: { WatercolorSampleTile(sample: sample) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: sample.title))
                        .accessibilityIdentifier("watercolor-library-picture")
                }
            }
        }
    }
}

private struct WatercolorSampleTile: View {
    let sample: Sample
    @State private var picture: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let picture {
                Image(decorative: picture, scale: 1).resizable().scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .task {
            guard let url = sample.url else { return }
            picture = await Background.run { ImageCodec.image(at: url, maxPixelSize: 300) }
        }
    }
}

/// The era's Settings: About's Year, whose wheel leaves the era.
struct WatercolorSettingsView: View {
    let leave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsClock = false

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    Button {
                        withAnimation { showsClock.toggle() }
                    } label: {
                        LabeledContent {
                            Text(verbatim: EraClock.text(of: EraYear.watercolor)).foregroundStyle(.tint)
                        } label: {
                            SwiftUI.Label {
                                Text("Year").foregroundStyle(Color.primary)
                            } icon: {
                                Image(systemName: "clock")
                            }
                        }
                    }
                    .accessibilityIdentifier("about-year")
                    if showsClock {
                        EraClock(year: EraYear.watercolor) { year in
                            guard year != EraYear.watercolor, EraYear.opensAnEra(year) else { return }
                            dismiss()
                            leave(year)
                        }
                        .accessibilityIdentifier("era-clock")
                    }
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
