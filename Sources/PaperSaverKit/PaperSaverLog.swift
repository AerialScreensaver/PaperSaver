import Foundation
import os

/// Where the library sends its diagnostics. The default writes to the unified log under the
/// subsystem `net.aerialscreensaver.PaperSaverKit`.
public struct PaperSaverLog: Sendable {
    public enum Level: Int, Sendable, Comparable {
        case debug, info, warning, error
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var handler: @Sendable (Level, String) -> Void

    public init(handler: @escaping @Sendable (Level, String) -> Void) {
        self.handler = handler
    }

    /// The unified log, category `PaperSaver`.
    public static let os: PaperSaverLog = {
        let logger = Logger(subsystem: "net.aerialscreensaver.PaperSaverKit", category: "PaperSaver")
        return PaperSaverLog { level, message in
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .warning: logger.warning("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
        }
    }()

    /// Drops everything.
    public static let silent = PaperSaverLog { _, _ in }

    /// Prints to standard error, for command-line use.
    public static func standardError(minimumLevel: Level = .info) -> PaperSaverLog {
        PaperSaverLog { level, message in
            guard level >= minimumLevel else { return }
            FileHandle.standardError.write(Data("[\(level)] \(message)\n".utf8))
        }
    }

    func debug(_ message: @autoclosure () -> String) { handler(.debug, message()) }
    func info(_ message: @autoclosure () -> String) { handler(.info, message()) }
    func warning(_ message: @autoclosure () -> String) { handler(.warning, message()) }
    func error(_ message: @autoclosure () -> String) { handler(.error, message()) }
}
