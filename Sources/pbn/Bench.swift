import Foundation
import PaintCore

func runBench(_ options: Options) throws {
    guard !options.positional.isEmpty else { fail("usage: pbn bench <in.ppm>...") }
    for path in options.positional {
        let image = loadImage(path)
        let m = measure(image, options.settings, runs: options.runs)
        print("\(path) — \(m.size), \(m.regions) regions, longest stretch without a cancellation check "
            + String(format: "%.1f ms (ending %.0f ms into the run, in ", m.gap.gap, m.gap.end) + m.stage
            + String(format: "; median over runs %.1f ms)", m.medianGap))
        for name in m.order + ["total"] {
            print(String(format: "  %-28@ ", name as NSString) + stat(m.totals[name]!))
        }
        // The app's other regimes: a live preview at about 700 px, full detail on a large photo
        // (the source is enlarged so the working size reaches its 2100 px cap), and that with
        // the largest palette.
        let long = max(image.width, image.height)
        let preview = Resample.area(image, width: max(1, image.width * 467 / long), height: max(1, image.height * 467 / long))
        var fine = options.settings
        fine.detail = 1
        var many = fine
        many.colorCount = GenerationSettings.colorCountRange.upperBound
        let big = Resample.area(image, width: image.width * 1400 / long, height: image.height * 1400 / long)
        let regimes = [
            ("preview", preview, options.settings), ("detail 1", big, fine),
            ("\(many.colorCount) colors, detail 1", big, many),
        ]
        for (label, input, settings) in regimes {
            let v = measure(input, settings, runs: options.runs)
            print(String(format: "  %-28@ ", "\(label) \(v.size)" as NSString) + stat(v.totals["total"]!)
                + String(format: "   worst gap %.1f ms (in ", v.gap.gap) + v.stage
                + String(format: "; median %.1f ms)", v.medianGap))
        }
        if let input = loadLineArt(options) {
            for style in [LineArtSettings.Style.layered, .coloringBook] {
                var drawn = options.settings
                drawn.lineArt = lineArtSettings(style, fields: options.lineArtFields)
                let v = measure(image, drawn, runs: options.runs, lineArt: input)
                print(String(format: "  %-28@ ", "\(style.rawValue) \(v.size), \(v.regions) cells" as NSString) + stat(v.totals["total"]!)
                    + String(format: "   worst gap %.1f ms (in ", v.gap.gap) + v.stage + ")")
                guard style == .layered else { continue }
                for name in v.order where name.hasPrefix("lineArt") {
                    print(String(format: "    %-26@ ", name as NSString) + stat(v.totals[name]!))
                }
            }
        }
        // Auto's suggestion as the create flow runs it, and its analysis alone.
        var auto = options
        auto.length = .relaxed
        auto.candidates = 5
        var suggestMs: [Double] = [], analysisMs: [Double] = []
        var decision: AutoDecision?
        for _ in 0..<options.runs {
            let start = ContinuousClock.now
            do {
                _ = try AutoSettings.analyze(image, importance: nil, hints: nil, cancel: .none)
            } catch { fail("\(error)") }
            analysisMs.append(milliseconds(since: start))
            let (d, ms) = suggest(image, importance: nil, options: auto)
            suggestMs.append(ms)
            decision = d
        }
        let draft = AutoSettings.draftImage(from: image)
        let chosen = decision!.settings
        print(String(format: "  %-28@ ", "suggest \(draft.width)×\(draft.height)" as NSString) + stat(suggestMs)
            + String(format: "   analysis median %.1f ms; %d candidates → %d colors, detail %.2f, smoothness %.2f",
                     analysisMs.sorted()[analysisMs.count / 2], decision!.candidates.count, chosen.colorCount,
                     Double(chosen.detail), Double(chosen.smoothness)))
    }
}

/// Runs the generator `runs` times; per-stage timings, region count, worst gap and the
/// median of the per-run worst gaps (a lone outlier on a busy machine is a scheduling
/// hiccup; a high median is a stretch of work that needs another check).
private func measure(_ image: RGBAImage, _ settings: GenerationSettings, runs: Int, lineArt: LineArtInput? = nil) -> (
    totals: [String: [Double]], order: [String], regions: Int, size: String,
    gap: (gap: Double, end: Double), stage: String, medianGap: Double
) {
    let generator = TemplateGenerator(settings: settings)
    var totals: [String: [Double]] = [:]
    var order: [String] = []
    var regionCount = 0
    var size = ""
    var worstGap = (gap: 0.0, end: 0.0)
    var worstStage = ""
    var gaps: [Double] = []
    for _ in 0..<runs {
        let probe = CancellationProbe()
        let out: TemplateGenerator.Output
        do { out = try generator.generate(from: image, lineArt: lineArt, cancel: probe.check) } catch { fail("\(error)") }
        regionCount = out.template.regions.count
        size = "\(out.template.width)×\(out.template.height)"
        let gap = probe.finish()
        gaps.append(gap.gap)
        if gap.gap > worstGap.gap {
            worstGap = gap
            // The innermost stage running when the stretch ended.
            let end = gap.end / 1000
            worstStage = out.timings.filter { $0.start <= end && end <= $0.start + $0.seconds }
                .min { $0.seconds < $1.seconds }?.name ?? "between stages"
        }
        var perRun: [String: Double] = ["total": out.totalSeconds * 1000]
        for t in out.timings {
            if totals[t.name] == nil && perRun[t.name] == nil { order.append(t.name) }
            perRun[t.name, default: 0] += t.seconds * 1000
        }
        for (k, v) in perRun { totals[k, default: []].append(v) }
    }
    return (totals, order, regionCount, size, worstGap, worstStage, gaps.sorted()[gaps.count / 2])
}

private func stat(_ values: [Double]) -> String {
    let v = values.sorted()
    return String(format: "median %8.1f ms   min %8.1f ms", v[v.count / 2], v[0])
}
