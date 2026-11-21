#if UNRELEASED
import CoreGraphics
import PaintCore
import PhotosUI
import Ravenna
import SwiftUI
import os

/// Woodblock, the era behind 1765 on the year wheel (painting-company row 375; SideStore and
/// Debug builds): your photos, printed by numbers. A mode of the app's own: a print is the app's
/// own template made with few paints (`WoodblockShelf.template`), its blocks the key block's
/// drawing and one block per numbered paint (`WoodblockPlan`), carved, inked and printed on the
/// bench (`WoodblockBenchView`). The era is its gallery of prints, New Print (a photo or a
/// library picture) and Settings, whose Year wheel leaves it. Dark only: a workshop by lamplight.
struct WoodblockEra: View {
    let leave: (Int) -> Void

    @State private var shelf = WoodblockShelf.shared
    @State private var path: [UUID] = []
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var showsSettings = false
    @State private var showsLibrary = false
    @State private var isCutting = false

    var body: some View {
        NavigationStack(path: $path) {
            WoodblockGalleryView(shelf: shelf, onNew: { picking = true }, onLibrary: { showsLibrary = true },
                                 onSettings: { showsSettings = true }, onOpen: { path.append($0) })
                .navigationDestination(for: UUID.self) { id in
                    WoodblockPrintScreen(shelf: shelf, id: id)
                }
        }
        .overlay {
            if isCutting {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Cutting the blocks…")
                        .font(.display(.body))
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .glassEffect(in: .rect(cornerRadius: 22))
            }
        }
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await load(item) }
        }
        .sheet(isPresented: $showsSettings) {
            WoodblockSettingsView(leave: leave)
        }
        .sheet(isPresented: $showsLibrary) {
            GlassLibraryView { sample in
                showsLibrary = false
                Task { await load(sample) }
            }
        }
        .task {
            await shelf.load()
            #if DEBUG
            await WoodblockDemo.run(scenario: DemoMode.scenario, shelf: shelf, path: $path)
            #endif
        }
        .tint(WoodblockEra.lamp)
        .preferredColorScheme(.dark)
    }

    /// The lamp's warm light, the era's tint.
    static let lamp = Color(red: 0.95, green: 0.72, blue: 0.42)
    static let bench = Color(.displayP3, red: Double(WoodblockMode.bench.x), green: Double(WoodblockMode.bench.y),
                             blue: Double(WoodblockMode.bench.z))

    /// Whether the launch asked for one of Woodblock's demo scenarios (`-demo woodblock-<name>`),
    /// which open the era whatever the clock says (Debug builds only).
    static var isDemoScenario: Bool {
        #if DEBUG
        return DemoMode.scenario?.hasPrefix("woodblock-") == true
        #else
        return false
        #endif
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let photo = try await Background.run { try PhotoLoader.load(data: data, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            await start(photo, title: shelf.title(), sampleName: nil)
        } catch {
            Log.library.error("Couldn't load a photo for a print: \(String(describing: error), privacy: .public)")
        }
    }

    private func load(_ sample: Sample) async {
        guard let url = sample.url else { return }
        do {
            let photo = try await Background.run {
                try PhotoLoader.load(data: Data(contentsOf: url), maxPixelSize: ArtworkStore.sourceMaxPixelSize)
            }
            await start(photo, title: sample.title, sampleName: sample.id)
        } catch {
            Log.library.error("Couldn't load a library picture for a print: \(String(describing: error), privacy: .public)")
        }
    }

    /// Cuts a photo's blocks and opens the print on the bench.
    private func start(_ photo: RGBAImage, title: String, sampleName: String?) async {
        isCutting = true
        defer { isCutting = false }
        do {
            let (template, settings) = try await WoodblockShelf.template(of: photo)
            let artwork = try await shelf.create(template: template, settings: settings, photo: photo, title: title,
                                                 sampleName: sampleName)
            path = [artwork.id]
        } catch {
            Log.library.error("Couldn't make a print: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The prints: a card each, newest first; none yet, a way to make the first.
struct WoodblockGalleryView: View {
    let shelf: WoodblockShelf
    let onNew: () -> Void
    let onLibrary: () -> Void
    let onSettings: () -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        Group {
            if shelf.isLoaded && shelf.prints.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 18)], spacing: 22) {
                        ForEach(shelf.prints) { artwork in
                            WoodblockCard(shelf: shelf, artwork: artwork, onOpen: { onOpen(artwork.id) })
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(WoodblockEra.bench.ignoresSafeArea())
        .navigationTitle(Text("Woodblock"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape", action: onSettings)
                    .accessibilityIdentifier("woodblock-settings")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("New Print", systemImage: "plus") {
                    Button("A Photo", systemImage: "photo", action: onNew)
                    Button("The Library", systemImage: "books.vertical", action: onLibrary)
                }
                .accessibilityIdentifier("woodblock-new")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 56))
                .foregroundStyle(WoodblockEra.lamp)
                .accessibilityHidden(true)
            Text("No prints yet")
                .font(.display(.title2))
            Text("Choose a photo: carve its blocks, then print them by number.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Choose a Photo", action: onNew)
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .padding(.top, 6)
                .accessibilityIdentifier("woodblock-choose-photo")
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A print on the shelf: as far as it is printed, on its paper, and its name.
struct WoodblockCard: View {
    let shelf: WoodblockShelf
    let artwork: Artwork
    let onOpen: () -> Void
    @State private var picture: CGImage?
    @State private var asksToDelete = false

    private var share: Double { Double(artwork.paintedCount) / Double(max(1, artwork.regionCount)) }

    private var progress: String {
        artwork.isComplete
            ? String(localized: "Finished")
            : String(localized: "woodblock.progress", defaultValue: "Printed: \(share.formatted(.percent.precision(.fractionLength(0))))",
                     comment: "A woodblock print's progress on its card and to VoiceOver: the share of its blocks printed, as a percentage")
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Rectangle().fill(Color(red: 0.95, green: 0.93, blue: 0.875))
                    if let picture {
                        Image(decorative: picture, scale: 1).resizable().scaledToFit().padding(8)
                    }
                }
                .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                Text(artwork.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(progress)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(artwork.isComplete ? WoodblockEra.lamp : .secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(progress))
        .accessibilityIdentifier("woodblock-card")
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { asksToDelete = true }
        }
        .confirmationDialog(Text("Delete Print"), isPresented: $asksToDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { shelf.delete(artwork.id) }
        }
        .task(id: artwork.thumbnailVersion) {
            picture = await shelf.thumbnail(of: artwork)
        }
    }
}

/// A print opened on the bench: read off the main actor, then the bench.
struct WoodblockPrintScreen: View {
    let shelf: WoodblockShelf
    let id: UUID
    @State private var model: WoodblockBenchModel?
    @State private var failed = false
    @State private var unavailable = false

    var body: some View {
        Group {
            if let model {
                WoodblockBenchView(model: model, title: shelf.print(id)?.title ?? "")
            } else if unavailable {
                CanvasUnavailableView()
            } else if failed {
                ContentUnavailableView("Can’t Open Print", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: shelf.print(id)?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            guard model == nil, let artwork = shelf.print(id) else { return }
            do {
                let opened = try await shelf.open(artwork)
                let plan = opened.plan, bench = opened.bench
                guard let context = await RenderContext.ready(),
                      let made = await Background.run({ () -> (WoodblockMode, WoodblockField)? in
                          let key = WoodblockField(plan: plan, block: 0)
                          guard let mode = WoodblockMode(plan: plan, key: key, context: context) else { return nil }
                          let field = WoodblockBenchModel.prepare(plan: plan, block: bench.block, mode: mode)
                          return (mode, field)
                      })
                else {
                    unavailable = true
                    return
                }
                let bench0 = bench
                let model = WoodblockBenchModel(id: id, plan: plan, bench: bench0, field: made.1, mode: made.0)
                model.onChange = { [shelf] bench in shelf.enqueue(bench, of: id, plan: plan) }
                #if DEBUG
                WoodblockDemo.prepare(model)
                #endif
                self.model = model
            } catch {
                failed = true
            }
        }
    }
}

/// The era's Settings: About's Year, whose wheel leaves the era.
struct WoodblockSettingsView: View {
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
                            Text(verbatim: EraClock.text(of: EraYear.woodblock)).foregroundStyle(.tint)
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
                        EraClock(year: EraYear.woodblock) { year in
                            guard year != EraYear.woodblock, EraYear.opensAnEra(year) else { return }
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
