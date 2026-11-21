#if UNRELEASED
import PaintCore
import SwiftUI
import UIKit
import os

/// A watercolor painting opened: read and made ready off the main actor (`WatercolorShelf.open`:
/// the sheet, its snapshot, the pencil and numbers), then painted (`WatercolorPaintView`).
struct WatercolorPaintScreen: View {
    let shelf: WatercolorShelf
    let id: UUID
    @State private var opened: (painting: WatercolorPainting, renderer: WatercolorRenderer)?
    @State private var failed = false

    var body: some View {
        Group {
            if let opened {
                WatercolorPaintView(shelf: shelf, painting: opened.painting, renderer: opened.renderer)
            } else if failed {
                ContentUnavailableView("Can’t Open Painting", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .background(WatercolorEra.desk.ignoresSafeArea())
        .navigationTitle(Text(verbatim: shelf.painting(id)?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            guard opened == nil, let artwork = shelf.painting(id) else { return }
            do {
                let read = try await shelf.open(artwork)
                let painting = WatercolorPainting(id: id, template: read.template, sim: read.sim.value, log: read.log)
                guard let renderer = WatercolorRenderer(painting: painting, assets: read.assets) else {
                    failed = true
                    return
                }
                #if DEBUG
                WatercolorDemo.prepare(painting)
                #endif
                opened = (painting, renderer)
            } catch {
                Log.library.error("Couldn't open watercolor \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                failed = true
            }
        }
    }
}

/// The sheet and the paints: a tap lays a wash of the paint in hand where it lands, or water.
struct WatercolorPaintView: View {
    let shelf: WatercolorShelf
    let painting: WatercolorPainting
    let renderer: WatercolorRenderer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 0) {
            WatercolorCanvas(renderer: renderer) { point in
                if painting.tap(at: point) != nil { taps += 1 }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Watercolor sheet"))
            .accessibilityValue(Text(progress))
            .accessibilityAction(named: Text("Lay the Next Wash")) {
                if let point = painting.nextArea(), painting.tap(at: point) != nil { taps += 1 }
            }
            .accessibilityIdentifier("watercolor-sheet")
            .ignoresSafeArea(edges: .horizontal)
            WatercolorPaletteBar(painting: painting)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: taps)
        .onAppear { painting.settlesAtOnce = reduceMotion }
        .onChange(of: reduceMotion) { _, reduce in painting.settlesAtOnce = reduce }
        .onChange(of: taps) { _, _ in
            if painting.unsavedTaps >= 12 { save(withPicture: false) }
        }
        .onChange(of: scenePhase) { _, phase in
            // The picture is drawn on the way out (inactive): in the background the GPU is refused.
            switch phase {
            case .inactive: save(withPicture: true)
            case .background:
                save(withPicture: false)
                BackgroundSaving.shared.hold { [shelf, id = painting.id] in await shelf.saved(id) }
            default: break
            }
        }
        .onDisappear { save(withPicture: true) }
    }

    private var progress: String {
        String(localized: "watercolor.progress", defaultValue: "Painted: \(painting.laidCount) of \(painting.regionCount)",
               comment: "VoiceOver value and caption of a watercolor painting: areas painted so far; the arguments are the areas painted and all its areas")
    }

    /// Saves what changed: the log and sheet after taps, and the shelf's picture when asked and
    /// the sheet has changed since the last. The save under way, nil when there was nothing to save.
    @discardableResult
    private func save(withPicture: Bool) -> Task<Void, Never>? {
        let drawsPicture = withPicture && painting.pictureIsStale
        guard painting.unsavedTaps > 0 || drawsPicture else { return nil }
        let picture = drawsPicture ? renderer.picture(maxPixelSize: ArtworkStore.thumbnailMaxPixelSize) : nil
        if picture != nil { painting.pictureIsStale = false }
        let saved = painting.saving()
        return shelf.enqueue(id: painting.id, log: saved.log, snapshot: saved.snapshot, painted: saved.laid, picture: picture)
    }
}

/// The paint box: a pan of each paint, its number on it; the one in hand raised, a paint whose
/// areas are all painted marked done. Finished, the box gives way to a word.
struct WatercolorPaletteBar: View {
    let painting: WatercolorPainting

    var body: some View {
        Group {
            if painting.isComplete {
                Text("Finished")
                    .font(.display(.title3))
                    .foregroundStyle(WatercolorEra.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(painting.template.palette.indices, id: \.self) { i in
                                pan(i).id(i)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: painting.selected) { _, selected in
                        guard let selected else { return }
                        withAnimation { reader.scrollTo(selected, anchor: .center) }
                    }
                }
            }
        }
        .background(.bar)
    }

    private func pan(_ i: Int) -> some View {
        let t = painting.template
        let rgb = t.palette[i].rgb
        let color = Color(t.colorSpace == .displayP3 ? .displayP3 : .sRGB,
                          red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
        let done = painting.remaining[i] == 0
        let selected = painting.selected == i
        let label = String(localized: "watercolor.paint", defaultValue: "Paint \(i + 1)",
                           comment: "VoiceOver label of a paint in a watercolor painting's paint box: its number")
        return Button {
            painting.selected = i
        } label: {
            ZStack {
                Circle().fill(color)
                Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 1)
                } else {
                    Text(verbatim: "\(i + 1)")
                        .font(.system(.caption, design: .serif, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(t.palette[i].oklab.x > 0.62 ? Color.black.opacity(0.7) : Color.white.opacity(0.92))
                }
            }
            .frame(width: 44, height: 44)
            .opacity(done ? 0.45 : 1)
            .scaleEffect(selected ? 1.12 : 1)
            .overlay {
                if selected { Circle().strokeBorder(WatercolorEra.ink, lineWidth: 2.5).padding(-5) }
            }
            .animation(.snappy, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("watercolor-paint-\(i + 1)")
    }
}
#endif
