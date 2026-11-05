import os

/// The app's loggers, a category per area.
nonisolated enum Log {
    private static let subsystem = "com.pbordjadze.paintbynumber"

    static let library = Logger(subsystem: subsystem, category: "ravenna.library")
    static let create = Logger(subsystem: subsystem, category: "ravenna.create")
    static let canvas = Logger(subsystem: subsystem, category: "ravenna.canvas")
    static let tips = Logger(subsystem: subsystem, category: "ravenna.tips")
    static let feedback = Logger(subsystem: subsystem, category: "ravenna.feedback")
    static let store = Logger(subsystem: subsystem, category: "ravenna.store")
    #if DEBUG
    static let demo = Logger(subsystem: subsystem, category: "ravenna.demo")
    #endif
}
