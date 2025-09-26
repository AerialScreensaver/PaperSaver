import Foundation

/// The type of screensaver technology used by a screensaver module.
///
/// macOS supports several different screensaver technologies, each with
/// different capabilities and system integration levels. This enum identifies
/// which technology a particular screensaver uses.
public enum ScreensaverType: String, Codable, CaseIterable {
    /// Traditional macOS screensaver bundle (.saver files).
    ///
    /// These are the classic screensaver format using ScreenSaverView
    /// framework. Most third-party screensavers use this format.
    case traditional = "saver"

    /// Modern App Extension screensavers (.appex bundles).
    ///
    /// New format introduced in macOS Monterey using ExtensionKit.
    /// These are sandboxed and provide better security and performance.
    case appExtension = "appex"

    /// Video-based screensavers from macOS Sequoia.
    ///
    /// New video screensaver format introduced in macOS 15 (Sequoia)
    /// for high-quality video backgrounds.
    case sequoiaVideo = "video"

    /// Built-in classic Mac screensavers.
    ///
    /// Legacy screensavers from classic Mac OS, available as
    /// nostalgic options in modern macOS.
    case builtInMac = "macintosh"

    /// Default system screensaver (typically "Random").
    ///
    /// The system's default screensaver selection that doesn't
    /// correspond to a specific module file.
    case defaultScreen = "default"
    
    /// The file extension used by this screensaver type.
    ///
    /// Returns the file extension (without the dot) for screensaver
    /// files of this type. Some types don't have discrete files and
    /// return an empty string.
    ///
    /// - Returns: File extension string, or empty string for built-in types.
    public var fileExtension: String {
        switch self {
        case .traditional: return "saver"
        case .appExtension: return "appex"
        case .sequoiaVideo: return ""
        case .builtInMac, .defaultScreen: return ""
        }
    }
    
    /// The provider identifier used by macOS for this screensaver type.
    ///
    /// Returns the bundle identifier or provider string that macOS uses
    /// internally to categorize and manage screensavers of this type.
    /// This is used in the system's wallpaper/screensaver configuration.
    ///
    /// - Returns: Provider identifier string used by the system.
    public var providerIdentifier: String {
        switch self {
        case .traditional:
            return "com.apple.wallpaper.choice.screen-saver"
        case .appExtension:
            return "com.apple.NeptuneOneExtension"
        case .sequoiaVideo:
            return "com.apple.wallpaper.choice.sequoia"
        case .builtInMac:
            return "com.apple.wallpaper.choice.macintosh"
        case .defaultScreen:
            return "default"
        }
    }
    
    /// Human-readable name for this screensaver type.
    ///
    /// Returns a user-friendly name that describes this screensaver
    /// technology. Useful for displaying screensaver categories or
    /// filtering screensavers by type in user interfaces.
    ///
    /// - Returns: Localized display name for the screensaver type.
    public var displayName: String {
        switch self {
        case .traditional: return "Screen Saver"
        case .appExtension: return "App Extension"
        case .sequoiaVideo: return "Video Screensaver"
        case .builtInMac: return "Classic Mac"
        case .defaultScreen: return "Default"
        }
    }
}

/// Information about an available screensaver module.
///
/// This struct represents a screensaver that is installed and available
/// for use on the system. It contains metadata about the screensaver including
/// its location, type, and system integration status.
public struct ScreensaverModule: Codable, Equatable {
    /// The user-friendly display name of the screensaver.
    ///
    /// This is the name shown in System Preferences and user interfaces.
    /// Examples: "Aerial", "Flurry", "Random", "Message".
    public let name: String

    /// The unique identifier for this screensaver module.
    ///
    /// This is typically the bundle identifier or internal name used by
    /// macOS to uniquely identify this screensaver. Used when setting
    /// the screensaver programmatically.
    public let identifier: String

    /// The file system location of the screensaver module.
    ///
    /// Points to the .saver bundle, .appex extension, or other screensaver
    /// file. For built-in screensavers without discrete files, this may
    /// point to a system directory or placeholder location.
    public let path: URL

    /// The technology type used by this screensaver.
    ///
    /// Indicates whether this is a traditional .saver bundle, modern
    /// app extension, or other type.
    public let type: ScreensaverType

    /// Whether this screensaver is provided by the system.
    ///
    /// `true` for screensavers that ship with macOS (like Flurry, Aerial),
    /// `false` for user-installed third-party screensavers. System
    /// screensavers are typically located in `/System/Library/Screen Savers/`.
    public let isSystem: Bool

    /// Optional URL to a thumbnail or preview image.
    ///
    /// Some screensavers provide preview images that can be shown in
    /// configuration interfaces. This is `nil` for screensavers that
    /// don't provide thumbnails or where the thumbnail cannot be located.
    public let thumbnail: URL?
    
    public init(
        name: String,
        identifier: String,
        path: URL,
        type: ScreensaverType,
        isSystem: Bool = false,
        thumbnail: URL? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.path = path
        self.type = type
        self.isSystem = isSystem
        self.thumbnail = thumbnail
    }
    
}