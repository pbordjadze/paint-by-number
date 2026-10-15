/// A picture or field of the show, row-major from the top-left, at the pipeline snapshots' own size
/// (`PipelineSnapshot`): the show computes there and leaves scaling to the renderer, so nothing it
/// decides depends on a resampler.
public struct Plane<Element: Sendable>: Sendable {
    public let width: Int
    public let height: Int
    public var data: [Element]

    public init(width: Int, height: Int, data: [Element]) {
        precondition(width >= 0 && height >= 0 && data.count == width * height, "a plane's data is width x height")
        self.width = width
        self.height = height
        self.data = data
    }

    public init(width: Int, height: Int, repeating value: Element) {
        self.init(width: width, height: height, data: Array(repeating: value, count: max(width, 0) * max(height, 0)))
    }

    public subscript(x: Int, y: Int) -> Element {
        get { data[y * width + x] }
        set { data[y * width + x] = newValue }
    }
}

extension Plane: Equatable where Element: Equatable {}
