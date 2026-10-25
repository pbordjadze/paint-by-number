/// The draft photo at the working size the candidates are segmented at, with what analysis
/// and scoring read from it: the pipeline's own OKLab (chroma stretched) and importance
/// weights, so Auto measures what the pipeline sees at the default settings.
struct AutoWorking {
    let image: RGBAImage
    let parameters: SegmentationParameters
    let lab: Grid<SIMD4<Float>>
    let weights: [Float]

    /// The draft enlarged (or reduced) to the working size `settings` give it, as the
    /// generator does.
    init(draft: RGBAImage, settings: GenerationSettings, importance: Grid<Float>?, cancel: CancellationCheck) throws {
        let size = settings.workingSize(sourceWidth: draft.width, sourceHeight: draft.height)
        try self.init(
            working: Resample.area(draft, width: size.width, height: size.height, cancel: cancel), importance: importance,
            cancel: cancel)
    }

    /// An image already at its working size. `parameters` are the default settings' at that
    /// size, whatever the candidate's: the structure radius follows the size alone and the
    /// histogram's gamma is fixed, but the chroma scale and palette saliency are untuned and the
    /// seed is the default's, so a candidate's `tuning` or `seed` doesn't reach what Auto reads
    /// here (`PhotoAnalyzer`, the palette curve, `score`'s importance weights).
    init(working: RGBAImage, importance: Grid<Float>?, cancel: CancellationCheck) throws {
        image = working
        parameters = SegmentationParameters(settings: GenerationSettings(), width: working.width, height: working.height)
        lab = try WorkingImage.okLab(image, chromaScale: parameters.chromaScale, cancel: cancel)
        let structure = try StructureMap(lab, radius: parameters.structureRadius, cancel: cancel)
        weights = try ImportanceMap.make(importance, structure: structure, cancel: cancel)
    }
}
