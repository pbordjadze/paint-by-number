#if UNRELEASED
import CoreGraphics
import PaintCore
import Ravenna
import SwiftUI
import os

/// The Cave, the era behind 15,000 BC on the year wheel (painting-company row 371; SideStore and
/// Debug builds), in the frame every mode shares (`ModeShell`, row 379). Its gallery is the
/// cave's paintings, each a bay of rock lit by a torch (`CavePicture`); empty, it is the cave's
/// mouth itself, alive, with the lump of charcoal on the bare rock that draws the first. A picked
/// picture is drawn on the rock as an animal, or as a stick figure posed as its person if it is
/// anything else (`CaveVision`, `CavePlan`), its areas numbered by dots of their pigment; the
/// painting screen is its bay alone, deep in the dark (`CaveScene.isSingle`), blown with pigment
/// and finished with the painter's hand.
struct CaveEra: View {
    let leave: (Int) -> Void

    /// The year on the wheel that opens the cave: Lascaux's paintings are about 17,000 years old.
    static let year = -15000

    @State private var shelf = CaveShelf.shared
    @State private var path: [UUID] = []
    @State private var isReady = false

    var body: some View {
        ModeShell(look: Self.look, path: $path, leave: { year in
            // The next visit starts at the mouth again.
            UserDefaults.standard.removeObject(forKey: CaveScene.cameraKey)
            leave(year)
        }, make: draw) { waysIn in
            CaveGalleryView(shelf: shelf, isReady: isReady, waysIn: waysIn, onOpen: { path.append($0) })
        } destination: { id in
            CavePaintingScreen(shelf: shelf, id: id)
        }
        .task {
            await shelf.load()
            #if DEBUG
            await CaveDemo.stock(shelf)
            CaveDemo.open(shelf, path: $path)
            #endif
            isReady = true
        }
    }

    /// The Cave in the frame every mode shares (`ModeShell`): red ochre on the dark of the rock.
    static var look: ModeLook {
        ModeLook(year: year, title: Text("The Cave"), newTitle: Text("New Painting"), accent: ochre,
                 backdrop: rock, working: Text("Drawing on the rock…"), id: "cave")
    }

    /// The era's accent: red ochre, lifted to read on the dark.
    static let ochre = Color(red: 0.86, green: 0.45, blue: 0.30)
    /// The rock in the dark, behind the gallery.
    static let rock = Color(red: 0.075, green: 0.062, blue: 0.055)

    /// Whether the launch asked for one of the cave's demo scenarios (`-demo cave-<name>`), which
    /// open the era whatever the clock says (Debug builds only).
    static var isDemoScenario: Bool {
        #if DEBUG
        return DemoMode.scenario?.hasPrefix("cave-") == true
        #else
        return false
        #endif
    }

    /// The picked picture drawn on the rock: its subject found, the drawing made, kept and opened.
    private func draw(_ picked: ModePicture) async {
        guard let image = picked.cgImage else { return }
        let photo = picked.photo
        let found = await CaveVision.look(at: image)
        let plan = await Background.run {
            CavePlan.make(photo: photo, subject: found.subject, kind: found.isAnimal ? .animal : .figure, pose: found.pose)
        }
        do {
            let id = try await shelf.add(plan, title: picked.sample?.title ?? shelf.title())
            path = [id]
        } catch {
            Log.library.error("Couldn't draw a picture on the cave wall: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The cave's paintings, newest first, each its bay lit by a torch; none yet, the cave's mouth.
struct CaveGalleryView: View {
    let shelf: CaveShelf
    let isReady: Bool
    let waysIn: ModeWaysIn
    let onOpen: (UUID) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isReady && shelf.paintings.isEmpty {
            // The cave's mouth, alive: the daylight behind, the fossils in the rock, and bare rock
            // with its charcoal, whose touch draws the first painting.
            CaveWallSurface(paintings: [], shelf: shelf, single: false, reduceMotion: reduceMotion, onChoosePhoto: waysIn.photo)
                .ignoresSafeArea(edges: .bottom)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .compact ? 140 : 190), spacing: 22)], spacing: 26) {
                    ForEach(shelf.paintings.reversed(), id: \.id) { painting in
                        CaveCard(shelf: shelf, painting: painting, onOpen: { onOpen(painting.id) })
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
    }
}

/// A painting in the gallery: its bay as the torch finds it, its name, and how far it is blown.
struct CaveCard: View {
    let shelf: CaveShelf
    let painting: CaveScene.Painting
    let onOpen: () -> Void
    @State private var picture: CGImage?
    @State private var asksToDelete = false

    private var done: Int { painting.progress.done.filter { $0 }.count }
    private var count: String { "\(done.formatted())/\(painting.progress.done.count.formatted())" }
    private var progress: String {
        String(localized: "cave.card.progress", defaultValue: "Areas blown: \(done) of \(painting.progress.done.count)",
               comment: "VoiceOver value of a cave painting's card in the gallery: the areas blown with pigment of all its areas")
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    CaveEra.rock
                    if let picture {
                        Image(decorative: picture, scale: 1).resizable().scaledToFill()
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(0.62, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: painting.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: painting.isComplete ? CaveFossils.year(-CaveEra.year) : count)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                        .foregroundStyle(painting.isComplete ? CaveEra.ochre : .secondary)
                }
                .font(.display(.caption, weight: .regular))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: painting.title))
        .accessibilityValue(Text(verbatim: painting.isComplete ? String(localized: "Finished") : progress))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("cave-card")
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { asksToDelete = true }
        }
        .confirmationDialog(Text("Delete Painting"), isPresented: $asksToDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { shelf.delete(painting.id) }
        }
        .task(id: "\(painting.id)-\(done)-\(painting.progress.hand != nil)") {
            picture = await shelf.picture(of: painting.id)
        }
    }
}

/// A painting's screen in the frame: its bay alone in the dark, blown and finished there.
struct CavePaintingScreen: View {
    let shelf: CaveShelf
    let id: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let painting = shelf.painting(id)
        ModePaintingFrame(title: painting?.title ?? "", opening: painting == nil ? .failed : .open,
                          cantOpen: Text("Can’t Open Painting"), backdrop: .black) {
            if let painting {
                CaveWallSurface(paintings: [painting], shelf: shelf, single: true, reduceMotion: reduceMotion, onChoosePhoto: {})
                    .ignoresSafeArea(edges: .bottom)
                    // A hand of four or five fingers is laid on the rock, not taken by the system.
                    .defersSystemGestures(on: .all)
            }
        }
    }
}

/// The wall as a SwiftUI view (PaintCore's `CaveWall` is its geometry): its `CaveWallView`, given the paintings as the shelf has them.
struct CaveWallSurface: UIViewRepresentable {
    let paintings: [CaveScene.Painting]
    let shelf: CaveShelf
    let single: Bool
    let reduceMotion: Bool
    let onChoosePhoto: () -> Void

    func makeUIView(context: Context) -> CaveWallView {
        let scene = CaveScene(paintings: paintings, sound: CaveSound.fromSettings(), single: single)
        let view = CaveWallView(scene: scene)
        // The painting screen's wall, or the empty gallery's mouth.
        view.accessibilityIdentifier = single ? "cave-painting" : "cave-wall"
        scene.onSave = { [shelf] id, progress, pigment in shelf.save(id, progress: progress, pigment: pigment) }
        view.flush = { [shelf] in await shelf.flush() }
        update(scene)
        #if DEBUG
        CaveDemo.play(on: view)
        #endif
        return view
    }

    func updateUIView(_ view: CaveWallView, context: Context) {
        update(view.scene)
        view.scene.update(paintings)
    }

    private func update(_ scene: CaveScene) {
        scene.reduceMotion = reduceMotion
        scene.onChoosePhoto = onChoosePhoto
    }
}
#endif
