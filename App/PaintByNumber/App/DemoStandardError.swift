#if DEBUG
import Darwin

/// Demo and UI-test launches write nothing to standard error. Under a test, os_log mirrors every
/// line to it (`_os_log_impl_mirror_to_stderr`), XCTest's own element queries inside the app
/// included, and once the pipe behind it is full the write blocks the thread that logged: CI's
/// ipad-ui stalls of up to 7 s had the main thread in `writev` there, answering an element query
/// (November 6). Nothing reads it: CI takes the app's lines from the log store (`ci/collect.sh`,
/// `ci/screenshots.sh`), which this leaves as it is.
nonisolated enum DemoStandardError {
    /// Points standard error at /dev/null. Call before anything logs.
    static func silence() {
        let null = open("/dev/null", O_WRONLY)
        guard null >= 0 else { return }
        dup2(null, STDERR_FILENO)
        close(null)
    }
}
#endif
