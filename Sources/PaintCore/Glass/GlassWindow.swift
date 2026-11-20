import Foundation

/// A Stained Glass window (painting-company row 366): the photo leaded by the painter's own
/// lines, each closed piece a region. A line stays as the finger drew it; only an end that stops
/// just short of other lead is joined to it (the Pen's `PenAssist`, before a line reaches here),
/// and a line that closes nothing is lead all the same. The window is a coloring book made from
/// `TemplateEditor.blank`, each line a Pen draw laid as Edit lays it (`painted`, then
/// `EditTrail.lay`), so it is a template an edit could have left and every renderer, the
/// gallery and progress take it as any other; then its paints are the glasses the photo
/// suggests (`GlassPalette`).
public enum GlassWindow {
    /// The window the photo and `lines` make on a `width` × `height` canvas (the working size,
    /// `GenerationSettings.workingSize`), in canvas units; a line the editor declines is left
    /// out, as Edit leaves it. Lines the app sends are already joined as the Pen joins them; raw
    /// lines (a finger's samples, `pbn glass`) take a `joining` reach in canvas units, and each
    /// end within it of the lead laid so far, or of the frame, is joined to it (`PenAssist`).
    /// Also the suggestion its paints came from and each line's verdict.
    public static func leaded(
        photo: RGBAImage, width: Int, height: Int, colorSpace: RGBColorSpace, lines: [[SIMD2<Float>]], joining reach: Float? = nil
    ) throws -> Leaded {
        var trail = EditTrail(base: try TemplateEditor.blank(width: width, height: height, photo: photo, colorSpace: colorSpace))
        var verdicts: [EditTrail.Verdict] = []
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        for var line in lines where line.count >= 2 {
            if let reach, reach > 0 {
                let lead = SnapLines(RefineGestures.drawingLines(of: trail.template, writing: false), frame: frame)
                line = PenAssist.joined(line.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }, to: lead, reach: CGFloat(reach), straight: false)
                    .map { SIMD2(Float($0.x), Float($0.y)) }
            }
            verdicts.append(trail.lay(TemplateEditor.painted(.draw(points: line), on: trail.template, photo: photo)).verdict)
        }
        let suggestion = GlassPalette.suggest(for: trail.template, photo: photo)
        return Leaded(template: GlassPalette.glazed(trail.template, with: suggestion), suggestion: suggestion, verdicts: verdicts)
    }

    public struct Leaded: Sendable {
        public var template: Template
        public var suggestion: GlassPalette.Suggestion
        public var verdicts: [EditTrail.Verdict]
    }
}
