#if UNRELEASED
import CoreGraphics
import PaintCore
import Ravenna
import SwiftUI
import os

/// Stained Glass, the era behind 1248 on the year wheel (painting-company row 366; SideStore and
/// Debug builds). A mode of the app's own, not a copy of it: a window is a PaintCore `Template`
/// cut as the photo suggests (`GlassWindow.Leading.suggested`), each piece numbered for its
/// glass, kept by an `ArtworkStore` of its own (`GlassShelf`), led in and glazed by number by the
/// painter (`GlassGlazeView`), in the frame every mode shares (`ModeShell`): its gallery of
/// windows, New Window (a photo or a library picture) and Settings, whose Year wheel leaves it.
/// Dark, as every mode: glass glows in a dark room.
struct GlassEra: View {
    let leave: (Int) -> Void

    @State private var shelf = GlassShelf.shared
    @State private var path: [GlassRoute] = []

    var body: some View {
        ModeShell(look: Self.look, path: $path, leave: leave, make: make) { waysIn in
            GlassGalleryView(shelf: shelf, onNew: waysIn.photo, onOpen: { path.append(.window($0)) })
        } destination: { route in
            switch route {
            case .window(let id):
                GlassWindowScreen(shelf: shelf, id: id)
            }
        }
        #if DEBUG
        .overlay {
            if let count = GlassRealPanes.count { GlassRealPanes(count: count) }
        }
        #endif
        .task {
            await shelf.load()
            #if DEBUG
            await GlassDemo.run(scenario: DemoMode.scenario, shelf: shelf, path: $path)
            #endif
        }
    }

    /// Stained Glass in the frame every mode shares (`ModeShell`).
    static var look: ModeLook {
        ModeLook(year: EraYear.stainedGlass, title: Text("Stained Glass"), newTitle: Text("New Window"), accent: gold,
                 backdrop: GlassPicture.color(GlassPicture.nave, space: .sRGB), id: "glass")
    }

    static let gold = Color(red: 0.96, green: 0.78, blue: 0.36)

    /// Whether the launch asked for one of Stained Glass's demo scenarios (`-demo glass-<name>`),
    /// which open the era whatever the clock says (Debug builds only).
    static var isDemoScenario: Bool {
        #if DEBUG
        return DemoMode.scenario?.hasPrefix("glass-") == true
        #else
        return false
        #endif
    }

    /// A photo or a library picture, cut into the window its photo suggests and opened, every
    /// piece numbered and waiting for the painter's lead (Paul, November 22, 2026: the cells are
    /// chosen and drawn already).
    private func make(_ picked: ModePicture) async {
        let photo = picked.photo
        let size = GenerationSettings().workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
        do {
            let window = try await Background.run {
                try GlassWindow.Leading.suggested(photo: photo, width: size.width, height: size.height,
                                                  colorSpace: photo.colorSpace).window()
            }
            let artwork = try await shelf.create(window, photo: photo, title: shelf.title())
            path = [.window(artwork.id)]
        } catch {
            Log.library.error("Couldn't make a window: \(String(describing: error), privacy: .public)")
        }
    }
}

enum GlassRoute: Hashable {
    case window(UUID)
}

/// The windows: a card each, newest first; none yet, a way to make the first.
struct GlassGalleryView: View {
    let shelf: GlassShelf
    let onNew: () -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        Group {
            if shelf.isLoaded && shelf.windows.isEmpty {
                empty
            } else {
                ScrollView {
                    // One container, so the cards' glass is sampled together and never melts
                    // card into card.
                    GlassEffectContainer(spacing: 0) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 18)], spacing: 22) {
                            ForEach(shelf.windows) { artwork in
                                GlassCard(shelf: shelf, artwork: artwork, onOpen: { onOpen(artwork.id) })
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 56))
                .foregroundStyle(GlassEra.gold)
                .frame(width: 112, height: 112)
                .glassEffect(.regular.tint(GlassEra.gold.opacity(0.12)), in: .circle)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text("No windows yet")
                .font(.display(.title2))
            Text("Choose a photo, lead its numbered pieces, and pour each its glass.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Choose a Photo", action: onNew)
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .padding(.top, 6)
                .accessibilityIdentifier("glass-choose-photo")
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A window on the shelf: its picture, lit as far as it is glazed, and its name.
struct GlassCard: View {
    let shelf: GlassShelf
    let artwork: Artwork
    let onOpen: () -> Void
    @State private var picture: CGImage?
    @State private var asksToDelete = false

    private var progress: String {
        String(localized: "glass.progress", defaultValue: "Glazed: \(artwork.paintedCount) of \(artwork.regionCount)",
               comment: "VoiceOver value of a stained glass window: pieces glazed of all its pieces")
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Rectangle().fill(.black.opacity(0.4))
                    if let picture {
                        Image(decorative: picture, scale: 1).resizable().scaledToFit()
                    }
                }
                .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 6))
                // Set in a frame of real Liquid Glass, warmer as the window is glazed.
                .padding(7)
                .glassEffect(.regular.tint(GlassEra.gold.opacity(artwork.isComplete ? 0.22 : 0.06)).interactive(),
                             in: .rect(cornerRadius: 13))
                .shadow(color: GlassEra.gold.opacity(artwork.isComplete ? 0.35 : 0.12), radius: 14)
                Text(artwork.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Group {
                    if artwork.isComplete {
                        Text("Finished").foregroundStyle(GlassEra.gold)
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
        .accessibilityIdentifier("glass-card")
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { asksToDelete = true }
        }
        .confirmationDialog(Text("Delete Window"), isPresented: $asksToDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { shelf.delete(artwork.id) }
        }
        .task(id: artwork.thumbnailVersion) {
            picture = await shelf.thumbnail(of: artwork)
        }
    }
}

/// A window opened to glaze: read off the main actor, then the glazing screen.
struct GlassWindowScreen: View {
    let shelf: GlassShelf
    let id: UUID
    @State private var model: GlassGlazeModel?
    @State private var failed = false
    /// The device can't draw the canvas.
    @State private var unavailable = false

    private var opening: ModeOpening {
        if model != nil { return .open }
        if unavailable { return .unavailable }
        return failed ? .failed : .opening
    }

    var body: some View {
        ModePaintingFrame(title: shelf.window(id)?.title ?? "", opening: opening, cantOpen: Text("Can’t Open Window")) {
            if let model {
                GlassGlazeView(model: model, title: shelf.window(id)?.title ?? "")
            }
        }
        .task(id: id) {
            guard model == nil, let artwork = shelf.window(id) else { return }
            do {
                let opened = try await shelf.open(artwork)
                guard let context = await RenderContext.ready(),
                      let mode = await Background.run({
                          GlassMode(template: opened.template, texture: opened.texture, offered: opened.offered,
                                    photo: opened.photo, context: context)
                      })
                else {
                    unavailable = true
                    return
                }
                let made = GlassGlazeModel(id: id, template: opened.template, glazing: opened.glazing, offered: opened.offered,
                                           mode: mode)
                made.onChange = { [shelf] glazing in
                    shelf.enqueue(glazing, of: id, template: opened.template, offered: opened.offered, texture: opened.texture,
                                  mode: mode)
                }
                #if DEBUG
                GlassDemo.prepare(made)
                #endif
                model = made
                #if DEBUG
                GlassDemo.shown(made)
                #endif
            } catch {
                failed = true
            }
        }
    }
}
#endif
