/// The draft photo at the working size the candidates are segmented at, with what analysis
/// and scoring read from it: the pipeline's own OKLab (chroma stretched) and importance
/// weights, so Auto measures what the pipeline sees.
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

    /// An image already at its working size. The fields read here (chroma scale, structure
    /// radius, histogram knobs, seed) depend only on the size, not on the settings.
    init(working: RGBAImage, importance: Grid<Float>?, cancel: CancellationCheck) throws {
        image = working
        parameters = SegmentationParameters(settings: GenerationSettings(), width: working.width, height: working.height)
        lab = try WorkingImage.okLab(image, chromaScale: parameters.chromaScale, cancel: cancel)
        let structure = try StructureMap(lab, radius: parameters.structureRadius, cancel: cancel)
        weights = try ImportanceMap.make(importance, structure: structure, cancel: cancel)
    }
}
