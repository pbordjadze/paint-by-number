import CoreGraphics
import SwiftUI

/// An iPhone Duo's fold while it is half open: its active reserved region (`.division`, iOS 27.1;
/// inactive and zero-wide while the Duo lies flat), margins included, in the coordinates of the
/// view whose geometry it was read from (x from the leading edge). Nil when flat or closed, and on
/// every other device. Read with `onGeometryChange(for: ActiveFold?.self) { ActiveFold.of($0) }`.
nonisolated struct ActiveFold: Equatable, Sendable {
    var frame: CGRect
    /// Down the middle, like a book; else across it, like a laptop.
    var isUpright: Bool { frame.height > frame.width }

    static func of(_ proxy: GeometryProxy) -> ActiveFold? {
        guard #available(iOS 27.1, *) else { return nil }
        guard let region = proxy.reservedRegions(kind: .division).first(where: \.isActive) else { return nil }
        return ActiveFold(frame: region.frame)
    }
}
