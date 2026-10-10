/// How big a region's number is drawn: the one sizing rule shared by SVG, the CoreGraphics
/// rasterizer (thumbnails, previews, PDF) and the Metal canvas, so they cannot drift apart.
///
/// A number's run of digits is fitted by its bounding-box diagonal (nominal digit metrics)
/// into the label's free disc, so a 3-digit number needs about twice the room of a 1-digit
/// one. The pipeline gives every label at least `minimumRadius(digits:)` of room, hence no
/// number is smaller than `minimumFontSize` whatever its digit count; renderers never drop a
/// number, they draw it at the floor instead (a region without a number cannot be painted).
///
/// A detail area (`Template.detailRegions`: a shape the painter filled in Refine, such as a
/// star of a few pixels) has a floor of its own, `detailMinimumRadius`, about half: its number
/// is read zoomed in. Every renderer asks with `detail:` for such a region's labels.
public enum LabelSizing {
    /// Nominal digit advance and cap height, em. Real fonts (SF Rounded, Helvetica) are a
    /// little narrower; `fill` leaves the slack.
    public static let digitAdvance: Float = 0.6
    public static let digitHeight: Float = 0.72
    /// Share of the free disc's diameter the run's diagonal may take.
    public static let fill: Float = 0.85

    /// Free radius (canvas units) every 1-digit label is guaranteed; longer numbers get
    /// proportionally more (`minimumRadius(digits:)`). It is the smoothed-polygon tolerance
    /// (`SegmentationParameters.vectorRadiusTolerance`) times the smallest raster minimum,
    /// bounded by what a pixel-exact outline around a raster disc of that minimum clears
    /// (1.5·√2 ≈ 2.121 for 2.7): `LabelSizingTests.minimumRadiusIsAchievable` ties them together.
    public static let minimumRadius: Float = 2.12

    /// Free radius every 1-digit number of a detail area is guaranteed, about half of
    /// `minimumRadius` (0.48 of it): a detail area's 3-digit number needs exactly the room a
    /// 1-digit number of any other area does, the 5-px spot the floor always held. Painters
    /// fill stars and dots of 10 to 15 canvas units, and a fill that needs a paint of its own
    /// takes the last number, 3 digits on a large palette (a Fra Angelico's gold stars on its
    /// blue arch, number 144 of 144). Its number is drawn at 0.48 of `minimumFontSize`: legible
    /// zoomed in twice as far (`SegmentationParameters.detailMinRadius(digits:)` is the raster
    /// room that keeps it).
    public static let detailMinimumRadius: Float = minimumRadius / roomFactor(digits: 3)

    /// Decimal digits of a positive number (at least 1).
    public static func digitCount(of number: Int) -> Int {
        var digits = 1
        var rest = number / 10
        while rest != 0 { digits += 1; rest /= 10 }
        return digits
    }

    /// Digits of the number shown for palette index `colorIndex` (numbers start at 1).
    public static func digitCount(colorIndex: UInt32) -> Int { digitCount(of: Int(colorIndex) + 1) }

    /// Diagonal of a run of `digits` digits at 1 em.
    static func runDiagonal(digits: Int) -> Float {
        let w = digitAdvance * Float(max(digits, 1)), h = digitHeight
        return (w * w + h * h).squareRoot()
    }

    /// How much more room than a single digit a run of `digits` digits needs at the same size.
    public static func roomFactor(digits: Int) -> Float { runDiagonal(digits: digits) / runDiagonal(digits: 1) }

    /// Free radius a label with `digits` digits is guaranteed.
    public static func minimumRadius(digits: Int) -> Float { minimumRadius * roomFactor(digits: digits) }

    /// Free radius a label with `digits` digits is guaranteed, in a detail area or another.
    public static func minimumRadius(digits: Int, detail: Bool) -> Float {
        (detail ? detailMinimumRadius : minimumRadius) * roomFactor(digits: digits)
    }

    /// Font size (canvas units) whose run of `digits` digits fits a free disc of `radius`.
    public static func fittedFontSize(radius: Float, digits: Int) -> Float {
        2 * radius * fill / runDiagonal(digits: digits)
    }

    /// The smallest size a number is drawn at: what a minimal label fits, for any digit count.
    public static var minimumFontSize: Float { fittedFontSize(radius: minimumRadius, digits: 1) }

    /// The smallest size a detail area's number is drawn at.
    public static var detailMinimumFontSize: Float { fittedFontSize(radius: detailMinimumRadius, digits: 1) }

    /// The smallest size a number is drawn at, in a detail area or another.
    public static func minimumFontSize(detail: Bool) -> Float { detail ? detailMinimumFontSize : minimumFontSize }

    /// Size to draw a label's number at: fitted to its room, at most `maximum` (a renderer's
    /// cap for huge regions) and never below the floor (`minimumFontSize`, or a detail area's
    /// `detailMinimumFontSize`), which wins over the cap.
    public static func fontSize(radius: Float, digits: Int, maximum: Float = .infinity, detail: Bool = false) -> Float {
        max(min(fittedFontSize(radius: radius, digits: digits), maximum), minimumFontSize(detail: detail))
    }
}
