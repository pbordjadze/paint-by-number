/// The pixels within a few pixels of one, for "is there one of these within r of here?" asked at
/// a pixel. `DistanceTransform.squaredEDT` answers it for every pixel of the picture at once: far
/// more than a stage needs that asks along a few lines, or wants only yes or no near a wall. The
/// answer is the transform's own, `squaredEDT(...)[i] <= r²`: the transform is exact, its squared
/// distances sums of two squares, and an offset is here exactly when its sum is at most r².
struct Reach {
    /// (dx, dy) with dx² + dy² <= the squared radius, by rows.
    let offsets: [(dx: Int, dy: Int)]

    init(squaredRadius: Float) {
        var extent = 0
        while Float((extent + 1) * (extent + 1)) <= squaredRadius { extent += 1 }
        var offsets: [(dx: Int, dy: Int)] = []
        for dy in -extent...extent {
            for dx in -extent...extent where Float(dx * dx + dy * dy) <= squaredRadius { offsets.append((dx, dy)) }
        }
        self.offsets = offsets
    }

    /// Whether `isFeature` holds for a pixel within reach of (x, y) in a `width` x `height` picture.
    @inline(__always)
    func touches(x: Int, y: Int, width: Int, height: Int, _ isFeature: (_ x: Int, _ y: Int) -> Bool) -> Bool {
        for (dx, dy) in offsets {
            let xx = x + dx, yy = y + dy
            if xx >= 0 && yy >= 0 && xx < width && yy < height && isFeature(xx, yy) { return true }
        }
        return false
    }
}
