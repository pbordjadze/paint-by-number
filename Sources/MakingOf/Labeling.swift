/// The connected areas of a picture or of a plane of keys.
struct RegionLabels: Sendable, Equatable {
    /// For each cell, the number of its area, from 0. `Int32` is the show's one type for an index
    /// of an area or a paint (`Arrival.regionMinimum` and `PaintFlow` take these planes as they
    /// are), signed so that -1 can mark no owner.
    var labels: Plane<Int32>
    var count: Int
}

enum Labeling {
    /// Connected areas of one color (4-connected) in a picture, by runs and union-find
    /// (`label_regions` in `making_of_exact.py`, the same numbering).
    static func regions(of picture: Plane<SIMD4<UInt8>>) -> RegionLabels {
        regions(keys: Plane(width: picture.width, height: picture.height, data: picture.data.map(ExactMath.colorKey)))
    }

    /// Connected areas of one key (4-connected). Areas are numbered by where their first run starts,
    /// rows top to bottom and left to right within a row, whichever way the runs were joined.
    static func regions(keys: Plane<UInt32>) -> RegionLabels {
        let w = keys.width, h = keys.height
        guard w > 0, h > 0 else { return RegionLabels(labels: Plane(width: w, height: h, repeating: 0), count: 0) }
        // a run is a stretch of one key in a row; its id is its place in these arrays
        var runStart: [Int32] = [], runEnd: [Int32] = [], runKey: [UInt32] = []
        var rowFirstRun = [Int](repeating: 0, count: h + 1)
        for y in 0..<h {
            rowFirstRun[y] = runStart.count
            let base = y * w
            var start = 0
            for x in 1...w where x == w || keys.data[base + x] != keys.data[base + x - 1] {
                runStart.append(Int32(start))
                runEnd.append(Int32(x))
                runKey.append(keys.data[base + start])
                start = x
            }
        }
        rowFirstRun[h] = runStart.count

        var parent = Array(0..<runStart.count)
        func find(_ a: Int) -> Int {
            var a = a
            while parent[a] != a {
                parent[a] = parent[parent[a]]
                a = parent[a]
            }
            return a
        }
        for y in 1..<max(h, 1) {
            var i = rowFirstRun[y], j = rowFirstRun[y - 1]
            let iEnd = rowFirstRun[y + 1], jEnd = rowFirstRun[y]
            while i < iEnd && j < jEnd {
                if runStart[i] < runEnd[j] && runStart[j] < runEnd[i] && runKey[i] == runKey[j] {
                    let a = find(i), b = find(j)
                    if a != b { parent[max(a, b)] = min(a, b) }
                }
                if runEnd[i] < runEnd[j] { i += 1 } else { j += 1 }
            }
        }

        var number = [Int32](repeating: -1, count: runStart.count)
        var count = 0
        var labels = [Int32](repeating: 0, count: w * h)
        for y in 0..<h {
            for r in rowFirstRun[y]..<rowFirstRun[y + 1] {
                let root = find(r)
                if number[root] < 0 {
                    number[root] = Int32(count)
                    count += 1
                }
                let label = number[root]
                for x in Int(runStart[r])..<Int(runEnd[r]) { labels[y * w + x] = label }
            }
        }
        return RegionLabels(labels: Plane(width: w, height: h, data: labels), count: count)
    }
}
