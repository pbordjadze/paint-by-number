#if UNRELEASED
import CoreGraphics
import PaintCore
import PhotosUI
import Ravenna
import SwiftUI
import os

/// The Cave, the era behind 15,000 BC on the year wheel (painting-company row 371; SideStore and
/// Debug builds). No app on screen at all: the whole screen is a rock wall in the dark, lit by a
/// torch (`CaveWallView`, `CaveScene`). The paintings are the cave itself, one long wall walked
/// with the torch (`CaveShelf`); the lump of charcoal on bare rock chooses the next photo, which
/// is drawn on the rock as an animal, or as a stick figure if it is anything else (`CaveVision`,
/// `CavePlan`). The way out is the one thing of the app left: a Liquid Glass Settings button,
/// whose Year wheel leaves the cave as every era's does (`CaveSettingsView`).
struct CaveEra: View {
    let leave: (Int) -> Void

    /// The year on the wheel that opens the cave: Lascaux's paintings are about 17,000 years old.
    static let year = -15000

    @State private var shelf = CaveShelf.shared
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var isDrawing = false
    @State private var isReady = false
    @State private var showsSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if isReady {
                CaveWallSurface(paintings: shelf.paintings, shelf: shelf, reduceMotion: reduceMotion,
                                onChoosePhoto: { if !isDrawing { picking = true } })
                    .ignoresSafeArea()
            }
            Button("Settings", systemImage: "gearshape") { showsSettings = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(16)
                .accessibilityIdentifier("cave-settings")
        }
        .sheet(isPresented: $showsSettings) {
            CaveSettingsView(leave: { year in
                // The next visit starts at the mouth again.
                UserDefaults.standard.removeObject(forKey: CaveScene.cameraKey)
                leave(year)
            })
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // A hand of four or five fingers is laid on the rock, not taken by the system.
        .defersSystemGestures(on: .all)
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await draw(item) }
        }
        .task {
            await shelf.load()
            #if DEBUG
            await CaveDemo.stock(shelf)
            #endif
            isReady = true
        }
        .preferredColorScheme(.dark)
    }

    /// Whether the launch asked for one of the cave's demo scenarios (`-demo cave-<name>`), which
    /// open the era whatever the clock says (Debug builds only).
    static var isDemoScenario: Bool {
        #if DEBUG
        return DemoMode.scenario?.hasPrefix("cave-") == true
        #else
        return false
        #endif
    }

    /// The photo drawn on the rock: its subject found, the drawing made, and kept as the next
    /// painting on the wall.
    private func draw(_ item: PhotosPickerItem) async {
        isDrawing = true
        defer { isDrawing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let photo = try await Background.run { try PhotoLoader.load(data: data, maxPixelSize: 1600) }
            guard let image = PhotoLoader.cgImage(from: photo) else { return }
            let found = await CaveVision.look(at: image)
            let plan = await Background.run {
                CavePlan.make(photo: photo, subject: found.subject, kind: found.isAnimal ? .animal : .figure)
            }
            try await shelf.add(plan)
        } catch {
            Log.library.error("Couldn't draw a photo on the cave wall: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The wall as a SwiftUI view (PaintCore's `CaveWall` is its geometry): its `CaveWallView`, given the paintings as the shelf has them.
struct CaveWallSurface: UIViewRepresentable {
    let paintings: [CaveScene.Painting]
    let shelf: CaveShelf
    let reduceMotion: Bool
    let onChoosePhoto: () -> Void

    func makeUIView(context: Context) -> CaveWallView {
        let scene = CaveScene(paintings: paintings, sound: CaveSound.fromSettings())
        let view = CaveWallView(scene: scene)
        scene.onSave = { [shelf] id, progress, pigment in shelf.save(id, progress: progress, pigment: pigment) }
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
/// The cave's Settings: About's Year, whose wheel leaves the cave for the present or another era.
struct CaveSettingsView: View {
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
                            Text(verbatim: CaveFossils.year(-CaveEra.year)).foregroundStyle(.tint)
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
                        EraClock(year: CaveEra.year) { year in
                            guard EraYear.returnsToThePresent(year) || EraYear.opensByzantium(year) || EraYear.opensStainedGlass(year) else { return }
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
