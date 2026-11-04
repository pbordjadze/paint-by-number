import CoreGraphics
import Observation
import SwiftUI
import UIKit

/// An iPhone Duo's fold while it is half open: its active reserved region (`.division`, iOS 27.1;
/// inactive and zero-wide while the Duo lies flat), margins included, in a view's coordinates, x
/// from the leading edge (`FoldPlace.active(rightToLeft:)`). Nil when flat or closed, and on every
/// other device.
nonisolated struct ActiveFold: Equatable, Sendable {
    var frame: CGRect
    /// Down the middle, like a book; else across it, like a laptop.
    var isUpright: Bool { frame.height > frame.width }
}

/// An iPhone Duo's fold where a view is, as UIKit has it in that view's own coordinates (left to
/// right, `UIView.reservedRegions`), active or not, with the view's size and side safe areas.
/// Read by `FoldReader`: SwiftUI's geometry proxies and its global space put the fold 42 pt off,
/// half the system's vertical bar, inside a navigation stack (CI's Duo simulator, November 4,
/// 2026), while UIKit's view measures what is on the screen.
nonisolated struct FoldPlace: Equatable, Sendable {
    var frame: CGRect
    var isActive: Bool
    var size: CGSize
    var safeLeft: CGFloat = 0
    var safeRight: CGFloat = 0

    /// Down the view, like a book's (an inactive one is zero-wide and full height).
    var isUpright: Bool { frame.height > frame.width }

    /// `frame` from the leading edge.
    func leadingFrame(rightToLeft: Bool) -> CGRect {
        guard rightToLeft else { return frame }
        return CGRect(x: size.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    }

    /// The fold while it is folded and runs through the view, x from its leading edge.
    func active(rightToLeft: Bool) -> ActiveFold? {
        guard isActive, size.width > 0, size.height > 0 else { return nil }
        let through = isUpright
            ? frame.minX > 0 && frame.maxX < size.width
            : frame.minY > 0 && frame.maxY < size.height
        return through ? ActiveFold(frame: leadingFrame(rightToLeft: rightToLeft)) : nil
    }

    @MainActor
    static func of(_ view: UIView) -> FoldPlace? {
        guard #available(iOS 27.1, *) else { return nil }
        let regions = view.reservedRegions(kind: .division, options: .includeInactive)
        guard let region = regions.first(where: \.isActive) ?? regions.first else { return nil }
        return FoldPlace(
            frame: region.frame, isActive: region.isActive, size: view.bounds.size,
            safeLeft: view.safeAreaInsets.left, safeRight: view.safeAreaInsets.right)
    }
}

/// Tells `onChange` where an iPhone Duo's fold is in the view it is the background of
/// (`FoldPlace`), whenever that view's room changes or the window's fold does (`trigger`, the
/// root's `FoldWatch`). Nil without a fold there.
struct FoldReader: UIViewRepresentable {
    var trigger: FoldWatch.Signal
    var onChange: (FoldPlace?) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
        view.read()
    }

    final class ReaderView: UIView {
        var onChange: ((FoldPlace?) -> Void)?
        private var reported: FoldPlace??

        override func layoutSubviews() {
            super.layoutSubviews()
            read()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            read()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            read()
        }

        /// Reports a change, after the update or layout under way (state changes inside one are
        /// lost or warned about).
        func read() {
            guard window != nil else { return }
            let place = FoldPlace.of(self)
            guard reported != .some(place) else { return }
            reported = .some(place)
            let onChange = onChange
            Task { @MainActor in onChange?(place) }
        }
    }
}

/// Whether the window has a fold, and where, kept for every view: refreshed from the root
/// (`watchesTheFold`), so the views that place things by it (`FoldReader`) read it again as the
/// Duo opens, closes, folds or turns; and whether it runs down the window like a book's, for the
/// sheets (`besideTheFold`).
@MainActor @Observable
final class FoldWatch {
    static let shared = FoldWatch()

    private(set) var signal = Signal()

    /// The window's fold, as UIKit has it in the window, and the window's size: what changes when
    /// it moves, folds or turns.
    nonisolated struct Signal: Equatable, Sendable {
        var frame: CGRect?
        var isActive = false
        var size: CGSize = .zero
    }

    /// A half-open Duo's fold runs down the window like a book's.
    var isBookFold: Bool { signal.isActive && (signal.frame.map { $0.height > $0.width } ?? false) }

    /// The window's fold while it is folded, x from the leading edge, in the window's points (the
    /// screen's): what a screen that fills the window lays out by until its own `FoldReader` has
    /// read the fold, so a painting opened on a half-open Duo isn't first laid out across it.
    func windowFold(rightToLeft: Bool) -> CGRect? {
        Self.fold(of: signal, rightToLeft: rightToLeft)
    }

    nonisolated static func fold(of signal: Signal, rightToLeft: Bool) -> CGRect? {
        guard let frame = signal.frame else { return nil }
        return FoldPlace(frame: frame, isActive: signal.isActive, size: signal.size).active(rightToLeft: rightToLeft)?.frame
    }

    func refresh() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var found = Signal()
        if let window, let place = FoldPlace.of(window) {
            found = Signal(frame: place.frame, isActive: place.isActive, size: place.size)
        }
        if found != signal { signal = found }
    }
}

/// What a view's geometry says of the fold, compared only to notice that it changed.
nonisolated struct FoldSignal: Equatable, Sendable {
    var size: CGSize
    var regions: [CGRect]
    var active: [Bool]

    static func of(_ proxy: GeometryProxy) -> FoldSignal {
        guard #available(iOS 27.1, *) else { return FoldSignal(size: proxy.size, regions: [], active: []) }
        let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        return FoldSignal(size: proxy.size, regions: regions.map(\.frame), active: regions.map(\.isActive))
    }
}

extension View {
    /// Keeps `FoldWatch` current as the window opens, closes, folds or turns: on the root view.
    func watchesTheFold() -> some View {
        onGeometryChange(for: FoldSignal.self) { FoldSignal.of($0) } action: { _ in
            FoldWatch.shared.refresh()
        }
        .onAppear { FoldWatch.shared.refresh() }
    }

    /// Where an iPhone Duo's fold is in this view (`FoldPlace`), told to `onChange` as it moves.
    func readsTheFold(_ onChange: @escaping (FoldPlace?) -> Void) -> some View {
        background { FoldReader(trigger: FoldWatch.shared.signal, onChange: onChange) }
    }

    /// A sheet's placement on an iPhone Duo half open like a book: the trailing page, off the fold,
    /// where the system's own controls are; anywhere else as the system places it.
    @ViewBuilder
    func besideTheFold() -> some View {
        if #available(iOS 27.0, *) {
            presentationPlacement(FoldWatch.shared.isBookFold ? .trailing : .automatic)
        } else {
            self
        }
    }
}
