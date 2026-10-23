import Foundation
import PaintCore
import Testing
@testable import MakingOf

#if canImport(Glibc)
import Glibc
#endif

/// How long the field show takes on a real picture: set `FIELD_SHOW_PHOTO` to
/// a binary PPM of 3:2 and 1536 px across (the pipeline makes the show's 1024 x 682 pictures of it) and
/// run in release (`swift test -c release -Xswiftc -enable-testing --filter FieldShowBenchmark`),
/// under `taskset -c 0` for one core. It prints the build, a frame and a composite, and the memory the
/// build peaks at and leaves. Without the variable it does nothing.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FIELD_SHOW_PHOTO"] != nil))
struct FieldShowBenchmark {
    @Test func timesTheBuildTheFramesAndTheComposites() throws {
        let path = try #require(ProcessInfo.processInfo.environment["FIELD_SHOW_PHOTO"])
        let photo = try Netpbm.read(Data(contentsOf: URL(fileURLWithPath: path)))
        let recorder = InputsSnapshotRecorder()
        let output = try TemplateGenerator(settings: GenerationSettings(colorCount: 24, detail: 0.5))
            .generate(from: photo, cancel: .none, observer: recorder.receive)
        let pictures = try ShowPictures(snapshots: recorder.values)
        let template = ShowTemplate(output.template, width: pictures.width, height: pictures.height)
        let spec = try ShowSpec(json: shippedSpecData())
        let points = template.strokes.reduce(0) { $0 + $1.points.count }
        print("""
            FieldShowBenchmark: \(pictures.width) x \(pictures.height), \(template.strokes.count) lines of \(points) \
            points, \(template.numbers.count) numbers, \(ProcessInfo.processInfo.activeProcessorCount) cores
            """)

        // memory first, before anything else has been built: the peak the build reaches above where it
        // started, and what the show keeps once the build's own is given back
        Self.giveBack()
        let before = Self.memory()
        Self.resetPeak()
        let show = try FieldShow(pictures: pictures, template: template, spec: spec, seed: 7)
        let peak = Self.memory().peak
        Self.giveBack()
        print("FieldShowBenchmark memory: build peaks \(Self.megabytes(peak - before.resident)) MB above the start, show keeps about \(Self.megabytes(Self.memory().resident - before.resident)) MB")

        // the same show whatever the cores: this line is the same on one and on four
        let parts = FieldShowTests.digest(of: show)
        print("FieldShowBenchmark digest: \(fingerprint(parts.map { Double($0 % (1 << 52)) }))")

        // the build, once to warm up, then the best and the mean of five
        _ = try FieldShow(pictures: pictures, template: template, spec: spec, seed: 7)
        var builds: [Double] = []
        for _ in 0..<5 {
            let began = Date()
            _ = try FieldShow(pictures: pictures, template: template, spec: spec, seed: 7)
            builds.append(Date().timeIntervalSince(began))
        }
        print("FieldShowBenchmark build: best \(builds.min()!) s, mean \(builds.reduce(0, +) / 5) s")

        // a frame and a composite, over the show
        let times = stride(from: 0.0, through: show.duration, by: show.duration / 200).map { $0 }
        var began = Date()
        var frames: [ShowFrame] = []
        for t in times { frames.append(show.frame(at: t)) }
        let frameTime = Date().timeIntervalSince(began) / Double(times.count)
        var pixels = Plane<SIMD4<UInt8>>(width: show.size.width, height: show.size.height, repeating: .zero)
        began = Date()
        for frame in frames { show.composite(frame, into: &pixels) }
        let compositeTime = Date().timeIntervalSince(began) / Double(frames.count)
        let heaviest = frames.max { $0.ink.count < $1.ink.count }!
        began = Date()
        for _ in 0..<20 { show.composite(heaviest, into: &pixels) }
        print("FieldShowBenchmark frame(at:): \(frameTime * 1000) ms on average; composite: \(compositeTime * 1000) ms on average, \(Date().timeIntervalSince(began) / 20 * 1000) ms with the most lines (\(heaviest.ink.count))")

    }

    /// The process's resident and peak resident sizes in bytes, from /proc (Linux).
    private static func memory() -> (resident: Int, peak: Int) {
        let status = (try? String(contentsOfFile: "/proc/self/status", encoding: .utf8)) ?? ""
        func kilobytes(_ key: String) -> Int {
            let line = status.split(separator: "\n").first { $0.hasPrefix(key) } ?? ""
            return (Int(line.split(whereSeparator: { $0 == " " || $0 == "\t" }).dropFirst().first ?? "0") ?? 0) * 1024
        }
        return (kilobytes("VmRSS:"), kilobytes("VmHWM:"))
    }

    /// Returns freed memory to the system, so the size measured is what is in use.
    private static func giveBack() {
        #if canImport(Glibc)
        typealias Trim = @convention(c) (Int) -> Int32          // malloc.h's, which Swift's Glibc does not import
        if let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "malloc_trim") {
            _ = unsafeBitCast(symbol, to: Trim.self)(0)
        }
        #endif
    }

    /// Starts the peak over from the size now.
    private static func resetPeak() {
        try? "5".write(toFile: "/proc/self/clear_refs", atomically: false, encoding: .utf8)
    }

    private static func megabytes(_ bytes: Int) -> Int { bytes / 1_048_576 }
}
