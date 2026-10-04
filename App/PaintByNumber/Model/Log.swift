import os

nonisolated enum Log {
    static let library = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "library")
    static let create = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "create")
}
