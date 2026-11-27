import Foundation

/// A short diary of what the app did with the painter's work (launches, the scene's comings and
/// goings, saves that failed, drafts and ✎ Change's edits kept, brought back or let go), kept on
/// disk so work a tester lost can be traced after iOS ended the app: Give Feedback's bundle
/// carries it (`FeedbackReport.File.breadcrumbs`). Ids, counts and events only, never a title or
/// anything the painter wrote. The file keeps about its newest `keep` bytes; writes run on a
/// queue of their own, and one that fails is let go.
nonisolated enum Breadcrumbs {
    static let file = URL.applicationSupportDirectory.appending(path: "breadcrumbs.log")
    static let limit = 128 * 1024
    static let keep = 64 * 1024
    private static let queue = DispatchQueue(label: "breadcrumbs", qos: .utility)

    static func trace(_ event: String) {
        let line = Data("\(Date.now.ISO8601Format()) \(EraSeam.logPrefix)\(event)\n".utf8)
        queue.async { append(line) }
    }

    /// The diary as it stands, once the notes before have landed; nil when there is none.
    static func read() -> Data? {
        queue.sync { try? Data(contentsOf: file) }
    }

    private static func append(_ line: Data) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) {
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: file.path, contents: line) else { return }
            return
        }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.write(contentsOf: line)
        try? handle.close()
        if size + UInt64(line.count) > UInt64(limit), let all = try? Data(contentsOf: file) {
            try? Data(all.suffix(keep)).write(to: file, options: .atomic)
        }
    }
}
