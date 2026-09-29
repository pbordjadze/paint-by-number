import Foundation

/// Development-only image dumps (PBN_DUMP_DIR). Removed before shipping.
enum DebugDump {
    static func lab(_ grid: Grid<SIMD4<Float>>, name: String, chromaScale: Float) {
        guard let dir = Tune.environment["PBN_DUMP_DIR"] else { return }
        var px = [UInt8](repeating: 255, count: grid.count * 4)
        for i in 0..<grid.count {
            let c = grid.storage[i]
            let rgb = ColorScience.okLabToEncoded(SIMD3(c.x, c.y / chromaScale, c.z / chromaScale), space: .sRGB)
            px[i * 4] = UInt8(min(max(rgb.x * 255, 0), 255))
            px[i * 4 + 1] = UInt8(min(max(rgb.y * 255, 0), 255))
            px[i * 4 + 2] = UInt8(min(max(rgb.z * 255, 0), 255))
        }
        let image = RGBAImage(width: grid.width, height: grid.height, pixels: px)
        try? Netpbm.encodePPM(image).write(to: URL(fileURLWithPath: dir + "/" + name + ".ppm"))
    }

    static func scalar(_ values: [Float], width: Int, height: Int, name: String) {
        guard let dir = Tune.environment["PBN_DUMP_DIR"] else { return }
        let px = values.map { UInt8(min(max($0 * 255, 0), 255)) }
        try? Netpbm.encodePGM(width: width, height: height, values: px)
            .write(to: URL(fileURLWithPath: dir + "/" + name + ".pgm"))
    }

    static func classes(_ classes: [UInt32], width: Int, height: Int, palette: [SIMD3<Float>], name: String, chromaScale: Float) {
        guard Tune.environment["PBN_DUMP_DIR"] != nil else { return }
        let grid = Grid(width: width, height: height, storage: classes.map { SIMD4(palette[Int($0)], 0) })
        lab(grid, name: name, chromaScale: chromaScale)
    }
}
