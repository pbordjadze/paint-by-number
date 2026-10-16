/// How to blend the show's layers at a moment: what the app's shader runs for every pixel, and
/// `Compositor.picture(at:ink:)` runs on the CPU. `stage` says which formulas (-1 the photo alone,
/// 0 to 5 the steps in order, 6 the finished drawing) and `time` is the t they are evaluated at.
public struct PictureRecipe: Sendable, Equatable {
    public var stage: Int
    public var time: Double
    /// 0...1, in stage 6: how far the real template has taken over from the finished drawing.
    public var handoff: Double
}

/// A spark at the tip of a burning line (the field show's ink step, `FieldShow`): a hot point that
/// cools as the fuse moves on. The view draws a filled circle at (`x`, `y`) of radius
/// `1.6 + 1.6 * heat` pixels in the ink color (`RevealStyle.ink`, 0...255) at `230 * heat / 255`
/// opacity, normally blended, over the picture and the seed rings (`draw_marks` in
/// `making_of_clip.py` does the same with Pillow).
public struct Spark: Sendable, Equatable {
    public var x: Double
    public var y: Double
    /// 1 as the fuse reaches the point, falling to 0 over `FieldShow.sparkLife` seconds (a spark is
    /// in a frame only while its heat is above 0).
    public var heat: Double
}

/// A faint ring that opens around a number as it comes out (the field show's last step,
/// `FieldShow`), growing and fading while the number fades in. The view draws a circle outline,
/// one pixel wide, at (`x`, `y`) of `radius` pixels in the ink color (`RevealStyle.ink`, 0...255)
/// at `alpha` opacity, normally blended, over the picture, the numbers and the seed rings
/// (`draw_marks` in `making_of_clip.py` does the same with Pillow).
public struct Star: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var radius: Double
    /// 0...1, falling to 0 over `FieldShow.starLife` seconds (a star is in a frame only while its
    /// alpha is above 0).
    public var alpha: Double
}

/// Everything to draw at one moment of the show, `Show.frame(at:)`'s answer (and
/// `FieldShow.frame(at:)`'s): plain numbers, from which the view executes the drawing. All places
/// are pixels of the working image (the pictures' own size, `Show.size`), origin top-left, y down:
/// the view scales them to fit.
///
/// The view draws, in this order:
///
/// 1. **The picture**: the layers blended as `picture` says, with the lines of `ink` darkening the
///    paper. Draw each line as a polyline `Show.lineWidth` pixels wide with round caps and joins,
///    coverage times the line's `value` (0 paper, 1 full ink), into one coverage plane where the
///    darker wins (a maximum, never a sum), and hand the plane to the shader.
///    `Show.composite` does exactly this on the CPU, for a view to be checked against.
/// 2. **The numbers**, from stage 5 on, in ink: number `i` of the template at its place and size
///    (`ShowTemplate.numbers`), as the painting screen draws it, at `numbers[i]` opacity.
/// 3. **The real template** over all of that at `picture.handoff` opacity, once the steps are over.
/// 4. **The seed rings** (`seedRings`, in the paints step), drawn as `SeedRing` says.
/// 5. **The sparks, then the stars** (`sparks`, `stars`: the field show's own, always empty in the
///    crew's), drawn as `Spark` and `Star` say.
/// 6. **The guardians** (`sprites`, back to front): each shadow, then its sprite. They may stand
///    below the picture, where the card is; the view decides whether to clip them.
/// 7. **The card** (`card`), in the band below the picture: the caption in New York, centered, and
///    under it the credit lines, smaller, at `footnoteOpacity`.
///
/// Reduce Motion needs nothing more than a few frames at chosen times: `frame(at:)` is a pure
/// function of the time.
public struct ShowFrame: Sendable, Equatable {
    public var time: Double
    /// The step playing, 0 to 5, or nil before the first and after the last.
    public var step: Int?
    public var picture: PictureRecipe
    /// The template's lines, drawn so far, in the ink step and after: their points, and the ink of
    /// each (0 paper, 1 full ink). `InkLine.stroke` indexes the template's strokes.
    public var ink: [InkLine]
    /// How much of each number of the template is in (0...1), in order; empty before the template step.
    public var numbers: [Double]
    public var seedRings: [SeedRing]
    /// The hot tips of the burning lines, in the field show's ink step; empty at any other time.
    public var sparks: [Spark]
    /// The rings opening round the numbers, in the field show's last step and the first moments of
    /// the hold; empty at any other time.
    public var stars: [Star]
    public var sprites: [SpriteDraw]
    public var card: CardDraw?
}
