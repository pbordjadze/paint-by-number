/// The one preference Auto needs: how long a painting the user wants (Settings › Painting
/// Length). It sets the bands the suggested settings stay inside and the painting time the
/// scoring aims for.
public enum PaintingLength: String, Sendable, Codable, CaseIterable {
    case quick, relaxed, detailed

    /// Colors a suggestion may use.
    public var colorBand: ClosedRange<Int> {
        switch self {
        case .quick: 6...24
        case .relaxed: 8...40
        case .detailed: 12...72
        }
    }

    /// The detail a suggestion starts from before the photo moves it. Detailed sits at 0.8:
    /// at 0.7 the median large corpus photo's full template (about 950 areas, 48 minutes) sat
    /// at the bottom of its band.
    public var detailCenter: Float {
        switch self {
        case .quick: 0.3
        case .relaxed: 0.5
        case .detailed: 0.8
        }
    }

    /// Detail a suggestion may use: the center ± 0.35 (room for the photo's own adjustments
    /// and the neighbours tried around them).
    public var detailBand: ClosedRange<Float> {
        max(0, detailCenter - 0.35)...min(1, detailCenter + 0.35)
    }

    /// Painting time (seconds, `PaintingTime.estimate`) the scoring aims for; outside it a
    /// candidate pays `AutoScore.bandPenalty`. Calibrated on what the app generates: a
    /// 12 MP photo is kept at 2048 px and segmented at 1100 + 1000 × detail px, where the
    /// corpus's 35 large photos give a median of about 380 areas (19 minutes) at detail 0.3,
    /// 680 (34) at 0.5 and 1350 (67) at 0.9, a busy one two to three times that; a 768-px
    /// sample reaches 300–950 areas at any detail. The bands overlap so that a photo which
    /// cannot fill one still lands near it. Those counts come from `pbn` with the pipeline's
    /// fallback importance map; Vision maps rate background texture lower and give about half
    /// as many areas at like settings, which the detail center and the region model follow
    /// through the map's mean importance (`AutoSettings.detailPerImportance`,
    /// `regionAreaExponent`). Under a Vision stand-in map the median large corpus photo's
    /// suggestion runs 16, 26 and 42 minutes for Quick, Relaxed and Detailed.
    public var timeBand: ClosedRange<Double> {
        switch self {
        case .quick: (8 * 60)...(25 * 60)
        case .relaxed: (20 * 60)...(50 * 60)
        case .detailed: (40 * 60)...(120 * 60)
        }
    }
}
