import Foundation

/// Every error the library throws.
public enum PaperSaverError: LocalizedError, Sendable {
    /// The store, its backup or an image file does not exist.
    case fileNotFound(URL)
    /// The store could not be read or is not a property-list dictionary.
    case plistReadError(String)
    /// The store, its backup or a preference could not be written.
    case plistWriteError(String)
    /// A value handed to the library does not fit the store format.
    case invalidConfiguration(String)
    /// No `.saver` or `.appex` bundle has that name.
    case screensaverNotFound(String)
    /// No Space has that UUID or number.
    case spaceNotFound(String)
    /// No display has that UUID or number.
    case displayNotFound(String)
    /// WallpaperAgent did not keep the written choice after its restart.
    case verificationFailed(expected: String, rolledBack: Bool)
    /// `killall WallpaperAgent` failed or no new agent appeared.
    case agentRestartFailed(String)
    /// `pluginkit` could not be run or reported an error.
    case pluginkitFailed(String)
    /// No wallpaper extension (`com.apple.wallpaper` extension point) is registered with that
    /// bundle identifier. `hint` says what the identifier is instead, when it is known.
    case wallpaperExtensionNotFound(bundleID: String, hint: String?)
    /// The running macOS lacks something the operation needs.
    case unsupportedOperation(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .plistReadError(let details):
            return "Failed to read property list: \(details)"
        case .plistWriteError(let details):
            return "Failed to write property list: \(details)"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .screensaverNotFound(let name):
            return "Screensaver not found: \(name)"
        case .spaceNotFound(let which):
            return "Space not found: \(which)"
        case .displayNotFound(let which):
            return "Display not found: \(which)"
        case .verificationFailed(let expected, let rolledBack):
            return "WallpaperAgent did not keep the written choice (\(expected))" + (rolledBack ? "; the previous store was restored" : "")
        case .agentRestartFailed(let reason):
            return "Could not restart WallpaperAgent: \(reason)"
        case .pluginkitFailed(let output):
            return "pluginkit failed: \(output)"
        case .wallpaperExtensionNotFound(let bundleID, let hint):
            return "No wallpaper extension is registered as \(bundleID)" + (hint.map { ". \($0)" } ?? ". `pluginkit -m -v -p com.apple.wallpaper` lists the registered ones.")
        case .unsupportedOperation(let details):
            return "Unsupported operation: \(details)"
        }
    }
}
