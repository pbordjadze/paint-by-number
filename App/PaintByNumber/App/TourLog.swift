#if DEBUG
import Foundation
import QuartzCore

/// `-tourLog YES` (Debug builds only): the performance tour's event log, `tmp/tour-log-<pid>.tsv` in the
/// app's data container, one file per process. One line per canvas tick (when it began, the gap since the last tick, how
/// long the tick's own work took, whether it drew), per camera flight (start: from and to, duration;
/// land), per sound and per haptic; about once a second, the thermal state, Low Power Mode and
/// the memory footprint. Times are wall-clock seconds (the device's clock, which the UI
/// test's segment marks share). Lines are buffered and written about once a second, off the main thread.
nonisolated enum TourLog {
    static let isOn = UserDefaults.standard.bool(forKey: "tourLog")
    static let url = FileManager.default.temporaryDirectory.appending(path: "tour-log-\(ProcessInfo.processInfo.processIdentifier).tsv")

    private static let queue = DispatchQueue(label: "tour-log", qos: .utility)
    nonisolated(unsafe) private static var pending: [String] = []
    nonisolated(unsafe) private static var scheduled = false
    nonisolated(unsafe) private static var handle: FileHandle? = {
        guard isOn else { return nil }
        // The process's start, so the first tick that drew gives the time to the first frame.
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_un.__p_starttime
        let line = String(format: "%.4f\tlaunch\tstarted=%.4f\n", Date().timeIntervalSince1970,
                          Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
        FileManager.default.createFile(atPath: url.path, contents: line.data(using: .utf8))
        let file = try? FileHandle(forWritingTo: url)
        _ = try? file?.seekToEnd()
        return file
    }()

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

    static func event(_ kind: String, _ fields: String) {
        guard isOn else { return }
        let line = String(format: "%.4f", Date().timeIntervalSince1970) + "\t\(kind)\t\(fields)\n"
        queue.async {
            pending.append(line)
            guard !scheduled else { return }
            scheduled = true
            queue.asyncAfter(deadline: .now() + 1) {
                let info = ProcessInfo.processInfo
                pending.append(String(format: "%.4f", Date().timeIntervalSince1970)
                    + "\tdevice\tthermal=\(info.thermalState.rawValue)\tlowPower=\(info.isLowPowerModeEnabled)"
                    + "\tfootprintMB=\(footprint() / 1_048_576)\n")
                handle?.write(pending.joined().data(using: .utf8)!)
                pending.removeAll(keepingCapacity: true)
                scheduled = false
            }
        }
    }
}
#endif
