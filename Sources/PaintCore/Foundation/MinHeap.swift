/// Binary min-heap of (key, region, stamp): smallest key first, ties by region id, so
/// smallest-first merging is fully deterministic.
struct MinHeap {
    struct Item {
        var key: Float
        var region: Int32
        var stamp: Int32
    }

    private var items: [Item] = []

    @inline(__always)
    private static func less(_ a: Item, _ b: Item) -> Bool {
        a.key < b.key || (a.key == b.key && a.region < b.region)
    }

    mutating func push(_ key: Float, _ region: Int32, _ stamp: Int32) {
        items.append(Item(key: key, region: region, stamp: stamp))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if !Self.less(items[i], items[parent]) { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> Item? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            let n = items.count
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < n && Self.less(items[l], items[m]) { m = l }
                if r < n && Self.less(items[r], items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return first
    }
}
