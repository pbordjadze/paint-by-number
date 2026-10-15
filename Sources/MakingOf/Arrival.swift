import PaintCore

/// When a step's change reaches each part of the picture: spreading from the crew's visits, so it
/// always grows from where somebody is working. `making_of_reveal.py` is the reference and equals
/// this bit for bit (distances are `sqrt` of a sum of squares, never a C library's `hypot`).
public enum Arrival {
    /// The time the change reaches each pixel: the earliest visit plus its distance over `speed`,
    /// plus `noise`, then squeezed toward the first visit so none is later than `end`. `visits`
    /// is never empty (the plan gives every step at least one).
    public static func field(
        visits: [Visit], width: Int, height: Int, speed: Double, end: Double, noise: StepNoise
    ) -> Plane<Double> {
        precondition(!visits.isEmpty, "a step has a visit to spread from")
        var data = [Double](repeating: 0, count: max(width, 0) * max(height, 0))
        guard !data.isEmpty else { return Plane(width: width, height: height, data: data) }
        let first = visits.reduce(Double.infinity) { min($0, $1.time) }
        let rowMaxima: [Double] = data.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            return Parallel.mapBands(height) { rows in
                var highest = -Double.infinity
                for y in rows {
                    let row = out.value + y * width
                    for x in 0..<width { row[x] = .infinity }
                    for visit in visits {
                        let dy = Double(y) - visit.y
                        let dySquared = dy * dy
                        for x in 0..<width {
                            let dx = Double(x) - visit.x
                            let reaches = visit.time + (dx * dx + dySquared).squareRoot() / speed
                            if reaches < row[x] { row[x] = reaches }
                        }
                    }
                    for x in 0..<width {
                        row[x] += noise[x, y]
                        if row[x] > highest { highest = row[x] }
                    }
                }
                return highest
            }
        }
        let highest = rowMaxima.reduce(-Double.infinity) { max($0, $1) }
        if highest > end && highest > first {
            data.withUnsafeMutableBufferPointer { buffer in
                let out = UncheckedSendable(buffer.baseAddress!)
                Parallel.forEachBand(height) { rows in
                    for i in (rows.lowerBound * width)..<(rows.upperBound * width) {
                        out.value[i] = first + (out.value[i] - first) * (end - first) / (highest - first)
                    }
                }
            }
        }
        return Plane(width: width, height: height, data: data)
    }

    /// Step `k`'s field from its plan visits, at the show's pace, roughened by the step's own noise.
    public static func field(
        step k: Int, visits: [Visit], width: Int, height: Int, timing: ScheduleTiming, streams: ShowStreams,
        style: ScheduleStyle = .standard
    ) -> Plane<Double> {
        field(
            visits: visits, width: width, height: height,
            speed: style.arrivalSpeed * Double(width) * timing.pace(style),
            end: timing.start(k) + timing.step - style.stepMargin,
            noise: StepNoise(step: k, width: width, height: height, streams: streams, style: style))
    }

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

/// How the paints of step 3 flow: each paint's areas spread from the k-means++ seeds that landed
/// on it (`PaintSeed`, which `CrewInputs.make` chooses), and a paint no seed landed on follows the
/// crew's own change.
public enum PaintFlow {
    public struct Result: Sendable, Equatable {
        /// When each region of the labels changes: its earliest pixel's time.
        public var regionTimes: [Double]
        /// For each paint, when its last region has changed: the seed rings fade out after.
        public var spread: [Double]

        public init(regionTimes: [Double], spread: [Double]) {
            self.regionTimes = regionTimes
            self.spread = spread
        }
    }

    /// `paints` says which paint (0..<`paintCount`) each pixel is, `labels` which of the
    /// `labelCount` regions (connected areas of one paint); `crew` is the paints step's own
    /// `Arrival.field`, which unseeded paints follow a moment behind.
    public static func times(
        seeds: [PaintSeed], paints: Plane<Int32>, paintCount: Int, labels: Plane<Int32>, labelCount: Int,
        following crew: Plane<Double>, timing: ScheduleTiming, style: ScheduleStyle = .standard
    ) -> Result {
        let (width, height) = (paints.width, paints.height)
        precondition(
            [labels.width, crew.width] == [width, width] && [labels.height, crew.height] == [height, height],
            "paints, labels and the crew's field cover the same picture")
        var bySeededPaint = [[PaintSeed]](repeating: [], count: paintCount)
        for seed in seeds {
            precondition((0..<paintCount).contains(seed.paint), "a seed lands on a paint")
            bySeededPaint[seed.paint].append(seed)
        }
        let speed = Double(width) / style.seedSpeedDivisor
        var data = [Double](repeating: 0, count: width * height)
        var highest = -Double.infinity
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var time = Double.infinity
                for seed in bySeededPaint[Int(paints.data[i])] {
                    let dx = Double(x) - seed.x
                    let dy = Double(y) - seed.y
                    time = min(time, seed.time + style.seedDelay + (dx * dx + dy * dy).squareRoot() / speed)
                }
                if time.isInfinite { time = crew.data[i] + style.unseededDelay }
                data[i] = time
                highest = max(highest, time)
            }
        }
        let low = timing.start(2) + style.paintFloor
        let cap = timing.start(2) + timing.step - style.stepMargin
        if highest > cap && highest > low {
            for i in data.indices { data[i] = low + (data[i] - low) * (cap - low) / (highest - low) }
        }
        let regionTimes = Arrival.regionMinimum(Plane(width: width, height: height, data: data), labels: labels, count: labelCount)
        var spread = [Double](repeating: -.infinity, count: paintCount)
        for (paint, label) in zip(paints.data, labels.data) {
            spread[Int(paint)] = max(spread[Int(paint)], regionTimes[Int(label)])
        }
        return Result(regionTimes: regionTimes, spread: spread)
    }
}
