import os

/// The app's loggers, a category per area.
nonisolated enum Log {
    private static let subsystem = "com.pbordjadze.paintbynumber"

    static let library = Logger(subsystem: subsystem, category: EraSeam.logPrefix + "library")
    static let create = Logger(subsystem: subsystem, category: EraSeam.logPrefix + "create")
    static let canvas = Logger(subsystem: subsystem, category: EraSeam.logPrefix + "canvas")
    static let tips = Logger(subsystem: subsystem, category: EraSeam.logPrefix + "tips")
    static let feedback = Logger(subsystem: subsystem, category: EraSeam.logPrefix + "feedback")
    static let store = Logger(subsystem: subsystem, category: EraSeam.logPrefix + "store")
    #if DEBUG
    static let demo = Logger(subsystem: subsystem, category: EraSeam.logPrefix + "demo")
    #endif
}
