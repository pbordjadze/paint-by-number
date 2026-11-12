#if DEBUG
import Foundation
import QuartzCore

/// `-tourLog YES` (Debug builds only): the performance tour's event log, `tmp/tour-log-<pid>.tsv` in the
/// app's data container, one file per process. A `launch` line gives the process's start; then one line
/// per canvas tick (the gap since the last tick, how long the tick's own work took, whether it drew),
/// per camera flight (start: from and to, duration; land), per sound and per haptic; and twice a second
/// the thermal state, Low Power Mode and the memory footprint. Times are wall-clock seconds (the
/// device's clock, which the UI test's segment marks share). Lines are buffered and written twice a
/// second, off the main thread.
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
            pending.append(stamp() + "\tlaunch\tstarted=\(String(format: "%.4f", started))\n")
            sample()
        }
    }

    static func event(_ kind: String, _ fields: String) {
        guard isOn else { return }
        let line = stamp() + "\t\(kind)\t\(fields)\n"
        queue.async { pending.append(line) }
    }

    private static func stamp() -> String { String(format: "%.4f", Date().timeIntervalSince1970) }

    private static func sample() {
        let info = ProcessInfo.processInfo
        pending.append(stamp() + "\tdevice\tthermal=\(info.thermalState.rawValue)\tlowPower=\(info.isLowPowerModeEnabled)"
            + "\tfootprintMB=\(footprint() / 1_048_576)\n")
        handle?.write(pending.joined().data(using: .utf8)!)
        pending.removeAll(keepingCapacity: true)
        queue.asyncAfter(deadline: .now() + 0.5) { sample() }
    }

    /// The process's memory footprint (what jetsam counts), in bytes.
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
#endif
