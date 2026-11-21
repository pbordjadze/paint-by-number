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
        var leading = try Leading(photo: photo, width: width, height: height, colorSpace: colorSpace)
        var verdicts: [EditTrail.Verdict] = []
        for line in lines where line.count >= 2 {
            verdicts.append(leading.add(line, joining: reach).verdict)
        }
        var window = leading.window()
        window.verdicts = verdicts
        return window
    }

    /// A window being leaded, a line at a time, as the Lead screen draws it: each line laid as it
    /// lifts, so the pieces it closes can light up at once.
    public struct Leading: Sendable {
        public let photo: RGBAImage
        private var trail: EditTrail
        /// What the painter did, each step one of `trail`'s edits: a line laid, or one taken away.
        private enum Step: Sendable { case line([SIMD2<Float>]), erase }
        private var steps: [Step] = []
        /// The lines the painter laid, as joined (the suggestion's are the ground they were laid on).
        public var lines: [[SIMD2<Float>]] {
            steps.compactMap { if case .line(let line) = $0 { line } else { nil } }
        }

        public init(photo: RGBAImage, width: Int, height: Int, colorSpace: RGBColorSpace) throws {
            self.photo = photo
            trail = EditTrail(base: try TemplateEditor.blank(width: width, height: height, photo: photo, colorSpace: colorSpace))
        }

        /// A window leaded as the photo suggests (`GlassLeadSuggestion`), for the painter to change:
        /// the suggestion is the ground of what they do, so Undo never takes it back line by line.
        public static func suggested(
            photo: RGBAImage, width: Int, height: Int, colorSpace: RGBColorSpace, cancel: CancellationCheck = .none
        ) throws -> Leading {
            var leading = try Leading(photo: photo, width: width, height: height, colorSpace: colorSpace)
            let reach = Float(max(width, height)) * GlassLeadSuggestion.joining
            for line in try GlassLeadSuggestion.lines(photo: photo, width: width, height: height, cancel: cancel) {
                try cancel.throwIfCancelled()
                leading.add(line, joining: reach)
            }
            leading.trail = EditTrail(base: leading.trail.template)
            leading.steps = []
            return leading
        }

        /// The lead as it stands: every line, the suggestion's and the painter's, as laid.
        public var lead: [[SIMD2<Float>]] {
            RefineGestures.drawingLines(of: trail.template, writing: false).map { $0.map { SIMD2(Float($0.x), Float($0.y)) } }
        }

        public var canUndo: Bool { !steps.isEmpty }

        /// Takes away the lead under `point` from junction to junction (Edit's Line Eraser's tap),
        /// within `reach` (canvas units). Whether there was lead there to take.
        @discardableResult
        public mutating func erase(at point: SIMD2<Float>, reach: Float) -> Bool {
            guard trail.lay(.eraseLine(at: point, reach: reach)).verdict.isMade else { return false }
            steps.append(.erase)
            return true
        }

        /// Takes back the painter's last step.
        public mutating func undo() throws {
            guard !steps.isEmpty else { return }
            try trail.move(to: Array(trail.edits.dropLast()))
            steps.removeLast()
        }

        /// The window as leaded so far, its paints the photo's under each piece.
        public var template: Template { trail.template }

        /// What a line made: the line as laid (its ends joined), the editor's verdict and the
        /// pieces it closed, new or cut smaller (none when it closed nothing).
        public struct Added: Sendable {
            public var line: [SIMD2<Float>]
            public var verdict: EditTrail.Verdict
            public var closed: [Int]
        }

        /// Lays `line` (canvas units). With a `reach`, each end within it of the lead laid so far,
        /// or of the frame, is joined to it (`PenAssist`, as the Pen joins).
        @discardableResult
        public mutating func add(_ line: [SIMD2<Float>], joining reach: Float? = nil) -> Added {
            guard line.count >= 2 else { return Added(line: line, verdict: .nothing, closed: []) }
            var line = line
            let before = trail.template
            if let reach, reach > 0 {
                let frame = CGRect(x: 0, y: 0, width: before.width, height: before.height)
                let lead = SnapLines(RefineGestures.drawingLines(of: before, writing: false), frame: frame)
                line = PenAssist.joined(line.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }, to: lead, reach: CGFloat(reach), straight: false)
                    .map { SIMD2(Float($0.x), Float($0.y)) }
            }
            let verdict = trail.lay(TemplateEditor.painted(.draw(points: line), on: before, photo: photo)).verdict
            let after = trail.template
            if verdict.isMade { steps.append(.line(line)) }
            guard after.regions.count > before.regions.count else {
                return Added(line: line, verdict: verdict, closed: [])
            }
            // A piece is closed by this line where its area isn't the area of the piece it was
            // part of: the new pieces, and the one they were cut from.
            var closed: [Int] = []
            for r in after.regions.indices {
                guard let at = after.labels(ofRegion: r).first?.position else { continue }
                let x = Int(at.x), y = Int(at.y)
                let wasArea = (0..<before.width).contains(x) && (0..<before.height).contains(y)
                    ? before.regions[Int(before.regionMap[x, y])].area : 0
                if after.regions[r].area != wasArea { closed.append(r) }
            }
            return Added(line: line, verdict: verdict, closed: closed)
        }

        /// The window with its glasses: the suggestion and its paints.
        public func window() -> Leaded {
            let suggestion = GlassPalette.suggest(for: trail.template, photo: photo)
            return Leaded(template: GlassPalette.glazed(trail.template, with: suggestion), suggestion: suggestion, verdicts: [])
        }
    }

    public struct Leaded: Sendable {
        public var template: Template
        public var suggestion: GlassPalette.Suggestion
        public var verdicts: [EditTrail.Verdict]
    }
}
