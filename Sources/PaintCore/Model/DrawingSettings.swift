/// How a template is made from a drawing (`GenerationSettings.drawing`): a photo of a line
/// drawing on paper (pen or pencil, a coloring page, a sketchbook page) whose lines, as drawn,
/// bound the areas, the way a coloring book works. No color comes from the photo, so the paints
/// come from a palette set (`DrawingPalette`), laid over the areas so neighbours never share
/// one. Everything here is generation input: changing it changes the template. A settings file
/// without `drawing` is a photo's (`GenerationSettings`); one with it that this build can't
/// read is a drawing's at these defaults.
public struct DrawingSettings: Sendable, Hashable, Codable {
    /// The palette set the paints come from.
    public var palette: DrawingPalette.Set
    /// How many of the set's paints to use; nil picks by the number of areas
    /// (`DrawingPalette.paintCount`).
    public var paints: Int?

    public init(palette: DrawingPalette.Set = .crayons, paints: Int? = nil) {
        self.palette = palette
        self.paints = paints
    }

    private enum CodingKeys: String, CodingKey { case palette, paints }

    /// Tolerant: a set this build doesn't know (a later app's) is the default, and the paint
    /// count is read as given.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        palette = ((try? c.decodeIfPresent(DrawingPalette.Set.self, forKey: .palette)) ?? nil) ?? .crayons
        paints = (try? c.decodeIfPresent(Int.self, forKey: .paints)) ?? nil
    }

    /// Clamped copy: the paint count within the set's.
    public var normalized: DrawingSettings {
        var s = self
        if let paints { s.paints = min(max(paints, DrawingPalette.minimumPaints), DrawingPalette.colors(of: palette).count) }
        return s
    }

    /// The line art a drawing is traced with: every line of the ink is drawn, and a line
    /// splits the paper on both sides where lines are not crowded (`samePaint:
    /// .joinAllButOutlines` with the outline threshold at the detail's: a line is an outline
    /// unless the clutter around it, hatching, fur, a scribbled shadow, lifts the threshold
    /// out of reach, `LineLayering`; there is one paint until the palette is laid, so the
    /// crowded lines draw inside the cell around them), as drawn (`lineSmoothing` 0: the lines follow the ink's pixels, the vectorizer's
    /// curve fit alone evens them), gaps up to `gapBridging` closed along the line's own
    /// direction, strokes shorter than `minimumStrokeLength` (specks of the paper) dropped.
    /// The thresholds are the ink's strength a pencil's faint stroke still reaches.
    /// Nothing is read from a photo: no eyes, subjects or writing. Public for `pbn`'s report.
    public static var lineArt: LineArtSettings {
        LineArtSettings(
            style: .coloringBook, detector: .drawing, outlineThreshold: 0.3, detailThreshold: 0.3,
            minimumStrokeLength: 10, gapBridging: 14, lineSmoothing: 0, samePaint: .joinAllButOutlines,
            keepColorEdges: true, outlineEyes: false, outlineObjects: false, keepWriting: false)
    }
}
