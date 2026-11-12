#if DEBUG
import Foundation
import QuartzCore

/// `-tourLog YES` (Debug builds only): the performance tour's event log, `tmp/tour-log-<pid>.tsv` in the
/// app's data container, one file per process. A `launch` line gives the process's start; then one line
/// per canvas tick (the gap since the last tick, how long the tick's own work took, whether it drew),
/// per camera flight (start: from and to, duration; land), per sound and per haptic; and twice a second
/// the thermal state, Low Power Mode and the memory footprint (now, and its peak since launch). Times are wall-clock seconds (the
/// device's clock, which the UI test's segment marks share). Lines are buffered and written twice a
/// second, off the main thread.
///
/// It also keeps a pulse (`TourPulse`): a `hitch` line whenever the main thread came to a screen
/// refresh late, with how long since the last one it met (`gap`) and how long a refresh is
/// (`frame`), both in ms. And `mark` lines name the moments a measurement is cut by (the first
/// refresh the app answers, `first refresh`; the line-art maps' `maps begin` and `end`; the start of
/// a painting's `start begin`, `handoff begin`, `handoff drew` and `start end`; a demo's own).
nonisolated enum TourLog {
    static let isOn = UserDefaults.standard.bool(forKey: "tourLog")

    private static let queue = DispatchQueue(label: "tour-log", qos: .utility)
    nonisolated(unsafe) private static var pending: [String] = []
    nonisolated(unsafe) private static var handle: FileHandle?

    /// Opens the log and starts the sampler (the app's launch).
    static func start() {
        guard isOn else { return }
        // The process's start, so the first tick that drew gives the time to the first frame.
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let started = Double(info.kp_proc.p_un.__p_starttime.tv_sec) + Double(info.kp_proc.p_un.__p_starttime.tv_usec) / 1e6
        let url = FileManager.default.temporaryDirectory.appending(path: "tour-log-\(getpid()).tsv")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        queue.async {
            handle = try? FileHandle(forWritingTo: url)
            sample()
        }
        trace("launch", "started=%.4f", started)
        // The app's launch is on the main thread.
        MainActor.assumeIsolated { TourPulse.shared.start() }
    }

    /// One line: the time, `kind`, then `format` filled with `arguments` (its fields, tab-separated
    /// `name=value` pairs, or a mark's words).
    static func trace(_ kind: String, _ format: String, _ arguments: any CVarArg...) {
        guard isOn else { return }
        let time = Date().timeIntervalSince1970
        let fields = String(format: format, arguments: arguments)
        queue.async { pending.append(String(format: "%.4f\t%@\t%@\n", time, kind, fields)) }
    }

    private static func sample() {
        let info = ProcessInfo.processInfo
        let memory = footprint()
        // Appended after this turn of the queue: written by the next sample.
        trace("device", "thermal=%ld\tlowPower=%@\tfootprintMB=%llu\tpeakMB=%llu",
              info.thermalState.rawValue, info.isLowPowerModeEnabled.description, memory.now / 1_048_576, memory.peak / 1_048_576)
        handle?.write(pending.joined().data(using: .utf8)!)
        pending.removeAll(keepingCapacity: true)
        queue.asyncAfter(deadline: .now() + 0.5) { sample() }
    }

    /// The process's memory footprint (what jetsam counts) now, and the most it has ever been (the
    /// kernel's own count, so a peak between two samples is not missed), in bytes.
    private static func footprint() -> (now: UInt64, peak: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, UInt64(max(info.ledger_phys_footprint_peak, 0)))
    }
}

/// The tour log's pulse: a display link of its own on the main run loop, at the screen's refresh
/// rate. A refresh the main thread was too busy to answer shows as a beat that comes more than a
/// frame and a half after the last: the hitches a painter sees as the picture or a bar catching,
/// whatever was drawing, with nothing recorded on the device but one line each.
@MainActor
private final class TourPulse: NSObject {
    static let shared = TourPulse()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(beat(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func beat(_ link: CADisplayLink) {
        let frame = link.targetTimestamp - link.timestamp
        // The first refresh the app answers: its first frame's, give or take one.
        if last == 0 { TourLog.trace("mark", "first refresh") }
        if last > 0, link.timestamp - last > frame * 1.5 {
            TourLog.trace("hitch", "gap=%.1f\tframe=%.1f", (link.timestamp - last) * 1000, frame * 1000)
        }
        last = link.timestamp
    }
}
#endif
