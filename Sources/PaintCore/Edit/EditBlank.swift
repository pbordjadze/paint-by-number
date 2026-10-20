import Foundation

extension TemplateEditor {
    /// Refine's Blank start: the photo as one area, which the painter cuts with the Pen, each
    /// piece a line closes off taking the photo's color there (a draw with paints, `painted`).
    /// A coloring book with nothing drawn and no strokes: one region over the `width` × `height`
    /// canvas (the working size the generator would make of the photo,
    /// `GenerationSettings.workingSize`), its ring the canvas frame, one closed edge from the
    /// top-left corner, undrawn (`LineLayer.color`) and, as every frame, ink a line's end joins;
    /// one paint, the photo's color over the area (`LineEdit.photoColor(ofRegion:in:image:)`,
    /// white for a photo with no pixels); its number where the editor puts a piece's
    /// (`labelPlan`), its fill triangulated and every pixel of `regionMap` its own, all laid out
    /// by the editor's own `finish`, so it is a template an edit could have left. It validates
    /// (`Template.validate(minLabelRadius:)`), records `TemplateGenerator.pipelineVersion`, and
    /// the same inputs give the same bytes. A canvas too thin for the usual number makes the area
    /// a detail area; one the editor cannot work on, or too thin for even a detail area's number,
    /// throws `Failure.unsupported`.
    public static func blank(width: Int, height: Int, photo: RGBAImage, colorSpace: RGBColorSpace) throws -> Template {
        guard width > 0, height > 0, width <= Lattice.maximumCanvas, height <= Lattice.maximumCanvas else {
            throw Failure.unsupported("canvas size")
        }
        let w = Float(width), h = Float(height)
        let frame: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(w, 0), SIMD2(w, h), SIMD2(0, h), SIMD2(0, 0)]
        var seed = Template(
            width: width, height: height, colorSpace: colorSpace, palette: [],
            regions: [Region(
                colorIndex: 0, area: w * h, bounds: PixelBounds(minX: 0, minY: 0, maxX: Int32(width), maxY: Int32(height)),
                inscribedRadius: 0, ringCount: 1)],
            points: frame, edges: [BoundaryEdge(left: 0, right: BoundaryEdge.outside, pointStart: 0, pointCount: UInt32(frame.count))],
            ringEdges: [EdgeRef(edge: 0, reversed: false)], rings: [Ring(edgeStart: 0, edgeCount: 1, isHole: false)],
            labels: [], mesh: FillMesh(), regionMap: RegionMap(width: width, height: height, repeating: 0),
            pipelineVersion: TemplateGenerator.pipelineVersion,
            lineArt: TemplateLineArt(edgeLayers: [LineLayer.color.rawValue], edgeWeights: [0], style: .coloringBook))
        let color = LineEdit.photoColor(ofRegion: 0, in: seed, image: photo) ?? SIMD3(1, 0, 0)
        seed.palette = [PaletteColor(oklab: color, space: colorSpace)]
        do {
            var work = try EditWork(seed)
            guard let plan = work.labelPlan(rings: work.polygons(of: 0), color: 0, detail: false, hints: [], region: 0, keepOut: [])
            else { throw Failure.unsupported("the canvas has no room for a number") }
            work.labels[0] = plan.labels
            work.regionDetail[0] = plan.needsDetail
            work.remesh.insert(0)
            return try work.finish().template
        } catch let failure as EditFailure {
            throw Failure.unsupported("\(failure)")
        }
    }
}
