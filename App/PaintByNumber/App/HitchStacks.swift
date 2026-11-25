#if DEBUG
import Darwin
import Foundation
import QuartzCore
import Synchronization

/// `-tourStacks YES` beside `-tourLog YES` (Debug and ReleaseTests builds): what the main thread was
/// doing during each hitch, read on the device with no Instruments (painting-company row 390). A
/// thread of its own reads the main thread's stack every `interval` (`MainThreadWatchdog.sample`:
/// suspended, its frame records walked, nothing allocated meanwhile) and keeps the last `kept`
/// seconds of them. When the tour's pulse sees a hitch it asks for the samples inside the gap,
/// and a `stacks` line follows the `hitch` line in the log: how many samples fell in the gap, and
/// the frames most of them were in, counted three ways: the innermost of the app's own frames
/// (what of ours was running), the outermost (what of ours started it: a task, a body, an
/// action), and the innermost frame of all (where the time went, often SwiftUI's or UIKit's).
/// Names are the symbol tables' (`dladdr`, Swift's mangled), named off the main thread;
/// `tools/perf-tour/hitchstacks.py` lays them out against the segment's marks, demangled.
///
/// Reading the stack 250 times a second costs the main thread a little: judge frame counts by runs
/// without it, and causes by runs with it.
nonisolated enum HitchStacks {
    static let isOn = TourLog.isOn && UserDefaults.standard.bool(forKey: "tourStacks")
    /// Between samples, seconds: a hitch of two frames gets about eight.
    private static let interval = 0.004
    /// How long a sample is kept: past the longest gap worth reading.
    private static let kept = 1.0
    /// How deep a stack is walked: SwiftUI's view building nests hundreds of frames deep, and the
    /// app's outermost frame, what started the work, is near the bottom.
    private static let maximumFrames = 1024
    /// How many of each count are written.
    private static let listed = 5

    private nonisolated struct Request: Sendable {
        var from: CFTimeInterval
        var to: CFTimeInterval
        var gap: Double
    }

    private static let requests = Mutex<[Request]>([])
    private static let naming = DispatchQueue(label: "hitch-stacks", qos: .utility)

    /// Call on the main thread, after `TourLog.start`.
    static func start() {
        #if arch(arm64)
        guard isOn else { return }
        dispatchPrecondition(condition: .onQueue(.main))
        let main = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(main))
        let stack = (top - UInt(pthread_get_stacksize_np(main)))...top
        let thread = pthread_mach_thread_np(main)
        let sampler = Thread { HitchStacks.run(thread, stack: stack) }
        sampler.name = "HitchStacks"
        sampler.qualityOfService = .userInteractive
        sampler.start()
        #endif
    }

    /// The pulse met the main thread late at `to`, its last beat at `from` (`CACurrentMediaTime`'s
    /// clock, as a display link's timestamps are): the samples between are written once taken.
    static func hitch(from: CFTimeInterval, to: CFTimeInterval, gap: Double) {
        guard isOn else { return }
        requests.withLock { $0.append(Request(from: from, to: to, gap: gap)) }
    }

    #if arch(arm64)
    private static func run(_ thread: thread_act_t, stack: ClosedRange<UInt>) {
        let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: maximumFrames)
        var ring: [(time: CFTimeInterval, frames: [UInt])] = []
        while true {
            Thread.sleep(forTimeInterval: interval)
            // Copied once the main thread runs again: nothing allocates while it is suspended.
            let depth = MainThreadWatchdog.sample(thread, stack: stack, into: frames)
            let now = CACurrentMediaTime()
            if depth > 0 { ring.append((now, Array(frames.prefix(depth)))) }
            let stale = ring.prefix { now - $0.time > kept }.count
            if stale > 0 { ring.removeFirst(stale) }
            let due = requests.withLock { (pending: inout [Request]) -> [Request] in
                let due = pending.filter { $0.to < now }
                pending.removeAll { $0.to < now }
                return due
            }
            for request in due {
                let inGap = ring.filter { $0.time > request.from && $0.time <= request.to }.map(\.frames)
                naming.async { write(request, inGap) }
            }
        }
    }
    #endif

    private static let appImage = Bundle.main.executableURL?.lastPathComponent ?? "PaintByNumber"

    /// One `stacks` line: the gap, the samples in it, and the three counts.
    private static func write(_ request: Request, _ samples: [[UInt]]) {
        var names: [UInt: (image: String, symbol: String)] = [:]
        func name(_ address: UInt) -> (image: String, symbol: String) {
            if let known = names[address] { return known }
            let named = describe(address)
            names[address] = named
            return named
        }
        var inner: [String: Int] = [:], outer: [String: Int] = [:], leaf: [String: Int] = [:]
        for frames in samples {
            let named = frames.map(name)
            if let first = named.first { leaf[first.symbol, default: 0] += 1 }
            let ours = named.filter { $0.image == appImage }
            inner[ours.first?.symbol ?? "-", default: 0] += 1
            outer[ours.last?.symbol ?? "-", default: 0] += 1
        }
        TourLog.trace(
            "stacks", "gap=%.1f\tsamples=%d\tinner=%@\touter=%@\tleaf=%@", request.gap, samples.count,
            top(inner), top(outer), top(leaf))
    }

    /// The most frequent names, "count×name", most first, " | " between.
    private static func top(_ counts: [String: Int]) -> String {
        counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(listed)
            .map { "\($0.value)×\($0.key)" }
            .joined(separator: " | ")
    }

    /// The image and symbol of a return address (the instruction before it is the call); an
    /// address no symbol names is its image and offset, for `atos`.
    private static func describe(_ address: UInt) -> (image: String, symbol: String) {
        var info = Dl_info()
        guard address > 1, dladdr(UnsafeRawPointer(bitPattern: address - 1), &info) != 0 else {
            return ("?", "0x" + String(address, radix: 16))
        }
        let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
        if let symbol = info.dli_sname { return (image, String(cString: symbol)) }
        let base = UInt(bitPattern: info.dli_fbase)
        return (image, "\(image)+0x" + String(address - base, radix: 16))
    }
}
#endif
