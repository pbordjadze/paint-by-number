/// What Auto's score values in a candidate (`AutoSettings.choose`'s `taste`). Decisions are
/// never stored, so a taste changes suggestions from now on and no painting.
public enum AutoTaste: String, Sendable, Hashable, Codable, CaseIterable {
    /// Fidelity to the photo: the colour error (ΔE) and its 95th percentile, with prices for
    /// rings, crumbs, paints and a painting time outside the length's band; a tie goes to the
    /// time nearest the band's middle. Every suggestion before the finished taste.
    case fidelity
    /// The painting as it will be finished (painting-company row 191): the colour error
    /// counts half (`fidelityShare`; the paints are a kit's, bolder than the regions' means,
    /// and a loosened subject is meant to lose detail), a time under the band costs nothing
    /// (fewer, larger areas are what a calmer painting is, and the band's floor bought detail
    /// back), crumbs on the subject cost three times what crumbs elsewhere do
    /// (`subjectCrumbWeight`), and a tie goes to the fewest regions.
    case finished

    /// The share of the colour error terms the finished taste keeps. At a half, the tie margin
    /// (`AutoSettings.tieMargin`, 0.006) spans twice the ΔE, about what one detail step buys on
    /// a loosened subject.
    static let fidelityShare: Float = 0.5
    /// Price of the share of regions that are crumbs on the subject (`AutoSettings.tinyRadius`),
    /// on top of `AutoSettings.tinyWeight`.
    static let subjectCrumbWeight: Float = 0.03
    /// A crumb whose number sits at this importance or more is on the subject (the app's map
    /// puts the subject at 0.75 and faces near 1, the background at 0.25 to 0.6).
    static let subjectImportance: Float = 0.7
}
