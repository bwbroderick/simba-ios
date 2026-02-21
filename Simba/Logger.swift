import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bb.simba.app"
    static let network = Logger(subsystem: subsystem, category: "network")
    static let auth    = Logger(subsystem: subsystem, category: "auth")
    static let cache   = Logger(subsystem: subsystem, category: "cache")
    static let sync    = Logger(subsystem: subsystem, category: "sync")
    static let ui      = Logger(subsystem: subsystem, category: "ui")
}
