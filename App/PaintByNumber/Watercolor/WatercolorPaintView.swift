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
    @State private var needsNewerApp = false

    private var opening: ModeOpening {
        if opened != nil { return .open }
        if needsNewerApp { return .needsNewerApp }
        return failed ? .failed : .opening
    }

    var body: some View {
        // A painting written by a newer app keeps its files as they are: an older app never
        // writes over a newer one's.
        ModePaintingFrame(title: shelf.painting(id)?.title ?? "", opening: opening, cantOpen: Text("Can’t Open Painting"),
                          backdrop: WatercolorEra.desk) {
            if let opened {
                WatercolorPaintView(shelf: shelf, painting: opened.painting, renderer: opened.renderer)
            }
        }
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
            } catch WatercolorLog.CodingError.newerVersion, WatercolorSim.SnapshotError.newerVersion {
                needsNewerApp = true
            } catch {
                Log.library.error("Couldn't open watercolor \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                failed = true
            }
        }
    }
}

/// The sheet and the paints: a tap lays a wash of the paint in hand on its area, as the main
/// painting screen fills one, with its Undo, Hint and Zen Mode (More). The paint box lies on the
/// desk below the sheet; finished, it is put away and the sheet, signed, settles into the room it
/// leaves.
struct WatercolorPaintView: View {
    let shelf: WatercolorShelf
    let painting: WatercolorPainting
    let renderer: WatercolorRenderer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.zenMode) private var zenMode = SettingsDefault.zenMode
    @State private var taps = 0
    @State private var boxHeight: CGFloat = 0
    @State private var flyTo: (area: CGRect, count: Int)?
    @State private var zenFlight: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                WatercolorCanvas(renderer: renderer,
                                 bottomInset: proxy.safeAreaInsets.bottom + (painting.isComplete ? 0 : boxHeight + 10),
                                 signed: painting.isComplete,
                                 title: shelf.painting(painting.id)?.title ?? "",
                                 reduceMotion: reduceMotion,
                                 flyTo: flyTo,
                                 onTap: { point, tolerance in
                                     handle(painting.tap(at: point, tolerance: tolerance), at: point)
                                 },
                                 onDrag: { point, tolerance in
                                     if case .painted = painting.tap(at: point, tolerance: tolerance, blooms: false) { taps += 1 }
                                 },
                                 selected: painting.selected)
                .accessibilityElement()
                .accessibilityLabel(Text("Watercolor sheet"))
                .accessibilityValue(Text(progress))
                .accessibilityAction(named: Text("Lay the Next Wash")) {
                    if let point = painting.nextArea() { handle(painting.tap(at: point), at: point) }
                }
                .accessibilityIdentifier("watercolor-sheet")
                .ignoresSafeArea(edges: [.horizontal, .bottom])
                if !painting.isComplete {
                    WatercolorPaintBox(painting: painting)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { boxHeight = $0 }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .toolbar {
            if !painting.isComplete {
                ToolbarItem(placement: .primaryAction) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        zenFlight?.cancel()
                        painting.undo()
                    }
                    .disabled(!painting.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier("watercolor-undo")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Hint", systemImage: "lightbulb", action: hint)
                        .disabled(painting.selected == nil)
                        .keyboardShortcut("h", modifiers: [])
                        .accessibilityIdentifier("watercolor-hint")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle(isOn: $zenMode) { SwiftUI.Label("Zen Mode", systemImage: "leaf") }
                    } label: {
                        SwiftUI.Label("More", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("watercolor-more")
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: painting.isComplete)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: taps)
        .sensoryFeedback(.selection, trigger: painting.shake.count)
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
        .onDisappear {
            zenFlight?.cancel()
            save(withPicture: true)
        }
    }

    /// What a tap did, felt and followed: a wash laid is felt and, in Zen Mode, the sheet goes on
    /// to the nearest area of the paint in hand once the wash has spread a moment (longer after
    /// one that finished its paint, as the main canvas's `zenShinePause`).
    private func handle(_ result: WatercolorPainting.TapResult?, at point: SIMD2<Float>) {
        guard let result else { return }
        zenFlight?.cancel()
        switch result {
        case .painted(let r):
            taps += 1
            guard zenMode, !painting.isComplete else { return }
            let finishedPaint = painting.selected != Int(painting.template.regions[r].colorIndex)
            zenFlight = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(finishedPaint ? 1100 : 450))
                guard !Task.isCancelled, let next = painting.nextAreaFrame(near: point) else { return }
                flyTo = (next.bounds, (flyTo?.count ?? 0) + 1)
            }
        case .bloomed:
            taps += 1
        case .otherPaint:
            break
        }
    }

    /// Flies to the largest area of the paint in hand not yet laid (the main canvas's Hint).
    private func hint() {
        zenFlight?.cancel()
        guard let next = painting.nextAreaFrame() else { return }
        flyTo = (next.bounds, (flyTo?.count ?? 0) + 1)
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

/// The paint box: a tin of half pans, one for each paint, its number below it; the pan in hand
/// lifted, a paint whose areas are all painted scooped out to the white of its pan. All the pans
/// in a row when they fit, scrolling sideways otherwise.
struct WatercolorPaintBox: View {
    let painting: WatercolorPainting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pans
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) { pans }
                    .clipShape(.rect(cornerRadius: 26, style: .continuous))
                    .onChange(of: painting.selected) { _, selected in
                        guard let selected else { return }
                        withAnimation { reader.scrollTo(selected, anchor: .center) }
                    }
                    .onChange(of: painting.shake.count) { _, _ in
                        // The pan shaken brought into view, as the main palette shows its swatch.
                        withAnimation { reader.scrollTo(painting.shake.color, anchor: .center) }
                    }
                    .onAppear {
                        if let selected = painting.selected { reader.scrollTo(selected, anchor: .center) }
                    }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(WatercolorEra.tin.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var pans: some View {
        HStack(spacing: 10) {
            ForEach(painting.template.palette.indices, id: \.self) { i in
                pan(i).id(i)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
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
            VStack(spacing: 5) {
                WatercolorPan(color: color, done: done)
                    .frame(width: 40, height: 46)
                    .modifier(PanShake(shakes: CGFloat(painting.shake.count),
                                       amplitude: painting.shake.color == i && !reduceMotion ? 6 : 0))
                    .animation(.linear(duration: 0.4), value: painting.shake.count)
                    .shadow(color: .black.opacity(selected ? 0.3 : 0.14), radius: selected ? 6 : 1, y: selected ? 7 : 1)
                    .offset(y: selected ? -7 : 0)
                Group {
                    if done {
                        Image(systemName: "checkmark").font(.caption2.bold())
                    } else {
                        Text(verbatim: "\(i + 1)").font(.system(.caption, design: .serif, weight: selected ? .bold : .semibold))
                    }
                }
                .monospacedDigit()
                .foregroundStyle(selected ? WatercolorEra.panInk : Color.black.opacity(done ? 0.3 : 0.62))
            }
            .contentShape(.rect)
            .animation(.snappy, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: done ? PaintSpeech.finished : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: "\(i + 1)")
        }
        .accessibilityIdentifier("watercolor-paint-\(i + 1)")
    }
}

/// A pan shaken side to side, once for each step of `shakes`: its area was tapped while another
/// paint was in hand (the main palette's shake).
private struct PanShake: GeometryEffect {
    var shakes: CGFloat
    var amplitude: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amplitude * sin(shakes * .pi * 4), y: 0))
    }
}

/// A half pan: a white well with its cake of paint, a little sheen on top; used up, the cake
/// scooped out to the well.
private struct WatercolorPan: View {
    let color: Color
    let done: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(WatercolorEra.well)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
                    .overlay {
                        // The cake's edge, a shade darker where it meets the well.
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.black.opacity(0.16), lineWidth: 2)
                            .blur(radius: 1.5)
                    }
                    .overlay(alignment: .top) {
                        if !done {
                            Capsule()
                                .fill(.white.opacity(0.24))
                                .frame(height: 6)
                                .padding(.horizontal, 6)
                                .padding(.top, 3)
                                .blur(radius: 2)
                        }
                    }
                    .overlay {
                        if done {
                            Ellipse()
                                .fill(WatercolorEra.well.opacity(0.85))
                                .padding(4)
                                .blur(radius: 2.5)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 4, style: .continuous))
                    .padding(4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.black.opacity(0.1), lineWidth: 0.5)
            }
    }
}
#endif
