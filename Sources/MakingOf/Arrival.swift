/// When a step's change reaches each region of the picture, from when it reaches each pixel
/// (`FieldSteps` makes those fields). `region_min` in `making_of_reveal.py` is the reference.
public enum Arrival {
    /// The earliest time in each of the `count` regions of `labels` (infinity for an empty one).
    public static func regionMinimum(_ times: Plane<Double>, labels: Plane<Int32>, count: Int) -> [Double] {
        precondition(times.width == labels.width && times.height == labels.height, "a time for every label")
        var minima = [Double](repeating: .infinity, count: count)
        for (time, label) in zip(times.data, labels.data) where time < minima[Int(label)] {
            minima[Int(label)] = time
        }
        return minima
    }
}
