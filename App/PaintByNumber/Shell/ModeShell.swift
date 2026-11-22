#if UNRELEASED
import CoreGraphics
import PaintCore
import PhotosUI
import Ravenna
import SwiftUI
import os

/// The frame every mode lives in (painting-company row 379; SideStore and Debug builds). A mode
/// behind the year wheel (Stained Glass, Watercolor, and The Frame, which is this and nothing
/// else) is a `ModeShell` around what is its own. The rules, with no exceptions:
///
/// 1. **A year.** The mode opens from its year on the wheel, and its Settings has About's Year
///    row, whose wheel leaves it (`ModeSettingsView`). Nothing else opens or leaves a mode.
/// 2. **A gallery** under the mode's name, a large navigation title, on the mode's backdrop. What
///    a card looks like, and the gallery empty, are the mode's.
/// 3. **Settings top left**, the gear (`<mode>-settings`).
/// 4. **New top right**, the + menu, with two ways in and only these: A Photo (the system photo
///    picker) and The Library (the app's pictures, `ModeLibraryPicker`). Every mode starts from
///    a picture: "Your photos, ___ by numbers".
/// 5. **One accent and the dark.** The mode tints every control with its one accent and is dark.
/// 6. **The painting screen** is pushed on the gallery: the system's back button, the painting's
///    name inline, and the same words while it opens or can't (`ModePaintingFrame`). Its canvas
///    and paints are the mode's.
///
/// And what every mode guarantees inside the frame, since a frame around something that isn't
/// paint by numbers is no use (Paul, November 21):
///
/// 7. **From the painter's picture.** Every painting starts from a picture (rule 4) and is made
///    from it: the regions and their paints come from that picture.
/// 8. **By numbers.** The picture is divided into numbered regions, each number one paint, shown
///    on the canvas until the region is done. The medium decides how a region gets done (glass
///    poured, a wash laid, a block printed), never whether it is numbered.
/// 9. **Always finishable.** Every painting can reach Finished: a painter doing what the numbers
///    say finishes it, no region can be left impossible, and Finished is the same moment in every
///    mode (the painting whole, the gallery's card saying so).
/// 10. **Played to the end before it ships.** A mode reaches a TestFlight or SideStore build only
///    after one painting has been painted from a photo to Finished end to end on a device or
///    simulator, its frames attached to the branch's report.
/// 11. **A Making Of shows the process, never the reveal** (Paul, November 22). A mode's Making Of
///    shows off its medium and how fully its simulation works (the water, the lead, the press),
///    never the finished painting of the painter's own picture: that is the joy the painter
///    uncovers along the way. Paint by Moonlight's own Making Of and Paint by Mosaic's are
///    settled and keep what they show.
///
/// What a mode supplies: its `ModeLook`, its gallery, its painting screen, and what a picked
/// picture becomes (`make`).
///
/// **How far a mode may go: Paint by Mosaic is the bar** (Paul, November 22). A mode may be as
/// different as Mosaic is, with a library of its own look, a book for making it for real, its own
/// doors and its own words, and still be in this frame; the frame widens, with optional parts a
/// mode opts into, until Mosaic fits in it. The frame constrains as well as stretches: where
/// Mosaic has something every mode should have, it becomes the frame and every mode follows it,
/// not a Mosaic exception. Until Mosaic is moved in, Paint by Mosaic is a copy of the app, not a
/// mode, and keeps its own.
struct ModeShell<Gallery: View, Route: Hashable, Destination: View>: View {
    let look: ModeLook
    @Binding var path: [Route]
    /// The wheel's year the painter left the mode for.
    let leave: (Int) -> Void
    /// What a picked picture becomes, while the shell shows it is working.
    let make: @MainActor (ModePicture) async -> Void
    let gallery: (ModeWaysIn) -> Gallery
    let destination: (Route) -> Destination

    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var choosingPicture = false
    @State private var showsSettings: Bool
    @State private var isWorking = false

    init(look: ModeLook, path: Binding<[Route]>, leave: @escaping (Int) -> Void, opensSettings: Bool = false,
         make: @escaping @MainActor (ModePicture) async -> Void,
         @ViewBuilder gallery: @escaping (ModeWaysIn) -> Gallery,
         @ViewBuilder destination: @escaping (Route) -> Destination) {
        self.look = look
        _path = path
        self.leave = leave
        self.make = make
        self.gallery = gallery
        self.destination = destination
        _showsSettings = State(initialValue: opensSettings)
    }

    private var waysIn: ModeWaysIn {
        ModeWaysIn(photo: { picking = true }, library: { choosingPicture = true })
    }

    var body: some View {
        NavigationStack(path: $path) {
            gallery(waysIn)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(look.backdrop.ignoresSafeArea())
                .navigationTitle(look.title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") { showsSettings = true }
                            .accessibilityIdentifier("\(look.id)-settings")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("A Photo", systemImage: "photo") { picking = true }
                            Button("The Library", systemImage: "books.vertical") { choosingPicture = true }
                        } label: {
                            SwiftUI.Label { look.newTitle } icon: { Image(systemName: "plus") }
                        }
                        .accessibilityIdentifier("\(look.id)-new")
                    }
                }
                .navigationDestination(for: Route.self) { destination($0) }
        }
        .overlay {
            if isWorking {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    if let working = look.working {
                        working.font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(28)
                .background(.regularMaterial, in: .rect(cornerRadius: 22))
            }
        }
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await take(item) }
        }
        .sheet(isPresented: $choosingPicture) {
            ModeLibraryPicker(id: look.id) { sample in
                choosingPicture = false
                Task { await take(sample) }
            }
        }
        .sheet(isPresented: $showsSettings) {
            ModeSettingsView(year: look.year, leave: leave)
        }
        .tint(look.accent)
        .preferredColorScheme(.dark)
    }

    private func take(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let photo = try await Background.run { try PhotoLoader.load(data: data, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            await make(ModePicture(photo: photo, sample: nil))
        } catch {
            Log.library.error("Couldn't load a photo for \(look.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func take(_ sample: Sample) async {
        guard let url = sample.url else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let photo = try await Background.run { try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            await make(ModePicture(photo: photo, sample: sample))
        } catch {
            Log.library.error("Couldn't load a library picture for \(look.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}

/// What is a mode's own in the frame: its year, its name, what New makes, its one accent and
/// its backdrop.
struct ModeLook {
    /// The year on the wheel that opens it.
    let year: Int
    let title: Text
    /// New's name: New Window, New Painting.
    let newTitle: Text
    let accent: Color
    let backdrop: Color
    /// What the shell says while a picked picture becomes a painting; nil for a spinner alone.
    var working: Text?
    /// The prefix of the frame's accessibility identifiers: `<id>-settings`, `<id>-new`,
    /// `<id>-library-picture`.
    let id: String
}

/// A picture picked for a new painting: the painter's photo, or one of the library's.
struct ModePicture {
    let photo: RGBAImage
    /// The library's picture it is, nil for the painter's own photo.
    let sample: Sample?

    var cgImage: CGImage? { PhotoLoader.cgImage(from: photo) }
}

/// The two ways in, for a gallery's own empty page to offer.
struct ModeWaysIn {
    let photo: () -> Void
    let library: () -> Void
}

/// A mode's Settings: About's Year, whose wheel leaves the mode.
struct ModeSettingsView: View {
    let year: Int
    let leave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.sounds) private var sounds = SettingsDefault.sounds
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
                            EraClock.Value(clockYear, home: year).foregroundStyle(.tint)
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
                        EraClock(year: year) { chosen in
                            guard chosen != year, EraYear.opensAnEra(chosen) else { return }
                            dismiss()
                            leave(chosen)
                        }
                        .reporting(to: clockYear)
                        .transformEnvironment(\.eraClockSound) { if !sounds { $0 = nil } }
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

/// The app's library, to start a painting from: the paintings, then the photographs.
struct ModeLibraryPicker: View {
    let id: String
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
                    Button { onPick(sample) } label: { ModeSampleTile(sample: sample) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: sample.title))
                        .accessibilityIdentifier("\(id)-library-picture")
                }
            }
        }
    }
}

private struct ModeSampleTile: View {
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

/// Where a painting stands as its screen opens.
enum ModeOpening {
    case opening
    case open
    /// The device can't draw the canvas.
    case unavailable
    case failed
    /// Written by a newer app: its files are left as they are.
    case needsNewerApp
}

/// A mode's painting screen as the frame has it: the painting's name inline under the system's
/// back button, and the same words while it opens or can't. The painting itself is the mode's.
struct ModePaintingFrame<Painting: View>: View {
    let title: String
    let opening: ModeOpening
    /// The words for a painting that can't be opened: Can't Open Window, Can't Open Painting.
    let cantOpen: Text
    var backdrop: Color?
    @ViewBuilder let painting: () -> Painting

    var body: some View {
        Group {
            switch opening {
            case .open:
                painting()
            case .opening:
                ProgressView()
            case .unavailable:
                CanvasUnavailableView()
            case .failed:
                ContentUnavailableView {
                    SwiftUI.Label { cantOpen } icon: { Image(systemName: "exclamationmark.triangle") }
                }
            case .needsNewerApp:
                ContentUnavailableView {
                    SwiftUI.Label("Needs a Newer Version", systemImage: "arrow.up.circle")
                } description: {
                    Text(verbatim: String(localized: "gallery.recovery.newer.untitled",
                                          defaultValue: "This painting was made with a newer version of Paint by Moonlight. Update the app to keep painting it.",
                                          comment: "Recovery screen text for an untitled painting made by a newer app version"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if let backdrop { backdrop.ignoresSafeArea() }
        }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
