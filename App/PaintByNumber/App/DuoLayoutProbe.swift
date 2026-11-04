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
        modifier(DuoProbe(name: name))
        #else
        self
        #endif
    }
}

#if DEBUG
/// Where the controls that report themselves (`duoProbe`) are, and where an iPhone Duo's fold is,
/// written in Debug demo launches to `tmp/duo-layout.json` in the app's data container whenever
/// either changes: ci/duo.sh copies it after each pose and ci/duo/check.py fails a control lying
/// on the fold. In the window's points: `size`, `folds` (the active division regions, margins
/// included, as UIKit has them) and `controls` (each one's frame), all `[x, y, width, height]`.
@MainActor
final class DuoLayoutProbe {
    static let shared = DuoLayoutProbe()
    static let file = FileManager.default.temporaryDirectory.appending(path: "duo-layout.json")

    private var controls: [String: CGRect] = [:]
    private var watch: Task<Void, Never>?
    private var written: Data?

    func set(_ name: String, frame: CGRect?) {
        guard DemoMode.isActive else { return }
        controls[name] = frame
        // The fold moves without any control moving (a layout that ignores it): looked at often.
        guard watch == nil else { return }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                self?.write()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
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
            "controls": controls.mapValues(Self.numbers),
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

/// `duoProbe`: the control's frame in the window (SwiftUI's global space), while it is on screen.
private struct DuoProbe: ViewModifier {
    let name: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if DemoMode.isActive {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    DuoLayoutProbe.shared.set(name, frame: frame)
                }
                .onDisappear { DuoLayoutProbe.shared.set(name, frame: nil) }
        } else {
            content
        }
    }
}
#endif
