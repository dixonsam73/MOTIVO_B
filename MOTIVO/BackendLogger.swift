import Foundation
import os

enum BackendLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MOTIVO", category: "Backend")

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
