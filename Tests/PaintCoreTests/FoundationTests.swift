import Foundation
import Testing
@testable import PaintCore

@Suite("Foundation")
struct FoundationTests {

    @Test func okLabRoundTrip() {
        var rng = SplitMix64(seed: 1)
        for space in [RGBColorSpace.sRGB, .displayP3] {
            for _ in 0..<500 {
                let rgb = SIMD3(rng.nextFloat(), rng.nextFloat(), rng.nextFloat())
                let lab = ColorScience.encodedToOKLab(rgb, space: space)
                let back = ColorScience.okLabToEncoded(lab, space: space)
                #expect(abs(back.x - rgb.x) < 2e-3 && abs(back.y - rgb.y) < 2e-3 && abs(back.z - rgb.z) < 2e-3)
            }
        }
    }

    @Test func okLabReferenceValues() {
        // White → L=1, a=b=0; sRGB red reference from Björn Ottosson's post.
        let white = ColorScience.linearSRGBToOKLab(SIMD3(1, 1, 1))
        #expect(abs(white.x - 1) < 1e-3 && abs(white.y) < 1e-3 && abs(white.z) < 1e-3)
        let red = ColorScience.linearSRGBToOKLab(SIMD3(1, 0, 0))
        #expect(abs(red.x - 0.627955) < 1e-3 && abs(red.y - 0.224863) < 1e-3 && abs(red.z - 0.125846) < 1e-3)
    }

    @Test func outOfGamutIsClippedByChroma() {
        let lab = SIMD3<Float>(0.7, 0.4, 0.3)  // far outside sRGB
        let rgb = ColorScience.okLabToEncoded(lab, space: .sRGB)
        #expect(rgb.min() >= 0 && rgb.max() <= 1)
        let back = ColorScience.encodedToOKLab(rgb, space: .sRGB)
        #expect(abs(back.x - 0.7) < 0.02)  // lightness preserved
        #expect(abs(atan2(back.z, back.y) - atan2(Float(0.3), Float(0.4))) < 0.05)  // hue preserved
    }

    @Test func paletteHexIsLowercaseEightBitAndClamped() {
        // 0.02 × 255 = 5.1 pads to "05"; 0.5 × 255 = 127.5 rounds away from zero to 0x80.
        #expect(PaletteColor(oklab: .zero, rgb: SIMD3(0.02, 0.5, 1)).hexDigits == "0580ff")
        #expect(PaletteColor(oklab: .zero, rgb: SIMD3(-0.1, 1.2, 0)).hexDigits == "00ff00")
    }

    @Test func distanceTransformMatchesBruteForce() {
        var rng = SplitMix64(seed: 7)
        let w = 37, h = 23
        let features = (0..<(w * h)).map { _ in rng.nextFloat() < 0.03 }
        let edt = DistanceTransform.squaredEDT(width: w, height: h) { features[$0] }
        for y in 0..<h {
            for x in 0..<w {
                var best = Float.infinity
                for fy in 0..<h {
                    for fx in 0..<w where features[fy * w + fx] {
                        best = min(best, Float((fx - x) * (fx - x) + (fy - y) * (fy - y)))
                    }
                }
                #expect(edt[x, y] == best)
            }
        }
    }

    @Test func distanceTransformWithoutFeaturesIsInfinite() {
        let edt = DistanceTransform.squaredEDT(width: 5, height: 4) { _ in false }
        #expect(edt.storage.allSatisfy { $0 == .infinity })
    }

    @Test func interiorDistanceOfSquare() {
        // 9×9 region inside a 1-pixel frame of another region: centre is 4.5 from edges.
        var map = RegionMap(width: 11, height: 11, repeating: 0)
        for y in 1..<10 { for x in 1..<10 { map[x, y] = 1 } }
        let d = DistanceTransform.interiorDistance(labels: map)
        #expect(d[5, 5] == 4.5)
        #expect(d[1, 1] == 0.5)
    }

    @Test func connectedComponents() {
        // Two same-class blobs separated by another class, plus a diagonal-only touch.
        let rows: [[UInt32]] = [
            [0, 0, 1, 0],
            [0, 1, 1, 0],
            [1, 1, 0, 1],
        ]
        let grid = Grid(width: 4, height: 3, storage: rows.flatMap { $0 })
        let cc = ConnectedComponents.label(grid)
        #expect(cc.count == 5)
        #expect(cc.labels[0, 0] == cc.labels[1, 0])
        #expect(cc.labels[3, 0] == cc.labels[3, 1])
        #expect(cc.labels[3, 0] != cc.labels[0, 0])
        #expect(cc.labels[2, 2] != cc.labels[3, 1])  // diagonal only: not connected under 4-connectivity
        #expect(cc.area.reduce(0, +) == 12)
    }

    @Test func disjointSetCompressesToTheRootTheCallerChose() {
        var sets = DisjointSet(count: 8)
        for i in 1..<6 { sets.parent[i] = i - 1 }  // the chain 5 → 4 → … → 0 and two loners
        #expect(sets.find(5) == 0)
        #expect(sets.parent[0..<6].allSatisfy { $0 == 0 })
        sets.parent[0] = 7
        #expect(sets.find(3) == 7)
        #expect(sets.find(6) == 6)
    }

    @Test func areaResampleOfUniformImageIsExact() {
        let img = RGBAImage(width: 30, height: 20, fill: SIMD4(200, 100, 50, 255))
        let small = Resample.area(img, width: 7, height: 5)
        for y in 0..<5 { for x in 0..<7 { #expect(small[x, y] == SIMD4(200, 100, 50, 255)) } }
    }

    @Test func resampleAveragesInLinearLight() {
        // Black beside white averages to half the light, which encodes as 188, not 128.
        let blackWhite = RGBAImage(width: 2, height: 1, pixels: [0, 0, 0, 255, 255, 255, 255, 255])
        #expect(Resample.area(blackWhite, width: 1, height: 1)[0, 0] == SIMD4(188, 188, 188, 255))
        // A transparent neighbour adds no color: red keeps its hue at half the alpha.
        let redClear = RGBAImage(width: 2, height: 1, pixels: [255, 0, 0, 255, 0, 255, 0, 0])
        #expect(Resample.area(redClear, width: 1, height: 1)[0, 0] == SIMD4(255, 0, 0, 128))
        #expect(Resample.area(blackWhite, width: 2, height: 1) == blackWhite)
    }

    @Test func rowDividerIsExact() {
        let limit = 1 << 26
        var rng = SplitMix64(seed: 5)
        for width in [1, 2, 3, 5, 7, 640, 768, 1023, 1024, 1500, 4096, 65535] {
            let divider = RowDivider(width: width)
            var indices = (0..<200).flatMap { row in (-1...1).map { row * width * 5 + $0 } }.filter { $0 >= 0 }
            indices += (1...64).map { limit - $0 } + (0..<500).map { _ in Int(rng.next() % UInt64(limit)) }
            for i in indices { #expect(divider.row(i) == i / width, "\(i) / \(width)") }
        }
    }

    @Test func encodeTableMatchesTransferFunction() {
        // Checked exhaustively over [0, 1.25] once, when the table was written; here a dense
        // sample (every 4099th bit pattern) plus every step position and its neighbours.
        let table = ColorScience.EncodeTable.shared
        @inline(__always) func direct(_ v: Float) -> UInt8 { Resample.quantize(ColorScience.encodeSRGB(v)) }
        var bits = UInt32(0)
        while bits <= Float(1.25).bitPattern {
            let v = Float(bitPattern: bits)
            #expect(table.quantized(v) == direct(v))
            bits += 4099
        }
        for code in 1...255 {
            // Smallest float with this code, by bisection on the direct function.
            var lo = Float(0).bitPattern, hi = Float(1).bitPattern
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                if direct(Float(bitPattern: mid)) < UInt8(code) { lo = mid + 1 } else { hi = mid }
            }
            for v in [Float(bitPattern: lo).nextDown, Float(bitPattern: lo), Float(bitPattern: lo).nextUp] {
                #expect(table.quantized(v) == direct(v))
            }
        }
    }

    @Test func parallelHelpersCoverEachIndexOnce() {
        for count in [0, 1, 7, 1000, 100_003] {
            for size in [1, 64] {
                var bandHits = [Int](repeating: 0, count: count)
                var chunkHits = bandHits
                bandHits.withUnsafeMutableBufferPointer { bands in
                    chunkHits.withUnsafeMutableBufferPointer { chunks in
                        let band = UncheckedSendable(bands.baseAddress), chunk = UncheckedSendable(chunks.baseAddress)
                        Parallel.forEachBand(count, minimumBandSize: size) { for i in $0 { band.value![i] += 1 } }
                        Parallel.forEachChunk(count, chunk: size) { for i in $0 { chunk.value![i] += 1 } }
                    }
                }
                #expect(bandHits.allSatisfy { $0 == 1 }, "forEachBand \(count) by \(size)")
                #expect(chunkHits.allSatisfy { $0 == 1 }, "forEachChunk \(count) by \(size)")
                #expect(Parallel.mapBands(count, minimumBandSize: size) { Array($0) }.flatMap { $0 } == Array(0..<count))
            }
        }
    }

    @Test func netpbmRoundTrip() throws {
        var img = RGBAImage(width: 3, height: 2, fill: SIMD4(1, 2, 3, 255))
        img[2, 1] = SIMD4(250, 128, 7, 255)
        let decoded = try Netpbm.read(Netpbm.encodePPM(img))
        #expect(decoded == img)
    }

    @Test func netpbmReadsGrayAndRejectsBadInput() throws {
        let gray = try Netpbm.read(Data("P5\n# a comment\n2 1\n255\n".utf8) + Data([7, 200]))
        #expect(gray.pixels == [7, 7, 7, 255, 200, 200, 200, 255])
        let rejected = [
            Data("P3\n1 1\n255\n".utf8) + Data([1, 2, 3]),  // magic
            Data("P5\n1 1\n65535\n".utf8) + Data([0, 0]),  // maxval
            Data("P5\n2 2\n255\n".utf8) + Data([1, 2, 3]),  // body one byte short
        ]
        for data in rejected { #expect(throws: Netpbm.Error.self) { try Netpbm.read(data) } }
    }

    @Test func emptyBoundsHaveNoSize() {
        #expect(PixelBounds.empty.width < 0)
        #expect(PixelBounds.empty.height < 0)
        #expect(PixelBounds.empty.isEmpty)
    }
}
