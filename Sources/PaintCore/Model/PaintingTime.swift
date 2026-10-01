import Foundation

/// How long a template takes to paint. One estimate for the app's summaries and for Auto's
/// painting-time bands.
public enum PaintingTime {
    /// Rough time to paint one area: the tap plus finding it (zoom, pan).
    public static let secondsPerRegion = 3.0

    /// Rough time to paint a template of `regionCount` areas, in seconds.
    public static func estimate(regionCount: Int) -> Double { Double(regionCount) * secondsPerRegion }
}
