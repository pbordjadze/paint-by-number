#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import Ravenna
import SwiftUI
import os

/// Woodblock, the era behind 1765 on the year wheel (painting-company row 375; SideStore and
/// Debug builds): your photos, printed by numbers. A mode in the frame every mode shares
/// (`ModeShell`): a print is the app's own template made with few paints
/// (`WoodblockShelf.template`), its blocks the key block's drawing and one block per numbered
/// paint (`WoodblockPlan`), carved, inked and printed on the bench (`WoodblockBenchView`). Dark,
/// a workshop by lamplight.
struct WoodblockEra: View {
    let leave: (Int) -> Void

    @State private var shelf = WoodblockShelf.shared
    @State private var path: [UUID] = []

    var body: some View {
        ModeShell(look: Self.look, path: $path, leave: leave, make: cut) { waysIn in
            WoodblockGalleryView(shelf: shelf, waysIn: waysIn, onOpen: { path.append($0) })
        } destination: { id in
            WoodblockPrintScreen(shelf: shelf, id: id)
        }
        .task {
            await shelf.load()
            #if DEBUG
            await WoodblockDemo.run(scenario: DemoMode.scenario, shelf: shelf, path: $path)
            #endif
        }
    }

    /// Woodblock in the frame every mode shares (`ModeShell`).
    static var look: ModeLook {
        ModeLook(year: EraYear.woodblock, title: Text("Woodblock"), newTitle: Text("New Print"), accent: lamp,
                 backdrop: bench, working: Text("Cutting the blocks…"), id: "woodblock")
    }

    /// The lamp's warm light, the era's accent.
    static let lamp = Color(red: 0.95, green: 0.72, blue: 0.42)
    /// The bench the canvas draws, for SwiftUI: `WoodblockMode.bench` is linear, a SwiftUI
    /// colour's components are encoded (read as they are, the bench showed black around it).
    static let bench: Color = {
        func encoded(_ c: Float) -> Double {
            Double(c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055)
        }
        let b = WoodblockMode.bench
        return Color(.displayP3, red: encoded(b.x), green: encoded(b.y), blue: encoded(b.z))
    }()

    /// Whether the launch asked for one of Woodblock's demo scenarios (`-demo woodblock-<name>`),
    /// which open the era whatever the clock says (Debug builds only).
    static var isDemoScenario: Bool {
        #if DEBUG
        return DemoMode.scenario?.hasPrefix("woodblock-") == true
        #else
        return false
        #endif
    }

    /// Cuts a picture's blocks and opens the print on the bench.
    private func cut(_ picked: ModePicture) async {
        do {
            let (template, settings) = try await WoodblockShelf.template(of: picked.photo)
            let artwork = try await shelf.create(template: template, settings: settings, photo: picked.photo,
                                                 title: picked.title ?? shelf.title(), sampleName: picked.sample?.id)
            path = [artwork.id]
        } catch {
            Log.library.error("Couldn't make a print: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The prints: a card each, newest first; none yet, a way to make the first.
struct WoodblockGalleryView: View {
    let shelf: WoodblockShelf
    let waysIn: ModeWaysIn
    let onOpen: (UUID) -> Void

    var body: some View {
        if shelf.isLoaded && shelf.prints.isEmpty {
            empty
        } else {
            ModeGallery(items: shelf.prints.map(\.shelfItem), actions: actions, deleteTitle: Text("Delete Print")) { item in
                if let artwork = shelf.print(item.id) {
                    WoodblockCard(shelf: shelf, artwork: artwork, onOpen: { onOpen(artwork.id) })
                }
            }
        }
    }

    /// The frame's card menu, in Woodblock's words for it: shared as the print stands (its
    /// picture on the shelf), printed as its numbered sheet.
    private var actions: ModeCardActions {
        let shelf = shelf
        return ModeCardActions(
            rename: { shelf.rename($0, to: $1) },
            delete: { shelf.delete($0) },
            picture: { id in await shelf.picture(of: id) },
            print: { id in
                guard let artwork = shelf.print(id) else { throw CocoaError(.fileNoSuchFile) }
                return try await PrintPreviewRequest.saved(store: shelf.store, artwork: artwork)
            })
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
            Button("Choose a Photo", action: waysIn.photo)
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
        .task(id: artwork.thumbnailVersion) {
            picture = await shelf.thumbnail(of: artwork)
        }
    }
}

/// A print opened on the bench, in the frame's painting screen (`ModePaintingFrame`): read off
/// the main actor, then the bench. A print written by a newer app keeps its files as they are.
struct WoodblockPrintScreen: View {
    let shelf: WoodblockShelf
    let id: UUID
    @State private var model: WoodblockBenchModel?
    @State private var failed = false
    @State private var unavailable = false
    @State private var needsNewerApp = false

    private var opening: ModeOpening {
        if model != nil { return .open }
        if unavailable { return .unavailable }
        if needsNewerApp { return .needsNewerApp }
        return failed ? .failed : .opening
    }

    var body: some View {
        ModePaintingFrame(title: shelf.print(id)?.title ?? "", opening: opening, cantOpen: Text("Can’t Open Print"),
                          backdrop: WoodblockEra.bench) {
            if let model {
                WoodblockBenchView(model: model, title: shelf.print(id)?.title ?? "")
            }
        }
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
                let model = WoodblockBenchModel(id: id, plan: plan, bench: bench, field: made.1, mode: made.0)
                model.onChange = { [shelf] bench in shelf.enqueue(bench, of: id, plan: plan) }
                #if DEBUG
                WoodblockDemo.prepare(model)
                #endif
                self.model = model
            } catch WoodblockBench.CodingError.newerVersion {
                needsNewerApp = true
            } catch {
                Log.library.error("Couldn't open print \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                failed = true
            }
        }
    }
}
#endif
