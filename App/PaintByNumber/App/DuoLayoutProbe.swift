import CoreGraphics
import Foundation
import SwiftUI
import UIKit

extension View {
    /// Reports this control's place to `DuoLayoutProbe` in Debug demo launches, for ci/duo.sh to
    /// check against an iPhone Duo's fold; nothing in other launches, and compiled out of Release.
    @ViewBuilder
    func duoProbe(_ name: String) -> some View {
        #if DEBUG
        if DemoMode.isActive {
            background { DuoProbeView(name: name) }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Where the controls that report themselves (`duoProbe`) are, and where an iPhone Duo's fold is,
/// written in Debug demo launches to `tmp/duo-layout.json` in the app's data container whenever
/// either changes: ci/duo.sh copies it after each pose and ci/duo/check.py fails a control lying
/// on the fold. In the window's points, as UIKit has them (SwiftUI's global space was 42 pt off
/// inside a navigation stack with the Duo's vertical bar): `size`, `folds` (the active division
/// regions, margins included) and `controls` (each one's frame), all `[x, y, width, height]`.
@MainActor
final class DuoLayoutProbe {
    static let shared = DuoLayoutProbe()
    static let file = FileManager.default.temporaryDirectory.appending(path: "duo-layout.json")

    /// Each control's view by name, measured as the file is written (a view moved, not resized,
    /// lays nothing out): a control laid out in two places in turn (the palette at the side, then
    /// at the bottom) is taken out only by its own view.
    private var controls: [String: Weak] = [:]
    private var watch: Task<Void, Never>?
    private var written: Data?

    private struct Weak {
        weak var view: UIView?
    }

    func add(_ name: String, view: UIView) {
        controls[name] = Weak(view: view)
        // The fold moves without any control moving (a layout that ignores it): looked at often.
        guard watch == nil else { return }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                self?.write()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func remove(_ name: String, view: UIView) {
        if controls[name]?.view === view { controls[name] = nil }
    }

    private func write() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return }
        var folds: [[Double]] = []
        if #available(iOS 27.1, *) {
            folds = window.reservedRegions(kind: .division).filter(\.isActive).map { Self.numbers($0.frame) }
        }
        let layout: [String: Any] = [
            "screen": DemoMode.scenario ?? "",
            "size": [Double(window.bounds.width), Double(window.bounds.height)],
            "folds": folds,
            "controls": controls.compactMapValues { entry in
                entry.view.flatMap { $0.window == nil ? nil : Self.numbers($0.convert($0.bounds, to: nil)) }
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: layout, options: [.sortedKeys]),
              data != written else { return }
        written = data
        try? data.write(to: Self.file, options: .atomic)
    }

    /// `[x, y, width, height]` to a tenth of a point.
    private static func numbers(_ rect: CGRect) -> [Double] {
        let values: [CGFloat] = [rect.minX, rect.minY, rect.width, rect.height]
        return values.map { (value: CGFloat) -> Double in (Double(value) * 10).rounded() / 10 }
    }
}

/// `duoProbe`'s view, behind the control: its frame in the window, while it is in one.
private struct DuoProbeView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.name = name
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.name = name
        view.report()
    }

    final class ProbeView: UIView {
        var name = ""

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                DuoLayoutProbe.shared.remove(name, view: self)
            } else {
                report()
            }
        }

        func report() {
            guard window != nil else { return }
            DuoLayoutProbe.shared.add(name, view: self)
        }
    }
}
#endif
