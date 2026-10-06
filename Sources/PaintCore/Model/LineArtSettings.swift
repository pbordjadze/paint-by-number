/// How a template's lines are made.
///
/// `coloringBook`, the default, splits the paint regions along a drawing found by learned
/// detectors (the app's line-drawing model laid over its HED contour map, or the maps handed
/// to `pbn`; see `Detector`) and is a coloring book:
/// the drawing alone is drawn, in full ink at every zoom, the paint boundaries inside an
/// outline are never lines (the areas inside it are told apart by their numbers, and by the
/// highlight of the selected color), the drawing stays over the paint (`TemplateLineArt.Style`)
/// and the paint is flatter (`SegmentationParameters.coloringBookFlattening`). `classic` is the
/// original look: every region boundary is one even line. Everything here is generation input:
/// changing it changes the template. Settings recorded with the retired layered style (the
/// drawing's lines faded in by strength as the painter zoomed) decode as the coloring book's
/// defaults.
///
/// Each style has defaults of its own for the thresholds, line lengths and smoothing
/// (`init(style:)`): the coloring book's are the ones measured in `docs/coloring-book.md`.
public struct LineArtSettings: Sendable, Hashable, Codable {
    public enum Style: String, Sendable, Codable, CaseIterable {
        case classic, coloringBook

        /// Whether templates of this style are made from an edge map (and eyes): all but classic.
        public var usesEdgeMap: Bool { self != .classic }

        /// The line art a template of this style carries; nil for classic templates.
        public var templateStyle: TemplateLineArt.Style? {
            switch self {
            case .classic: nil
            case .coloringBook: .coloringBook
            }
        }
    }

    /// What happens where a drawn line runs between two cells of the same paint.
    public enum SamePaint: String, Sendable, Codable, CaseIterable {
        /// Every line splits: the two sides are separate cells with the same number.
        case split
        /// Cells separated only by texture lines are one cell. A coloring book has no texture
        /// lines, so this splits like `split`.
        case joinTexture
        /// Only outlines split same-paint cells; detail and texture lines are drawn inside cells.
        case joinAllButOutlines
    }

    /// Which of the app's two models the lines come from (`LineArtInput`): the generator reads
    /// whatever maps it is handed; the app and `pbn` choose them by this.
    public enum Detector: String, Sendable, Codable, CaseIterable {
        /// The line drawing over the contour map, the contours deciding the outlines.
        case drawingAndContours
        /// The line drawing alone, its strongest strokes the outlines.
        case drawing
        /// The contour map (HED) alone, as the first books were made.
        case contours
    }

    public var style: Style
    public var detector: Detector
    /// Edge strength (0...1) from which a line is an outline, read off the contour map
    /// (`LineArtInput.contours`) when there is one, else the stroke's own strength in the edge
    /// map; `normalized` keeps it at or above `detailThreshold`. A line keeps its layer along a
    /// stretch that stays above 60 % of the threshold once it has held the threshold for a few
    /// pixels. Where lines crowd (a shell's pattern, rock strata, a truss) the threshold rises
    /// toward 1, except for long contours, so busy texture stays detail. The coloring book's
    /// 0.6 equals its detail threshold.
    public var outlineThreshold: Float
    /// Edge strength from which a line is drawn at all, as detail (stretches above half of it,
    /// once reached); slightly lower on the subject, higher in the background.
    public var detailThreshold: Float
    /// Lines shorter than this (canvas units) are dropped.
    public var minimumStrokeLength: Float
    /// Line ends closer than this (canvas units) are joined, closing small gaps; a free end
    /// also reaches this far (outlines 1.6×, detail 1.2×) for the nearest line, paint
    /// boundary or frame, so an open stroke still closes a cell.
    public var gapBridging: Float
    /// 0 = lines follow the edge map's pixels … 1 = smooth, flowing curves.
    public var lineSmoothing: Float
    public var samePaint: SamePaint
    /// Keep the cells that only a change of paint separates (banded skies, soft shading). Off
    /// merges cells whose paints are close, for calmer plans.
    public var keepColorEdges: Bool
    /// Draw detected eyes as outlines (their contours and irises), whatever their contrast;
    /// lines around an eye draw one layer stronger.
    public var outlineEyes: Bool
    /// Close each subject's silhouette (`LineArtInput.objects`) with outlines where the
    /// drawing leaves it open, so a subject is an area of its own.
    public var outlineObjects: Bool
    /// Draw the writing found in the photo (`LineArtInput.writing`: a note, a card, a sign) in
    /// ink traced from the photo itself, so it stays legible, over paper painted as if it
    /// weren't there, with the numbers kept off it (`Writing`).
    public var keepWriting: Bool

    /// A style at its defaults, any field given set instead. The coloring book draws every
    /// line the combined map holds at 0.6, and a line is an outline where the contour map holds
    /// 0.6 too (HED's silhouettes mostly do, the drawing's strokes rarely; `normalized` keeps the
    /// outline threshold at or above the detail threshold, so it cannot sit lower), so same-paint
    /// cells join across everything but silhouettes and the fur, creases and strands draw inside
    /// their cells; its longer shortest line and gap closing drop specks and close cells, and its
    /// curves flow (measured in `docs/coloring-book.md`, Defaults). Classic lines read none of
    /// them and record the values the retired layered style had, as they always did.
    public init(
        style: Style = .coloringBook, detector: Detector = .drawingAndContours,
        outlineThreshold: Float? = nil, detailThreshold: Float? = nil,
        minimumStrokeLength: Float? = nil, gapBridging: Float? = nil, lineSmoothing: Float? = nil,
        samePaint: SamePaint? = nil, keepColorEdges: Bool = true, outlineEyes: Bool = true,
        outlineObjects: Bool = true, keepWriting: Bool = true
    ) {
        let d = Self.numbers(for: style)
        self.style = style
        self.detector = detector
        self.outlineThreshold = outlineThreshold ?? d.outline
        self.detailThreshold = detailThreshold ?? d.detail
        self.minimumStrokeLength = minimumStrokeLength ?? d.minimumStrokeLength
        self.gapBridging = gapBridging ?? d.gapBridging
        self.lineSmoothing = lineSmoothing ?? d.lineSmoothing
        self.samePaint = samePaint ?? d.samePaint
        self.keepColorEdges = keepColorEdges
        self.outlineEyes = outlineEyes
        self.outlineObjects = outlineObjects
        self.keepWriting = keepWriting
    }

    /// A style's default thresholds, line lengths, smoothing and same-paint rule.
    private struct Numbers {
        var outline: Float, detail: Float
        var minimumStrokeLength: Float, gapBridging: Float, lineSmoothing: Float
        var samePaint: SamePaint
    }

    private static func numbers(for style: Style) -> Numbers {
        switch style {
        case .coloringBook:
            Numbers(outline: 0.6, detail: 0.6, minimumStrokeLength: 36, gapBridging: 16, lineSmoothing: 0.7,
                    samePaint: .joinAllButOutlines)
        case .classic:
            Numbers(outline: 0.85, detail: 0.5, minimumStrokeLength: 18, gapBridging: 9, lineSmoothing: 0.5,
                    samePaint: .joinTexture)
        }
    }

    /// Clamped copy: thresholds in 0...1 and ordered (detail ≤ outline).
    public var normalized: LineArtSettings {
        var s = self
        s.detailThreshold = min(max(detailThreshold, 0), 1)
        s.outlineThreshold = min(max(outlineThreshold, s.detailThreshold), 1)
        s.minimumStrokeLength = min(max(minimumStrokeLength, 0), 200)
        s.gapBridging = min(max(gapBridging, 0), 40)
        s.lineSmoothing = min(max(lineSmoothing, 0), 1)
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case style, detector, outlineThreshold, detailThreshold, minimumStrokeLength, gapBridging,
             lineSmoothing, samePaint, keepColorEdges, outlineEyes, outlineObjects, keepWriting
    }

    /// Tolerant: missing or unknown values fall back to the defaults (the decoded style's), so
    /// settings written by another build always decode. Settings of the retired layered style
    /// are the coloring book's defaults whole: its numbers meant other lines.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if (try? c.decodeIfPresent(String.self, forKey: .style)) == "layered" {
            self = LineArtSettings()
            return
        }
        style = ((try? c.decodeIfPresent(Style.self, forKey: .style)) ?? nil) ?? LineArtSettings().style
        let d = LineArtSettings(style: style)
        detector = ((try? c.decodeIfPresent(Detector.self, forKey: .detector)) ?? nil) ?? d.detector
        outlineThreshold = (try? c.decodeIfPresent(Float.self, forKey: .outlineThreshold)) ?? d.outlineThreshold
        detailThreshold = (try? c.decodeIfPresent(Float.self, forKey: .detailThreshold)) ?? d.detailThreshold
        minimumStrokeLength = (try? c.decodeIfPresent(Float.self, forKey: .minimumStrokeLength)) ?? d.minimumStrokeLength
        gapBridging = (try? c.decodeIfPresent(Float.self, forKey: .gapBridging)) ?? d.gapBridging
        lineSmoothing = (try? c.decodeIfPresent(Float.self, forKey: .lineSmoothing)) ?? d.lineSmoothing
        samePaint = (try? c.decodeIfPresent(SamePaint.self, forKey: .samePaint)) ?? d.samePaint
        keepColorEdges = (try? c.decodeIfPresent(Bool.self, forKey: .keepColorEdges)) ?? d.keepColorEdges
        outlineEyes = (try? c.decodeIfPresent(Bool.self, forKey: .outlineEyes)) ?? d.outlineEyes
        outlineObjects = (try? c.decodeIfPresent(Bool.self, forKey: .outlineObjects)) ?? d.outlineObjects
        keepWriting = (try? c.decodeIfPresent(Bool.self, forKey: .keepWriting)) ?? d.keepWriting
    }
}
