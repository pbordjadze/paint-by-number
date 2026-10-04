/// Union-find over `0..<count` with path compression. A union is the caller's assignment
/// `parent[other] = root`, so callers pick each set's representative (the larger area, the
/// smaller index) and compression never changes it.
struct DisjointSet {
    var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    /// The root of `x`'s set; everything on the way to it now points at it directly.
    mutating func find(_ x: Int) -> Int {
        var r = x
        while parent[r] != r { r = parent[r] }
        var c = x
        while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
        return r
    }
}
