import CoreGraphics
import Observation
import SwiftUI
import UIKit

/// An iPhone Duo's fold while it is half open: its active reserved region (`.division`, iOS 27.1;
/// inactive and zero-wide while the Duo lies flat), margins included, in the coordinates of a view
/// (`FoldWatch.fold(in:rightToLeft:)`, x from the leading edge). Nil when flat or closed, and on every
/// other device.
nonisolated struct ActiveFold: Equatable, Sendable {
    var frame: CGRect
    /// Down the middle, like a book; else across it, like a laptop.
    var isUpright: Bool { frame.height > frame.width }
}

/// Where the iPhone Duo's fold is in the window, kept for every view: read from UIKit's window
/// (`UIView.reservedRegions`), which puts it where the display folds, and placed in a view by that
/// view's frame in the window. A view's own geometry proxy put it 42 pt off, half the system's
/// vertical bar, inside a navigation stack (CI's Duo simulator, November 4, 2026); the painting
/// screen, which has no bar, reads its own proxy (`PaintingLayout.fold(in:)`). `RootView` refreshes
/// it as the window's geometry changes (`watchesTheFold`).
@MainActor @Observable
final class FoldWatch {
    static let shared = FoldWatch()

    /// The fold in window coordinates, active or not (an open Duo's while it lies flat), and
    /// whether it is active; nil without one in the window.
    private(set) var region: Region?

    nonisolated struct Region: Equatable, Sendable {
        var frame: CGRect
        var isActive: Bool
        var windowWidth: CGFloat
        var isUpright: Bool { frame.height > frame.width }
    }

    func refresh() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var found: Region?
        if #available(iOS 27.1, *), let window {
            let regions = window.reservedRegions(kind: .division, options: .includeInactive)
            if let region = regions.first(where: \.isActive) ?? regions.first {
                found = Region(frame: region.frame, isActive: region.isActive, windowWidth: window.bounds.width)
            }
        }
        if found != region { region = found }
    }

    /// The active fold in the coordinates of a view at `frame` in the window (`.global`).
    func fold(in frame: CGRect, rightToLeft: Bool) -> ActiveFold? {
        guard let region, region.isActive else { return nil }
        return ActiveFold(frame: Self.local(region.frame, in: frame, rightToLeft: rightToLeft))
    }

    /// Whether a half-open Duo's fold runs down the window like a book's: sheets keep to the
    /// trailing page then (`besideTheFold`).
    var isBookFold: Bool { region.map { $0.isActive && $0.isUpright } ?? false }

    /// `rect` (window coordinates) in a view at `frame`, x from its leading edge.
    nonisolated static func local(_ rect: CGRect, in frame: CGRect, rightToLeft: Bool) -> CGRect {
        let x = rightToLeft ? frame.maxX - rect.maxX : rect.minX - frame.minX
        return CGRect(x: x, y: rect.minY - frame.minY, width: rect.width, height: rect.height)
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
