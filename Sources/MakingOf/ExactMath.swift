/// Exact arithmetic for the show's discrete decisions: where the crew stands and which pixel a seed
/// lands on. Everything here is integer arithmetic or IEEE double arithmetic made of `+ - * /` and
/// `squareRoot()` in a fixed order (Swift does not fuse a multiply and an add), and
/// `tools/factory/making_of_exact.py` makes the same bits, so both test suites compare with `==`.
/// Nothing calls `pow`, `cbrt` or `hypot`, whose last bits differ between C libraries, and nothing
/// sums in a pairwise or parallel order.
enum ExactMath {
    /// The sRGB transfer curve decoded, for each byte: the true value of `c / 12.92`
    /// (c <= 0.04045) or `((c + 0.055) / 1.055) ^ 2.4` at c = i / 255, to 60 digits and then rounded
    /// once to a double, so no library's `pow` is in it.
    static let srgbLinear: [Double] = [
        0.0, 0.0003035269835488375, 0.000607053967097675,
        0.0009105809506465125, 0.00121410793419535, 0.0015176349177441874,
        0.001821161901293025, 0.0021246888848418626, 0.0024282158683907,
        0.0027317428519395373, 0.003035269835488375, 0.0033465357638991586,
        0.003676507324047435, 0.004024717018496304, 0.0043914420374102925,
        0.0047769534806937275, 0.005181516702338385, 0.005605391624202721,
        0.006048833022857052, 0.006512090792594472, 0.006995410187265385,
        0.00749903204322617, 0.008023192985384993, 0.008568125618069302,
        0.009134058702220785, 0.009721217320237844, 0.010329823029626936,
        0.01096009400648824, 0.011612245179743881, 0.012286488356915867,
        0.012983032342173007, 0.013702083047289683, 0.014443843596092541,
        0.015208514422912706, 0.015996293365509628, 0.016807375752887377,
        0.017641954488384078, 0.01850022012837969, 0.019382360956935723,
        0.02028856305665239, 0.021219010376003555, 0.022173884793387375,
        0.023153366178110403, 0.02415763244850475, 0.025186859627361623,
        0.02624122189484989, 0.02732089163907489, 0.028426039504420787,
        0.029556834437808797, 0.03071344373299362, 0.03189603307301152,
        0.03310476657088505, 0.03433980680868216, 0.03560131487502032,
        0.03688945040110002, 0.03820437159534648, 0.03954623527673283,
        0.04091519690685317, 0.042311410620809654, 0.04373502925697345,
        0.04518620438567554, 0.04666508633688008, 0.048171824226889405,
        0.04970656598412722, 0.051269458374043224, 0.05286064702318025,
        0.054480276442442355, 0.05612849004960008, 0.05780543019106721,
        0.059511238162981185, 0.061246054231617594, 0.06301001765316766,
        0.06480326669290576, 0.06662593864377288, 0.06847816984440015,
        0.07036009569659588, 0.07227185068231748, 0.07421356838014961,
        0.07618538148130781, 0.07818742180518633, 0.08021982031446831,
        0.0822827071298148, 0.08437621154414877, 0.08650046203654974,
        0.08865558628577294, 0.09084171118340768, 0.09305896284668742,
        0.09530746663096466, 0.09758734714186242, 0.09989872824711389,
        0.10224173308810128, 0.10461648409110416, 0.10702310297826759,
        0.10946171077829933, 0.11193242783690557, 0.11443537382697372,
        0.11697066775851081, 0.1195384279883456, 0.12213877222960184,
        0.12477181756095046, 0.12743768043564743, 0.13013647669036427,
        0.13286832155381792, 0.13563332965520564, 0.13843161503245183,
        0.14126329114027164, 0.14412847085805772, 0.14702726649759498,
        0.14995978981060853, 0.15292615199615014, 0.15592646370782734,
        0.15896083506088035, 0.162029375639111, 0.1651321945016676,
        0.1682694001896907, 0.17144110073282254, 0.17464740365558498,
        0.17788841598362912, 0.18116424424986013, 0.1844749945004409,
        0.18782077230067779, 0.19120168274079136, 0.1946178304415757,
        0.1980693195599488, 0.20155625379439707, 0.2050787363903169,
        0.20863687014525567, 0.2122307574140551, 0.21586050011389915,
        0.21952619972926918, 0.22322795731680842, 0.22696587351009834,
        0.23074004852434896, 0.23455058216100508, 0.23839757381227095,
        0.24228112246555472, 0.2462013267078354, 0.2501582847299533,
        0.2541520943308267, 0.25818285292159576, 0.262250657529696,
        0.2663556048028623, 0.27049779101306576, 0.27467731206038454,
        0.27889426347681034, 0.28314874042999194, 0.2874408377269174,
        0.29177064981753587, 0.29613827079832095, 0.3005437944157764,
        0.3049873140698861, 0.30946892281750843, 0.3139887133757175,
        0.31854677812509175, 0.3231432091129507, 0.32777809805654207,
        0.3324515363461792, 0.33716361504833026, 0.34191442490866075,
        0.3467040563550295, 0.3515325995004392, 0.3564001441459434,
        0.36130677978350945, 0.3662525955988394, 0.37123768047414896,
        0.3762621229909062, 0.38132601143253, 0.3864294337870489,
        0.3915724777497231, 0.3967552307256268, 0.4019777798321956,
        0.40724021190173665, 0.4125426134839036, 0.41788507084813725,
        0.4232676699860715, 0.42869049661390657, 0.4341536361747488,
        0.43965717384091874, 0.44520119451622775, 0.45078578283822335,
        0.4564110231804045, 0.46207699965440685, 0.4677837961121588,
        0.4735314961480093, 0.47932018310082664, 0.4851499400560704,
        0.49102084984783545, 0.49693299506087035, 0.5028864580325684,
        0.5088813208549335, 0.5149176653765213, 0.5209955732043541,
        0.527115125705813, 0.533276404010505, 0.539479489012107,
        0.5457244613701866, 0.5520114015119999, 0.5583403896342677,
        0.5647115057049289, 0.5711248294648729, 0.5775804404296505,
        0.584078417891164, 0.5906188409193368, 0.5972017883637631,
        0.6038273388553375, 0.6104955708078647, 0.6172065624196509,
        0.6239603916750759, 0.6307571363461467, 0.6375968739940324,
        0.644479681970582, 0.6514056374198239, 0.6583748172794482,
        0.6653872982822719, 0.6724431569576873, 0.6795424696330937,
        0.6866853124353132, 0.6938717612919898, 0.7011018919329731,
        0.7083757798916867, 0.7156935005064805, 0.7230551289219689,
        0.7304607400903533, 0.7379104087727307, 0.7454042095403872,
        0.7529422167760778, 0.7605245046752922, 0.7681511472475069,
        0.7758222183174234, 0.7835377915261932, 0.79129794033263,
        0.7991027380144087, 0.8069522576692514, 0.8148465722161011,
        0.8227857543962833, 0.8307698767746545, 0.8387990117407399,
        0.8468732315098577, 0.8549926081242336, 0.863157213454102,
        0.8713671191987971, 0.8796223968878317, 0.8879231178819664,
        0.8962693533742666, 0.9046611743911491, 0.9130986517934189,
        0.9215818562772945, 0.9301108583754234, 0.9386857284578878,
        0.9473065367331996, 0.955973353249286, 0.9646862478944651,
        0.9734452903984123, 0.982250550333117, 0.9911020971138297,
        1.0,
    ]

    /// Newton steps for `cbrt`: from 1.0 it settles within about 16 for the smallest value a byte
    /// colour can have (1.5e-5), so 32 leave no input unsettled.
    static let cbrtSteps = 32

    /// `x` rounded to the nearest integer, halves to the even one: Python's `round(x)`, so 2.5 is 2.
    /// (`Double.rounded()` rounds halves away from zero.)
    static func halfEven(_ x: Double) -> Double {
        x.rounded(.toNearestOrEven)
    }

    /// `x` rounded to `decimals` places as `halfEven(x * 10^decimals) / 10^decimals`: the plan file's
    /// precision (`making_of_exact.quantize`).
    static func quantize(_ x: Double, decimals: Int) -> Double {
        var scale = 1.0
        for _ in 0..<decimals { scale *= 10 }
        return halfEven(x * scale) / scale
    }

    /// The cube root of a non-negative double by a fixed number of Newton steps from 1.0. 0 stays 0.
    static func cbrt(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        var y = 1.0
        for _ in 0..<cbrtSteps { y = (y + y + x / (y * y)) / 3 }
        return y
    }

    /// OKLab of a byte colour in doubles (`oklab` in `making_of_exact.py`), the chroma axes stretched
    /// by `chroma`: the grid k-means++ measures in.
    static func oklab(_ r: UInt8, _ g: UInt8, _ b: UInt8, chroma: Double = 1) -> SIMD3<Double> {
        let rl = srgbLinear[Int(r)], gl = srgbLinear[Int(g)], bl = srgbLinear[Int(b)]
        let l = cbrt(0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return SIMD3(lightness, a * chroma, bb * chroma)
    }

    /// Squared distance between two OKLab points, summed left to right.
    static func distance2(_ p: SIMD3<Double>, _ q: SIMD3<Double>) -> Double {
        let da = p.x - q.x, db = p.y - q.y, dc = p.z - q.z
        return da * da + db * db + dc * dc
    }

    /// Sums of an integer plane over the window of radius `r` around each cell, a window that
    /// sticks out of the plane counting the edge cell again (`np.pad(mode='edge')`): rows, then
    /// columns, as sliding sums. Exact while a window's sum fits `Int32`.
    static func boxSums<T: BinaryInteger>(_ plane: Plane<T>, radius r: Int) -> Plane<Int32> {
        let w = plane.width, h = plane.height
        guard w > 0, h > 0 else { return Plane(width: w, height: h, repeating: 0) }
        var rows = [Int32](repeating: 0, count: w * h)
        for y in 0..<h {
            let base = y * w
            func cell(_ x: Int) -> Int32 { Int32(truncatingIfNeeded: plane.data[base + min(max(x, 0), w - 1)]) }
            var sum: Int32 = 0
            for dx in -r...r { sum += cell(dx) }
            for x in 0..<w {
                rows[base + x] = sum
                sum += cell(x + r + 1) - cell(x - r)
            }
        }
        var out = [Int32](repeating: 0, count: w * h)
        var column = [Int32](repeating: 0, count: w)
        for dy in -r...r {
            let base = min(max(dy, 0), h - 1) * w
            for x in 0..<w { column[x] += rows[base + x] }
        }
        for y in 0..<h {
            let base = y * w
            for x in 0..<w { out[base + x] = column[x] }
            let entering = min(y + r + 1, h - 1) * w, leaving = min(max(y - r, 0), h - 1) * w
            for x in 0..<w { column[x] += rows[entering + x] - rows[leaving + x] }
        }
        return Plane(width: w, height: h, data: out)
    }

    /// The `percent`th percentile (an integer) of `values`, linear between the two ranks around it,
    /// as numpy's default but written out: `lo + (hi - lo) * rem / 100` with the rank
    /// `(n - 1) * percent / 100` split into a whole part and `rem` hundredths.
    static func percentile(_ values: [Int32], percent: Int) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let (lo, rem) = ((sorted.count - 1) * percent).quotientAndRemainder(dividingBy: 100)
        let a = Int(sorted[lo]), b = Int(sorted[min(lo + 1, sorted.count - 1)])
        return Double(a) + Double((b - a) * rem) / 100
    }

    /// Running sums of `weights` in index order, each added to the one before.
    static func cumulative(_ weights: [Double]) -> [Double] {
        var total = 0.0
        return weights.map { w in
            total += w
            return total
        }
    }

    /// How many entries of the nondecreasing `cdf` are <= `value` (`bisect.bisect_right`): the index of
    /// the first entry past it, which has weight when `0 <= value < cdf.last`.
    static func bisectRight(_ cdf: [Double], _ value: Double) -> Int {
        var lo = 0
        var hi = cdf.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cdf[mid] <= value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// One integer per byte colour, `r << 16 | g << 8 | b`; equal keys are equal colours.
    static func colorKey(_ c: SIMD4<UInt8>) -> UInt32 {
        UInt32(c.x) << 16 | UInt32(c.y) << 8 | UInt32(c.z)
    }
}
