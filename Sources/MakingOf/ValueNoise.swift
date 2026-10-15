import PaintCore

/// A smooth random field made from random values on a coarse lattice, blended bilinearly with
/// smoothstep so no cell's edge shows. The picture spans exactly `cellsX` by `cellsY` cells.
/// `value_noise` in `making_of_reveal.py` is the same, bit for bit: it uses only `+ - *`.
public struct ValueNoise: Sendable {
    public let cellsX: Int
    public let cellsY: Int
    public let width: Int
    public let height: Int
    /// `cellsY + 1` rows of `cellsX + 1` values, row-major.
    public let lattice: [Double]
    private let columns: [Cut]
    private let rows: [Cut]

    /// Where a pixel's row or column falls in the lattice: the cell it is in, and how far across
    /// it, already eased.
    private struct Cut: Sendable {
        var cell: Int
        var blend: Double

        init(pixel: Int, of count: Int, cells: Int) {
            let at = Double(pixel) * (Double(cells) / Double(count))
            cell = truncated(at)
            let t = min(max(at - Double(cell), 0), 1)
            blend = t * t * (3 - 2 * t)
        }
    }

    /// The lattice's random values, one draw each in row-major order.
    public static func lattice(cellsX: Int, cellsY: Int, using rng: inout SplitMix64) -> [Double] {
        (0..<(cellsY + 1) * (cellsX + 1)).map { _ in rng.nextDouble() }
    }

    public init(lattice: [Double], cellsX: Int, cellsY: Int, width: Int, height: Int) {
        precondition(cellsX > 0 && cellsY > 0 && width > 0 && height > 0, "a field has cells and pixels")
        precondition(lattice.count == (cellsX + 1) * (cellsY + 1), "a lattice has (cells + 1) values each way")
        self.cellsX = cellsX
        self.cellsY = cellsY
        self.width = width
        self.height = height
        self.lattice = lattice
        columns = (0..<width).map { Cut(pixel: $0, of: width, cells: cellsX) }
        rows = (0..<height).map { Cut(pixel: $0, of: height, cells: cellsY) }
    }

    public init(cellsX: Int, cellsY: Int, width: Int, height: Int, using rng: inout SplitMix64) {
        self.init(
            lattice: Self.lattice(cellsX: cellsX, cellsY: cellsY, using: &rng),
            cellsX: cellsX, cellsY: cellsY, width: width, height: height)
    }

    /// The field at pixel (x, y), in [0, 1).
    public subscript(x: Int, y: Int) -> Double {
        let column = columns[x]
        let row = rows[y]
        let top = row.cell * (cellsX + 1) + column.cell
        let bottom = top + cellsX + 1
        let a = lattice[top], b = lattice[top + 1]
        let c = lattice[bottom], d = lattice[bottom + 1]
        return (a + (b - a) * column.blend) * (1 - row.blend) + (c + (d - c) * column.blend) * row.blend
    }

    public func plane() -> Plane<Double> {
        var data: [Double] = []
        data.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width { data.append(self[x, y]) }
        }
        return Plane(width: width, height: height, data: data)
    }
}

/// The roughness of one step's change, in seconds: a broad swell and a fine grain, each its own
/// lattice drawn from the show's `.noise` streams (`2k` for step k's broad one, `2k + 1` for its
/// fine one), so a step's roughness never depends on how the other steps drew theirs.
public struct StepNoise: Sendable {
    public let coarse: ValueNoise
    public let fine: ValueNoise
    private let coarseWeight: Double
    private let fineWeight: Double

    public init(step k: Int, width: Int, height: Int, streams: ShowStreams, style: ScheduleStyle = .standard) {
        var broad = streams.stream(.noise, 2 * k)
        var grain = streams.stream(.noise, 2 * k + 1)
        coarse = ValueNoise(cellsX: style.coarseCellsX, cellsY: style.coarseCellsY, width: width, height: height, using: &broad)
        fine = ValueNoise(cellsX: style.fineCellsX, cellsY: style.fineCellsY, width: width, height: height, using: &grain)
        coarseWeight = style.coarseNoise
        fineWeight = style.fineNoise
    }

    public subscript(x: Int, y: Int) -> Double {
        coarseWeight * coarse[x, y] + fineWeight * fine[x, y]
    }

    public func plane() -> Plane<Double> {
        var data: [Double] = []
        data.reserveCapacity(coarse.width * coarse.height)
        for y in 0..<coarse.height {
            for x in 0..<coarse.width { data.append(self[x, y]) }
        }
        return Plane(width: coarse.width, height: coarse.height, data: data)
    }
}
