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
        .preferredColorScheme(.dark)
    }

    /// The era's accent: an ultramarine wash, lifted to read on the slate.
    static let ink = Color(red: 0.55, green: 0.66, blue: 0.95)
    /// The slate desk the sheets lie on (`WatercolorRenderer.background`, linear, is the same).
    static let desk = Color(red: 0.396, green: 0.424, blue: 0.463)
    /// The sheet's paper, as the renderer draws it.
    static let paper = Color(red: 0.949, green: 0.933, blue: 0.894)
    /// Graphite on the paper: a sheet's title and year.
    static let pencil = Color(red: 0.44, green: 0.43, blue: 0.44)
    /// The paint box's enamel, and the white of its pans.
    static let tin = Color(red: 0.86, green: 0.85, blue: 0.82)
    static let well = Color(red: 0.97, green: 0.96, blue: 0.94)
    /// The pan in hand's number: the ultramarine itself, on the tin's light enamel.
    static let panInk = Color(red: 0.22, green: 0.33, blue: 0.62)

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

/// The paintings: a sheet each on the slate, newest first; none yet, a blank sheet waiting.
struct WatercolorGalleryView: View {
    let shelf: WatercolorShelf
    let onPhoto: () -> Void
    let onPicture: () -> Void
    let onSettings: () -> Void
    let onOpen: (UUID) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isEmpty: Bool { shelf.isLoaded && shelf.paintings.isEmpty }

    var body: some View {
        Group {
            if isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .compact ? 140 : 200), spacing: 28)], spacing: 30) {
                        ForEach(shelf.paintings) { artwork in
                            WatercolorCard(shelf: shelf, artwork: artwork, onOpen: { onOpen(artwork.id) })
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
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
            // Empty, the blank sheet's own two buttons are the way in.
            if !isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu("New Painting", systemImage: "plus") {
                        Button("A Photo", systemImage: "photo", action: onPhoto)
                        Button("The Library", systemImage: "books.vertical", action: onPicture)
                    }
                    .accessibilityIdentifier("watercolor-new")
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 32) {
            Text("No paintings yet")
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(WatercolorEra.pencil)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    DeckleEdge(seed: 5)
                        .fill(WatercolorEra.paper)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(maxWidth: 400)
                .rotationEffect(.degrees(-0.8))
                .padding(.horizontal, 8)
            HStack(spacing: 12) {
                Button("A Photo", action: onPhoto)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("watercolor-choose-photo")
                Button("The Library", action: onPicture)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("watercolor-choose-picture")
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A painting on the shelf: its picture on a sheet of its own, laid down a little askew, and
/// in pencil under it its name and how far it has come, or, finished, the year it was signed.
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

    private var count: String {
        String(localized: "watercolor.count", defaultValue: "\(artwork.paintedCount) of \(artwork.regionCount)",
               comment: "Written in pencil under a watercolor painting not yet finished, on its sheet in the gallery: the areas painted, and all its areas")
    }

    private var finished: String {
        String(localized: "Finished")
    }

    /// A tilt of its own for each painting, the same every time: up to 0.7° either way.
    private var tilt: Double { (Double(artwork.id.uuid.0) / 255 - 0.5) * 1.4 }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Rectangle().fill(WatercolorEra.paper)
                    if let picture {
                        Image(decorative: picture, scale: 1).resizable().scaledToFit()
                    }
                }
                .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: artwork.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: artwork.isComplete ? EraClock.text(of: EraYear.watercolor) : count)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .font(.system(.caption, design: .serif).italic())
                .foregroundStyle(WatercolorEra.pencil)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 9)
            .background {
                DeckleEdge(seed: Int(artwork.id.uuid.1))
                    .fill(WatercolorEra.paper)
                    .shadow(color: .black.opacity(0.32), radius: 7, y: 3)
            }
            .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: artwork.title))
        .accessibilityValue(Text(verbatim: artwork.isComplete ? finished : progress))
        .accessibilityAddTraits(.isButton)
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

/// A sheet of handmade paper: a rectangle whose edges wander in by up to a point or so, the same
/// for the same seed.
nonisolated struct DeckleEdge: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 3, depth: CGFloat = 1.2
        // The hash the renderer frays the painted sheet with (Watercolor.metal), here on doubles.
        func jitter(_ i: Int, _ side: Int) -> CGFloat {
            var px = Double(i) * 0.37 * 123.34 + Double(side) * 13.1 * 123.34, py = Double(seed) * 1.7 * 456.21
            px -= px.rounded(.down)
            py -= py.rounded(.down)
            let d = px * (px + 45.32) + py * (py + 45.32)
            px += d
            py += d
            let h = px * py
            return CGFloat(h - h.rounded(.down)) * depth
        }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        for side in 0..<4 {
            let a = corners[side], b = corners[(side + 1) % 4]
            let length = max(hypot(b.x - a.x, b.y - a.y), 1)
            let n = max(2, Int(length / step))
            // The edge's normal, turned in toward the middle (corners run clockwise on screen).
            let normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n), j = jitter(i, side)
                let p = CGPoint(x: a.x + (b.x - a.x) * t + normal.x * j, y: a.y + (b.y - a.y) * t + normal.y * j)
                if side == 0 && i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        path.closeSubpath()
        return path
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
    /// The year the Year row's wheel rests on (`EraClock.Reading`).
    @State private var clockYear = EraClock.Reading()

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    Button {
                        withAnimation { showsClock.toggle() }
                        // Closed without opening an era: the row reads its own year again.
                        clockYear.isOpen = showsClock
                        if !showsClock { clockYear.year = nil }
                    } label: {
                        LabeledContent {
                            EraClock.Value(clockYear, home: EraYear.watercolor).foregroundStyle(.tint)
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
                        .reporting(to: clockYear)
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
