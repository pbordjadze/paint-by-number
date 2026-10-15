/// A step's card: what the step does in a few plain words, and under it, smaller and fainter like
/// a footnote, the credit of each method it stands on (`ShowSpec.Step`). The card is the view's to
/// lay out; this is what it says and how opaque it is.
///
/// `methods` are names as `Acknowledgements` has them, exactly: the app looks each one up there
/// and prints its credit line letter for letter after the caption, numbered ¹ ² ³ in order, the
/// title in italics. (This module can't see `Acknowledgements`; `ShowSpecTests` checks every method
/// of the shipped spec names exactly one entry of `ACKNOWLEDGEMENTS.md`, which the app keeps in
/// step.) `making_of_clip.py`'s `Cards` is the factory's layout of the same.
///
/// Opacities are final: the view draws the caption at `opacity` and each credit line at
/// `footnoteOpacity`, ink on paper, with nothing more to multiply.
public struct CardDraw: Sendable, Equatable {
    /// The step it belongs to, 0 to 5.
    public var step: Int
    public var caption: String
    public var methods: [String]
    /// The caption's: the spec's `cards.opacity` times how far the card has faded in or out.
    public var opacity: Double
    /// The credit lines': `opacity` times the spec's `cards.footnote`.
    public var footnoteOpacity: Double

    public init(step: Int, caption: String, methods: [String], opacity: Double, footnoteOpacity: Double) {
        self.step = step
        self.caption = caption
        self.methods = methods
        self.opacity = opacity
        self.footnoteOpacity = footnoteOpacity
    }
}
