import Foundation
import PaintCore

/// The words of Settings › Advanced: values, effects and the names and one-line explanations
/// of every setting.
nonisolated enum AdvancedText {
    static func onOff(_ on: Bool) -> String {
        on ? String(localized: "advanced.value.on", defaultValue: "On",
                    comment: "Settings › Advanced: value of a switch that is on, in shared settings text and VoiceOver")
            : String(localized: "advanced.value.off", defaultValue: "Off",
                     comment: "Settings › Advanced: value of a switch that is off, in shared settings text and VoiceOver")
    }

    /// Line Appearance's switch for weighting lines within a layer by their edge's strength.
    static var weightTitle: String {
        String(localized: "advanced.appearance.weighted", defaultValue: "Weight by Edge Strength",
               comment: "Settings › Advanced › Line Appearance: switch that draws stronger edges heavier within each layer")
    }

    /// Line Appearance's slider for how heavy a coloring book's lines are.
    static var coloringBookWeightTitle: String {
        String(localized: "advanced.appearance.bookWeight", defaultValue: "Line Weight",
               comment: "Settings › Advanced › Line Appearance: slider for how heavy a coloring book's lines are drawn")
    }

    static var coloringBookWeightSummary: String {
        String(localized: "advanced.appearance.bookWeight.summary",
               defaultValue: "How heavy the drawing’s lines are, at every zoom. Coloring books draw every line alike, in full ink, over the paint.",
               comment: "Settings › Advanced › Line Appearance: explanation under the Line Weight slider of a coloring book")
    }

    /// "8 px": a length in pixels of the image the template is made at.
    static func pixels(_ count: Int) -> String {
        String(localized: "advanced.value.pixels", defaultValue: "\(count) px",
               comment: "Settings › Advanced: a length in pixels, e.g. 8 px; the argument is the number of pixels")
    }

    /// "1.5×", "0.25×", "1×".
    static func multiplier(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: "advanced.value.multiplier", defaultValue: "\(number)×",
                      comment: "Settings › Advanced: a multiplier or zoom, e.g. 1.5×; the argument is the formatted number")
    }

    /// "2×": one of the preview's zoom levels.
    static func zoom(_ level: Int) -> String {
        String(localized: "advanced.zoom", defaultValue: "\(level)×",
               comment: "Settings › Advanced: a zoom level of the preview, relative to the whole picture in view, e.g. 2×; the argument is the level")
    }

    /// "+212", "−85".
    static func signed(_ value: Int) -> String {
        signed(abs(value).formatted(), positive: value > 0)
    }

    /// "+10 min", "−1 h 5 min".
    static func signedDuration(_ seconds: TimeInterval) -> String {
        signed(PaintingTime.spent(abs(seconds)), positive: seconds > 0)
    }

    private static func signed(_ text: String, positive: Bool) -> String {
        positive
            ? String(localized: "advanced.delta.plus", defaultValue: "+\(text)",
                     comment: "Settings › Advanced: an increase over the default settings, e.g. +212 or +10 min; the argument is the amount")
            : String(localized: "advanced.delta.minus", defaultValue: "−\(text)",
                     comment: "Settings › Advanced: a decrease from the default settings, e.g. −85 or −5 min; the argument is the amount")
    }

    /// What a change does to the painting: "+212 areas · about 10 min longer".
    static func effect(_ delta: AdvancedStats.Delta) -> String {
        var parts: [String] = []
        let areas = abs(delta.areas)
        if delta.areas > 0 {
            parts.append(String(localized: "advanced.effect.areas.more", defaultValue: "+\(areas) areas",
                                comment: "Settings › Advanced: a setting's effect, more areas to paint; the argument is how many more"))
        } else if delta.areas < 0 {
            parts.append(String(localized: "advanced.effect.areas.fewer", defaultValue: "−\(areas) areas",
                                comment: "Settings › Advanced: a setting's effect, fewer areas to paint; the argument is how many fewer"))
        }
        let colors = abs(delta.colors)
        if delta.colors > 0 {
            parts.append(String(localized: "advanced.effect.colors.more", defaultValue: "+\(colors) colors",
                                comment: "Settings › Advanced: a setting's effect, more paints; the argument is how many more"))
        } else if delta.colors < 0 {
            parts.append(String(localized: "advanced.effect.colors.fewer", defaultValue: "−\(colors) colors",
                                comment: "Settings › Advanced: a setting's effect, fewer paints; the argument is how many fewer"))
        }
        if let change = delta.lines, change != 0 {
            let lines = abs(change)
            parts.append(change > 0
                ? String(localized: "advanced.effect.lines.more", defaultValue: "+\(lines) lines",
                         comment: "Settings › Advanced: a setting's effect, more drawn lines; the argument is how many more")
                : String(localized: "advanced.effect.lines.fewer", defaultValue: "−\(lines) lines",
                         comment: "Settings › Advanced: a setting's effect, fewer drawn lines; the argument is how many fewer"))
        }
        let minutes = Int((abs(delta.seconds) / 60).rounded())
        if minutes >= 1 {
            let duration = PaintingTime.spent(Double(minutes) * 60)
            parts.append(delta.seconds > 0
                ? String(localized: "advanced.effect.longer", defaultValue: "about \(duration) longer",
                         comment: "Settings › Advanced: a setting's effect on the estimated painting time; the argument is a duration such as 10 min")
                : String(localized: "advanced.effect.shorter", defaultValue: "about \(duration) shorter",
                         comment: "Settings › Advanced: a setting's effect on the estimated painting time; the argument is a duration such as 10 min"))
        }
        guard let first = parts.first else {
            return String(localized: "advanced.effect.none", defaultValue: "No change to areas or colors",
                          comment: "Settings › Advanced: a changed setting that leaves the preview's areas and colors as they were")
        }
        return parts.dropFirst().reduce(first) { joined, part in
            String(localized: "advanced.effect.join", defaultValue: "\(joined) · \(part)",
                   comment: "Settings › Advanced: joins the parts of a setting's effect, e.g. +212 areas · about 10 min longer; the arguments are the text so far and the next part")
        }
    }

    /// The zoom from which a layer's lines read clearly (half opacity or more), for the Line
    /// Appearance editor.
    static func clarity(of layer: LineAppearance.Layer) -> String {
        let threshold: Float = 0.5
        if layer.opacity(atZoom: 4) < 0.05 {
            return String(localized: "advanced.appearance.hidden", defaultValue: "Hidden at every zoom",
                          comment: "Settings › Advanced › Line Appearance: the selected layer's lines are never visible")
        }
        if layer.opacity(atZoom: 1) >= threshold {
            return String(localized: "advanced.appearance.clearAlways", defaultValue: "Clear in the full view",
                          comment: "Settings › Advanced › Line Appearance: the selected layer's lines read clearly with the whole picture in view")
        }
        guard layer.opacity(atZoom: 4) >= threshold else {
            return String(localized: "advanced.appearance.faint", defaultValue: "Faint even at 4×",
                          comment: "Settings › Advanced › Line Appearance: the selected layer's lines stay faint at the closest zoom the editor sets")
        }
        // Opacity is piecewise linear in log₂ of the zoom: find where it crosses the threshold.
        var zoom: Float = 4
        for step in 0..<2 {
            let a = layer.opacity[step], b = layer.opacity[step + 1]
            if a < threshold, b >= threshold {
                zoom = exp2(Float(step) + (threshold - a) / (b - a))
                break
            }
        }
        let text = multiplier((Double(zoom) * 10).rounded() / 10)
        return String(localized: "advanced.appearance.clearFrom", defaultValue: "Clear from about \(text)",
                      comment: "Settings › Advanced › Line Appearance: the zoom from which the selected layer's lines read clearly; the argument is a zoom such as 2.4×")
    }
}

nonisolated extension AdvancedControl {
    var title: String {
        switch self {
        case .style:
            String(localized: "advanced.control.style", defaultValue: "Line Style",
                   comment: "Settings › Advanced › Line Art: name of the choice between Classic and Layered lines")
        case .outlineThreshold:
            String(localized: "advanced.control.outlineThreshold", defaultValue: "Outlines From",
                   comment: "Settings › Advanced › Line Art: slider for the edge strength from which a line is an outline")
        case .detailThreshold:
            String(localized: "advanced.control.detailThreshold", defaultValue: "Detail From",
                   comment: "Settings › Advanced › Line Art: slider for the edge strength from which a line is a detail line")
        case .textureThreshold:
            String(localized: "advanced.control.textureThreshold", defaultValue: "Texture From",
                   comment: "Settings › Advanced › Line Art: slider for the edge strength from which a line is drawn at all (as texture)")
        case .minimumStrokeLength:
            String(localized: "advanced.control.minimumStrokeLength", defaultValue: "Shortest Line",
                   comment: "Settings › Advanced › Line Art: slider for the length below which lines are left out")
        case .gapBridging:
            String(localized: "advanced.control.gapBridging", defaultValue: "Gap Closing",
                   comment: "Settings › Advanced › Line Art: slider for how far apart line ends may be and still be joined")
        case .lineSmoothing:
            String(localized: "advanced.control.lineSmoothing", defaultValue: "Line Smoothing",
                   comment: "Settings › Advanced › Line Art: slider for how much lines are smoothed into curves")
        case .samePaint:
            String(localized: "advanced.control.samePaint", defaultValue: "Same Paint Across a Line",
                   comment: "Settings › Advanced › Line Art: choice of what happens where a line runs between two areas of the same paint")
        case .keepColorEdges:
            String(localized: "advanced.control.keepColorEdges", defaultValue: "Keep Color Edges",
                   comment: "Settings › Advanced › Line Art: switch that keeps boundaries where only the paint changes as faint lines")
        case .outlineEyes:
            String(localized: "advanced.control.outlineEyes", defaultValue: "Outline Eyes",
                   comment: "Settings › Advanced › Line Art: switch that draws detected eyes as outlines")
        case .smoothing:
            String(localized: "advanced.control.smoothing", defaultValue: "Smoothing",
                   comment: "Settings › Advanced › Pipeline: multiplier on how much the photo is smoothed before paints are picked")
        case .textureFlattening:
            String(localized: "advanced.control.textureFlattening", defaultValue: "Texture Flattening",
                   comment: "Settings › Advanced › Pipeline: multiplier on how much fine texture is smoothed away")
        case .minimumCellSize:
            String(localized: "advanced.control.minimumCellSize", defaultValue: "Smallest Area",
                   comment: "Settings › Advanced › Pipeline: multiplier on the smallest area a template keeps")
        case .subjectEmphasis:
            String(localized: "advanced.control.subjectEmphasis", defaultValue: "Subject Emphasis",
                   comment: "Settings › Advanced › Pipeline: multiplier on how strongly the subject gets more paints and detail")
        case .accentColors:
            String(localized: "advanced.control.accentColors", defaultValue: "Accent Colors",
                   comment: "Settings › Advanced › Pipeline: multiplier on how readily small, distinctive colors get their own paint")
        case .colorfulness:
            String(localized: "advanced.control.colorfulness", defaultValue: "Colorfulness",
                   comment: "Settings › Advanced › Pipeline: multiplier on how much hue counts against lightness when telling paints apart")
        }
    }

    /// The setting's name under `style`: a coloring book, which draws every line at or above
    /// the detail threshold alike, calls that threshold Lines From.
    func title(for style: LineArtSettings.Style) -> String {
        guard style == .coloringBook, self == .detailThreshold else { return title }
        return String(localized: "advanced.control.detailThreshold.book", defaultValue: "Lines From",
                      comment: "Settings › Advanced › Line Art, Coloring Book: slider for the edge strength from which a line is drawn")
    }

    /// One line on what the setting does under `style` (a coloring book has no faint lines and
    /// never draws color edges, so some settings mean something else there).
    func summary(for style: LineArtSettings.Style) -> String {
        guard style == .coloringBook else { return summary }
        switch self {
        case .outlineThreshold:
            return String(localized: "advanced.control.outlineThreshold.summary.book",
                          defaultValue: "Edges at least this strong are outlines, which reach further to close an area.",
                          comment: "Settings › Advanced › Line Art, Coloring Book: explanation under the Outlines From slider")
        case .detailThreshold:
            return String(localized: "advanced.control.detailThreshold.summary.book",
                          defaultValue: "Edges at least this strong are drawn; weaker ones are left out. Lower draws more lines.",
                          comment: "Settings › Advanced › Line Art, Coloring Book: explanation under the Lines From slider")
        case .keepColorEdges:
            return String(localized: "advanced.control.keepColorEdges.summary.book",
                          defaultValue: "Keeps the paints inside an outline as separate areas, told apart by their numbers. Off merges close paints for fewer areas.",
                          comment: "Settings › Advanced › Line Art, Coloring Book: explanation under the Keep Color Edges switch")
        default:
            return summary
        }
    }

    /// One line on what the setting does (for the line style and same-paint choices, see
    /// their options' summaries).
    var summary: String {
        switch self {
        case .style:
            String(localized: "advanced.control.style.summary", defaultValue: "How the template’s lines are made.",
                   comment: "Settings › Advanced › Line Art: explanation under the Line Style choice")
        case .outlineThreshold:
            String(localized: "advanced.control.outlineThreshold.summary",
                   defaultValue: "Edges at least this strong become outlines, always drawn at full strength.",
                   comment: "Settings › Advanced › Line Art: explanation under the Outlines From slider")
        case .detailThreshold:
            String(localized: "advanced.control.detailThreshold.summary",
                   defaultValue: "Weaker edges, down to this strength, become detail lines: lighter when zoomed out.",
                   comment: "Settings › Advanced › Line Art: explanation under the Detail From slider")
        case .textureThreshold:
            String(localized: "advanced.control.textureThreshold.summary",
                   defaultValue: "The faintest edges drawn at all. Lower draws more texture lines.",
                   comment: "Settings › Advanced › Line Art: explanation under the Texture From slider")
        case .minimumStrokeLength:
            String(localized: "advanced.control.minimumStrokeLength.summary",
                   defaultValue: "Lines shorter than this are left out, so specks don’t turn into areas.",
                   comment: "Settings › Advanced › Line Art: explanation under the Shortest Line slider")
        case .gapBridging:
            String(localized: "advanced.control.gapBridging.summary",
                   defaultValue: "Line ends closer than this are joined, closing small gaps in outlines.",
                   comment: "Settings › Advanced › Line Art: explanation under the Gap Closing slider")
        case .lineSmoothing:
            String(localized: "advanced.control.lineSmoothing.summary",
                   defaultValue: "Higher smooths lines into flowing curves; lower follows the drawing closely.",
                   comment: "Settings › Advanced › Line Art: explanation under the Line Smoothing slider")
        case .samePaint:
            String(localized: "advanced.control.samePaint.summary",
                   defaultValue: "Whether a line between two areas of the same paint keeps them apart.",
                   comment: "Settings › Advanced › Line Art: explanation of the Same Paint Across a Line choice")
        case .keepColorEdges:
            String(localized: "advanced.control.keepColorEdges.summary",
                   defaultValue: "Keeps boundaries where only the paint changes, like banded skies, as faint lines. Off merges close paints for a calmer plan.",
                   comment: "Settings › Advanced › Line Art: explanation under the Keep Color Edges switch")
        case .outlineEyes:
            String(localized: "advanced.control.outlineEyes.summary",
                   defaultValue: "Draws the eyes of faces in the picture as outlines, however soft they are.",
                   comment: "Settings › Advanced › Line Art: explanation under the Outline Eyes switch")
        case .smoothing:
            String(localized: "advanced.control.smoothing.summary",
                   defaultValue: "How much the photo is smoothed before paints are picked. Higher melts texture into flat areas.",
                   comment: "Settings › Advanced › Pipeline: explanation under the Smoothing slider")
        case .textureFlattening:
            String(localized: "advanced.control.textureFlattening.summary",
                   defaultValue: "How much fine texture, like grass or fabric, is smoothed away while edges stay.",
                   comment: "Settings › Advanced › Pipeline: explanation under the Texture Flattening slider")
        case .minimumCellSize:
            String(localized: "advanced.control.minimumCellSize.summary",
                   defaultValue: "The smallest area a template keeps. Higher gives fewer, larger areas.",
                   comment: "Settings › Advanced › Pipeline: explanation under the Smallest Area slider")
        case .subjectEmphasis:
            String(localized: "advanced.control.subjectEmphasis.summary",
                   defaultValue: "How strongly faces, animals and the subject get extra paints and detail.",
                   comment: "Settings › Advanced › Pipeline: explanation under the Subject Emphasis slider")
        case .accentColors:
            String(localized: "advanced.control.accentColors.summary",
                   defaultValue: "How readily small, distinctive colors get a paint of their own.",
                   comment: "Settings › Advanced › Pipeline: explanation under the Accent Colors slider")
        case .colorfulness:
            String(localized: "advanced.control.colorfulness.summary",
                   defaultValue: "How much hue counts against lightness when paints are told apart.",
                   comment: "Settings › Advanced › Pipeline: explanation under the Colorfulness slider")
        }
    }
}

nonisolated extension LineArtSettings.Style {
    var name: String {
        switch self {
        case .classic: String(localized: "advanced.style.classic", defaultValue: "Classic",
                              comment: "Settings › Advanced › Line Art: the original line style, every boundary one even line")
        case .layered: String(localized: "advanced.style.layered", defaultValue: "Layered",
                              comment: "Settings › Advanced › Line Art: the line style that follows a drawing of the picture, with lines in layers that fade in as you zoom")
        case .coloringBook: String(localized: "advanced.style.coloringBook", defaultValue: "Coloring Book",
                                   comment: "Settings › Advanced › Line Art: the line style that draws the picture's outlines in thick ink, with the paints inside an outline told apart only by their numbers")
        }
    }

    var summary: String {
        switch self {
        case .classic: String(localized: "advanced.style.classic.summary",
                              defaultValue: "Every boundary between areas is the same even line.",
                              comment: "Settings › Advanced › Line Art: what the Classic line style does")
        case .layered: String(localized: "advanced.style.layered.summary",
                              defaultValue: "Lines follow a drawing of the picture: outlines stay strong, finer lines come in as you zoom.",
                              comment: "Settings › Advanced › Line Art: what the Layered line style does")
        case .coloringBook: String(localized: "advanced.style.coloringBook.summary",
                                   defaultValue: "A drawing in thick ink that stays over the paint. Inside an outline, only the numbers tell the paints apart.",
                                   comment: "Settings › Advanced › Line Art: what the Coloring Book line style does")
        }
    }
}

nonisolated extension LineArtSettings.SamePaint {
    var name: String {
        switch self {
        case .split: String(localized: "advanced.samePaint.split", defaultValue: "Always Split",
                            comment: "Settings › Advanced › Line Art: Same Paint Across a Line option, every line separates areas")
        case .joinTexture: String(localized: "advanced.samePaint.joinTexture", defaultValue: "Join Across Texture",
                                  comment: "Settings › Advanced › Line Art: Same Paint Across a Line option, areas split only by texture lines are joined")
        case .joinAllButOutlines: String(localized: "advanced.samePaint.joinAllButOutlines", defaultValue: "Join Across Detail",
                                         comment: "Settings › Advanced › Line Art: Same Paint Across a Line option, only outlines split areas of one paint")
        }
    }

    /// The option's name under `style`: a coloring book has no texture lines, so joining across
    /// them is splitting.
    func name(in style: LineArtSettings.Style) -> String {
        style == .coloringBook && self == .joinTexture ? Self.split.name : name
    }

    var summary: String {
        switch self {
        case .split: String(localized: "advanced.samePaint.split.summary",
                            defaultValue: "Every line separates areas, even where both sides take the same paint.",
                            comment: "Settings › Advanced › Line Art: what the Always Split option does")
        case .joinTexture: String(localized: "advanced.samePaint.joinTexture.summary",
                                  defaultValue: "Areas of one paint split only by texture lines become one area; the line is still drawn.",
                                  comment: "Settings › Advanced › Line Art: what the Join Across Texture option does")
        case .joinAllButOutlines: String(localized: "advanced.samePaint.joinAllButOutlines.summary",
                                         defaultValue: "Only outlines split areas of one paint; detail and texture lines are drawn inside them.",
                                         comment: "Settings › Advanced › Line Art: what the Join Across Detail option does")
        }
    }

    func summary(in style: LineArtSettings.Style) -> String {
        guard style == .coloringBook else { return summary }
        switch self {
        case .split, .joinTexture:
            return Self.split.summary
        case .joinAllButOutlines:
            return String(localized: "advanced.samePaint.joinAllButOutlines.summary.book",
                          defaultValue: "Only outlines split areas of one paint; other lines are drawn across them.",
                          comment: "Settings › Advanced › Line Art, Coloring Book: what the Join Across Detail option does")
        }
    }
}

nonisolated extension LineLayer {
    var name: String {
        switch self {
        case .outline: String(localized: "advanced.layer.outline", defaultValue: "Outlines",
                              comment: "Settings › Advanced: the layer of the strongest lines, always at full strength")
        case .detail: String(localized: "advanced.layer.detail", defaultValue: "Detail",
                             comment: "Settings › Advanced: the layer of weaker lines, lighter when zoomed out")
        case .texture: String(localized: "advanced.layer.texture", defaultValue: "Texture",
                              comment: "Settings › Advanced: the layer of the faintest drawn lines")
        case .color: String(localized: "advanced.layer.color", defaultValue: "Color Edges",
                            comment: "Settings › Advanced: the layer of boundaries where only the paint changes")
        }
    }
}

nonisolated extension LineAppearancePreset {
    var name: String {
        switch self {
        case .fade: String(localized: "advanced.preset.fade", defaultValue: "Fade",
                           comment: "Settings › Advanced › Line Appearance: preset where fainter lines fade in as you zoom")
        case .grow: String(localized: "advanced.preset.grow", defaultValue: "Grow",
                           comment: "Settings › Advanced › Line Appearance: preset where fainter lines grow thicker as you zoom")
        case .even: String(localized: "advanced.preset.even", defaultValue: "Even",
                           comment: "Settings › Advanced › Line Appearance: preset where every line is drawn alike")
        }
    }

    var summary: String {
        switch self {
        case .fade: String(localized: "advanced.preset.fade.summary", defaultValue: "Fainter lines fade in as you zoom.",
                           comment: "Settings › Advanced › Line Appearance: what the Fade preset does")
        case .grow: String(localized: "advanced.preset.grow.summary", defaultValue: "Fainter lines start thin and grow as you zoom.",
                           comment: "Settings › Advanced › Line Appearance: what the Grow preset does")
        case .even: String(localized: "advanced.preset.even.summary", defaultValue: "Every line is drawn alike, like Classic.",
                           comment: "Settings › Advanced › Line Appearance: what the Even preset does")
        }
    }
}
