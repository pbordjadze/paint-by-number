import Metal

/// How a mode draws a painting on the canvas, in place of the painting's own look
/// (painting-company row 366: the canvas hosts every mode, so each later one is cheap). Without
/// a mode (`RenderContext.Content.mode` nil) a frame is drawn exactly as it always was; a mode
/// changes only what it supplies:
///
/// - `prepare`: work encoded before the frame's passes, such as a compute pass over state the
///   mode keeps across frames (a wash still drying, sand settling);
/// - `drawPaint`: the paint, in place of the fills, inside the sheet: from the region states
///   (`RegionState.mode` carries a value of the mode's own per region), or a layer the mode
///   draws whole (paint that bleeds past its outline);
/// - `drawOver`: light over the finished picture, before the brush;
/// - whether the canvas's own outlines and numbers still show, and whether the mode still moves
///   with nothing touched (`isAnimating`), so the canvas keeps drawing frames.
///
/// A mode is made off the main actor and used from Metal's encoding: it is immutable after it is
/// made, or guards what it changes.
nonisolated protocol CanvasMode: AnyObject, Sendable {
    /// The backdrop around the sheet (linear Display P3), nil for the painting's own.
    var backdrop: SIMD3<Float>? { get }
    var drawsOutlines: Bool { get }
    var drawsNumbers: Bool { get }
    /// The numbers' ink (linear Display P3), nil for the paper's.
    var ink: SIMD3<Float>? { get }
    /// Whether the canvas draws this mode past white where the screen can (`ExtendedRange`):
    /// its layer then takes `RenderContext.extendedFormat`, and `CanvasModeFrame.headroom` says
    /// how far past white the mode may go.
    var wantsExtendedRange: Bool { get }
    func prepare(_ commands: any MTLCommandBuffer, frame: CanvasModeFrame)
    func drawPaint(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame)
    func drawOver(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame)
    func isAnimating(at time: Float) -> Bool
}

nonisolated extension CanvasMode {
    var backdrop: SIMD3<Float>? { nil }
    var ink: SIMD3<Float>? { nil }
    var wantsExtendedRange: Bool { false }
    func prepare(_ commands: any MTLCommandBuffer, frame: CanvasModeFrame) {}
    func drawOver(_ encoder: any MTLRenderCommandEncoder, frame: CanvasModeFrame) {}
    func isAnimating(at time: Float) -> Bool { false }
}

/// What a mode draws a frame from: the template's buffers, this frame's region states and the
/// frame's uniforms (`frame.uniforms` is a copy to bind with `setVertexBytes`), the target's pixel
/// format (its pipelines' `format`) and how many times brighter than white the screen can show
/// (1 but on a canvas drawing past white).
nonisolated struct CanvasModeFrame {
    let context: RenderContext
    let scene: CanvasScene
    let states: any MTLBuffer
    var uniforms: CanvasUniforms
    var format: MTLPixelFormat = RenderContext.colorFormat
    var headroom: Float = 1
}

/// A mode that takes the canvas's touches (`CanvasView.touches`) and shows what they do through
/// `CanvasView.showMode`: a tap, or a stroke from `began` through `moved` to `ended`, at a point
/// in canvas units.
protocol CanvasTouches: AnyObject {
    /// Whether the touch changed the picture: a tap that changed nothing may be the first of a
    /// double tap, which zooms.
    @discardableResult
    func canvas(_ canvas: CanvasView, touched point: SIMD2<Float>, phase: CanvasTouchPhase) -> Bool
    /// What VoiceOver says of `region`: the canvas offers each region in view as a button (its
    /// frames follow the camera), and activating one taps it at its anchor.
    func canvas(_ canvas: CanvasView, speak region: Int) -> (label: String, value: String)
    /// The canvas's own VoiceOver label and value while a mode has its touches.
    func canvasSummary(_ canvas: CanvasView) -> (label: String, value: String)
    /// Whether one finger draws a stroke at once, a flick too, and two move the picture: a mode
    /// that draws with the finger (Stained Glass's lead). False, one finger moves the picture and
    /// a stroke begins only after the finger rests (the painting's drag paint).
    var strokesWithOneFinger: Bool { get }
}

extension CanvasTouches {
    var strokesWithOneFinger: Bool { false }
}

enum CanvasTouchPhase { case tap, began, moved, ended }
