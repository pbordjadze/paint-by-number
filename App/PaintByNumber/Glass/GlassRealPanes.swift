#if DEBUG && UNRELEASED
import AVFoundation
import CoreGraphics
import PaintCore
import QuartzCore
import SwiftUI
import UIKit
import os

/// A test of Apple's own Liquid Glass as a window's glass (painting-company row 366): every pane a
/// SwiftUI shape with `.glassEffect`, tinted with its glass, over the window's photo, all in one
/// `GlassEffectContainer`, which merges glass that comes within its spacing of other glass. It
/// answers whether 30 to 120 real glass panes stay smooth before the glazing moves onto them.
///
/// `-demo glass-real-panes-<N>` (N panes, 60 when no number) lays the monarch's photo under N
/// panes cut as a Voronoi of jittered seeds, and plays a fixed script while a display link counts
/// frames: 0 to 8 s the window drifts and zooms as glass is poured pane by pane; 8 to 11 s the
/// container's spacing grows past the lead, so neighbouring panes melt together; 11 to 13 s it
/// snaps back; 13 to 15 s still. At 15 s it prints and logs one `real-panes` line (frames, the
/// mean and 95th percentile gap, frames over 1.5 refreshes) and holds the last frame.
/// `-realPanesLoop YES` plays the script again and again, for Instruments' Animation Hitches.
/// `-realPanesCamera YES` holds the window up to the light: the rear camera's live picture is
/// behind the glass, the photo a faint layer over it, and the window stays still for the hand
/// to move instead.
struct GlassRealPanes: View {
    static var count: Int? {
        guard let name = DemoMode.scenario, name.hasPrefix("glass-real-panes") else { return nil }
        return Int(name.dropFirst("glass-real-panes".count).drop { $0 == "-" }) ?? 60
    }

    static let loops = UserDefaults.standard.bool(forKey: "realPanesLoop")
    static let usesCamera = UserDefaults.standard.bool(forKey: "realPanesCamera")

    let count: Int

    @State private var photo: CGImage?
    @State private var panes: [Pane] = []
    @State private var start = Date()
    @State private var meter = FrameMeter()

    struct Pane: Identifiable {
        let id: Int
        /// In unit coordinates of the photo, shrunk toward the middle to leave the lead.
        let polygon: [CGPoint]
        let glass: Color
        /// When it is poured, seconds into the script; past the script it stays clear.
        let pouredAt: Double
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let t = script(timeline.date.timeIntervalSince(start))
                ZStack {
                    Color.black
                    if let photo {
                        let rect = fitted(CGSize(width: photo.width, height: photo.height), in: proxy.size)
                        ZStack(alignment: .topLeading) {
                            if Self.usesCamera {
                                CameraBackdrop()
                                    .frame(width: rect.width, height: rect.height)
                                Image(decorative: photo, scale: 1)
                                    .resizable()
                                    .frame(width: rect.width, height: rect.height)
                                    .opacity(0.3)
                            } else {
                                Image(decorative: photo, scale: 1)
                                    .resizable()
                                    .frame(width: rect.width, height: rect.height)
                            }
                            GlassEffectContainer(spacing: melt(t) * rect.width) {
                                ZStack(alignment: .topLeading) {
                                    ForEach(panes) { pane in
                                        Color.clear
                                            .frame(width: rect.width, height: rect.height)
                                            .glassEffect(glass(pane, at: t), in: PaneShape(polygon: pane.polygon))
                                    }
                                }
                            }
                        }
                        .frame(width: rect.width, height: rect.height)
                        .scaleEffect(1 + 0.25 * drift(t))
                        .offset(x: 40 * sin(t * 0.9) * drift(t), y: 30 * cos(t * 0.7) * drift(t))
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
                .onChange(of: timeline.date) { _, date in meter.tick(at: date) }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task { await prepare() }
    }

    private func glass(_ pane: Pane, at t: Double) -> Glass {
        t >= pane.pouredAt ? .clear.tint(pane.glass.opacity(0.55)) : .clear
    }

    /// The script's clock: looping, or held at its end.
    private func script(_ elapsed: Double) -> Double {
        Self.loops ? elapsed.truncatingRemainder(dividingBy: 15) : min(elapsed, 15)
    }

    private func drift(_ t: Double) -> Double { !Self.usesCamera && t < 8 ? sin(.pi * t / 8) : 0 }

    /// The container's spacing as a share of the window's width: none, growing past the lead from 8
    /// to 11 s (the panes melting), and none again from 11 s (the lead snapping them apart).
    private func melt(_ t: Double) -> Double {
        guard t >= 8, t < 11 else { return 0 }
        return 0.04 * min(1, (t - 8) / 2)
    }

    private func fitted(_ size: CGSize, in bounds: CGSize) -> CGRect {
        let s = min(bounds.width / size.width, bounds.height / size.height) * 0.92
        let w = size.width * s, h = size.height * s
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    private func prepare() async {
        guard let image = try? await Background.run({ try GlassDemo.photo() }),
              let picture = PhotoLoader.cgImage(from: image) else { return }
        let aspect = Double(image.width) / Double(image.height)
        panes = Self.panes(count: count, aspect: aspect)
        photo = picture
        start = Date()
        meter.reset(panes: count, until: start.addingTimeInterval(15))
        try? await Task.sleep(for: .seconds(1))
        DemoMode.markReady()
    }

    /// `count` panes: a Voronoi of seeds jittered on a grid, each cell shrunk toward its middle by
    /// half the lead, given one of a stained glass window's colors and a moment to be poured.
    static func panes(count: Int, aspect: Double) -> [Pane] {
        var random = SplitMix64(seed: 1248)
        func unit() -> Double { Double(random.next() >> 11) / Double(1 << 53) }
        let columns = max(1, Int((Double(count) * aspect).squareRoot().rounded()))
        let rows = max(1, Int((Double(count) / Double(columns)).rounded(.up)))
        var seeds: [CGPoint] = []
        for k in 0..<count {
            let col = k % columns, row = k / columns
            seeds.append(CGPoint(x: (Double(col) + 0.2 + 0.6 * unit()) / Double(columns),
                                 y: (Double(row) + 0.2 + 0.6 * unit()) / Double(rows)))
        }
        let glasses: [Color] = [
            Color(red: 0.75, green: 0.08, blue: 0.12), Color(red: 0.10, green: 0.25, blue: 0.75),
            Color(red: 0.95, green: 0.70, blue: 0.15), Color(red: 0.10, green: 0.55, blue: 0.30),
            Color(red: 0.45, green: 0.15, blue: 0.55), Color(red: 0.90, green: 0.92, blue: 0.95),
        ]
        let lead = 0.006
        return seeds.indices.map { i in
            var cell = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
            // In a square space, so cells are true Voronoi cells of the photo's shape.
            let a = seeds[i]
            for (j, b) in seeds.enumerated() where j != i {
                let n = CGPoint(x: (b.x - a.x) * aspect * aspect, y: b.y - a.y)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                cell = clip(cell, keeping: { ($0.x - mid.x) * n.x + ($0.y - mid.y) * n.y <= 0 })
            }
            let cx = cell.reduce(0) { $0 + $1.x } / Double(max(cell.count, 1))
            let cy = cell.reduce(0) { $0 + $1.y } / Double(max(cell.count, 1))
            let shrunk = cell.map { p -> CGPoint in
                let dx = p.x - cx, dy = p.y - cy, d = max(((dx * aspect) * (dx * aspect) + dy * dy).squareRoot(), 1e-6)
                let k = max(0, 1 - lead / d)
                return CGPoint(x: cx + dx * k, y: cy + dy * k)
            }
            return Pane(id: i, polygon: shrunk, glass: glasses[Int(random.next() % UInt64(glasses.count))],
                        pouredAt: 0.5 + 7 * Double(i) / Double(max(count, 1)))
        }
    }

    /// Sutherland–Hodgman: the polygon's part where `inside` holds, for a straight boundary.
    private static func clip(_ polygon: [CGPoint], keeping inside: (CGPoint) -> Bool) -> [CGPoint] {
        guard !polygon.isEmpty else { return [] }
        var out: [CGPoint] = []
        for k in polygon.indices {
            let p = polygon[k], q = polygon[(k + 1) % polygon.count]
            let pIn = inside(p), qIn = inside(q)
            if pIn { out.append(p) }
            if pIn != qIn {
                // Bisect for the crossing: the boundary is straight, so 24 halvings are exact enough.
                var lo = p, hi = q
                if !pIn { swap(&lo, &hi) }
                for _ in 0..<24 {
                    let m = CGPoint(x: (lo.x + hi.x) / 2, y: (lo.y + hi.y) / 2)
                    if inside(m) { lo = m } else { hi = m }
                }
                out.append(lo)
            }
        }
        return out
    }
}

/// The rear camera's live picture, filling its frame.
private struct CameraBackdrop: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview?.session = view.session
        view.preview?.videoGravity = .resizeAspectFill
        Self.start(UncheckedSendable(view.session))
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    static func dismantleUIView(_ view: PreviewView, coordinator: ()) {
        stop(UncheckedSendable(view.session))
    }

    nonisolated private static func stop(_ box: UncheckedSendable<AVCaptureSession>) {
        DispatchQueue.global(qos: .userInitiated).async { box.value.stopRunning() }
    }

    /// Configured and started off the main thread, once the camera is allowed.
    nonisolated private static func start(_ box: UncheckedSendable<AVCaptureSession>) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let session = box.value
                session.beginConfiguration()
                session.sessionPreset = .hd1920x1080
                if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
                session.startRunning()
            }
        }
    }
}

/// A pane's outline, laid on the view's rect from unit coordinates.
nonisolated private struct PaneShape: Shape {
    let polygon: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = polygon.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for p in polygon.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}

/// Counts the frames the timeline drew and reports them once, at the script's end.
@MainActor
private final class FrameMeter {
    private var last: Date?
    private var gaps: [Double] = []
    private var panes = 0
    private var until = Date.distantFuture
    private var reported = false

    func reset(panes: Int, until: Date) {
        self.panes = panes
        self.until = until
        last = nil
        gaps = []
        reported = false
    }

    func tick(at date: Date) {
        if let last { gaps.append(date.timeIntervalSince(last) * 1000) }
        last = date
        guard !reported, date >= until, !gaps.isEmpty else { return }
        reported = true
        let sorted = gaps.sorted()
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let refresh = sorted[sorted.count / 2]
        let late = gaps.filter { $0 > refresh * 1.5 }.count
        // Tab-separated, as the tour log's lines are; milliseconds.
        let fields: [(String, String)] = [
            ("panes", "\(panes)"), ("frames", "\(gaps.count + 1)"), ("mean", ms(mean)), ("median", ms(refresh)),
            ("p95", ms(p95)), ("max", ms(sorted.last ?? 0)), ("late", "\(late)"),
        ]
        let line = (["real-panes"] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: "\t")
        print(line)
        Log.demo.notice("\(line, privacy: .public)")
    }

    private func ms(_ value: Double) -> String { String(format: "%.2f", value) }
}
#endif
