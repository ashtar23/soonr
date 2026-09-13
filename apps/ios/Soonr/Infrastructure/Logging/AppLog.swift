import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ashtar23.soonr.native"

    static let api = Logger(subsystem: subsystem, category: "api")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let watchlist = Logger(subsystem: subsystem, category: "watchlist")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
