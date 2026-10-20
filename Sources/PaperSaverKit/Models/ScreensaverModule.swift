import Foundation

/// The technology behind a screensaver.
public enum ScreensaverType: String, Codable, CaseIterable, Sendable {
    /// A `.saver` plug-in built with the public ScreenSaver framework.
    case traditional = "saver"
    /// An app extension on the `com.apple.screensaver` extension point (`.appex`), the format
    /// Apple's own screensavers use.
    case appExtension = "appex"
    /// A wallpaper extension (`com.apple.wallpaper` extension point) selected as the screensaver,
    /// identified by its bundle identifier.
    case wallpaperExtension = "wallpaper-extension"
    /// Apple's aerial videos.
    case sequoiaVideo = "video"
    /// The classic Macintosh screensavers.
    case builtInMac = "macintosh"
    /// Nothing chosen: the agent's placeholder or the system default.
    case defaultScreen = "default"

    /// The bundle extension, when the type is a bundle on disk.
    public var fileExtension: String? {
        switch self {
        case .traditional: return "saver"
        case .appExtension, .wallpaperExtension: return "appex"
        case .sequoiaVideo, .builtInMac, .defaultScreen: return nil
        }
    }

    /// The store provider for this type. A wallpaper extension's provider is its own bundle
    /// identifier, so it has none here.
    public var provider: ChoiceProvider? {
        switch self {
        case .traditional, .appExtension: return .screenSaver
        case .wallpaperExtension: return nil
        case .sequoiaVideo: return .aerials
        case .builtInMac: return .macintosh
        case .defaultScreen: return .placeholder
        }
    }

    public var displayName: String {
        switch self {
        case .traditional: return "Screen Saver"
        case .appExtension: return "App Extension"
        case .wallpaperExtension: return "Wallpaper Extension"
        case .sequoiaVideo: return "Video Screensaver"
        case .builtInMac: return "Classic Mac"
        case .defaultScreen: return "Default"
        }
    }

    /// The type of a bundle on disk, by its extension.
    public init(bundleURL: URL) {
        self = bundleURL.pathExtension.lowercased() == "appex" ? .appExtension : .traditional
    }
}

/// A screensaver installed on the Mac.
public struct ScreensaverModule: Codable, Equatable, Sendable {
    /// The name System Settings lists it under and `setScreensaver(module:)` accepts: the
    /// bundle's file name without extension.
    public let name: String
    /// The bundle's file name with extension.
    public let identifier: String
    public let path: URL
    public let type: ScreensaverType
    /// `true` for the screensavers macOS ships.
    public let isSystem: Bool
    /// The bundle identifier, when known (app extensions registered with pluginkit).
    public let bundleIdentifier: String?

    public init(name: String, identifier: String, path: URL, type: ScreensaverType, isSystem: Bool = false, bundleIdentifier: String? = nil) {
        self.name = name
        self.identifier = identifier
        self.path = path
        self.type = type
        self.isSystem = isSystem
        self.bundleIdentifier = bundleIdentifier
    }
}
